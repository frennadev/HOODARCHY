# Glossary

> **Status: pre-launch draft.**

### Arbitrage (in this context)
Trading the gap between the conditional markets and the spot price when they
drift out of line. The most important activity on the platform: it's what keeps
conditional prices honest, and therefore what makes governance work.

### Conditional token
A token that pays out only if a specific outcome occurs. Each proposal creates
pass tokens and fail tokens. Exactly one set survives; the other goes to zero.
Written `pCAP`/`fCAP` for the ownership coin and `pUSDG`/`fUSDG` for the quote
asset.

### Conditional vault
The contract that splits an underlying token into pass and fail versions, and
merges or redeems them afterwards. Splitting is not a bet — you get both sides
and can always recombine.

### Decision market
The pair of markets — pass and fail — that together settle a proposal.

### Fail market
The market pricing the company **assuming the proposal is rejected**. Must be as
liquid as the pass market for the comparison to mean anything.

### Float
The portion of supply actually liquid and tradeable. Capital DAO targets high
float at launch, so the price is real and exits are possible.

### Futarchy
Governing by prediction market. Robin Hanson's formulation: *vote on values, bet
on beliefs* — decide democratically what you're optimising for, then use markets
to determine which actions achieve it. See [Why Futarchy](02-why-futarchy.md).

### Merge
Recombining equal amounts of pass and fail tokens back into the underlying.
Available at any time, before or after resolution.

### Milestone
A specific, objectively checkable condition that unlocks a tranche of team
tokens. Settled onchain where possible, by oracle otherwise. See
[Pay for Performance](07-pay-for-performance.md).

### Ownership coin
The token a company launches on Capital DAO. Carries a contract-enforced claim
on the treasury and influence through market participation. Not equity, not
debt, not a promise of profit. See [Ownership Coins](04-ownership-coins.md).

### Pass market
The market pricing the company **assuming the proposal executes**.

### Pass threshold
The margin by which the pass market must beat the fail market for a proposal to
execute (*initial: 2%*). Prevents noise-level differences from passing
proposals. The default is "don't."

### Proposal
An executable transaction submitted for market decision. Crucially, a proposal
*is* the calldata — not a description of intent implemented later. What the
market prices is byte-identical to what executes.

### Redemption
Exchanging winning conditional tokens 1:1 for the underlying after resolution.
Losing tokens redeem for nothing.

### Resolution
The moment a proposal is settled — TWAPs compared, outcome fixed, conditional
tokens become redeemable or worthless.

### Rug / unruggable
A rug is founders taking the treasury. "Unruggable" here has a specific meaning:
the treasury contract exposes no function that lets them, has no owner, and
cannot be upgraded to add one. See [The Treasury](06-treasury.md).

### Spot market
The ordinary market for the ownership coin itself, on Uniswap v3, unconditioned
on any proposal.

### Split
Depositing an underlying token into the vault to receive both pass and fail
versions. Not a bet.

### Timelock
The delay between a proposal passing and executing (*initial: 24–48h, TBD*).
Exists so humans can react if the mechanism fails.

### Trading period
How long conditional markets stay open before settlement (*initial: 7 days*).
Longer means more manipulation-resistant and slower.

### Treasury
The contract holding a company's assets. Spendable only by passed proposal.

### TWAP
Time-weighted average price. Settlement uses a TWAP over the full trading period
rather than a spot price, because a spot price can be pushed in a single block
while a multi-day average cannot.

### USDG
The native stablecoin on Robinhood Chain, used as the default quote asset.
**Has 6 decimals, not 18** — a recurring source of catastrophic accounting bugs.

### Vesting
Release of allocated tokens over time. Capital DAO replaces time-based vesting
with milestone-based unlocks.

---

See also: [How It Works](03-how-it-works.md) · [FAQ](13-faq.md)
