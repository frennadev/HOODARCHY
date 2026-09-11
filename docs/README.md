# Hoodarchy — Documentation

> **Status: pre-launch draft.** Hoodarchy is in development. Nothing described
> here is deployed, audited, or available to use yet. Parameters marked
> *initial* are proposals, not commitments. This documentation has **not yet had
> legal review** — see [Before You Publish](#before-you-publish) below.

Hoodarchy is a launch and governance platform built on Robinhood Chain. It
lets a company raise capital onchain, hand control of its treasury to a market
rather than to its founders, and make its biggest decisions by asking a simple
question: *does this make the company more valuable, or less?*

The answer isn't decided by a vote. It's decided by people putting money behind
their answer.

---

## Start here

| If you are… | Read |
| --- | --- |
| New to all of this | [Introduction](01-introduction.md), then [Why Futarchy](02-why-futarchy.md) |
| A founder thinking about raising | [Launching on Hoodarchy](05-launching.md) |
| A trader or investor | [For Traders](08-for-traders.md), then [Risks](12-risks.md) |
| An engineer | [Architecture](10-architecture.md), [Why Robinhood Chain](09-why-robinhood-chain.md) |
| Doing diligence | [Security](11-security.md), [Risks](12-risks.md), [Treasury](06-treasury.md) |

## All documents

**The idea**
1. [Introduction](01-introduction.md) — what Hoodarchy is and what it's for
2. [Why Futarchy](02-why-futarchy.md) — why markets decide better than votes
3. [How It Works](03-how-it-works.md) — the mechanism, end to end

**The product**
4. [Ownership Coins](04-ownership-coins.md) — what you actually own
5. [Launching on Hoodarchy](05-launching.md) — the founder's path
6. [The Treasury](06-treasury.md) — why the money can't walk away
7. [Pay for Performance](07-pay-for-performance.md) — unlocks tied to results
8. [For Traders](08-for-traders.md) — how to participate

**The technical side**
9. [Why Robinhood Chain](09-why-robinhood-chain.md) — the network, and what we verified
10. [Architecture](10-architecture.md) — contracts, data flow, open questions
11. [Security](11-security.md) — audits, keys, disclosure

**The fine print**
12. [Risks and Disclosures](12-risks.md) — read this one properly
13. [FAQ](13-faq.md)
14. [Glossary](14-glossary.md)
15. [Roadmap](15-roadmap.md)

---

## Before you publish

These files are portable Markdown with no site generator attached, so they can
be dropped into any docs host, CMS, or static site later without rework.

Two things must happen before any of this goes public:

1. **Legal review.** Several pages describe raising capital and buying tokens
   that represent claims on a company. Depending on jurisdiction and framing,
   that language carries securities implications. A lawyer needs to review at
   minimum [Introduction](01-introduction.md),
   [Ownership Coins](04-ownership-coins.md),
   [Launching](05-launching.md), and [Risks](12-risks.md) before publication.
2. **Fill the placeholders.** Search for `TODO` and `TBD`. Anything still marked
   is an open decision, not an oversight — resolve it or cut the claim.

## Conventions used here

- **Initial** — a proposed starting parameter, changeable by governance.
- **TBD** — a decision nobody has made yet.
- **Verified** — a fact we confirmed directly against Robinhood Chain, with the
  date of the check. See [Why Robinhood Chain](09-why-robinhood-chain.md).
