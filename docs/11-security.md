# Security

> **Status: pre-launch draft.** **The core contracts are now written, tested
> (129 tests) and deployed to mainnet as a smoke test — see DEPLOYMENTS.md.
> They are NOT audited,
> audited, or deployed.** This page describes the security commitments we intend
> to hold ourselves to. It is a statement of intent, not a record of completed
> work.

## Current status, stated plainly

| | Status |
| --- | --- |
| Contracts written | **No** |
| Audited | **No** |
| Deployed | **No** |
| Bug bounty live | **No** |
| Funds at risk today | **None — nothing is live** |

We will keep this table current, including when the answers are unflattering.
A security page that only reports good news isn't a security page.

## The commitments

### Audits before mainnet, published in full

**Minimum two independent audits from reputable firms** before any mainnet
deployment holding user funds.

Reports are published in full — findings, severities, our responses, and what we
chose not to fix and why. Partial publication, or publishing only a summary, is
a way of hiding things, and we'd rather not have the option.

The `ConditionalVault`, `TwapOracle`, and `Treasury` get the deepest scrutiny.
An error in the oracle corrupts every decision; an error in the vault or
treasury loses money directly.

### No unaudited upgrades

The treasury is non-upgradeable by design. Where upgradeability exists elsewhere,
an upgrade is a proposal that clears its market like anything else, and upgrades
of security-critical code are audited before proposal, not after.

### A real bug bounty

Live before mainnet, scaled so that reporting a critical vulnerability pays
better than any plausible alternative. Scope, severity definitions, and payouts
published in advance.

**Amounts: TBD.** They'll be set relative to the value the contracts hold, and
published before launch.

### Timelocks on execution

A delay (*initial: 24–48 hours, TBD*) between a proposal passing and executing.
This exists because the mechanism might fail, and humans need a window to notice
and react. Designing as though your own mechanism is infallible is how protocols
lose money.

### Minimal admin authority, fully disclosed

The goal is no privileged actor. Where the launch phase requires one, we commit
to publishing:

- What the key can do, precisely
- Who holds it (multisig composition and threshold)
- The timelock on its use
- When and how it goes away

**Whether a pause authority should exist at all is an open question** (see
[Architecture](10-architecture.md)). A pause that can stop an attack can also
stop a legitimate proposal, which is a real centralisation cost. We'd rather
argue this out in public before launch than quietly ship one.

## Where the real risk is

Being honest about which parts worry us most:

**The TWAP oracle.** Corrupting a price corrupts a decision. This is where a
serious attacker goes, and it's the component that most needs an adversarial
review rather than a checklist audit.

**Thin conditional markets.** Every security property here assumes liquid
markets that arbitrageurs police. New conditional pools start thin. A small
launch with low liquidity has meaningfully weaker governance guarantees than a
large one, and pretending otherwise would be dishonest.

**Economic attacks, not just code bugs.** An audit finds reentrancy. It doesn't
necessarily find "if you borrow enough USDG at the right moment, moving this
price for six hours is profitable." Economic modelling of manipulation cost is
a separate workstream from a code audit, and it needs to happen.

**Composability with Uniswap v3.** We inherit its behaviour and its edge cases.

**Our own novelty.** These contracts are new. New contracts have bugs. The
mechanism is proven, but our implementation of it isn't.

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

**Contact: TBD** — a security contact address and PGP key will be published here
before any deployment. Until contracts exist, there is nothing to report against.

When live, we commit to:

- Acknowledgement within 24 hours
- An assessment and severity within 72 hours
- Regular updates until resolution
- Credit to the reporter, unless they prefer otherwise
- No legal action against good-faith researchers

## Operational security

- Deployment keys in hardware wallets or a Foundry keystore, never plaintext
- Multisig for any platform-level authority, with published composition
- Reproducible builds — `bytecode_hash = "none"` and `cbor_metadata = false` are
  already set so deployed bytecode is verifiable against source
- All contracts verified on
  [Blockscout](https://robinhoodchain.blockscout.com) at deployment
- Continuous monitoring of treasury movements and proposal execution

## What you should verify yourself

Don't take our word for any of this. Before putting money into a launch:

1. **Read the treasury contract.** Confirm there is no withdrawal function and
   no owner. This is checkable in a few minutes on the explorer.
2. **Confirm the contracts are verified** and the source matches what's
   documented.
3. **Read the audit reports** — the findings, not the summary.
4. **Check the token's mint authority.** Confirm supply can't be inflated.
5. **Check market liquidity.** Thin markets mean weak governance guarantees.
6. **Read the proposal calldata**, not the proposal's description of itself.

If any of these can't be checked, that itself is the answer.

## Next

- [Architecture](10-architecture.md) — including open security questions
- [Risks and Disclosures](12-risks.md)
- [The Treasury](06-treasury.md)
