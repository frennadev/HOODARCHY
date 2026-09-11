# RH Futarchy — contracts

| Path | What it is |
| --- | --- |
| `conditional/ConditionalToken.sol` | One outcome of one underlying, as a plain ERC-20. Minted and burned only by the vault. |
| `conditional/ConditionalVault.sol` | Escrows an underlying and issues matched PASS/FAIL claims. Enforces `held == PASS supply == FAIL supply`. |
| `oracle/LaggedTwapOracle.sol` | The anti-manipulation core. Records a rate-limited price and time-weights it. Reads an `IPriceSource`, so it does not know which AMM is underneath (D15). Holds no funds. |
| `oracle/sources/UniswapV2PriceSource.sol` | Reads spot price from a V2 pair's reserves. |
| `oracle/sources/UniswapV4PriceSource.sol` | Reads spot price from one V4 pool inside the singleton — used for the **parent/spot** pool. Withholds a price when the pool is empty or mid-transaction. |
| `amm/ConditionalAmm.sol` | The per-proposal pass/fail market. Constant-product, stored reserves, updates the oracle before every trade. Ported from MetaDAO (D19). |
| `governance/FutarchyExecutor.sol` | The only thing that can spend a treasury. A Safe module that runs one hash-bound batch, once (D21). |
| `interfaces/ISafe.sol` | The slice of Safe the module touches, declared locally rather than vendored. |
| `config/RobinhoodChain.sol` | Verified on-chain addresses. Mirror of `packages/chain/src/addresses.ts`. |

**Where each pool type lives (D19).** The project's *parent* TOKEN/USDG pool is a
real Uniswap V4 pool — that is where the chain's liquidity and traders are. The
*per-proposal* pass/fail markets are `ConditionalAmm`, our own pool, because they
hold freshly minted tokens with no liquidity to inherit and no passing trade to
catch, so a DEX buys nothing there and costs a great deal.

The Uniswap price sources are kept for the parent pool, and they are what prove
the oracle is genuinely independent of any one AMM rather than independent in
principle only.

Design rationale: [`DECISIONS.md`](../../../DECISIONS.md).
Full spec: [`MECHANISM-REFERENCE.md`](../../../MECHANISM-REFERENCE.md).
