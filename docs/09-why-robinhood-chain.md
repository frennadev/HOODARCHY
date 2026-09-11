# Why Robinhood Chain

> **Status: pre-launch draft.** Facts marked *verified* were checked directly
> against the network on the date given. Everything else is subject to change.

## The short answer

Futarchy needs three things to work: **cheap transactions**, **deep stablecoin
liquidity**, and **a mature AMM**. Robinhood Chain has all three, plus a large
existing user base that most new chains spend years trying to acquire.

## What Robinhood Chain is

An Ethereum Layer 2 built by Robinhood on Arbitrum technology, aimed at
tokenized real-world assets. It posts compressed transaction batches to Ethereum
using EIP-4844 blobs, inheriting Ethereum's security while executing fast and
cheaply.

It's a standard EVM chain. Solidity, Foundry, Hardhat, viem, wagmi, MetaMask —
everything works the way it does on Ethereum or Arbitrum.

## Verified network facts

We checked these directly against the RPC rather than taking documentation at
face value. **All verified 2026-07-26.**

| Property | Value | How verified |
| --- | --- | --- |
| Mainnet chain ID | **4663** | `eth_chainId` → `0x1237` |
| Testnet chain ID | **46630** | `eth_chainId` → `0xb626` |
| Node software | Arbitrum Nitro v3.11.3 | `web3_clientVersion` |
| ArbOS version | **61** | `ArbSys.arbOSVersion()` → 116 |
| EVM target | **Cancun** — safe | ArbOS 61 is well past ArbOS 32, which introduced Cancun |
| Gas token | ETH | — |
| Gas price | **~0.05 gwei** | `eth_gasPrice` → `0x2fee050` |
| Mainnet height | ~20,100,000 | `eth_blockNumber` |

**Endpoints**

