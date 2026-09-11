import { ponder } from "ponder:registry";
import {
  market,
  observation,
  oracle,
  position,
  proposal,
  trade,
  vaultFlow,
} from "ponder:schema";

const WAD = 10n ** 18n;

/** Quote units per 1e18 of base, matching `ConditionalAmm.spotPrice()`. */
function priceOf(reserveBase: bigint, reserveQuote: bigint): bigint {
  if (reserveBase === 0n) return 0n;
  return (reserveQuote * WAD) / reserveBase;
}

const eventId = (event: { id: string }) => event.id;

// ---------------------------------------------------------------- proposals

ponder.on("FutarchyGovernor:Proposed", async ({ event, context }) => {
  await context.db.insert(proposal).values({
    id: event.args.proposalId,
    proposer: event.args.proposer,
    descriptionUri: event.args.descriptionUri,
    descriptionHash: event.args.descriptionHash,
    actionsHash: event.args.actionsHash,
    teamSponsored: event.args.teamSponsored,
    state: "proposed",
    proposedAt: event.block.timestamp,
    proposedAtBlock: event.block.number,
  });
});

/**
 * Launch is where a proposal acquires its markets.
 *
 * Note this handler runs *after* the pools' own `LiquidityAdded` and the
 * oracles' `Started`, because the governor seeds and anchors before it emits.
 * Those handlers therefore create stub rows, and this one back-fills the link
 * to the proposal. Assuming the opposite order silently loses the first
 * liquidity event of every proposal.
 */
ponder.on("FutarchyGovernor:Launched", async ({ event, context }) => {
  const {
    proposalId,
    seeder,
    passAmm,
    failAmm,
    passOracle,
    failOracle,
    anchorPrice,
    tradingOpensAt,
    tradingClosesAt,
  } = event.args;

  await context.db.update(proposal, { id: proposalId }).set({
    state: "active",
    seeder,
    launchedAt: event.block.timestamp,
    passAmm,
    failAmm,
    passOracle,
    failOracle,
    anchorPrice,
    tradingOpensAt: BigInt(tradingOpensAt),
    tradingClosesAt: BigInt(tradingClosesAt),
  });

  for (const [amm, orc, side] of [
    [passAmm, passOracle, "pass"],
    [failAmm, failOracle, "fail"],
  ] as const) {
    await context.db
      .insert(market)
      .values({
        address: amm,
        proposalId,
        side,
        oracle: orc,
        reserveBase: 0n,
        reserveQuote: 0n,
        spotPrice: 0n,
        swapCount: 0,
      })
      .onConflictDoUpdate({ proposalId, side, oracle: orc });

    await context.db
      .insert(oracle)
      .values({ address: orc, proposalId, side, market: amm, observation: 0n })
      .onConflictDoUpdate({ proposalId, side, market: amm });
  }
});

ponder.on("FutarchyGovernor:Finalized", async ({ event, context }) => {
  await context.db.update(proposal, { id: event.args.proposalId }).set({
    state: event.args.passed ? "passed" : "failed",
    passed: event.args.passed,
    twapPass: event.args.twapPass,
    twapFail: event.args.twapFail,
    threshold: event.args.threshold,
    finalizedAt: event.block.timestamp,
  });
});

ponder.on("FutarchyGovernor:Cancelled", async ({ event, context }) => {
  await context.db
    .update(proposal, { id: event.args.proposalId })
    .set({ state: "cancelled", cancelledBy: event.args.by });
});

ponder.on("FutarchyGovernor:SeedReclaimed", async ({ event, context }) => {
  await context.db
    .update(proposal, { id: event.args.proposalId })
    .set({ seedReclaimedAt: event.block.timestamp });
});

ponder.on("FutarchyExecutor:Executed", async ({ event, context }) => {
  await context.db
    .update(proposal, { id: event.args.proposalId })
    .set({ executedAt: event.block.timestamp });
});

// ------------------------------------------------------------------ markets

ponder.on("ConditionalAmm:LiquidityAdded", async ({ event, context }) => {
  await upsertReserves(context, event.log.address, event.args.reserveBase, event.args.reserveQuote);
});

ponder.on("ConditionalAmm:LiquidityRemoved", async ({ event, context }) => {
  await upsertReserves(context, event.log.address, event.args.reserveBase, event.args.reserveQuote);
});

