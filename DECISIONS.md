# RH Futarchy — Decision Log

Every significant choice, in plain English: **what we decided, why, and what it
costs us.** Written so a non-engineer can follow it. Newest decisions go at the
bottom.

The detailed technical spec lives in [MECHANISM-REFERENCE.md](MECHANISM-REFERENCE.md).

---

## D1 — The project is called **RH Futarchy**

**Decided:** RH Futarchy. Folder stays `robinhood futurachy` for now (renaming a
folder mid-build breaks paths for no benefit); contracts, docs and package names
use "RH Futarchy".

**Why:** The existing docs called it "Capital DAO", but Capital DAO is now a
separate, already-deployed product. Two different things sharing one name would
confuse users and us.

**Cost:** The 16 files in `docs/` still say "Capital DAO" and need a pass.

---

## D2 — It lives in its own folder, completely separate from Capital DAO

**Decided:** RH Futarchy is its own project with its own git repository. It never
imports, links to, or depends on the Capital DAO code. If we want something from
Capital DAO, we copy it in.

**Why:** You asked for this directly. It means updating one project can never
break the other. Capital DAO is live on mainnet with real money in it; nothing we
do here should be able to touch it.

**Cost:** If we copy code from Capital DAO and they later fix a bug in it, we
don't get that fix automatically. We accept that — it's the price of safety.

---

## D3 — We are **not** building on Uniswap V4, because V4 is not on the chain

**Decided:** Do not build on Uniswap V4.

**Why:** You asked for V4. I checked the live chain rather than assume, and V4
simply isn't deployed on Robinhood Chain:

- Both addresses Uniswap normally uses for V4 are **empty**
- I also checked the V4 addresses from twelve other chains (Ethereum, Base,
  Arbitrum, Optimism, Polygon, BNB, Avalanche, Unichain, Blast, Worldchain, Ink,
  Zora) — **all empty**
- Your own July investigation found the same thing

What *is* live, checked at block 57,906,854:

| | Status |
| --- | --- |
| Uniswap V2 | Live — **41,375 trading pairs** |
| Uniswap V3 | Live and deep — the main USDG/WETH pool holds **5,510 WETH** |
| Uniswap V4 | **Not deployed** |

**Cost:** V4's "hooks" feature would have been an elegant way to build this. We
lose that. See D4 for how we get the same result without it.

**If this changes:** If V4 ships on Robinhood Chain later, D4 is designed so we
can move to it without redesigning anything.

---

## D4 — We are **not** writing our own AMM. We use real Uniswap pools plus a small
separate "price recorder"

This is the most important technical decision, so it's worth explaining properly.

**The problem.** Futarchy decides things by comparing two market prices. If
someone can shove a price around for a few seconds, they can steal the decision.
So we can't use a raw market price — we need a *deliberately slow* price that
takes a long time to move, no matter how hard someone pushes.

