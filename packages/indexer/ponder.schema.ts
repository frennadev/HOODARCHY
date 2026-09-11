import { index, onchainTable, primaryKey } from "ponder";

/**
 * One row per proposal, carrying its whole life.
 *
 * Denormalised on purpose. A frontend's commonest query is "show me the
 * proposals and their current state", and making that a single table scan
 * rather than a join across five event tables is worth the duplication.
 */
export const proposal = onchainTable(
  "proposal",
  (t) => ({
    id: t.hex().primaryKey(),

    proposer: t.hex().notNull(),
    /** Where to read the proposal. Emitted, never stored on chain. */
    descriptionUri: t.text().notNull(),
    /** Commitment to the description's contents — fetch the URI and compare. */
    descriptionHash: t.hex().notNull(),
    actionsHash: t.hex().notNull(),
    teamSponsored: t.boolean().notNull(),

    /** proposed | active | passed | failed | cancelled */
    state: t.text().notNull(),
    proposedAt: t.bigint().notNull(),
    proposedAtBlock: t.bigint().notNull(),

    seeder: t.hex(),
    launchedAt: t.bigint(),
    passAmm: t.hex(),
    failAmm: t.hex(),
    passOracle: t.hex(),
    failOracle: t.hex(),
    anchorPrice: t.bigint(),
    /** When observations start counting, and when they stop. Unix seconds. */
    tradingOpensAt: t.bigint(),
    tradingClosesAt: t.bigint(),

    passed: t.boolean(),
    twapPass: t.bigint(),
    twapFail: t.bigint(),
    /** What the pass market had to beat: fail x 1.03, or x 0.97 if team-sponsored. */
    threshold: t.bigint(),
    finalizedAt: t.bigint(),

    executedAt: t.bigint(),
    seedReclaimedAt: t.bigint(),
    cancelledBy: t.hex(),
  }),
  (table) => ({
    stateIdx: index().on(table.state),
    proposerIdx: index().on(table.proposer),
    closesIdx: index().on(table.tradingClosesAt),
  }),
);

/**
 * A pass or fail pool.
 *
 * Created by whichever event arrives first. The launch transaction emits
 * `LiquidityAdded` and `Started` *before* `Launched`, because the pools are
 * seeded and the oracles anchored before the governor announces the result — so
 * a handler cannot assume the proposal link already exists. Rows are upserted
 * and `Launched` fills in the rest.
 */
export const market = onchainTable(
  "market",
  (t) => ({
    address: t.hex().primaryKey(),
    proposalId: t.hex(),
    /** "pass" | "fail" — unknown until Launched is seen. */
    side: t.text(),
    oracle: t.hex(),
    base: t.hex(),
    quote: t.hex(),
    reserveBase: t.bigint().notNull(),
    reserveQuote: t.bigint().notNull(),
    /** Quote units per 1e18 of base, from the stored reserves. */
    spotPrice: t.bigint().notNull(),
    swapCount: t.integer().notNull(),
  }),
  (table) => ({
    proposalIdx: index().on(table.proposalId),
  }),
);

/** Maps an oracle back to its proposal, so observations can be attributed. */
export const oracle = onchainTable("oracle", (t) => ({
  address: t.hex().primaryKey(),
  proposalId: t.hex(),
  side: t.text(),
  market: t.hex(),
  twapActiveFrom: t.bigint(),
  twapEndsAt: t.bigint(),
  observation: t.bigint().notNull(),
}));

/**
 * The recorded price over time — the series a proposal's chart is drawn from.
 *
 * `spot` is stored alongside `observation` deliberately: the gap between them is
 * the lag doing its job, and being able to show both is how a trader sees that
 * pushing the price does not immediately move the decision.
 */
export const observation = onchainTable(
  "observation",
  (t) => ({
    id: t.text().primaryKey(),
    oracle: t.hex().notNull(),
    proposalId: t.hex(),
    side: t.text(),
    /** The slow, rate-limited price. This is what decides the proposal. */
    observation: t.bigint().notNull(),
    /** What the pool actually read at that moment. */
    spot: t.bigint().notNull(),
    timestamp: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
  }),
  (table) => ({
    oracleIdx: index().on(table.oracle),
    proposalIdx: index().on(table.proposalId),
    tsIdx: index().on(table.timestamp),
  }),
);

export const trade = onchainTable(
  "trade",
  (t) => ({
    id: t.text().primaryKey(),
    market: t.hex().notNull(),
    proposalId: t.hex(),
    side: t.text(),
    trader: t.hex().notNull(),
    /** true = sold the project token, false = bought it. */
    baseForQuote: t.boolean().notNull(),
    amountIn: t.bigint().notNull(),
    amountOut: t.bigint().notNull(),
    reserveBase: t.bigint().notNull(),
    reserveQuote: t.bigint().notNull(),
    priceAfter: t.bigint().notNull(),
    timestamp: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
  }),
  (table) => ({
    marketIdx: index().on(table.market),
    proposalIdx: index().on(table.proposalId),
    traderIdx: index().on(table.trader),
  }),
);

/**
 * Who holds what, per proposal and underlying.
 *
 * Tracks only vault flows — splits, merges and redemptions — not transfers of
 * the conditional tokens themselves. It answers "what did this address put in
 * and take out", which is enough for a positions view without indexing every
 * ERC-20 transfer of four tokens per proposal.
 */
export const vaultFlow = onchainTable(
  "vault_flow",
  (t) => ({
    id: t.text().primaryKey(),
    proposalId: t.hex().notNull(),
    underlying: t.hex().notNull(),
    account: t.hex().notNull(),
    /** "split" | "merge" | "redeem" */
    kind: t.text().notNull(),
    amount: t.bigint().notNull(),
    /** Set on redeem only. */
    outcome: t.text(),
    timestamp: t.bigint().notNull(),
  }),
  (table) => ({
    accountIdx: index().on(table.account),
    proposalIdx: index().on(table.proposalId),
  }),
);

/** Running totals per account per proposal, so a positions view is one lookup. */
export const position = onchainTable(
  "position",
  (t) => ({
    proposalId: t.hex().notNull(),
    underlying: t.hex().notNull(),
    account: t.hex().notNull(),
    split: t.bigint().notNull(),
    merged: t.bigint().notNull(),
    redeemed: t.bigint().notNull(),
  }),
  (table) => ({
    pk: primaryKey({ columns: [table.proposalId, table.underlying, table.account] }),
  }),
);
