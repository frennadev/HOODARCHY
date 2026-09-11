# RH Futarchy — contracts

| Path | What it is |
| --- | --- |
| `conditional/ConditionalToken.sol` | One outcome of one underlying, as a plain ERC-20. Minted and burned only by the vault. |
| `conditional/ConditionalVault.sol` | Escrows an underlying and issues matched PASS/FAIL claims. Enforces `held == PASS supply == FAIL supply`. |
| `oracle/LaggedTwapOracle.sol` | The anti-manipulation core. Records a rate-limited price and time-weights it. Reads an `IPriceSource`, so it does not know which AMM is underneath (D15). Holds no funds. |
| `oracle/sources/UniswapV2PriceSource.sol` | Reads spot price from a V2 pair's reserves. |
| `oracle/sources/UniswapV4PriceSource.sol` | Reads spot price from one V4 pool inside the singleton. Withholds a price when the pool is empty or mid-transaction (D17). |
| `config/RobinhoodChain.sol` | Verified on-chain addresses. Mirror of `packages/chain/src/addresses.ts`. |

The conditional pools target **Uniswap V4** (D17). The V2 source is kept: it is
the simpler reference implementation, and it is what proves the oracle is
genuinely independent of the AMM rather than independent in principle only.

Design rationale: [`DECISIONS.md`](../../../DECISIONS.md).
Full spec: [`MECHANISM-REFERENCE.md`](../../../MECHANISM-REFERENCE.md).