MetaDAO (the system we're modelling) solved this by **writing their own exchange**
with the slow-price logic built inside it. That works, but writing your own
exchange is where most of the security risk in a project like this lives.

**What we're doing instead.** We split it into two pieces:

1. **The trading happens in ordinary Uniswap pools.** Battle-tested code, already
   deployed here, holding 41,375 pairs in production. We write none of it.
2. **A separate small contract watches those pools and records a slow price.**
   It holds no money. It can't move funds. All it does is read the pool and do
   arithmetic — every few seconds it looks at the real price and is allowed to
   step its recorded price *a little bit* toward it, never more.

**Why this is better:** The dangerous part of an exchange is the part that holds
money and moves it around. Our recorder holds nothing, so even if it had a bug,
nobody's funds are at risk — the worst case is a bad decision, not a theft. And
we get exactly the same "slow price" protection MetaDAO has.

**How the slow price stops an attacker:** Suppose the real price is $1 and an
attacker slams it to $100 for one block. The recorder is only allowed to move a
capped amount per second, so it barely notices. To actually move the recorded
price, the attacker has to *hold* the fake price for a long time — around 35
minutes to double it — while everyone else is free to trade against them and take
their money. That's the whole security model.

**Cost:** The recorder only updates when someone "pokes" it. Anyone can poke it,
and we'll run a bot that does it constantly, but we have to make sure a long gap
between pokes can't be exploited — see D8.

---

## D5 — Conditional pools use **Uniswap V2**, not V3

**Decided:** V2 pairs for the pass/fail markets.

**Why:** Two reasons.

1. **Shared liquidity is the make-or-break feature.** Every proposal needs *two*
   markets ("if this passes" and "if this fails"). If both are thin, they're easy
   to manipulate, and MetaDAO's biggest real-world complaint is exactly this. The
   fix is to borrow liquidity from the project's main pool and split it into both.
   V2 makes this trivial — a V2 pool is just two piles of tokens, so you halve
   each pile. V3 liquidity is spread across price ranges and doesn't split
   cleanly.
2. **V2 pools are simpler to read.** Our price recorder just asks "how much of
   each token is in there?" V3 requires interpreting a much more complex state.

**Cost:** V3 has the deeper liquidity on this chain today. But that's for
*existing* tokens — conditional tokens are freshly created per proposal, so
neither pool type starts with liquidity anyway. We're not giving anything up.

**Note:** The project's *main* token pool can be V2 or V3 — that's the project's
choice, not ours. Only the per-proposal conditional pools are fixed to V2.

---

## D6 — Conditional tokens are plain **ERC-20** tokens, not ERC-1155

**Decided:** Each outcome gets its own ordinary ERC-20 token, created cheaply
using a standard "clone" pattern.

**Why:**

- **It's what users already have.** Every wallet, every price chart, every
  trading bot understands ERC-20. ERC-1155 support is patchy — people would see
  their positions as unrecognised NFT-ish objects.
- **Uniswap needs ERC-20.** D5 puts these tokens in real Uniswap pools. Uniswap
  pools only hold ERC-20. This decision follows from D5.
- **It removes a whole category of attack.** ERC-1155 calls back into whoever
  receives a token, which is a classic way attackers re-enter a contract
  mid-operation and confuse its bookkeeping. Plain ERC-20 has no such callback.
  We deleted the risk instead of defending against it.

**Cost:** Slightly more gas to create four tokens per proposal than to create
four entries in one ERC-1155 contract. Clones make this cheap — a few cents.

---

## D7 — Seeding a pool must **absorb** an attacker's donation, never reject it

**Decided:** When we create and fund a proposal's markets, if someone has already
sent tokens to that pool address, we fund the difference rather than refusing.

**Why:** We already got hit by this exact bug on Capital DAO, and it was the most
serious finding in that audit. Pool addresses are predictable, so an attacker can
send a tiny amount to a pool *before* it exists. On Capital DAO, **three cents**
of USDG permanently prevented a raise from ever launching — and it couldn't be
undone.

That would be far worse here. Capital DAO created one pool per fundraise. RH
Futarchy creates two pools **per proposal**. The same three cents could block
every proposal on the platform, forever.

The fix is proven — it's live on Capital DAO mainnet today. Absorbing the
donation also makes the starting price *exactly* right, where the old approach
made it only approximately right. It's strictly better, not a compromise.

**Cost:** None. The attacker's donation just becomes a small windfall for the
treasury.

---

## D8 — The price recorder adds up time **before** it moves, and ignores very long gaps

**Decided:** Two rules inside the recorder:

1. When poked, first credit the time that has passed **at the old recorded
   price**, and only then step the price toward the market.
2. Treat any gap longer than a few minutes as if it were only a few minutes, for
   the purpose of how far the price is allowed to step.

**Why:** Without rule 1, an attacker could stop anyone poking the contract, shove
the price, poke once, and have hours of quiet time credited at their fake price.
Without rule 2, a long gap would grant one enormous step, which is the same
attack by another route.

This is also our defence against the chain operator. Robinhood runs the sequencer
and could, in principle, delay transactions. These two rules mean delay can only
postpone a decision — it can never change one.

**Cost:** In a genuine outage, the recorded price lags reality. That's the safe
direction to fail.

---

## D9 — First version decides on **token price only**

**Decided:** Version one asks only "would the project's token be worth more?"
The Stock-Token version (deciding based on HOODx, NVDAx etc.) comes later.

**Why:** The Stock-Token version is the genuinely novel thing only this chain can
do, and it's the eventual headline. But it needs Chainlink price feed addresses,
which **we still don't have** — the chain's feed addresses are unconfirmed. It
also needs a policy for stock market hours, because a price average taken over a
weekend is meaningless.

**Cost:** We ship the less exciting version first. Getting Chainlink feed
addresses confirmed is the single task that unblocks the interesting one.

---

## D10 — The treasury is a Safe that only the market can move

**Decided:** Each project's money sits in a Safe (the standard Ethereum
multisig). It has no human signers who can move funds. The only thing that can
spend from it is our Executor contract, and only after a proposal has passed.

