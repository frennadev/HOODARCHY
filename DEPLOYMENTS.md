# Deployments

## Robinhood Chain mainnet (4663)

**These are smoke tests, not production systems.** Throwaway tokens, windows
compressed so a proposal completes in minutes instead of four days, and the
treasury's ownership was never handed to an unheld address. Treat them as proof
the mechanism works on a real chain, not as anything to put money into.

### Current — 2026-09-11 (second deployment)

| Contract | Address |
| --- | --- |
| FutarchyGovernor | `0x1D346cd2d281bb2c07E7803Da98350ECb4e9e3eE` |
| ConditionalVault (built by the governor) | `0xd80DF1C07252dA38C2928DD08D114BE3B92B8659` |
| FutarchyExecutor | `0xB469cFdf1B62f9A7dBbb562b471f9bEd982a1Feb` |
| MarketFactory | `0xDfE16dDC68aFd064573C68e68163DDE2d0BbbC03` |
| Safe treasury (v1.4.1) | `0xBB9A6D7A932BA7062abd33df0Ea7670d98383e14` |
| Project token — `FTT`, 18dp, throwaway | `0xC634E3d67a37E4bc59e3aE6d69e99De5A763eBB0` |
| Quote token — `tUSDG`, 6dp, throwaway | `0xC58C3A43B2c3Fa5981222633B9422Ede6B4f53A8` |

First event at block **60,276,901**; the indexer starts at 60,276,500.

Parameters: dark period 60s, trading window 300s, rate limit 20,000/s, stake
1,000 FTT, no guardian. Production values are 24h / 72h (§7).

#### Proposal — "pay 120,000 tUSDG to the contributor"

`0x360a0080a24fec6f99dd21268414b7d18419c5159fb6aba648357a03a48556e8`

| | |
| --- | --- |
| Pass market | `0x1DFC1648598182a07e75bD3966d7AE7Cf3f9eC0f` |
| Fail market | `0x7bB88BDBf6bf2685eb72F545bBAD91DA84bC7c96` |
| Pass oracle | `0x0047779d0a869B2C6602c3Bf54042E6f7C916C21` |
| Fail oracle | `0x7900BBeB81D7c99E40719cab830613D6101FA8EC` |

Both markets opened at `2000000` from a single seed of 1,000 FTT + 2,000 tUSDG.
A 600 ptUSDG trade moved the pass market to `3378049`; fail stayed at `2000000`.
The observation climbed `2000000 → 2560000 → 3060000 → 3378049` in capped steps.
Passed, and the treasury paid out.

### Why there are two deployments

The first deployment is **stale and cannot be indexed**. Adding `descriptionUri`
to `Proposed` changed that event's topic hash, so logs emitted by the old
contract are invisible to any consumer built from current ABIs — the indexer
synced happily, found no proposal rows, and then failed on `Finalized` for a
proposal it had never seen.

Worth stating as a rule: **an ABI is an interface, and changing an event breaks a
deployment as surely as changing a function would.** The first deployment was
not wrong when it was made; it was made obsolete by a later source change, and
nothing warned us.

### Superseded — 2026-09-11 (first deployment)

Left here because the transactions are real and the run is described in D23.
Do not point anything at these.

| Contract | Address |
| --- | --- |
| FutarchyGovernor | `0x597d97EF05f0c6C8D554E7bA9bdb138b42ADD044` |
| ConditionalVault | `0xd85f0C05D0Ecd4eF649D05310c528873b71b8718` |
| FutarchyExecutor | `0x67BE25fBE43AeA5204C15335954932838B5755CA` |
| MarketFactory | `0x7962047FE25ef414b9fD83e9e1f0Fb1788820f27` |
| Safe treasury | `0xBeB4ED388302Ee7e91B828865Ca8810CA42b693c` |

Its proposal `0x4d12e835…96aab3` passed on a settled pass TWAP of `2721374`
against a threshold of `2060000`, and moved 120,000 tUSDG out of the treasury.

Defences checked against it live: replay reverted `AlreadyExecuted`
(`0xd1d36dcd`), a substituted treasury-draining batch reverted `WrongActions`
(`0xb4c3ae99`), and calling the Safe to attach a second module reverted before
the target check was even reached.

## Known gap in both deployments

**The treasury owner was never handed over.** The final step of
`FutarchyDeployer` swaps the Safe's owner to an address nobody controls, which
is what makes the treasury market-only (D10). It was not performed here — the
step is irreversible and pointless for a Safe holding throwaway tokens.

So the deployer key remains an owner and can move those funds directly.
**Neither deployment is unruggable and neither should be treated as such.** A
production deployment must complete the handover; `FutarchyDeployer.verify`
reverts if it has not.
