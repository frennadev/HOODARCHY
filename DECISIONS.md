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

## D3 — ~~We are not building on Uniswap V4~~ **CORRECTED: V4 is on the chain**

> **This decision was wrong and is withdrawn.** Superseded by D15. Kept here
> rather than deleted, because the reasoning error is worth remembering.

**What I originally decided:** Do not build on Uniswap V4, on the grounds that
it isn't deployed on Robinhood Chain.

**Why that was wrong:** I checked 14 addresses — the 2 Uniswap normally uses,
plus the V4 addresses from 12 other chains — found all of them empty, and
concluded V4 was absent. **That method cannot prove absence.** Uniswap V4 is
deployed to a different address on every chain, so "not at any address I happened
to know" was never evidence of "not deployed". You said V4 had the most volume on
Robinhood Chain, and you were right.

**Where it actually is** (verified live, and cross-checked — the PositionManager's
`poolManager()` points back at the PoolManager, so these are genuinely a matched
pair, not two unrelated contracts):

| | Address | Size |
| --- | --- | --- |
| V4 PoolManager | `0x8366a39CC670B4001A1121B8F6A443A643e40951` | 48,021 bytes |
| V4 PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` | 47,757 bytes |

**How I found out:** Capital DAO migrated itself to V4 and recorded the addresses.
I should have looked at how the chain's own ecosystem deploys, rather than
pattern-matching addresses from other chains.

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

## D5 — ~~Conditional pools use **Uniswap V2**, not V3~~ **Superseded by D17**

> **Superseded, not withdrawn.** This decision was sound given what we believed
> at the time — the choice really was V2 or V3, because we thought V4 was not
> here. D3 was wrong about that, which put a third option on the table. The
> reasoning below still holds and is the reason the shared-liquidity question in
> D17 is the hard part.

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

**Built and tested (121 tests passing — 100 unit, 21 against the live chain):**

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

---

## D15 — The oracle no longer knows which Uniswap version it is reading

**Decided:** Split the price recorder in two. The recorder itself now takes a
**price source** — a tiny read-only contract whose only job is to answer "what is
the price right now?". Today there's a Uniswap V2 source; a V4 one drops in
without touching the recorder.

**Why:** D3 was wrong about V4, which means D5 (which pool to use) is now a real
open question rather than a forced one. Rather than guess again, I removed the
need to guess: the part that carries the security — the rate-limiting and
time-weighting — no longer cares which AMM is underneath.

**Why this matters beyond the mistake:** The security argument for this design is
that the recorder holds no money and is small enough to reason about. Welding it
to one AMM version would have meant re-auditing that security core every time the
pool choice changed. Now the pool choice is a swappable part, and the piece that
must be correct stays still.

**Cost:** One extra contract and one extra external call per price read. Trivial.

**Status of D5 (V2 vs V4 for the pass/fail pools):** **now genuinely open.** In
V4's favour: it's where the chain's volume is, Capital DAO just moved there, and
V4 "hooks" let a pool update the recorder automatically on every trade instead of
waiting to be poked. Against it: V4 is newer and more complex than V2, and the
shared-liquidity trick in D5 — splitting a normal pool's two token piles into the
two conditional markets — is straightforward in V2 and needs rethinking in V4.
All tests pass either way, so this could be decided on merit rather than urgency.
**Resolved in D17: V4.**

---

## D16 — Capital DAO moved to V4; our notes on it are now historical

**Decided:** Record that Capital DAO migrated from Uniswap V2 to V4, and stop
describing its V2 usage as current.

**Why:** Several of our notes cited "Capital DAO seeds V2 pools in production" as
the proof that V2 was live here. That proof is now historical — still true that V2
exists, but Capital DAO no longer uses it.

**What did not change:** The security lessons we inherited from the Capital DAO
audit (D7 especially — absorb a donation rather than reject it) are about
*predictable addresses*, which V4 has too. They still apply in full.

---

## D17 — The pass/fail markets will run on **Uniswap V4**

**Decided:** V4 for the per-proposal conditional pools. This replaces D5.

**Why:** You chose it, and the reasons hold up. V4 is where the chain's money
actually is — its pools hold about **$45M**, against roughly $5.6M across all
three V3 USDG/WETH pools. Building the markets somewhere the liquidity isn't
would be starting at a disadvantage for no reason.

The bigger prize is **hooks**. A hook is code a pool runs automatically on every
trade, which means the pool can update our slow price itself. Today something has
to "poke" the recorder, and D8 exists entirely to make sure a gap between pokes
can't be exploited. With a hook, trading and recording happen together and that
whole class of problem largely goes away.

**What's built and tested now:** a V4 price source, reading the pool through the
same swappable interface D15 introduced. The recorder itself was not touched —
that was the entire point of D15, and it paid off immediately. **47 tests pass**,
including two that read a real live V4 pool on mainnet and correctly price ETH at
about $2,498 across the 18-decimal / 6-decimal boundary.

### Two things we found by checking, that would have been expensive to assume

**1. An "initialised" V4 pool is not necessarily a real one.** This chain carries
a V4 pool that was created, never funded, and left parked at the maximum price
the format can represent. Its stored price reads back as a perfectly well-formed
number and is complete fiction. A price source that only read the price field
would have handed the recorder that fiction with total confidence. Ours checks
the pool actually holds liquidity first, and a test reads that exact live pool to
prove it stays refused.

**2. V4 lets you see a price nobody could have traded against.** V4 allows one
transaction to open the pool, move it anywhere, act on it, and put it back before
finishing. The recorder's rate limit already bounds the damage, but the security
argument in D4 is stronger than "bounded" — it's that moving the recorded price
means *holding* a false price in the open where other traders can profit by
fading you. A price that exists only inside someone's own transaction was never
exposed to that. So the source refuses to answer at all while the pool is
mid-transaction. Cheap to do, and it keeps D4's argument true rather than merely
survivable.

**Cost, stated plainly:** V4 is newer and more complex than V2, and reading it
means depending on the internal storage layout of Uniswap's contract rather than
a published getter. We pinned that layout with a test that reads the live chain,
so if Uniswap ever changes it we fail loudly instead of silently pricing things
wrong. That is the right failure direction, but it is a real dependency and worth
knowing about.

**Still open, and genuinely the hard part:** the shared-liquidity trick from D5.
Borrowing a project's main pool and splitting it into the two conditional markets
is easy in V2, where a pool is just two piles of tokens you halve. V4 keeps
everything in one shared vault, so the split has to be done differently. Nothing
is blocked — but this is the piece that needs designing, and D5's reasoning about
why it matters is still the best statement of the stakes.

**Not started:** creating and seeding V4 pools (D7's absorb-the-donation rule has
to be re-derived for V4's accounting, since there is no per-pool address to
donate to — this may be simpler on V4, but "may be" is not "is"), and the hook
itself.

---

## D18 — On V4, a proposal's pool can be **stolen before it exists** — and the
seeder must take it back rather than give up

I set out to design shared liquidity. The first question turned out to be whether
we can safely *create* the two markets at all, and the answer was no — not
without this.

**The hazard, confirmed against the live chain.** A V4 pool is identified by the
addresses of its two tokens. Our conditional token addresses are deliberately
predictable (D13), so anyone can work out a future proposal's pool in advance.
Creating a pool in V4:

- is open to anyone,
- costs only gas,
- needs **no tokens at all** — I confirmed a pool can be created for two addresses
  that hold no code whatsoever, so the attack lands before the tokens are even
  deployed,
- and **cannot be done twice**.

So an attacker sits on a proposal's pool, sets the price to something absurd, and
when our seeder tries to create it properly the call fails. Every proposal on the
platform, blocked permanently, for pennies each.

**This is the Capital DAO bug again.** Audit finding H-1 was three cents of USDG
sent to a predictable pool address, which stopped a raise from ever launching and
could not be undone. D7 was written in response, and it says the answer is always
the same: **absorb the interference, never reject it.** Different chain, different
DEX, same shape. It is worth noting the rule caught this before the code existed.

**The defence, and why it costs nothing.** An empty pool has nothing to trade
against. So the seeder can push the price back wherever it wants and no tokens
move — the pool has none. Concretely: if the pool already exists, don't try to
create it; take the price back and continue as normal.

I did not take that on trust. There are now four tests running against the **real
V4 contract on mainnet** which show the attack succeeding, our creation call
failing exactly as feared, and the seeder reclaiming the price — from too high,
and from too low. Cost of the recovery: roughly 111,000 gas, a fraction of a cent
here.

**What this changes:** seeding a conditional pool is never "create it", it is
"make sure it reads the price we intend, whoever got there first". The V2 rule
was absorb a *donation*; the V4 rule is absorb a *pre-creation*. Same principle,
adapted rather than copied — which is what D7 anticipated when it said predictable
addresses mean the defence is mandatory rather than optional.

**Still open, and still the hard part.** This makes the pools safe to create. It
does not yet put liquidity in them. The shared-liquidity design — borrowing from
the project's main pool so both markets have depth — is the remaining piece, and
D5 is still the best statement of why it matters.

One thing already settled by it: the borrowed liquidity should sit across the
**full price range** rather than concentrated. V4 lets liquidity be placed in a
narrow band, which is more efficient, but a band the price moves outside of stops
quoting entirely — and our recorder reads these pools to decide the proposal. A
market that can silently stop having a price is not one a decision should rest on.
Full range cannot go out of range, and it is how V2 behaved anyway.

---

## D19 — Back to the MetaDAO model: the pass/fail markets are **our own small
pool**, not a Uniswap pool

**Decided:** Build the two per-proposal markets as a purpose-built
constant-product pool with the slow-price logic attached, the way MetaDAO does.
This reverses D17, narrows D4, and finally does what our own spec said in §5.2
all along. Uniswap V4 stays — for the project's *main* pool, where it belongs.

**Why — you were right, and the evidence is in our own files.** MetaDAO has run
96 proposals across 14 organisations on this design. We are porting a system that
works, not inventing one. Where we departed from it, we paid for it.

The spec never actually agreed with the departure. §5.2 has said from the start:
*"Do not use vanilla Uniswap V2 for these... We want the observation clamp inside
the pool."* Yesterday's V4 work rewrote a summary row to say the opposite, and the
document has been contradicting itself ever since. That is a good signal we drifted
rather than decided.

**The argument that actually decides it.** You use a big exchange to reach its
liquidity and its traders. D5 already wrote down that this cannot apply here:

> *conditional tokens are freshly created per proposal, so neither pool type
> starts with liquidity anyway.*

The pass/fail markets are brand-new tokens minted for one proposal and worthless
after it resolves. There is no existing liquidity to plug into and no passing
trade to catch. So we took on all of V4's difficulty in exchange for a benefit
that structurally cannot exist for these particular pools.

**What that difficulty actually was.** Every one of these came out of the last two
days, and none of them exists in MetaDAO's design:

| Problem we hit | Why it existed |
| --- | --- |
| Reading pool state through assumed storage slots | V4 has no getter; we depend on Uniswap's internal layout |
| A price readable mid-trade, that nobody could trade against | V4's flash accounting |
| A pool quoting a confident, fictional price | V4 pools can be created and never funded |
| Anyone can brick a proposal for gas (D18) | V4 pool creation is open, unrepeatable, and needs no tokens |
| Shared liquidity is unsolved | V4 keeps everything in one shared vault |
| Full-range vs concentrated | V4 has ranges at all |

**And the class of bug we inherited from Capital DAO disappears.** H-1 and D18 are
both the same shape: someone touches a pool before we do. Both are only possible
because the pool's price depends on state a stranger can reach. If we write the
pool, we create it ourselves and store the reserves explicitly instead of reading
token balances — so a donation changes nothing, and nobody can get there first.
D7's rule stops being a defence we implement and becomes a bug we do not have.

**What D4 got right, and where it went too far.** D4's instinct — *the dangerous
part of an exchange is the part that holds money* — is sound and stands. But it
concluded "therefore use someone else's exchange", and that was too broad. The
conditional pool is not a general exchange: it is a constant-product pool holding
two throwaway tokens for three days, with no router, no fee tiers, no ranges, and
no external integrations. It is a few hundred lines. Integrating V4 safely is
turning out to be more code, and more subtle code, than writing it.

**What we keep, and what it cost.** The V4 price reader keeps its job — the
project's main TOKEN/USDG pool really is on V4, and we need to read it to anchor a
proposal's starting price and to price the team's performance tranches. D18's
finding stays on the record because it applies wherever we touch a V4 pool we did
not create. The genuinely wasted work is small: roughly a day, and it bought a
verified map of V4 that we will still use.

**Cost, stated plainly:** we write and must audit a pool that holds real money —
exactly the thing D4 wanted to avoid. It is small and it is a direct port of a
design with production history, but the bytecode will be ours and new. That is the
price of the whole list above going away, and on balance it is worth paying.

**How the slow price attaches.** MetaDAO puts the clamp inside the pool. We keep
our already-tested recorder as a separate contract and have the pool update it on
every trade. Behaviourally identical — the observation moves as trading happens,
so nothing depends on a bot remembering to poke — but the security-critical
arithmetic stays in the one small contract we have already attacked in tests, and
the pool cannot corrupt it. The update happens **before** a trade is applied, so
no one can move the price and collect the movement in the same transaction.

---

## D20 — The slow price is averaged over a **window that closes on schedule**, so
waiting cannot change a decision

**Decided:** Each proposal's recorded average runs from the end of the quiet
period to a fixed end time, and stops. Once that moment passes the number is
frozen — reading it a second later, a day later or a year later gives the
identical answer.

**Why: it was a live hole, and a bad one.** Our recorder averaged from the start
of trading up to *whenever someone asked*. That means whoever calls "finalise"
chooses the end point, and an attacker does not have to call it at all.

The attack: spend the real, expensive ~35 minutes pushing the price near the end
of trading — that part is supposed to be costly, and it is. Then simply **decline
to finalise**. Every additional second keeps crediting the average at the
manipulated price. Patience converts a bounded, expensive manipulation into an
unbounded free one.

**How bad, measured.** In the test, after an hour of pushing at the close the
average sits at **1.01** — the manipulation barely registers, exactly as
designed. Wait thirty days without finalising and the same average reads
**49.11**. A proposal needs to win by 3%. This wins by a factor of a thousand,
and the only thing it costs is time.

**This is a bug we had already written down.** Audit finding M-1 on Capital DAO
was the same shape: a value read at a moment someone chooses is a value they
control. Our own spec says in §6.2(b) to *"prefer state fixed by elapsed time
rather than by a transaction someone chooses to send."* The recorder did the
opposite. Writing the rule down did not apply it.

It also matters against the chain operator. D8 promised that Robinhood delaying
transactions could postpone a decision but never change one. That promise was not
actually true until now — a long enough delay changed the answer.

**Cost:** None that we can see. The window is set when the proposal starts, along
with everything else about it.

**Proof it is fixed, rather than assertion.** Four tests cover the close. All four
were run against the old, unclamped code first and **all four fail there** — the
fix is load-bearing rather than decorative. Two of them originally passed against
the broken code and were rewritten: with the observation sitting at the average,
extending the window changes nothing and the test proves nothing. A test has to
leave the price somewhere other than the average to have any power.

**What this unblocks:** the Governor can now compare two markets and get the same
answer no matter who calls it or when, which is the property `finalize()` needs
to be safe.

---

## D21 — The Executor is a Safe module, copied from how MetaDAO holds its treasury

**Decided:** Each project's treasury is a Safe. The only thing that can spend
from it is our `FutarchyExecutor` module, which runs one batch of calls, once,
after the market approved that exact batch. No allowlist of permitted actions
beyond two structural rules — see below.

**Why this shape:** it is what MetaDAO does, translated. Their treasury is a
Squads multisig configured 1-of-1 whose sole signer is the futarchy program
itself, and a proposal's payload is a Squads transaction the program merely
*approves* — the governance program never runs arbitrary code. We keep that
split exactly: the Governor decides and records a fingerprint, the Executor
matches the fingerprint and spends, and neither knows much about the other.

**The one thing that does not translate.** On Solana, programs can sign for
addresses natively, so "the treasury's only signer is the market" is a literal
setting. EVM contracts cannot sign that way. The equivalent is a Safe *module*:
modules skip the owner-signature check entirely, which lets a contract move money
no human can. Safe is deployed on Robinhood Chain — checked before building on
it, and checked by asking `VERSION()` rather than trusting that bytecode exists.

**Two rules, both closing doors that only exist on EVM.** This is the whole of
the restriction, and each is there for a specific reason rather than as
general-purpose caution:

1. **A batch may not call the Safe.** `enableModule` is an ordinary call to the
   Safe's own address. Without this rule, one passed proposal attaches a second
   module — and that module answers to nobody. The treasury leaves futarchy
   permanently, by market vote, once. There is no undo.
2. **A batch may never `delegatecall`.** Rule 1 alone is not enough, which is the
   part that is easy to miss. Delegatecalling *any* contract runs its code inside
   the Safe's own storage, so it can rewrite the module list without the Safe ever
   appearing as a target. The operation is hard-coded, never a parameter.

I described this as one rule when we discussed it. It is two, and the second is
the one that would have been quietly missing.

**What we deliberately did not build.** The kernel/growth allowlist in §5.4 —
forbidding Chainlink feed changes, Governor replacement, L2 precompiles. MetaDAO
has no equivalent, and every extra rule is another way to block a legitimate
proposal. The two rules above are not that list; they are the minimum that stops
the treasury voting itself out of the system. The rest is recorded as a possible
later addition rather than shipped now.

**Tested against a real Safe, not only a mock.** Audit lesson §6.2(d) is that
Capital DAO's H-1 fix passed against a mock and reverted against real Uniswap. A
Safe module is the same bet, so there is a fork test that deploys a genuine Safe
through the real proxy factory on mainnet and runs the module against it: money
moves, replay is refused, and the escape attempt fails.

One of those tests exists only to check the defence is real: it makes the same
`enableModule` call *directly* and shows it succeeds. Without that, "the attack
was blocked" could just mean the call was a no-op all along.

**Cost:** a Safe whose owner is an address nobody holds is unrecoverable by
design. If the Governor is ever broken and no proposal can pass, the money is
stuck. That is the deal — D10 said it plainly, and it is the product.

**98 tests pass.**

---

## D22 — The Governor, and the first proposal that runs end to end

**Decided:** Build the Governor as the single piece that owns the proposal
lifecycle — take the stake, open the two markets, run the clock, compare the two
settled prices, resolve the vault, unlock the Executor. Everything else already
existed; nothing was connected until this.

**The system now works end to end.** Two tests run a whole proposal: submitted,
markets opened, traded by someone with real money at stake, clock run out,
finalised, and the treasury pays a contributor — with no human signature anywhere
in the path. The mirror test runs the same proposal against a market that says no
and confirms nothing moves. That is the product, demonstrated rather than
described.

**Choices worth recording:**

**The Governor builds its own vault.** The vault answers only to its governor, and
that address is fixed when the vault is built — so whoever creates the vault
decides who controls it. Passing an address in leaves a gap where the wrong one
could be supplied. Creating it in the constructor closes that by construction.

**One seed funds both books.** Splitting `X` of the project token yields `X`
pass-tokens *and* `X` fail-tokens, so a single deposit opens both markets to
equal depth rather than dividing one pot in two. This is the property that makes
the fail market — usually the thin one, and the one §6.3.2 warns is as attackable
as the pass side — just as deep as the pass market from the first second.

**No parameter is settable.** Windows, the margin, the stake, the rate limit are
all fixed at deployment. §6.3.3 warns that a proposal setting the margin to -100%
makes everything after it pass automatically, and that a timelock only postpones
that. The simplest answer to a system that can rewrite its own rules is one that
cannot. When parameters do become changeable, they need hard bounds in code
first — a delay is the second line, never the first.

**The guardian can stop a proposal and nothing else.** Cancelling a live proposal
resolves it to Fail, which is the honest reading — the instruction did not
happen. It is a real power, and worth naming: anyone holding the pass side loses.
The alternative, leaving the question open forever, strands anyone holding only
one side, which is worse. A test asserts the guardian cannot make anything pass.

**Seed capital comes back.** Without `reclaimSeed`, the money that opens the
markets is locked forever and nobody funds a second proposal.

### A design flaw the end-to-end test caught

The Executor originally hashed the proposal id together with the batch, which
looks stricter. It is impossible: a proposal's id is derived from the actions
hash it was submitted with, so computing either requires the other. Nothing could
ever have been executed. Writing a test that ran the real sequence surfaced it
immediately; every unit test passed happily because each side was mocked.

The fix drops the id from the hash. Nothing is lost — the Governor records one
hash per proposal and the Executor checks the batch matches *that* proposal's
hash, so a batch still cannot be swapped into a proposal that approved something
else. Replay within a proposal is stopped separately.

**Cost:** `MarketFactory` exists for a dull reason — a contract that deploys
another carries its full creation code, and four of those would push the Governor
past the 24KB limit. It is a size workaround, not a design idea, and it is worth
knowing that so nobody looks for deeper meaning in it.

**121 tests pass.**