**Why:** This is the actual product. "You cannot rug, because the treasury's only
signer is a market." Everything else is plumbing.

**Cost:** If the market makes a bad decision, no human can stop it. That's the
point, but it must be said out loud. We will allow a "guardian" that can *cancel*
a proposal before it finishes, but **never** one that can execute or move money —
a guardian who can spend is how you stop being a futarchy.

---

## D11 — Proposals can only do things from an approved list

**Decided:** A passed proposal can move money, mint tokens within limits, manage
liquidity, and change its own settings. It **cannot** change who issues Stock
Tokens, replace the core contracts, or touch the chain's own machinery.

**Why:** Otherwise someone writes a proposal that says "give me the keys", buys a
thin market for twenty minutes, and takes everything. The market is good at
pricing "is this a good idea"; it is not a substitute for not handing out the
keys.

Settings that change the rules themselves (like how big a margin a proposal needs
to win) get an **extra 7-day delay**, and are additionally capped in the code —
so a passed proposal can't set the winning margin to "always win".

**Cost:** Genuinely new kinds of action need a contract upgrade rather than just
a proposal. Deliberate.

---

## D12 — The price recorder is anchored, not read, at launch

**Decided:** When a proposal's markets start, we *tell* the recorder what the
starting price is. It does not look at the pool to find out.

**Why:** If it read the pool, someone could send a tiny amount to the pool
address before launch and set the starting price to whatever they liked. Anchoring
it closes that off entirely, and it costs nothing — we already know the price,
because we're the ones seeding the pool.

**Cost:** None. Whoever launches the proposal must pass the right number, and the
seeding code already computes it.

---

## D13 — Conditional token addresses are deliberately predictable

**Decided:** The PASS/FAIL tokens for a proposal are created at addresses we can
work out in advance, and the vault exposes a function to compute them.

**Why:** The user interface, the seeding logic and the price recorder all need to
know where the pools will be before they exist. Predictable addresses make that
straightforward.

**Cost:** This is exactly the surface D7 is about — predictable addresses mean an
attacker can send dust to a pool before it exists. That's why D7 is mandatory
rather than optional. We accepted the predictability and defend against its
consequence, rather than trying to hide the addresses.

---

## D14 — What we built first, and what we deliberately left out

**Built and tested (28 tests passing):**

- **The vault** — takes in a token, gives out matched PASS and FAIL claims, and
  swaps the winning claim back for the real token after the decision. The rule it
  exists to enforce is *"the tokens locked up always exactly equal the claims
  issued"*, and the tests check that holds after every possible sequence,
  including with randomly generated amounts.
- **The price recorder** — the slow-price mechanism from D4, with the two
  ordering rules from D8.

**The attack tests are the point.** They are written to *try to break it*:

| Attack tried | Result |
| --- | --- |
| Slam the price 100× for one block | Moves the settled average **less than 0.1%** |
| Push 100× and hold it | Takes **~35 minutes** just to double the recorded price |
| Stop anyone updating it, then push and update once | Quiet period is credited at the **old** price — the attack gains nothing |
| Stall the chain for 30 days, then update | Only **one capped step** is allowed, not 30 days' worth |
| Any random price, any random gap (512 random tries) | The recorded price **never** moves faster than its limit |

**Not built yet:** the Governor (runs proposals and compares the two averages),
the Executor (the Safe module that spends the money), the pool seeding with
shared liquidity, and the launchpad. Those come next, in that order.

**Why this order:** These two pieces are the ones where a mistake loses money or
lets someone steal a decision. Everything after them is orchestration built on
top. Getting these right first means the rest can't be built on sand.
