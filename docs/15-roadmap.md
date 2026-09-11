# Roadmap

> **Status: pre-launch draft.** Forward-looking and not a commitment. Dates are
> deliberately omitted — we'd rather ship in the right order than to a schedule
> we invented before writing any contracts.

## Where we actually are

**Phase 0 — Foundations. In progress.**

| | |
| --- | --- |
| ✅ | Robinhood Chain verified directly: chain IDs, ArbOS 61, EVM target, gas costs |
| ✅ | Ecosystem addresses verified on-chain — WETH, USDG, Uniswap v3, Permit2, Multicall |
| ✅ | Key blockers identified: Chainlink feeds unconfirmed, Gnosis CTF is Solidity 0.5 |
| ✅ | Archive RPC resolved — fork tests pin to a fixed block instead of drifting with the chain tip |
| ✅ | Corrected an earlier error that recorded Uniswap v4 as absent — it is deployed here, at a chain-specific address |
| ✅ | Development environment built and verified end to end |
| ✅ | Public documentation drafted (this set) |
| ⬜ | Legal review of documentation and token structure |
| ⬜ | Resolve open architecture questions — oracle design above all |

**The core contracts are written, tested and running on mainnet.** A market
decided a proposal and a Safe treasury paid out, with no human signature in the
path (see DEPLOYMENTS.md). They are unaudited, the deployment uses throwaway
tokens with compressed windows, and the treasury handover step was not
performed — so it demonstrates the mechanism rather than being usable.

## What comes next

### Phase 1 — Core contracts

The primitives, in dependency order:

- `ConditionalVault` and conditional tokens — split, merge, redeem
- `TwapOracle` — the security-critical component; **needs an adversarial design
  review before implementation**, not after
- `MarketFactory` — paired conditional pools on Uniswap v3
- `FutarchyGovernor` — proposal lifecycle and settlement
- `Treasury` and `Timelock`

Exit criteria: full unit and integration coverage, invariant tests, and a
complete proposal → market → settlement → execution flow passing against a
forked mainnet.

### Phase 2 — Launch infrastructure

- `OwnershipCoin`, `DAOFactory`, `MilestoneVesting`
- Deployment scripts and a full testnet deployment (chain ID 46630)
- Public testnet round with real participants and real (worthless) money

The testnet round is not a formality. Futarchy's failure modes are economic, and
economic failure modes only show up when people are actually trying to win.

### Phase 3 — Hardening

- Two independent audits, published in full
- Economic modelling of manipulation cost — a separate workstream from code audit
- Bug bounty live before mainnet
- Frontend, indexer, and market data infrastructure
- Legal structure finalised; token characterisation resolved

### Phase 4 — First launches

- Applications open, curated
- A small first cohort, chosen deliberately
- Everything watched closely, findings published

### Later

Deliberately vague, because it depends on what the earlier phases teach us:
Uniswap v4 hooks if a PoolManager appears, treasury yield strategies by
proposal, cross-chain participation via LayerZero, and progressive removal of
any remaining platform-level authority.

## What would make us stop or change course

Stating these in advance, so they're harder to rationalise away later:

- **Audits find fundamental mechanism flaws**, as opposed to fixable bugs
- **The testnet round shows manipulation is cheaper than modelled**
- **Legal review concludes the structure can't be done compliantly** in our
  target jurisdictions
- **Liquidity doesn't materialise.** Futarchy without liquid markets isn't
  futarchy — it's a slow, expensive way to make bad decisions. If we can't
  bootstrap real liquidity, the honest response is to say so rather than launch
  something that only looks like the thing.

## Open items tracked publicly

The undecided questions are listed in
[Architecture](10-architecture.md#open-questions) rather than hidden. Ten of
them are open right now, including oracle design, who seeds conditional pool
liquidity, and whether a pause authority should exist at all.

## Next

- [Architecture](10-architecture.md)
- [Security](11-security.md)
- [Introduction](01-introduction.md)
