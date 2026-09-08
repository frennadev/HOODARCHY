# FAQ

> **Status: pre-launch draft.**

## Basics

**What is Capital DAO in one sentence?**
A platform for launching companies onchain where markets — not votes — make the
decisions, and where the treasury is structurally out of the founders' reach.

**Is it live?**
No. Nothing is deployed, audited, or available to use. See
[Roadmap](15-roadmap.md).

**Who is it for?**
Founders who want to raise without asking backers to trust them, traders who
want to be paid for being right, and people who want to own a piece of a company
whose money can't be taken.

**How is this different from a normal DAO?**
A normal DAO votes. Token voting measures who holds the most tokens, not what's
true, and rewards nobody for being right. Capital DAO replaces the vote with a
market where being right pays and being wrong costs.

**Is this just a MetaDAO clone?**
Futarchy is Robin Hanson's idea, and MetaDAO proved it works in production on
Solana. We're not claiming either. Capital DAO is a fresh EVM implementation on
Robinhood Chain — different chain, different tech stack, purpose-built contracts
rather than a port. The mechanism is prior art we're building on, and we'd
rather say so than pretend otherwise.

## How it works

**How does a decision actually get made?**
Two markets open on every proposal: one pricing the company if it passes, one if
it fails. After the trading period (*initial: 7 days*), if the pass market's
time-weighted price beats the fail market's by the threshold (*initial: 2%*),
the proposal executes automatically. See [How It Works](03-how-it-works.md).

**What stops someone manipulating the price to force a decision?**
Settlement uses a time-weighted average over the full period, and the oracle
caps how far the price can move per observation. To force an outcome you must
hold a price away from fair value for days while everyone else takes free money
off you. Cost scales with how wrong you are — unlike vote-buying, which is a
fixed cost.

**What if nobody trades a proposal's markets?**
It fails. Below minimum liquidity, proposals are rejected by default rather than
settled on a price nobody believes.

**Who can submit a proposal?**
Anyone, subject to a bond (*TBD*) to prevent spam.

**How long does a decision take?**
*Initial: 7 days* of trading, plus a timelock (*initial: 24–48h*) before
execution. Deliberately slower than a founder deciding alone — that's the cost
of the guarantee.

## Tokens and money

**What do I own when I hold an ownership coin?**
A contract-enforced claim on the company's treasury and the ability to influence
decisions by trading its markets. It is **not** equity, not debt, and not a
promise of profit. See [Ownership Coins](04-ownership-coins.md).

**Can founders take the treasury?**
No. The treasury contract has no withdrawal function, no owner, no multisig
escape hatch, and no upgrade path to add one. Funds move only via a passed
proposal. See [The Treasury](06-treasury.md).

**What if they write a proposal to send themselves the money?**
The pass market would price a company with no assets — near zero — and the fail
market a company that kept its money. The proposal is rejected, and everyone who
noticed profits. Futarchy is most reliable exactly where the theft is most
obvious.

**What are conditional tokens and can I lose money on them?**
Tokens that only pay out if a specific outcome occurs. Splitting your tokens
into pass and fail versions is *not* a bet — you can always recombine. You take
a position only by selling one side. And yes: the losing side goes to exactly
zero on every proposal.

**Is there a Capital DAO platform token?**
**TBD.** Not decided. If there is one, its terms will be published in full
before any launch.

**What are the fees?**
**TBD.** Published in full before applications open.

## Participating

**How do I connect?**
Robinhood Chain is a standard EVM L2 — chain ID **4663**, RPC
`https://rpc.mainnet.chain.robinhood.com`, gas paid in ETH. MetaMask, Rabby,
Robinhood Wallet, Backpack and other EVM wallets all work.

**Is it expensive to use?**
No. Gas was around **0.05 gwei** when we measured it (2026-07-26), which is what
makes the constant small transactions futarchy needs economically viable.

**How do I launch my company here?**
Applications aren't open. When they are, expect curation rather than
permissionless listing — see [Launching](05-launching.md).

**Why do you curate instead of letting anyone launch?**
Because the mechanism's credibility depends on the first cohort being real
businesses. We accept that this limits growth early on.

## Risk and safety

**Has this been audited?**
No. Nothing is written yet. Minimum two independent audits, published in full,
before any mainnet deployment. See [Security](11-security.md).

**Is my money safe?**
There is nothing to put money into yet. When there is: the treasury structure
protects against founders taking funds. It does not protect against the business
failing, the market being wrong, a contract bug, or your own trading losses. See
[Risks](12-risks.md).

**Is an ownership coin a security?**
**Under legal review.** It may be, depending on jurisdiction and structure.
Nothing in these docs should be read as a conclusion that it isn't.

**What's the biggest weakness of futarchy?**
Two honest ones. It optimises over the settlement window, so it can favour
decisions that look good over days and turn out badly over years. And it needs
liquid markets — thin markets give weak guarantees. Neither is solved.

## Technical

**Why Robinhood Chain?**
Native stablecoin liquidity, negligible fees, a fully deployed Uniswap v3, and a
large existing retail user base. See
[Why Robinhood Chain](09-why-robinhood-chain.md).

**Which Uniswap version?**
v3 — verified deployed. v4 was **not** found at either canonical PoolManager
address, so the AMM layer sits behind an interface that a v4 implementation can
satisfy later.

**Are you forking Gnosis CTF?**
No. It's `pragma ^0.5.1` and can't compile with 0.8.x, and it's built for
arbitrary outcome partitions when we need one binary case. We take the idea and
write purpose-built 0.8 vaults. See [Architecture](10-architecture.md).

**Is it open source?**
Intended, yes. Licensing **TBD**.

**Can I run my own frontend?**
Yes — the contracts are permissionless. Encouraged, in fact: a protocol reachable
through only one website has a single point of failure.

## Next

- [Introduction](01-introduction.md)
- [How It Works](03-how-it-works.md)
- [Glossary](14-glossary.md)
- [Risks and Disclosures](12-risks.md)
