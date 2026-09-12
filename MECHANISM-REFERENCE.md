# Futarchy on Robinhood Chain — Mechanism Reference

> **This file is the permanent reference for what we are building.** It is meant to
> outlive any individual work session. If something here goes stale, edit it —
> do not fork it into a second document.
>
> Status: the full mechanism is built and tested (192 tests, 27 of them against
> a live chain) — conditional vault, lagged-price oracle, conditional AMM,
> Governor and Executor. **Deployed to Robinhood Chain mainnet and run end to
> end on 2026-09-11**: a market decided a proposal and a Safe treasury paid out.
> See [DEPLOYMENTS.md](DEPLOYMENTS.md), including what that deployment does *not*
> yet do. Per-proposal conditional pools are our own CPMM, ported from MetaDAO
> per §5.2 and D19; Uniswap V4 is the parent/spot venue only.
> Still to come: shared liquidity, launchpad, indexer and web.
> Last verified against chain: 2026-09-09.

---

## 0. Scope and priorities

We are building **futarchy-as-a-service on Robinhood Chain**: a market decides
what a treasury does, and a Safe whose only signer is that market executes it.

Ordering of concerns, decided:

1. **Futarchy on Robinhood Chain is the product.** Ship the mechanism.
2. **Security is the constraint, not a phase.** The threat model in §6 is a
   build input, not a post-hoc audit.
3. **Compatibility with the existing Capital DAO raise contracts is explicitly
   not a goal.** Capital DAO can be reworked later to feed this. Do not bend the
   futarchy design to fit it.

**Isolation rule.** This project lives in its own folder and its own git repo.
The Capital DAO repo (`~/Documents/capital dao`, GitHub
`alphadevelopmentorg/CapitalDao-contract`) must never be a dependency of this
one, so pulling either cannot disturb the other. If we want Capital DAO code,
**copy it in** — never symlink, never submodule it, never edit it in place.

---

## 1. Chain facts (verified)

Robinhood Chain is an **Arbitrum Nitro** rollup (ArbOS 61, `arbOSVersion()` →
116), single sequencer operated by Robinhood, FCFS ordering, ~100ms blocks, no
native gas token, USDG as the house stablecoin.

### Mainnet — chain ID `4663`
Explorer: https://robinhoodchain.blockscout.com

| What | Address | Source |
| --- | --- | --- |
| USDG (**6 decimals**) | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | live, in production use |
| WETH (18 dp) | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | probed 2026-07-26 |
| Multicall3 | `0xcA11bde05977b3631167028862bE2a173976CA11` | probed |
| L2 Multicall | `0x2cAC2D899eCC914d704FeaAE33ac1bF36277DaD1` | probed |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` | probed |
| ArbSys precompile | `0x0000000000000000000000000000000000000064` | probed |
| Uniswap V2 factory | `0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f` | confirmed live, 41,375 pairs |
| Uniswap V2 router | `0x89e5DB8B5aA49aA85AC63f691524311AEB649eba` | confirmed live |
| Uniswap V3 factory | `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA` | probed |
| Uniswap V3 SwapRouter02 | `0xCaf681a66D020601342297493863E78C959E5cb2` | probed |
| Uniswap V3 UniversalRouter | `0x8876789976dEcBfCbBbe364623C63652db8C0904` | probed |
| Uniswap V3 PositionManager | `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3` | probed |
| Uniswap V3 QuoterV2 | `0x33e885eD0Ec9bF04EcfB19341582aADCb4c8A9E7` | probed |
| **Uniswap V4 PoolManager** | `0x8366a39CC670B4001A1121B8F6A443A643e40951` | **confirmed live** — non-canonical address |
| **Uniswap V4 PositionManager** | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` | confirmed; `poolManager()` points back |
| Chainlink feeds | **unconfirmed** | blocking for the Stock-Token metric (§5.6 template B) |

> **Uniswap V4 IS deployed here**, at a non-canonical address that a probe of
> other chains' addresses will never find. An earlier note in this file claimed
> otherwise; see decision D3 for why that reasoning was invalid. Capital DAO has
> since migrated itself from V2 to V4, which is how the address surfaced.
>
> **All three Uniswap versions are live here.** The 2026-07-26 probe recorded V3
> only. V2 is confirmed (41,375 pairs) and V4 is confirmed at the non-canonical
> address above. `addresses.ts` and `src/config/RobinhoodChain.sol` are updated.
>
> Capital DAO used V2 in production until 2026-09; it has since migrated to V4,
> so cite it as evidence that V2 *exists*, not that it is the chain's default.

