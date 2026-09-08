# Why Futarchy

> **Status: pre-launch draft.**

## The one-line version

Robin Hanson's summary of futarchy is **"vote on values, bet on beliefs."**

Decide democratically *what you're trying to achieve*. Then use markets — not
votes — to work out *which actions achieve it*.

The split matters. "What should this company be optimising for?" is a question
about values, and there's no expert answer to it. "Will hiring this person
increase the value of the company?" is a question about facts, and some people
genuinely know better than others. Voting is a reasonable tool for the first
question and a bad tool for the second.

## Why voting fails at factual questions

Token voting has four failure modes, and every real DAO exhibits all of them.

**It measures wealth, not knowledge.** A vote asks "who holds the most tokens?"
and reports the answer as if it were "what's true?" Someone with deep knowledge
of why a proposal is a mistake loses to someone with more tokens and no view at
all.

**Being right is unrewarded.** If you vote correctly on a proposal that improves
the company, you capture only your pro-rata share of the improvement — the same
share you'd get by not voting. There's no return to effort, so nobody does the
work. Rational ignorance is the equilibrium, and low turnout is the symptom.

**Voters aren't accountable.** A voter who backs a disastrous proposal bears
almost none of the cost. They keep their tokens. They vote again next month.
Nothing about the system distinguishes the voter with a good track record from
the one with a terrible one.

**It's trivially capturable.** Delegation concentrates. Vote-buying markets
exist. Large holders coordinate off-chain. By the time a proposal reaches a
vote, the outcome is usually already known, which is why so many DAO votes pass
with 95%+ approval — the disagreement happened somewhere the token holders
weren't.

## Why markets do better

A prediction market inverts every one of those properties.

**Being right pays, directly.** If you know a proposal is bad and the market
disagrees, you take the other side and profit when you're proven correct. The
return to accurate private information is immediate and personal.

**Being wrong costs, directly.** Traders who consistently misjudge lose capital
and stop being able to move prices. The system defunds bad judgment
automatically — no reputation system, no moderation, no appeals.

**It aggregates information nobody collected.** Prices absorb what every
participant knows, including things no forum post would ever surface: a supplier
who knows the deal is shaky, an engineer who knows the timeline is fiction, a
competitor who knows the market is smaller than claimed. None of them have to
explain themselves. They just trade, and the price moves.

**Manipulation is self-defeating.** To push a decision your way, you must move a
price away from its fair value — which hands free money to everyone willing to
take the other side. In a vote, buying influence is cheap and the cost is fixed.
In a market, buying influence means subsidising your opponents, and the cost
scales with how wrong you are.

That last property is the one people underrate. Futarchy doesn't assume
participants are honest or well-intentioned. It assumes they're greedy, and
routes that greed into producing accurate prices.

## The measure Capital DAO uses

Every futarchy needs a metric that defines "better." Capital DAO uses **the
market value of the company's [ownership coin](04-ownership-coins.md)**.

It's a defensible choice for a company, if not for a government. It's
continuously observable, hard to fake, and it's the thing every holder of the
token already has in common. If a decision makes the company more valuable, the
people who own the company are better off. That's a real and meaningful
alignment, and it's the alignment token holders signed up for.

It's also a genuinely limited one, and we'd rather say so:

- **Price is noisy.** Markets move for reasons unrelated to the proposal.
  Capital DAO addresses this by comparing two *simultaneous* markets rather than
  measuring price before and after — see [How It Works](03-how-it-works.md) —
  which cancels out anything affecting both.
- **Price is short-horizon.** A market can favour a decision that looks good
  over the trading window and turns out badly later. This is a real weakness of
  futarchy, not a solved problem.
- **Price isn't everything.** Some things worth doing don't show up in a token
  price, and some things that raise a token price are bad. Futarchy optimises
  what you point it at. Point it carelessly and it will faithfully deliver
  something you didn't want.

Where these limits bind hardest, and what can be done about it, is covered in
[Risks](12-risks.md).

## What the evidence says

Futarchy sat unused for twenty years — not because it was disproven, but because
it needs cheap, liquid, fast markets, and running one on legacy infrastructure
was impossible.

MetaDAO changed that. Running futarchy in production on Solana, it governed a
real treasury through real decisions with real money at stake, and demonstrated
that the mechanism holds outside a thought experiment: markets stayed liquid,
decisions resolved, and the treasury did what the contracts said it would.

Capital DAO's contribution isn't the mechanism — that's Hanson's, and the
production proof is MetaDAO's. It's bringing a serious implementation to the EVM
and to a chain where tokenized assets and stablecoin liquidity already
concentrate.

## Next

- The mechanism in detail: [How It Works](03-how-it-works.md)
- How to trade these markets: [For Traders](08-for-traders.md)

## Further reading

- Robin Hanson, *Shall We Vote on Values, But Bet on Beliefs?* (2000) — the
  original paper
- [MetaDAO documentation](https://docs.metadao.fi) — futarchy in production