| | Mainnet | Testnet |
| --- | --- | --- |
| Public RPC | `https://rpc.mainnet.chain.robinhood.com` | `https://rpc.testnet.chain.robinhood.com` |
| Explorer | [robinhoodchain.blockscout.com](https://robinhoodchain.blockscout.com) | explorer.testnet.chain.robinhood.com |
| Sequencer feed | `wss://feed.mainnet.chain.robinhood.com` | `wss://feed.testnet.chain.robinhood.com` |

Docs: [docs.robinhood.com/chain](https://docs.robinhood.com/chain/)

## Verified contract addresses

Each of these was confirmed to hold bytecode on mainnet.

**Tokens**

| Token | Address | Decimals |
| --- | --- | --- |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | 18 |
| USDG | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | **6** |

> ⚠️ **USDG has 6 decimals.** Any code that assumes 18 will be wrong by a factor
> of a trillion. Called out here, in the contracts, and in the test suite.

**Uniswap v3 — verified live**

| Contract | Address |
| --- | --- |
| Factory | `0x1f7d7550B1b028f7571E69A784071F0205FD2EfA` |
| SwapRouter02 | `0xCaf681a66D020601342297493863E78C959E5cb2` |
| UniversalRouter | `0x8876789976dEcBfCbBbe364623C63652db8C0904` |
| NonfungiblePositionManager | `0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3` |
| QuoterV2 | `0x33e885eD0Ec9bF04EcfB19341582aADCb4c8A9E7` |

Fee tiers behave normally — the factory returns tick spacing 10 / 60 / 200 for
the 0.05% / 0.30% / 1.00% tiers.

**Infrastructure**

| Contract | Address |
| --- | --- |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| Multicall3 | `0xcA11bde05977b3631167028862bE2a173976CA11` |
| Robinhood L2 Multicall | `0x2cAC2D899eCC914d704FeaAE33ac1bF36277DaD1` |

## Three things we found that you should know

Documentation and marketing said one thing; the chain said another. These are
worth stating publicly because anyone building here will hit them.

### 1. Uniswap v4 is not where you'd expect

Ecosystem materials describe Robinhood Chain as shipping "Uniswap v2, v3, v4 and
UniswapX from day one." All of that is true — but v4 is **not** at the canonical
`PoolManager` address it uses on other chains:

```
0x000000000004444c5dc75cB358380D2e3dE08A90   -> no code
0x1F98400000000000000000000000000000000004   -> no code

0x8366a39CC670B4001A1121B8F6A443A643e40951   -> PoolManager      (24,009 bytes)
0x58daec3116aae6D93017bAAea7749052E8a04fA7   -> PositionManager  (23,877 bytes)
```

We got this wrong once, and the mistake is instructive: we probed the canonical
addresses plus twelve more from other chains, found nothing, and recorded v4 as
absent. **A v4 deployment has a different address on every chain**, so absence at
addresses you already know is not evidence of anything. v4 is in fact the deepest
venue here — its singleton holds roughly 45M USDG, an order of magnitude more
stablecoin than all three v3 USDG/WETH fee tiers combined.

What we should have done, and now do: verify by asking contracts what they are
wired to. `PositionManager.poolManager()` returning the PoolManager — and both
naming the same Permit2 and WETH we verified independently — is evidence a
codesize probe cannot give you. The clue was in our own address list the whole
time: the UniversalRouter we verified in July is v4-capable, and its
`poolManager()` points straight at the deployment we said did not exist.

The AMM integration sits behind an `IPriceSource` interface, so which version the
markets use is a decision on merit rather than a constraint.

### 2. The public RPC is not an archive node

Fork testing against a pinned historical block — the normal way to write
deterministic integration tests — **does not work on the public endpoint.**
State older than roughly 20k–100k blocks returns `metadata is not found`.

Practical consequence: fork tests must either run against the latest block
(non-deterministic) or use a dedicated archive provider such as Alchemy. Our
test harness defaults to latest and accepts a `FORK_BLOCK` override for when an
archive endpoint is configured.

The public RPC is also rate limited, and not suitable for production frontends
or indexers.

### 3. Chainlink feed addresses are still unconfirmed

Chainlink is the chain's designated official oracle, but we have not yet
confirmed specific feed addresses or whether the deployment is Data Feeds, Data
Streams, or both.

This matters more than it sounds: oracle-attested milestone settlement
([Pay for Performance](07-pay-for-performance.md)) depends on it. It's tracked
as a blocking item in [Architecture](10-architecture.md), and the constants are
deliberately left as zero addresses so accidental use reverts rather than
silently failing.

## Why this chain rather than another

**Stablecoin liquidity is native.** USDG exists on this chain by design, not as a
bridged wrapper. Futarchy markets are quoted in stablecoins, and quoting against
bridged assets adds a bridge's risk to every market.

**Fees are negligible.** At ~0.05 gwei, the constant small transactions futarchy
requires — splitting, merging, arbitraging, market making — are economically
viable. On L1 they simply aren't; the arbitrage that keeps conditional prices
honest would be eaten by gas.

**Uniswap v3 is fully deployed and verified.** We don't have to bootstrap an AMM.

**Distribution.** Robinhood brings an enormous existing retail user base. The
hardest problem for a launch platform isn't the contracts, it's having anyone
there to participate.

**Tokenized real-world assets are the chain's thesis.** A platform for owning and
governing companies onchain fits a chain built for tokenized ownership better
than it fits a general-purpose chain.

## What we depend on, and the risk that carries

Being explicit, since these are real dependencies:

- **The chain itself** — a young L2 with a centralised sequencer. Downtime,
  reorgs, or censorship would affect settlement.
- **USDG** — a specific issuer's stablecoin. Depeg or freeze would hit every
  market and treasury.
- **Uniswap v3 deployment** — our AMM layer.
- **Chainlink** — for any oracle-settled milestone, once confirmed.

See [Risks and Disclosures](12-risks.md).

## Next

- [Architecture](10-architecture.md) — how we build on top of this
- [Security](11-security.md)
