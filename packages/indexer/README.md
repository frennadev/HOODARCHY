# Indexer

Turns contract events into queryable tables: proposals, markets, the recorded
price series, trades, and positions.

```
pnpm install
pnpm --filter @capital-dao/indexer dev
```

Needs `PONDER_RPC_URL_4663` and `DATABASE_URL` (see `.env.example` at the repo
root). Ponder serves a GraphQL API at `/graphql` and SQL over HTTP.

## What it indexes, and why that was not free

Pools and oracles are created per proposal, so their addresses cannot be listed
in a config. They are discovered through `MarketFactory.MarketCreated`, which is
why that event names the oracle as well as the pool.

**Event ordering has one trap.** A launch transaction emits, in order:

```
LiquidityAdded   (pools seeded)
Started          (oracles anchored)
Launched         (governor announces the markets)
```

So a pool's first liquidity event arrives *before* anything says which proposal
that pool belongs to. Handlers therefore upsert stub rows and `Launched`
back-fills the link. Assuming the intuitive order silently drops the opening
liquidity of every proposal — and leaves the pool's reserves wrong forever,
since reserves are read from events rather than accumulated.

## The one table worth explaining

`observation` stores the slow, rate-limited `observation` *and* the raw `spot`
alongside it. The gap between them is the lag doing its job. Being able to draw
both is how a trader sees that shoving the price does not move the decision —
which is the whole security argument, made visible.
