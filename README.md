# Hoodarchy

Futarchy-governed treasuries on [Robinhood Chain](https://docs.robinhood.com/chain).

A market decides what a treasury does, and a Safe whose only signer is that
market executes it. The product is one sentence: **you cannot rug, because the
treasury's only signer is a market.**

Modelled on [MetaDAO](https://metadao.fi), which has run 96 proposals across 14
organisations on Solana. We port the invariants, not the programs.

> **Status: unaudited, and not usable.** The mechanism is built, tested and has
> run end to end on Robinhood Chain mainnet — a market decided a proposal and a
> treasury paid out, with no human signature anywhere in the path. That
> deployment is a *demonstration*: throwaway tokens, trading windows compressed
> from 96 hours to 6 minutes, and the treasury's ownership was never handed over,
> so a human key can still move those funds. Read
> [DEPLOYMENTS.md](DEPLOYMENTS.md) before trusting any address in it.

## How a proposal works

1. **Propose.** Someone submits a batch of actions and a link to the description.
   Only a fingerprint of the batch is stored, so what gets traded and what gets
   executed are provably the same thing.
2. **Launch.** Two markets open — one priced *if this passes*, one *if it fails*.
   A single deposit funds both to equal depth, because splitting one token yields
   a matched pair of conditional tokens.
3. **Trade.** Anyone can buy either side. A rate-limited recorder follows the
   price slowly: moving it means *holding* a false price in the open, where
   others can trade against you.
4. **Finalise.** After the window closes, the two averages are compared. Pass
   must beat fail by 3% — or lose by less than 3%, if the team sponsored it.
5. **Execute.** If it passed, anyone can trigger the batch. The treasury pays.

## The bit worth seeing

From the live deployment, a single trade moved a market 69% in one transaction.
The recorded price refused to follow:

```
spot:        2000000 → 3378049   (one trade)
recorded:    2000000 → 2560000 → 3080000 → 3378049   (~75 seconds, capped steps)
```

That gap is the entire security model, in public rather than in a comment.

## Layout

| | |
| --- | --- |
| [`packages/contracts`](packages/contracts) | Foundry. Vault, oracle, AMM, Governor, Executor. |
| [`packages/chain`](packages/chain) | Verified addresses, deployments, and exported ABIs. |
| [`packages/indexer`](packages/indexer) | Ponder. Proposals, markets, price series, trades, positions. |
| [`docs/`](docs) | Product documentation. Pre-launch drafts, not legally reviewed. |

## Reading order

- **[DECISIONS.md](DECISIONS.md)** — every significant choice, in plain English:
  what was decided, why, and what it cost. Including the ones that were wrong.
- **[MECHANISM-REFERENCE.md](MECHANISM-REFERENCE.md)** — the technical spec and
  threat model.
- **[DEPLOYMENTS.md](DEPLOYMENTS.md)** — what is deployed, and what it does not do.

Where the docs and the decision log disagree, the decision log is authoritative.

## Running it

```bash
git clone --recursive https://github.com/frennadev/HOODARCHY
pnpm install
pnpm verify        # everything that needs no credentials
```

`pnpm verify:chain` additionally runs the fork tests and address checks against
mainnet, and needs an **archive** RPC in `RH_MAINNET_RPC_URL` — the public
endpoint loses state within about a thousand blocks.

## What is not built

The launchpad and the web app.

Shared liquidity is **not** on this list any more, though it was for most of the
project's life: anyone can already deepen both books on a live proposal, and
quadrupling depth cuts a trade's price impact from +69% to +16% (D27). What is
missing there is a router to make it one transaction instead of six.

Two mechanism parameters still hold placeholder values — the observation rate
limit and the gap-freeze threshold. The deployed demo runs at 20,000/s, which is
far too fast for real money. See §11 of the reference.

## Licence

UNLICENSED. Published to be read and checked, not to be deployed.
