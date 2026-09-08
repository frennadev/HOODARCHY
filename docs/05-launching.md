# Launching on Capital DAO

> **Status: pre-launch draft.** Applications are not open yet. Process details
> and all figures below are provisional.

This page is for founders considering raising capital on Capital DAO.

## Read this part first

Launching here means giving up things founders normally keep. You should decide
whether that trade is acceptable before you go further, because it isn't
reversible afterwards.

**You will not control the treasury.** Not "control it with oversight" — you
will have no ability to move the money. Every spend, including ones you consider
obvious and urgent, goes through a market that takes days to settle and can
reject you. If you need discretionary spending authority, this is the wrong
platform.

**The market can tell you no.** Publicly, with a price attached. Your own
investors can bet against your proposal and profit when it fails. Some founders
find this clarifying and some find it intolerable; both reactions are
reasonable.

**Your allocation is tied to performance.** You don't vest for showing up. See
[Pay for Performance](07-pay-for-performance.md).

**Everything is visible.** Proposals, treasury movements, unlocks, and market
prices are all onchain and permanent.

What you get in exchange is the ability to raise from people who don't need to
trust you — which, if you don't already have a track record and a network, is
the difference between raising and not raising.

## The process

### 1. Application

You submit what the company is, who's building it, what you'd raise, and what
you'd do with it.

Capital DAO **curates**. We are not a permissionless launchpad and we don't
intend to become one. Early launches will be few and selected deliberately,
because the mechanism's credibility depends on the first cohort being real. This
is a deliberate constraint on growth and we accept it.

### 2. Structuring

If accepted, we work through:

- **Raise size and valuation** — what you're raising and at what terms
- **Token supply and distribution** — subject to Capital DAO's structural rules
  ([Ownership Coins](04-ownership-coins.md))
- **Milestones** — the specific, checkable conditions your allocation unlocks
  against ([Pay for Performance](07-pay-for-performance.md))
- **Governance parameters** — trading period, threshold, minimum liquidity
- **Legal structure** — jurisdiction, entity, and how the token relates to it

The milestones are the hardest part and the part worth spending real time on. A
vague milestone ("grow the community") can't be settled objectively and will
poison every unlock decision you make for years. A precise one ("10,000 monthly
active wallets, measured onchain, sustained for 30 days") settles itself.

### 3. Launch

Deployment happens as one atomic process:

1. Ownership coin deployed, supply fixed, no hidden mint authority
2. Treasury contract deployed — no admin key, no withdrawal function
3. Futarchy governance wired as the treasury's only spending path
4. Vesting contract deployed with milestones locked in
5. Public sale opens
6. Proceeds route directly to the treasury
7. Liquidity seeded on Uniswap v3

After step 7 there is no privileged actor. The founders hold tokens and a
proposal right, the same as anyone else.

### 4. Operating

From launch onward, running the company means writing proposals.

Day-to-day work doesn't need governance — you build, hire within budget, and
ship. What needs a proposal is anything that spends treasury funds or changes
the company's direction materially. In practice this means learning to write
proposals that are specific enough for a market to price, which is a skill, and
early ones are usually too vague.

## What a raise looks like

Illustrative, not a template:

```
Company:        Capital Widgets
Raise:          $2,000,000 USDG
Valuation:      $10,000,000 fully diluted
Token:          CAP, 100,000,000 fixed supply

Distribution
  Public sale         20,000,000  (20%)  liquid at launch
  Treasury            50,000,000  (50%)  released only by passed proposal
  Team                20,000,000  (20%)  unlocks on milestones
  Liquidity            8,000,000   (8%)  seeded to Uniswap v3 at launch
  Advisors             2,000,000   (2%)  unlocks on milestones

Float at launch:    28%  (public sale + liquidity)

Team milestones
  25%   product live on mainnet, 1,000 monthly actives sustained 30 days
  25%   $500,000 cumulative protocol revenue
  25%   10,000 monthly actives sustained 90 days
  25%   $2,000,000 cumulative protocol revenue

Governance
  Trading period      7 days
  Pass threshold      2%
  Quote asset         USDG
```

Note that the team's 20% is worth nothing on day one and everything if the
company works. That's the intended shape.

## What we look for

- **A real business.** Something that could plausibly generate value, not a
  narrative with a token attached.
- **Founders who want this.** The constraints have to look like a feature to
  you. If you're accepting them to access capital, it will go badly.
- **Milestones that settle themselves.** If we can't agree on how a milestone
  gets objectively verified, it isn't a milestone.
- **A legitimate reason to be onchain.** Not every company benefits from this
  structure.

## Costs

**TBD.** The fee model is not finalised. Whatever it is, it will be published
here in full before applications open, including any platform token allocation.

## Applying

**Applications are not open yet.** Follow the project for announcements — see
[Roadmap](15-roadmap.md) for timing.

## Next

- [Ownership Coins](04-ownership-coins.md)
- [The Treasury](06-treasury.md)
- [Pay for Performance](07-pay-for-performance.md)

---

*Not an offer to sell securities or a solicitation of investment. See
[Risks and Disclosures](12-risks.md).*
