# Deployments

## Robinhood Chain mainnet (4663) — first live run, 2026-09-11

**This is a smoke test, not a production system.** It uses throwaway tokens and
deliberately short windows so a full proposal completes in minutes instead of
four days. Treat the addresses as a demonstration that the mechanism works on a
real chain, not as anything to put money into.

| Contract | Address |
| --- | --- |
| FutarchyGovernor | `0x597d97EF05f0c6C8D554E7bA9bdb138b42ADD044` |
| ConditionalVault (built by the governor) | `0xd85f0C05D0Ecd4eF649D05310c528873b71b8718` |
| FutarchyExecutor | `0x67BE25fBE43AeA5204C15335954932838B5755CA` |
| MarketFactory | `0x7962047FE25ef414b9fD83e9e1f0Fb1788820f27` |
| Safe treasury (v1.4.1) | `0xBeB4ED388302Ee7e91B828865Ca8810CA42b693c` |
| Project token — `FTT`, 18dp, throwaway | `0xC634E3d67a37E4bc59e3aE6d69e99De5A763eBB0` |
| Quote token — `tUSDG`, 6dp, throwaway | `0xC58C3A43B2c3Fa5981222633B9422Ede6B4f53A8` |

Parameters: dark period 60s, trading window 300s, rate limit 20,000/s, stake
1,000 FTT, no guardian. Production values are 24h / 72h (§7) — these are
compressed purely so the lifecycle fits in one sitting.

### Proposal #1 — "pay 120,000 tUSDG to the contributor"

`0x4d12e83540d009ae1dd0fbc7038e9be81c0f259a2f3e0e332a7df86eee96aab3`

| | |
| --- | --- |
| Pass market | `0x7827bEF4D4d7d31cC5c52CefE02A4106c735760C` |
| Fail market | `0x225124a2873846aA01361E3638150cFe6D7AeD4E` |
| Pass oracle | `0xae9Df5D7b65B6b60bf67a7a9Fe3Ce1A155Ab70D8` |
| Fail oracle | `0x686f2e9B5CE385C897C7EA1cEbCC2BE2028154d7` |

Both markets opened at exactly `2000000` (2 tUSDG per FTT) from a single seed of
1,000 FTT + 2,000 tUSDG — one complete set funding both books to equal depth.

A trade of 600 ptUSDG moved the pass market to `3378049`; the fail market stayed
at `2000000`.

**The rate limit, observed on a live chain.** Spot jumped 69% in one
transaction. The recorded price did not follow it:

```
2000000  ->  2600000  ->  3080000  ->  3378049
```

Three cranks, roughly 75 seconds, each step capped at 600,000 (20,000/s ×
30s max step). This is D4 and D8 working in public rather than in a test.

Settled: pass `2721374`, fail `2000000`, threshold `2060000` (+3%, external
proposal). Passed. The settled average sits below the final observation because
it includes the ramp — which is the lag doing its job.

Outcome: treasury 500,000 → 380,000 tUSDG, payee 0 → 120,000 tUSDG.

### Defences, checked against the live deployment

| Attempt | Result |
| --- | --- |
| Replay the same batch | reverted `AlreadyExecuted` (`0xd1d36dcd`) |
| Substitute a batch draining the treasury | reverted `WrongActions` (`0xb4c3ae99`) |
| Call the Safe to attach a second module | reverted `WrongActions` — the hash binding catches it before the target check runs |

### Known gap in this deployment

**The treasury owner was never handed over.** The final step of
`FutarchyDeployer` swaps the Safe's owner to an address nobody controls, which
is what makes the treasury market-only (D10). That step was not performed here,
so the deployer key remains an owner and can still move funds directly.

That is deliberate for a smoke test — permanently burning ownership of a Safe
holding throwaway tokens would only make it unusable for further experiments —
but it means **this deployment is not unruggable and must not be treated as
such.** A production deployment must complete the handover, and
`FutarchyDeployer.verify` reverts if it has not.
