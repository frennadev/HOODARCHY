# Introduction

> **Status: pre-launch draft.** Nothing described here is deployed or available
> to use yet.

## The problem

Most onchain companies are governed badly, and everyone involved knows it.

A token launches. Governance is promised. What arrives instead is a forum where
a handful of large holders and the founding team decide everything, ratified by
votes where turnout is thin and the outcome was never in doubt. Proposals pass
because the people who wrote them hold the most tokens. Treasuries worth tens of
millions get spent on things no outsider would have funded, and the people who
bought the token have no real say and no real recourse.

The failure has two halves, and they compound:

**Decisions are made by the wrong signal.** Token voting measures *who holds the
most tokens*, not *what is actually good for the company*. Those are different
questions. A large holder with a conflicting interest outvotes a small holder
who happens to be right. Being correct earns you nothing; being large earns you
everything.

**Capital isn't actually protected.** "The treasury is controlled by the DAO"
usually means it's controlled by a multisig held by the founders, with a
governance process that can be steered by the same people. When a team decides
to walk away with the money, the structure rarely stops them. It wasn't built
to.

## What Capital DAO does

Capital DAO is a platform for launching and governing companies where **markets
make the decisions and the treasury is structurally out of the founders'
reach**.

Concretely, three things are true of every company launched on Capital DAO:

**1. Decisions are settled by markets, not votes.**

When someone proposes a decision — a hire, an acquisition, a spend, a change of
direction — Capital DAO opens two markets: one that prices the company's token
*assuming the proposal passes*, and one that prices it *assuming the proposal
fails*. Traders buy and sell in both. If the market says the company is worth
more with the proposal than without it, the proposal executes automatically. If
not, it doesn't.

Nobody's opinion is polled. Nobody's tokens are counted. The question "will this
make the company more valuable?" is answered by people who are putting their own
money behind the answer, and who lose that money if they're wrong.

**2. The treasury can only move by market decision.**

Money raised at launch goes into a treasury contract that has no admin key, no
founder withdrawal function, and no multisig escape hatch. The only way funds
leave is a proposal that passed its market. The founders cannot take the money.
Not because they promised not to — because the contract has no function that
lets them.

**3. Founders get paid when the company performs.**

Founder and team allocations don't vest on a calendar. They unlock against
outcomes the market has confirmed. A team that delivers gets paid well. A team
that doesn't, doesn't. See [Pay for Performance](07-pay-for-performance.md).

## What we're actually aiming at

The honest ambition is this: **make it possible to fund a company onchain
without asking anyone to trust the founders.**

Not "trust them less." Not "trust them but with a timelock." Remove trust from
the parts of the arrangement where it currently does all the work — custody of
the money and control of the decisions — and replace it with mechanisms that
hold whether or not the team is honest.

If that works, a few things follow. Good teams can raise without needing a
reputation or a warm introduction, because backers don't have to believe them,
only check the contract. Bad actors find the structure unattractive, because
there's nothing to extract. And retail participants get something they almost
never get in this market: a position where the downside is the business failing,
not the team absconding.

That's the aim. It is not guaranteed to work, and [Risks](12-risks.md) is a
serious document, not a formality.

## Why this is possible now

Futarchy — the idea of governing by prediction market — was proposed by the
economist Robin Hanson in 2000. It stayed theoretical for two decades because it
needs cheap, fast, liquid markets to function, and those didn't exist.

They do now. MetaDAO demonstrated on Solana that futarchy works in production at
real scale: real treasuries, real decisions, real money. The mechanism is
proven. What's missing is a serious implementation on an EVM chain where
tokenized real-world assets, deep stablecoin liquidity, and a large existing
user base already live.

That's what Capital DAO is building, on [Robinhood
Chain](09-why-robinhood-chain.md).

## Where to go next

- The reasoning behind market-based governance: [Why Futarchy](02-why-futarchy.md)
- The actual mechanism, step by step: [How It Works](03-how-it-works.md)
- What you own when you hold one of these tokens: [Ownership Coins](04-ownership-coins.md)

---

*This document is informational. It is not an offer to sell securities, an
invitation to invest, or financial advice. See [Risks and
Disclosures](12-risks.md).*