ponder.on("ConditionalAmm:Swapped", async ({ event, context }) => {
  const address = event.log.address;
  const { reserveBase, reserveQuote } = event.args;

  await upsertReserves(context, address, reserveBase, reserveQuote);
  const row = await context.db.find(market, { address });

  await context.db.insert(trade).values({
    id: eventId(event),
    market: address,
    proposalId: row?.proposalId ?? null,
    side: row?.side ?? null,
    trader: event.args.trader,
    baseForQuote: event.args.baseForQuote,
    amountIn: event.args.amountIn,
    amountOut: event.args.amountOut,
    reserveBase,
    reserveQuote,
    priceAfter: priceOf(reserveBase, reserveQuote),
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
  });

  if (row) {
    await context.db
      .update(market, { address })
      .set((m) => ({ swapCount: m.swapCount + 1 }));
  }
});

// ------------------------------------------------------------------ oracles

ponder.on("LaggedTwapOracle:Started", async ({ event, context }) => {
  await context.db
    .insert(oracle)
    .values({
      address: event.log.address,
      observation: event.args.initialObservation,
      twapActiveFrom: BigInt(event.args.twapActiveFrom),
      twapEndsAt: BigInt(event.args.twapEndsAt),
    })
    .onConflictDoUpdate({
      observation: event.args.initialObservation,
      twapActiveFrom: BigInt(event.args.twapActiveFrom),
      twapEndsAt: BigInt(event.args.twapEndsAt),
    });
});

ponder.on("LaggedTwapOracle:Observed", async ({ event, context }) => {
  const address = event.log.address;
  const row = await context.db.find(oracle, { address });

  await context.db.insert(observation).values({
    id: eventId(event),
    oracle: address,
    proposalId: row?.proposalId ?? null,
    side: row?.side ?? null,
    observation: event.args.observation,
    spot: event.args.spot,
    timestamp: event.block.timestamp,
    blockNumber: event.block.number,
  });

  await context.db
    .insert(oracle)
    .values({ address, observation: event.args.observation })
    .onConflictDoUpdate({ observation: event.args.observation });
});

// -------------------------------------------------------------------- vault

ponder.on("ConditionalVault:Split", async ({ event, context }) => {
  await recordFlow(context, event, "split", event.args.amount);
});

ponder.on("ConditionalVault:Merged", async ({ event, context }) => {
  await recordFlow(context, event, "merge", event.args.amount);
});

ponder.on("ConditionalVault:Redeemed", async ({ event, context }) => {
  await recordFlow(
    context,
    event,
    "redeem",
    event.args.amount,
    event.args.outcome === 0 ? "pass" : "fail",
  );
});

// ----------------------------------------------------------------- helpers

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function upsertReserves(
  context: any,
  address: `0x${string}`,
  reserveBase: bigint,
  reserveQuote: bigint,
) {
  const spotPrice = priceOf(reserveBase, reserveQuote);
  await context.db
    .insert(market)
    .values({ address, reserveBase, reserveQuote, spotPrice, swapCount: 0 })
    .onConflictDoUpdate({ reserveBase, reserveQuote, spotPrice });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function recordFlow(
  context: any,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  event: any,
  kind: "split" | "merge" | "redeem",
  amount: bigint,
  outcome?: "pass" | "fail",
) {
  const { questionId, underlying, account } = event.args;

  await context.db.insert(vaultFlow).values({
    id: eventId(event),
    proposalId: questionId,
    underlying,
    account,
    kind,
    amount,
    outcome: outcome ?? null,
    timestamp: event.block.timestamp,
  });

  const key = { proposalId: questionId, underlying, account };
  await context.db
    .insert(position)
    .values({
      ...key,
      split: kind === "split" ? amount : 0n,
      merged: kind === "merge" ? amount : 0n,
      redeemed: kind === "redeem" ? amount : 0n,
    })
    .onConflictDoUpdate((p: { split: bigint; merged: bigint; redeemed: bigint }) => ({
      split: kind === "split" ? p.split + amount : p.split,
      merged: kind === "merge" ? p.merged + amount : p.merged,
      redeemed: kind === "redeem" ? p.redeemed + amount : p.redeemed,
    }));
}
