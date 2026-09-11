# Pay for Performance

> **Status: pre-launch draft.** Mechanism design is provisional.

## The problem with time-based vesting

Standard token vesting is a four-year cliff-and-linear schedule. Its defining
property is that **it pays for elapsed time, not for results.**

A team that ships nothing for four years vests exactly as much as a team that
builds something valuable. The only requirement is not quitting. This is a
strange thing to pay millions of dollars for, and it produces the outcomes you'd
expect: teams that go quiet after launch, projects maintained just enough to
justify the next unlock, and a steady supply of tokens hitting the market on a
schedule unrelated to whether anything worked.

Holders end up funding the *option* on a team's effort rather than the effort
itself.

## What Hoodarchy does instead

Team and advisor allocations unlock against **milestones**, not dates.

A milestone is a specific, objectively checkable condition — a revenue figure,
a usage number, a shipped product verifiable onchain. When it's met, the
corresponding tranche unlocks. When it isn't, the tokens stay locked, however
much time passes.

```
Team allocation: 20,000,000 CAP

  25%  ->  product live on mainnet, 1,000 monthly actives sustained 30 days
  25%  ->  $500,000 cumulative protocol revenue
  25%  ->  10,000 monthly actives sustained 90 days
  25%  ->  $2,000,000 cumulative protocol revenue
```

On day one this allocation is worth nothing. If the company works, it's worth a
great deal. That asymmetry is the entire point: the team is paid out of value
they actually created, and holders aren't diluted by a team that didn't create
any.

## How a milestone gets settled

Every milestone needs an answer to: *who decides it happened?* Getting this
wrong makes the whole scheme worse than time vesting, because now you have
disputes as well as misalignment.

Three settlement routes, in strong order of preference:

**1. Onchain and self-evident.** The condition is a fact the contract can read
directly — cumulative revenue through a known contract, unique addresses that
transacted, TVL sustained above a threshold. No human judgment enters. Use this
whenever it's remotely possible.

**2. Oracle-attested.** The condition depends on data from outside the chain and
is delivered by an oracle ([Chainlink](09-why-robinhood-chain.md) is the
designated oracle on Robinhood Chain). Weaker than option 1, because now the
oracle's correctness and liveness matter.

**3. Market-settled.** For genuinely unquantifiable milestones, the question
goes to a futarchy market: *is the company worth more with this tranche unlocked
than locked?* Slower and costlier than the other two, and reserved for cases
where nothing better exists.

**The rule we intend to hold to:** if a milestone can't be settled by route 1 or
2, it should probably be rewritten until it can. "Grow the community" is not a
milestone. "10,000 monthly active wallets, measured onchain, sustained 90 days"
is the same intent, made settleable.

## Designing milestones that don't backfire

Milestones are incentives, and incentives get gamed. Not always maliciously —
often just by a team optimising hard for the thing you told them to optimise
for.

**Metrics you can buy are metrics you will buy.** "10,000 wallets" is
satisfiable with an airdrop and a script. Prefer sustained metrics over
snapshots, revenue over vanity numbers, and retention over acquisition.

**Sequence matters.** Front-loaded unlocks pay before value is proven.
Back-loaded ones can leave a team with nothing for years and no reason to
continue. Ladder them so each tranche corresponds to a genuine step up.

**Leave room for pivots.** A company that discovers its original plan was wrong
should be able to change course without permanently forfeiting its allocation.
Milestones themselves can be amended — by proposal, priced by the market, like
anything else. This is a necessary escape valve and also an obvious attack
surface, which is why it goes through the market rather than through a committee.

**Don't over-specify.** Twelve milestones with elaborate conditions produce
twelve arguments. Three or four crisp ones work better.

## Interaction with the treasury

Milestone unlocks release **existing allocated tokens** from a vesting contract.
They do not mint new supply and they do not spend treasury funds. Total supply
is unaffected; only the circulating float changes, and it changes on a schedule
that tracks the company's performance rather than the calendar.

## Honest caveats

- **This is harder than time vesting.** It requires real thought upfront and
  gets disputed more. The upside is that the disputes happen at design time
  rather than after the money is gone.
- **Metrics distort behaviour.** Any metric you attach millions of dollars to
  will be optimised for, including in ways you didn't intend.
- **It can be too harsh.** A team that does excellent work in a bad market may
  miss every milestone and be paid nothing. Whether that's correct is genuinely
  debatable.
- **Amendment is a real attack surface.** The ability to change milestones must
  exist, and it will be probed.

## Next

- [Launching on Hoodarchy](05-launching.md) — where milestones get set
- [The Treasury](06-treasury.md)
- [How It Works](03-how-it-works.md)