### Testnet — chain ID `46630`
Explorer: https://explorer.testnet.chain.robinhood.com

| What | Address |
| --- | --- |
| USDG | `0x58157811a8646424ca9633394a9985F44a92C58B` |
| Uniswap V2 factory | `0x1942665C44b2957074D7907391557d1A46F112D8` |
| Uniswap V2 router | `0x6f63Fcd2C81d217770da3978401AdEC2Fc0831Ef` |

### Neighbouring deployment (reference only, not a dependency)

Capital DAO raise factory `0x31876B5F966B88E288a010B5c187e14c48cA8868`,
operator Safe `0x2D1b91b7089471CD2d828b4f59081a9b38Cd136d` (2-of-3),
fee recipient `0x64d352e845155265E6C4c58Ef82C6f3bDa50a177`. Migrated from
Uniswap V2 to V4 in 2026-09; the factory address above predates that migration,
so re-read its deployment record before citing it.

---

## 2. What futarchy actually decides

Hanson: *"vote values, bet beliefs."* MetaDAO collapses the value layer to one
measurable — the project token's price in a stablecoin. Every proposal asks the
same question:

> Would the token be worth more if this instruction executes, or if it does not?

There is no separate KPI vote. **Token price is the welfare metric.** That is a
design choice, not a law of futarchy, and it is why the system can settle
on-chain with no external oracle for "did this help".

