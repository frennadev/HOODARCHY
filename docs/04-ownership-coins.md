# Ownership Coins

> **Status: pre-launch draft.** The legal characterisation of ownership coins is
> under review and the language on this page may change materially.

## What an ownership coin is

An **ownership coin** is the token a company launches on Capital DAO. Holding it
gives you two things:

1. **A claim on the company's treasury**, enforced by contract.
2. **Influence over decisions** — not by voting, but by trading the markets that
   decide them.

The name is deliberate. Most tokens are not ownership of anything. They're
access passes, or fee-sharing arrangements, or pure speculation with a
whitepaper attached. An ownership coin is designed to be what it sounds like: a
proportional stake in a real entity with real assets and real decisions.

## What makes it different from a normal token launch

### High float, not a slow-drip cartel

The standard playbook launches 5–10% of supply and locks the rest. The float is
tiny, the price is trivially moved, and the published "valuation" is a fiction
derived from a market that couldn't absorb a serious sell order.

Then the unlocks start, and everyone who bought at the top discovers what the
other 90% was for.

Capital DAO launches target a **high float from day one** (*initial: majority of
supply liquid at launch*). This is worse for the optics of the launch price and
much better for everything else — the price means something, entering and
exiting is possible at size, and there's no overhang of insider supply waiting
to be distributed onto latecomers.

### The treasury backs it

At launch, the capital raised sits in a treasury that only a passed market can
move. This gives the token a floor that isn't sentiment: a claim on real assets
under contractual control. A company that raises $2M and hasn't spent it is a
company holding $2M, and that's verifiable onchain rather than asserted in a
blog post.

### Governance you can act on without permission

Holding an ownership coin doesn't get you a vote that doesn't matter. It gets
you access to markets where, if you're right about something, you can take a
position and both profit and change the outcome. Influence is available to
anyone with a correct view and capital to back it — not only to whales, and not
gated on being liked by the core team.

## Supply and distribution

Exact numbers are set per launch. The structural rules Capital DAO enforces:

| Rule | Why it exists |
| --- | --- |
| High float at launch | The price should be real and exits should be possible |
| Team allocation unlocks on performance, not time | See [Pay for Performance](07-pay-for-performance.md) |
| Treasury spendable only by passed market | See [The Treasury](06-treasury.md) |
| No hidden mint authority | Supply changes require a passed proposal |
| Full distribution published pre-launch | Nobody discovers an allocation later |

**No hidden mint authority** deserves emphasis. A great many "fixed supply"
tokens have an owner-gated mint function or an upgradeable proxy that can add
one. On Capital DAO the token's minting rules are fixed at deployment and any
change is a proposal that must clear its market like anything else.

## What an ownership coin is *not*

Being precise here protects everyone, and vagueness on this point is how people
get hurt.

- **It is not equity.** It does not give you shares in a legal company, a seat
  on a board, or the statutory rights a shareholder has. The claim it carries is
  the one written into the contracts, and nothing beyond that.
- **It is not a debt instrument.** Nothing is owed to you. There is no principal,
  no repayment, and no maturity.
- **It is not a promise of profit.** Companies fail. Treasuries get spent on
  things that don't work. Markets can be wrong for a long time.
- **It is not insured or guaranteed** by anyone, including Capital DAO.

**Regulatory status: TBD.** Depending on jurisdiction, structure, and how a
given launch is conducted, an ownership coin may be treated as a security. This
is under active legal review, and launches will be structured to comply with the
advice we receive. Nothing here should be read as a conclusion that ownership
coins are not securities. See [Risks](12-risks.md).

## The relationship to futarchy

Ownership coins and futarchy need each other, which is easy to miss.

Futarchy needs a metric to optimise. The ownership coin's price is that metric —
a continuously updating, hard-to-fake measure of how the company is doing that
every holder shares an interest in.

And the ownership coin needs futarchy for its claim to mean anything. A token
that represents a share of a treasury the founders can drain represents nothing.
The treasury's protection is what makes the claim real, and market governance is
what protects it.

Neither half works alone. Together they're the whole product.

## Next

- Launching one: [Launching on Capital DAO](05-launching.md)
- What secures the treasury: [The Treasury](06-treasury.md)
- Buying and trading: [For Traders](08-for-traders.md)

---

*Not an offer to sell securities or financial advice. See
[Risks and Disclosures](12-risks.md).*
