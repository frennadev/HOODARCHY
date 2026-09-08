# For Traders

> **Status: pre-launch draft.** Markets are not live. Nothing here is trading
> advice.

Futarchy only works if its markets are liquid and well-priced. That makes
traders load-bearing infrastructure rather than an afterthought — the mechanism
literally cannot function without people willing to take positions.

This page explains what there is to trade and where the edge comes from.

## What you can trade

### The spot token

The ownership coin itself, on Uniswap v3. A normal long or short on the company.

### Conditional markets

For each open proposal, two markets:

- **Pass market** (pCAP/pUSDG) — the company's value if the proposal executes
- **Fail market** (fCAP/fUSDG) — its value if the proposal is rejected

You acquire conditional tokens by depositing into the vault, which always
returns both sides:

```
deposit 100 CAP  ->  100 pCAP + 100 fCAP
```

Splitting is not a bet — you can recombine at any time and get your 100 CAP
back. **You take a position by selling one side and keeping the other.** Sell
your fCAP and hold pCAP, and you're betting the proposal passes and is good.

At resolution, the winning side redeems 1:1 for the underlying and the losing
side is worthless.

## Where the edge is

**Directional views on proposals.** The straightforward trade: you think the
market has mispriced a proposal's effect, so you take the other side. This is
the trade the mechanism is built to reward, and it's the one that produces the
governance signal.

**Arbitrage between conditional and spot.** The conditional markets and the spot
market are linked by an identity that must hold:

```
spot price  ~=  P(pass) x pass price  +  P(fail) x fail price
```

When it doesn't hold, there's a risk-managed arb. This is the highest-value
activity on the platform — it's what keeps the conditional prices honest, and
therefore what keeps governance working. It should be the most reliably
profitable thing to do here, and if it isn't, the design is wrong.

**Market making.** Both markets need continuous two-sided liquidity for the full
trading period, in a fee-earning position. Note the asymmetry to watch: your
inventory in the losing market goes to zero at resolution, so a market maker's
risk profile here is not the same as in a normal pair.

**Information advantage.** If you know something real about a company — you're a
customer, a competitor, an engineer who has read the code — futarchy is one of
the few venues that pays you for it directly and immediately. You don't have to
publish, argue, or convince anyone. You just trade, and the price moves.

## Risks specific to conditional markets

Ordinary token risk applies, plus several things that are particular to this
structure and catch people out.

**Losing-side tokens go to exactly zero.** Not "down a lot." Zero. If you hold
pCAP and the proposal fails, you have nothing. Conditional tokens are not
positions you can hold through an adverse outcome and wait out.

**Conditional markets are thinner than spot.** Slippage is worse, spreads are
wider, and exiting a large position before resolution may not be possible at a
price you like.

**Resolution is a hard deadline.** These markets settle at a known time. There
is no rolling, no extension, and no second chance.

**Both sides can be right and you can still lose.** You can correctly predict
that a proposal passes and still lose money if you paid too much for pCAP
relative to where the company trades afterwards.

**Timelocks delay redemption.** Settlement and redemption are not instantaneous.

**Smart contract risk.** These are new, unaudited-at-time-of-writing contracts.
See [Security](11-security.md).

## Getting set up

Robinhood Chain is a standard EVM L2 — anything that works on Ethereum or
Arbitrum works here.

| | |
| --- | --- |
| Network | Robinhood Chain |
| Chain ID | 4663 |
| RPC | `https://rpc.mainnet.chain.robinhood.com` |
| Gas token | ETH |
| Explorer | [robinhoodchain.blockscout.com](https://robinhoodchain.blockscout.com) |

Wallets: Robinhood Wallet, MetaMask, Rabby, Backpack, and other EVM wallets.
Bridging: the canonical Arbitrum bridge and several cross-chain routes.

Transaction costs are negligible — the chain was running at roughly **0.05
gwei** when we measured it (2026-07-26), so active position management and
arbitrage are economically viable in a way they wouldn't be on L1.

## A note on responsibility

The mechanism assumes traders are self-interested, not that they're
public-spirited. You do not owe anyone good governance.

But it's worth understanding what your trading does: when you correct a
mispriced proposal, you're not just making money, you're changing a real
outcome for a real company. Arbitrageurs are what stands between a malicious
proposal and a drained treasury. The profit motive and the security model are
the same thing here, which is the elegant part of the design.

## Next

- The mechanism: [How It Works](03-how-it-works.md)
- Full risk disclosure: [Risks and Disclosures](12-risks.md)
- [Glossary](14-glossary.md)

---

*Nothing here is financial or trading advice. Conditional tokens can and
routinely will go to zero. See [Risks and Disclosures](12-risks.md).*
