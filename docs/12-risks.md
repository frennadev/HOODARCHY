# Risks and Disclosures

> **Status: pre-launch draft. This page requires legal review before
> publication.**

This is the document that matters most if things go wrong. It is deliberately
blunt.

**Nothing described in this documentation is deployed, audited, or available to
use. There is currently nothing to buy.** When there is, everything below
applies.

## The short version

**You can lose everything you put in.** Not "you may experience volatility." The
tokens described here can go to zero, and conditional tokens go to exactly zero
by design on every single proposal. If losing your entire position would
materially harm you, do not participate.

## Protocol and mechanism risks

**Futarchy is lightly tested at scale.** The theory is 25 years old and the
production track record is a few years long, on one chain, at limited scale.
Capital DAO's implementation is new. Mechanisms that work in theory and in
limited practice can fail in ways nobody anticipated.

**Markets can be wrong.** Futarchy produces the market's best estimate. Best
estimates are frequently wrong. A proposal can pass its market and destroy the
company.

**Markets optimise the short term.** Settlement happens over days. Decisions
that look good over a 7-day window can be bad over five years. This is a known,
unsolved weakness of futarchy — not something Capital DAO has fixed.

**Thin markets price badly.** Every protection depends on liquid markets policed
by arbitrageurs. New launches and small companies will have thin conditional
markets, and their governance guarantees are correspondingly weaker.

**Manipulation is expensive, not impossible.** A well-capitalised attacker
willing to lose money on the trade to win the decision may find it worthwhile,
particularly against a thin market with a large treasury behind it.

**Conditional tokens expire worthless.** On every proposal, one entire side goes
to zero. This is normal operation, not a malfunction.

## Technical risks

**Smart contract risk.** The contracts are unwritten and unaudited. Audits
reduce risk; they don't remove it. Audited protocols are exploited regularly.

**Oracle risk.** Settlement depends on price oracles. Oracle failure or
manipulation can produce wrong outcomes. Chainlink availability on Robinhood
Chain is not yet confirmed.

**Chain risk.** Robinhood Chain is a young L2 with a centralised sequencer.
Downtime, censorship, reorgs, or bugs would affect settlement and execution.

**Stablecoin risk.** Treasuries and markets are denominated in USDG. A depeg,
freeze, or issuer failure would directly impair treasuries and market pricing.

**Dependency risk.** We rely on Uniswap v3, Chainlink, and the chain's bridges.
Failures propagate.

**Irreversibility.** Onchain transactions cannot be undone. A passed proposal
executes even if everyone later agrees it was a mistake.

## Company and business risks

**Most startups fail.** Companies launched here will fail at roughly the rates
startups fail everywhere. The structure protects against *theft*. It does not
protect against a business simply not working.

**Curation is not endorsement.** Capital DAO selecting a project means it met our
criteria. It is not a judgment that the business will succeed or that the token
is a good investment. We will select projects that fail.

**Milestones may never be met.** Team tokens may never unlock, teams may lose
motivation and leave, and a company can end up with a treasury and nobody
working on it.

**Treasury funds get spent.** A treasury is not a floor. The market can approve
spending that turns out to be worthless.

## Market and liquidity risks

**Volatility.** Expect large, rapid price movements.

**Liquidity risk.** You may be unable to exit at any price you find acceptable,
particularly in conditional markets and particularly at size.

**High float cuts both ways.** More supply liquid at launch means a real,
tradeable price — and more sell pressure available.

**No market maker of last resort.** Nobody is obliged to buy from you.

## Regulatory and legal risks

**Ownership coins may be securities. TBD.** Their legal characterisation is
under active review and will vary by jurisdiction and by how each launch is
structured. Nothing in this documentation should be read as a conclusion that
they are not securities.

**Regulation may change.** New rules could restrict or prohibit participation,
force changes to the protocol, or make tokens untradeable in your jurisdiction.

**Your jurisdiction may prohibit this.** Participation may be illegal where you
live. Determining that is your responsibility.

**Tax treatment is unclear.** Conditional token splitting, trading, and
expiry-to-zero may have tax consequences that are complex or unsettled. Get
professional advice.

**Access may be restricted.** Geographic restrictions, KYC/AML requirements, or
eligibility limits may apply.

## Governance risks

**You cannot outvote a bad outcome.** There is no vote. If you disagree with the
market, your recourse is to trade against it — which requires capital.

**Influence tracks capital.** Futarchy rewards being right *and* having money to
back it. Someone right and poor has less influence than someone right and rich.

**Proposals are permissionless.** Anyone can propose anything, including
malicious things. The market is the defence, and it is not perfect.

## Platform risks

**Capital DAO is early.** We are a small team building something novel. We may
fail, run out of funding, or make serious mistakes.

**Frontends can go down or be compromised.** Contracts are permissionless, but
most people reach them through a website, and websites get attacked.

**Support is limited.** There is no customer service that can reverse a
transaction or recover funds.

## Not advice

Nothing in this documentation is investment, financial, legal, or tax advice.
Nothing here is an offer to sell, or a solicitation of an offer to buy, any
security or financial instrument. No relationship is created by reading this.

Capital DAO makes no representation as to the accuracy or completeness of this
documentation and accepts no liability for reliance on it. Forward-looking
statements — plans, roadmaps, intended parameters — are not commitments and will
change.

Do your own research. Consult professionals in your jurisdiction. Only commit
capital you can afford to lose entirely.

---

*Last updated: 2026-07-26. This page must be reviewed by counsel before
publication.*