As of mid-2026 MetaDAO has run **96 proposals across 14 orgs** (MetaDAO, Sanctum,
Drift, Jito, ORE, Island/Dean's List, Flash, mtnCapital, …).

---

## 3. MetaDAO as it actually works

This is the reference implementation. We port the **invariants**, not the Anchor
programs.

### 3.1 The three programs (v0.6)

| Program | Job |
| --- | --- |
| Futarchy (was Autocrat) | DAO config, proposal lifecycle, compare TWAPs, tell the executor to fire |
| Conditional Vault | Escrow underlying, mint/burn PASS/FAIL conditionals, resolve, redeem |
| AMM (folded into Futarchy AMM) | Constant-product pools for pBASE/pQUOTE and fBASE/fQUOTE, lagging TWAP |

Add-ons: Launchpad, price-based performance package, gated mint, bid wall,
Squads as treasury signer. Fee: **25 bps** on Futarchy AMM volume to the
protocol treasury.

### 3.2 Conditional tokens — the whole trick

A proposal creates a **Question** with two outcomes: Pass, Fail. For each
underlying you care about (BASE = project token, QUOTE = USDC) you open a
conditional vault.

**Split.** Deposit X underlying → receive X PASS-conditional *and* X
FAIL-conditional. Conservation:

```
underlying locked  ==  PASS supply  ==  FAIL supply
```

A **complete set** `{pTOKEN, fTOKEN}` is always worth exactly 1 TOKEN regardless
of outcome. Same for the quote.

**Trade.** Sell the side you do not want.
- Bullish on the proposal → sell fTOKEN, keep/buy pTOKEN. You are long
  *token-if-pass*.
- Bearish → sell pTOKEN, keep fTOKEN.
- Trading the *quote* conditionals expresses "I want my stable back in the world
  I think happens."

**Resolve.** The futarchy program is the question's oracle. After TWAP
comparison it calls `resolve` with payout vector `[1,0]` or `[0,1]`.

**Redeem.** Winning conditionals burn 1:1 for underlying; losing burn for zero.
Complete sets can be **merged** back to underlying at any time before
resolution — this is how LPs and market makers unwind without waiting.

Economically this *simulates reverting the losing world's trades* without ever
unwinding AMM state transaction by transaction. The losing tokens simply become
worthless.

Two vaults per proposal (base → pTOKEN/fTOKEN, quote → pUSD/fUSD) and two AMMs:

| Pool | Pair | Reads as |
| --- | --- | --- |
| Pass | pTOKEN / pQUOTE | "token price if this executes" |
| Fail | fTOKEN / fQUOTE | "token price if this does not" |

Spot keeps trading normally. The decision markets are a parallel universe
sharing collateral through the split.

### 3.3 Proposal lifecycle

1. **Draft / initialize.** Anyone can create. Payload is an executable
   instruction. In v0.6 it lives as a Squads vault transaction; futarchy only
   approves. Description URL on-chain — no hidden proposals.
2. **Stake gate.** e.g. META: 200,000 tokens (2% of initial 10M) staked before
   markets go live. **Returned when trading starts** — anti-spam, not slashing.
3. **Launch.** Half the project's spot LP is often moved into the two
   conditional pools so the books are not empty.
4. **24-hour TWAP delay.** Markets trade immediately; observations do not enter
   the TWAP for 24h. Time to read the proposal and get capital in.
5. **Trading window.** Currently 3 full days (historically ~10).
   Anyone can trade — you only need the stable, not the DAO token.
6. **Finalize.** Anyone can crank after the window. Compare lagged TWAPs.
7. **Execute or die.** Pass → executor runs the instruction with the treasury as
   authority. Fail → it never runs. Then users redeem.

States: `Draft → Active → Passed | Failed → Executed`.

### 3.4 Lagging TWAP — the anti-manipulation core

Spot at `t_end` is worthless as a signal; a validator or last-block whale can
print anything. MetaDAO does **not** feed raw AMM price into the average. It
feeds an **observation** that is a clamped chase of spot:

- `twap_start_delay_seconds` (24h)
- `twap_initial_observation`
- `twap_max_observation_change_per_update` — the observation may only move a
  capped amount per update (docs example: $5/min toward $550 from $500;
  other versions ~2%/min)
- anyone can crank even with no trade, so **time still accrues**
- TWAP = time-weighted average **of observations**, not of ticks

A 100× spike for one slot barely moves the observation. To steal a proposal you
must hold a distorted price for a large fraction of the window against everyone
who can fade you. **That is the entire security model.**

Decision rule:

```
pass  ⟺  TWAP_pass  >  TWAP_fail × (1 + τ)
```

| Proposer | τ |
| --- | --- |
| Team-sponsored | **−3%** (pass slightly easier; fail must be clearly higher to kill it) |
| External | **+3%** (pass must be clearly more valuable) |

Older docs used a flat comparison or 5%. The signed band is current policy.

### 3.5 Execution layer

Treasury is a Squads 1-of-1 whose **sole signer is the futarchy program**.
Humans cannot move funds; the market can. Mint authority belongs to the
governance program, not a person. No hard cap — dilution only if markets say
minting raises value.

### 3.6 Launchpad (why people actually use it)

Capital formation, not just governance-as-a-service:

- Open ICO, min/ideal raise, pro-rata fill + refund on oversubscription
- ~20% of raise + token allocation into the Futarchy AMM (price floor)
- Rest of stable + LP into the treasury
- Team tokens in a **performance package**: unlock in 5 tranches at
  **2× / 4× / 8× / 16× / 32×** launch TWAP
- Some deals wrap in a Marshall Islands DAO LLC whose board is bound to follow
  futarchy

The product is *"you cannot rug, because the treasury signer is a market."*
Governance is the enforcement mechanism for the raise.

### 3.7 What MetaDAO gets wrong or leaves sharp

- **Metric is only token price.** Goodhart: pass something that pumps the token
  and burns the business. No second metric, no human veto beyond instruction
  allowlisting.
- **Liquidity split three ways** (spot, pass, fail). Thin books are easy to
  shove. Shared-liquidity work (v0.5 `shared_liquidity_manager`) tried to fix
  this; still the #1 practical complaint.
- **Binary only.** No A/B/C menu without running multiple proposals.
- **Proposal quality is off-chain.** Markets price; they do not write specs.
- **Team −3% is a thumb on the scale.**
- **Anyone-can-finalize / anyone-can-execute** needs airtight windows or a late
  crank is a grief vector.
- **No current public audit** called out as of some 2026 reviews (Neodyme/Zenith
  covered older vault versions).
- Validator games are why the lag exists. **On a single-sequencer L2 this gets
  worse, not better.**

---

## 4. What changes on Robinhood Chain

| MetaDAO assumption | Robinhood Chain fact | What we change |
| --- | --- | --- |
| Solana slot attacker | Single Robinhood sequencer, FCFS, no priority fee | Lag must be **stricter**. Cap observation per *second*, not per tx. Ignore intra-block bursts. |
| USDC quote | USDG is native, 6 dp | Quote = USDG everywhere. Scale explicitly. |
| Token price = welfare | Stock Tokens + Chainlink exist here | Allow metric ∈ {project token, Stock Token, USDG-NAV vault share} |
| Squads | Safe is the EVM equivalent | Safe + Zodiac; futarchy module is the only exec role |
| Custom AMM / OpenBook | Uniswap V2, V3 **and V4** all deployed | Do **not** fork Uniswap for spot — the parent TOKEN/USDG pool uses V4, where the chain's liquidity is. Custom CPMM **only** for the per-proposal conditional pools, per §5.2 and D19: they hold freshly minted tokens with no liquidity to inherit, so a DEX buys nothing and costs a great deal |
| 3-day window | 100ms blocks, retail + agents | Keep 3 days. Optional 1-day "agent sprint" market type later |
| Permissionless L1 | Permissionless L2, but Stock Tokens have issuer constraints | Kernel/growth split — futarchy must not touch Stock Token custody or settlement |

---

## 5. Architecture

```
Factory
  └─ DAO (one per project)
       ├─ Safe treasury (USDG + tokens + Uni LP)
       ├─ Question / ConditionalVault (ERC-1155)
       ├─ PassPool + FailPool (lagged-TWAP CPMM)
       ├─ Governor (stake, windows, thresholds, finalize)
       └─ Executor (Safe module; allowlisted call targets)
```

### 5.1 ConditionalVault

Shape it like the **Gnosis Conditional Token Framework** — that is the
battle-tested Solidity version of this idea. Wrap it; do not be original here.

ERC-1155, one collection per DAO:
```
id = hash(questionId, outcome, underlying)     // PASS=0, FAIL=1
```

| Function | Behaviour |
| --- | --- |
| `split(underlying, amount)` | mint `amount` of **both** outcomes |
| `merge(underlying, amount)` | burn both, return underlying |
| `redeem(questionId, outcome, amount)` | after resolve, 1:1 for winners, 0 for losers |
| `resolve(questionId, payouts[2])` | **Governor only** |

**Invariant tests written before any UI:**
- `split` then `merge` is the identity
- after resolve, winning redeem + losing redeem = underlying, exactly
- no other mint path exists
- `underlying locked == PASS supply == FAIL supply` at all times

### 5.2 Decision pools with a lagged observation oracle

Two CPMM pools per proposal: `pTOKEN/pUSDG` and `fTOKEN/fUSDG`.

**Do not use vanilla Uniswap V2 for these.** V2's cumulative-price TWAP can
still be slammed for a block. We want the observation clamp *inside* the pool:

```
on every swap or crank:
    dt = block.timestamp - lastUpdate

    # ACCRUE FIRST, using the OLD observation — see §6.4
    if timestamp >= start + DELAY:
        accum += observation * dt

    cap    = maxChangePerSecond * dt
    target = reserveQuote * 1e18 / reserveBase
    observation += clamp(target - observation, -cap, +cap)

    lastUpdate = block.timestamp
    twap = accum / (timestamp - twapStart)
```

Crank is permissionless. The indexer should crank every block during live
proposals — 100ms blocks make this cheap.

**Shared liquidity — already works (D27).** This paragraph previously described
borrowing from the parent pool: *"the vault borrows LP by splitting parent
reserves into complete sets and placing them in both decision pools."*

**That mechanism is impossible and was never built.** A parent pool's reserves
belong to its LPs, and D19 put the parent on Uniswap V4, where nothing lets a
third party relocate other people's capital. The paragraph was written before we
decided where the parent lives, and the two never got reconciled.

What is true instead: **anyone can deepen both books on a live proposal, and
always could.** `ConditionalAmm.addLiquidity` has no access control, and a
complete set is obtainable by anyone. One split of collateral funds both
markets, because splitting X yields X of both conditionals — so the fail book is
never the thin one, and depth costs half what funding two markets separately
would.

Measured: quadrupling a book's depth cuts the price impact of a 600-unit trade
from +69% to +16%. Manipulation cost scales with depth exactly as intended, and
the capital comes back through the ordinary AMM and vault paths with no
privileged route.

What is genuinely missing is **ergonomics, not capability**: deepening both books
takes six transactions today (two splits, two approvals, two deposits) and
unwinding takes four. A router would make it one each. Nobody has been unable to
provide liquidity; it has just been tedious and undocumented.

### 5.3 Governor — **BUILT (D22)**

`FutarchyGovernor`. The lifecycle, in four moments:

```solidity
propose(bytes32 descriptionHash, bytes32 actionsHash, bool teamSponsored)
launch(bytes32 proposalId, uint256 seedBase, uint256 seedQuote)
finalize(bytes32 proposalId)          // after DELAY + WINDOW, by timestamp
cancel(bytes32 proposalId)            // guardian, or proposer before launch
reclaimSeed(bytes32 proposalId)       // seed capital back after resolution
```

Pass rule, as MetaDAO:

```
pass = twap_pass > twap_fail * (teamSponsored ? 0.97 : 1.03)
```

The Governor builds its own `ConditionalVault` in its constructor, so the vault's
governor is this contract by construction rather than by a correctly-supplied
argument. `actions` never touches the chain until execution: the Governor stores
only the hash and the Executor matches it (§5.5).

**Seeding uses one complete set, not two.** Splitting `X` base yields `X` of both
conditionals, so a single deposit opens the pass and fail books to equal depth —
which is what stops the fail side being the thin one §6.3.2 warns about.

**No parameter is settable in v1.** See §6.3.3: bounds in code must come before
configurability, and a timelock is the second line rather than the first.

### 5.4 Action allowlist — kernel vs growth

Allowlist the action surface, or someone prices "transfer mint authority to
attacker" on a thin book for 20 minutes.

**Allowed (growth):**
- ERC-20 transfer from treasury
- mint via GatedMint (cap per proposal, cap per 30 days)
- Uniswap V3/V4 LP add/remove
- Morpho supply/withdraw
- set DAO params (windows, τ, stake, fee) — **plus a 7-day extra timelock**
- grant / revoke non-kernel roles

**Forbidden in the module (kernel):**
- change Stock Token issuer or Chainlink feed
- pause user withdrawals from other protocols
- replace the Governor or ConditionalVault
- touch L2 precompiles or the sequencer inbox

### 5.5 Executor = Safe + our own module — **BUILT (D21)**

One Safe per DAO, owner set to an address nobody holds. The only module that can
`exec` is `FutarchyExecutor`, and only when the Governor reports the proposal
approved **and** the actions hash matches. Executed is marked before any external
call, so replay is refused. This is Squads, in EVM.

Safe 1.4.1 is deployed on Robinhood Chain (verified by `VERSION()`, addresses in
`RobinhoodChain.sol`). Our own minimal module rather than Zodiac — D2 says copy
patterns, do not take dependencies.

**Two structural rules, and deliberately no action allowlist beyond them:**

1. A batch may not call the Safe. `enableModule` is an ordinary call to the
   Safe's own address, so one passed proposal could attach a second module that
   answers to nobody — futarchy exited permanently, by market vote, once.
2. A batch may never `delegatecall`. Rule 1 is insufficient on its own:
   delegatecall runs any contract's code in the Safe's storage and can rewrite
   the module list without naming the Safe. Hard-coded, never a parameter.

The kernel/growth table in §5.4 is **not built**, on purpose. MetaDAO has no
equivalent and each extra rule is a way to block a legitimate proposal. Revisit
if a concrete need appears; the two rules above are structural, not policy.

### 5.6 DAO templates — which metric

| Template | BASE in decision pools | Use for |
| --- | --- | --- |
| **A. Token DAO** (MetaDAO clone) | project ERC-20 | launchpad tokens, "unruggable treasury", protocol fee switches |
| **B. Stock-metric DAO** | a Stock Token (HOODx, NVDAx, SPYx) | "if we fund Morpho incentives, does HOODx 7-day TWAP beat the fail world?" |
| **C. Hybrid** | project token, **plus** a non-executing advisory scalar market on a Stock Token | when you want the equity signal without binding to it |

Template B is the **Robinhood-native wedge** — closer to Hanson's original
"national welfare" than token-price-is-welfare, and only clean on a chain where
the equity is a first-class ERC-20 with a live feed.

**Never mix two metrics into one TWAP comparison.**

Ship A first. Ship B as the headline once A is not on fire.

### 5.7 Launchpad — ship with governance, not after

- Cap + min raise in USDG, pro-rata fill, refund dust
- 20% of USDG + 10–20% of supply → parent TOKEN/USDG pool
- Rest of USDG → Safe
- Mint authority → Governor
- Team allocation → performance package, 5 tranches at 2×/4×/8×/16×/32×
  **lagged** launch TWAP
- First proposal auto-created: *"ratify launch params"*, so the market can reject
  a poisoned raise

Capital DAO already has launch-factory patterns on this chain. Copy the
patterns; do not compete on UX and do not take a dependency.

---

## 6. Security model

The goal is stated plainly: **futarchy without security risk.** Everything below
is a build input.

### 6.1 Threat model

| Adversary | Capability | Primary defence |
| --- | --- | --- |
| Trader with capital | Push a decision pool for the window | Lagged observation clamp + shared liquidity depth |
| Griefer with dust | Break proposal setup for pennies | §6.2 — absorb, never reject |
| Sequencer (Robinhood) | Delay, reorder within arrival window, stall cranks | Time-based caps, timestamp-gap freeze (§6.5) |
| Proposer | Smuggle a hostile action | Hash-bound batch + kernel allowlist (§5.4) |
| Operator/insider | Front-run a state snapshot they schedule | Snapshot at the earliest public signal (§6.3) |
| LP / market maker | Extract via complete-set arbitrage | Merge is always available; price it in |

### 6.2 Inherited lessons from the Capital DAO audit

These are **confirmed bugs we already shipped and fixed once**. They map
directly onto this design. Do not relearn them.

**(a) Deterministic pool addresses + `sync()` = denial of launch.**
On Capital DAO, `0.029 USDG` sent to a raise's future Uniswap pair, followed by
`sync()`, promoted the donation to a *reserve*. Reserves cannot be skimmed while
LP supply is zero, so settlement reverted **forever**. Cost to attacker: three
cents. This was audit finding **H-1**.

> **This is worse for futarchy.** Capital DAO created one pair per *raise*;
> we create two pools per *proposal*. An attacker could brick every proposal on
> the platform, permanently, for pennies each.
>
> **Rule: seeding must absorb any preseed, never reject it.** Fund only the
> shortfall so the pool ends up holding exactly the intended reserve. In Capital
> DAO this made the opening price *exactly* right where the previous tolerance
> made it approximately right — absorbing is strictly better, not a loosening.
> Alternatively, make conditional pools non-address-predictable or
> permissioned-to-create. Decide in §11.

**(b) Any state read at a predictable moment is front-runnable.**
Capital DAO's wind-down snapshot sat in `startWindDown()`, which required a
*prior* `pauseTap()` transaction — so the snapshot was announced a full
transaction in advance. Buying excluded inventory before it landed converted
dead tokens into a live claim: **3,797 USDG in, 26,250 out** of a 70,000 pot.
Audit finding **M-1**. Fixed by snapshotting at the earliest public signal.

> Applies here to **`finalize()` and any TWAP read**. Prefer state that is fixed
> by *elapsed time* rather than by a transaction someone chooses to send.

**(c) Never gate on an exact-equality condition a participant can be permanently
unable to satisfy.**
A dust-sweep ledger closed only when `settled == totalCommitted`. Contributors
whose floored share was zero reverted *before* being marked processed. One such
contributor self-healed; **two deadlocked the pool permanently.** This bug was
introduced by us and caught by an external reviewer.

> Applies to complete-set accounting, redemption closure, and LP unwind. Process
> a zero share; do not revert on it.

**(d) Mock AMMs hide real failures.**
Capital DAO's fix for (a) initially reverted against real Uniswap because
`skim()` pushes *both* sides unconditionally and the token's transfer gate
rejected a zero-value move. The mock did not model it. **Write fork tests
against real Uniswap from day one.**

**(e) Checks-effects-interactions, always.** Commit state before external calls.
Capital DAO wrote its settlement flag after the router call; a probe token
proved it observable.

### 6.3 New surfaces this design introduces

Not present in Capital DAO. Treat as first-class.

1. **ERC-1155 receive hooks are a reentrancy surface.** `onERC1155Received` /
   `onERC1155BatchReceived` call back into the recipient. Capital DAO was
   ERC-20-only and had no equivalent. `split`/`merge`/`redeem` must be CEI and
   guarded. Consider whether ERC-20 clones per outcome are safer than ERC-1155.
2. **The denominator is as attackable as the numerator.** `pass > fail × (1+τ)`
   — pushing the *fail* pool **down** is exactly as good as pushing pass up, and
   the fail pool is usually the thinner book. Depth requirements apply to both.
3. **Governor self-amendment must be hard-bounded in code, not only timelocked.**
   A passed proposal that sets `τ = -100%` auto-passes everything thereafter.
   Bound τ, windows, stake and fee to sane ranges in the contract; the 7-day
   timelock is a second line, not the first.
4. **Stock Tokens have market hours.** A TWAP over a weekend or a halt is stale
   or degenerate. Template B needs an explicit staleness and trading-hours
   policy before it ships, plus Chainlink feed addresses we do not yet have.
5. **Executor replay and hash binding.** Bind the exact calldata batch hash;
   mark executed; never allow a re-run.

### 6.4 Crank ordering (subtle, gets it wrong easily)

Accrue **before** moving the observation. If nobody cranks for hours, the elapsed
time must accrue at the *old* observation; only then may the observation chase
spot, bounded by `cap × dt`. Getting this backwards lets an attacker suppress
cranking, push spot, then crank once and have a long-idle period retroactively
accrue at the new manipulated value.

Sizing: choose `maxChangePerSecond` so that a 2× move requires **~35 minutes of
uninterrupted pressure** against everyone who can fade it.

### 6.5 Sequencer-specific defences

Robinhood runs the sequencer. FCFS removes tip auctions, but the operator can
still delay, reorder within the arrival window, or stall cranks.

- Observation cap is **time-based, not tx-based**. Stalling the chain delays
  finalize; it does not let anyone jump the observation.
- Earliest finalize is `start + DELAY + WINDOW` **by timestamp**, plus an L1
  posting-lag check if the rollup inbox is readable.
- **If the timestamp gap exceeds N minutes, freeze the observation.** Do not let
  one skipped 2-hour block apply `cap × 7200`.
- Optional: snapshot the TWAP to L1 via the native bridge as an audit log. Not
  required for safety if the cap is tight.
- **The Security Council must never be an oracle for proposal outcome.**

### 6.6 Emergency powers

A Safe "guardian" that can **cancel a not-yet-finalized proposal** but cannot
move funds is reasonable. **A guardian that can execute is how you stop being a
futarchy.**

---

## 7. Canonical parameters

Changeable only by a prior passed proposal, and only within hard-coded bounds.

| Parameter | Value | Note |
| --- | --- | --- |
| Quote asset | USDG, 6 dp | scale explicitly, never assume 18 |
| `DELAY` (TWAP dark period) | 24 hours | markets trade, observations do not count |
| `WINDOW` (trading) | 72 hours | after the delay |
| `maxChangePerSecond` | sized for ~35 min per 2× | §6.4 |
| Timestamp-gap freeze | N minutes (TBD) | §6.5 |
| τ — team-sponsored | −3% | |
| τ — external | +3% | |
| Pool fee | 25 bps → DAO treasury | same as MetaDAO; do not get cute |
| `baseToStake` | per-DAO, ~2% of initial supply | returned at launch, not slashed |
| Param-change extra timelock | 7 days | on top of the normal lifecycle |
| Team performance tranches | 2× / 4× / 8× / 16× / 32× | of lagged launch TWAP |

---

## 8. Build order

1. **Spec + invariant tests** for `split`/`merge`/`redeem` and the lagged TWAP
   (Foundry). ~2 weeks. Tests before UI.
2. **Vault + two pools + governor on testnet 46630.** Run fake proposals with a
   $1k USDG book. **Try to steal a pass with a one-block spike — the test fails
   if you can.**
3. **Safe module + allowlisted actions.**
4. **One guinea-pig token (ours).** Three real proposals: (a) pay a contributor,
   (b) reject a mint, (c) change τ. Publish every crank.
5. **Shared liquidity + router.**
6. **Launchpad + performance package.**
7. **Stock-Token metric template** — once Chainlink Data Streams on HOODx/NVDAx
   are boringly reliable.
8. **Only then:** futarchy-as-a-service factory for other tokens on the chain.

Fork tests against real Uniswap run from step 2 onward, not at the end (§6.2d).

---

## 9. Risk register

| Risk | Status |
| --- | --- |
| Thin-market capture | Mitigated: anyone can deepen both books on a live proposal, and depth cuts price impact proportionally (D27). Not eliminated — it still depends on somebody choosing to, and the incentive to do so is untested in the wild. |
| Goodhart on token price | Inherent to the metric choice. Same as MetaDAO. Disclose. |
| Sequencer trust | Mitigated by time-caps, **not eliminated**. Disclose plainly. |
| US persons / securities | A launchpad governing a Stock-Token derivative is a lawyer problem. Keep Stock Tokens as **metric**, not as the fundraising asset, unless counsel says otherwise. |
| Preseed grief on conditional pools | **Designed out for V4 (D18)** — pre-creation absorbed by reclaiming the price of an empty pool; proven against the live PoolManager. Re-derive if the parent pool moves to another version. |
| Chainlink feeds unconfirmed | Blocks template B entirely. |

---

## 10. Explicit non-goals

- Do **not** try to govern Robinhood Chain upgrades or the L2 Security Council.
- Do **not** futarchy HOOD listed equity or Rothera event contracts — different
  legal object.
- Do **not** use event-market venues (Podium/World) as the governor. They
  resolve from documents; they do not execute treasury calls.
- Do **not** use vanilla Uniswap V2 TWAP as the decision oracle.
- Do **not** start with Hanson combinatorial markets. **Binary first.**
- Do **not** make this depend on the Capital DAO contracts.

---

## 11. Open decisions

Two are genuinely open. Four were answered by building, and are listed
underneath so the list stops hiding the real blockers behind settled ones.

### Still open

1. **`maxChangePerSecond`, and the timestamp-gap freeze threshold.** Every
   deployment so far has used placeholder values chosen to make a test or a demo
   run in reasonable time — the mainnet smoke test used 20,000/s with a 30s cap,
   which is far too fast for anything real. §6.4 fixes the shape of the answer
   ("a 2x move should need ~35 minutes of unbroken pressure") but the number has
   to be derived from the treasury being defended and the depth of the books
   defending it. **This is the last mechanism parameter without a real value.**

2. **Chainlink.** Feed addresses on this chain are still unconfirmed, and we do
   not know whether the deployment is Data Feeds, Data Streams, or both. Blocks
   template B (§5.6) entirely — the Stock-Token metric, which is the thing only
   this chain can do. Unchanged since July; it needs someone to ask Robinhood
   rather than more probing.

### Answered by building

| Was | Answer |
| --- | --- |
| Conditional token standard: ERC-1155 or ERC-20 clones? | **ERC-20 clones** (D6). Built. No receive-hook reentrancy surface, and they drop into any AMM. |
| Preseed defence for conditional pools | **Absorb, never reject** (D18), proven against the live V4 PoolManager. Moot for the conditional pools themselves now that they are our own CPMM with stored reserves (D19) — the bug class is absent rather than defended. |
| Uniswap V2 or V3 for the parent spot pool? | **V4** (D17). It holds roughly 8x the stablecoin depth of all V3 USDG/WETH tiers combined. The *conditional* pools are not Uniswap at all (D19). |
| Naming | **Hoodarchy** (D1). |

## 12. Where things live

| | |
| --- | --- |
| This project | `~/Documents/robinhood futurachy`, pushed to **https://github.com/frennadev/HOODARCHY** (public). The folder keeps its old name; see D1. |
| Contracts | `packages/contracts` (Foundry; forge-std, OZ, OZ-upgradeable, v3-core, v3-periphery, chainlink submodules) |
| Chain constants | `packages/contracts/src/config/RobinhoodChain.sol` ↔ `packages/chain/src/addresses.ts` — **keep both in sync**, `pnpm chain:check` re-verifies against live RPC |
| Product docs | `docs/` (16 files, pre-launch drafts, not legally reviewed) |
| Indexer | `packages/indexer` — Ponder. Proposals, markets, price series, trades, positions. Run against mainnet (D25). |
| Web | `packages/web` — **empty**. Owned by the web developer; this repo provides the backend, ABIs and addresses. |
| ABIs + deployments | `packages/chain/src/abis`, `packages/chain/src/deployments.ts` — committed so consumers never reach into Foundry's `out/`. `pnpm abis:check` fails on drift. |
| CI | `.github/workflows/ci.yml` runs without secrets on every push. `chain-drift.yml` runs daily and holds the checks only a live chain can answer — including whether the deployed contracts still speak our ABI (D24). |
| Capital DAO (reference only) | `~/Documents/capital dao` — **never a dependency** |
