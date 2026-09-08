# RH Futarchy — contracts

| Path | What it is |
| --- | --- |
| `conditional/ConditionalToken.sol` | One outcome of one underlying, as a plain ERC-20. Minted and burned only by the vault. |
| `conditional/ConditionalVault.sol` | Escrows an underlying and issues matched PASS/FAIL claims. Enforces `held == PASS supply == FAIL supply`. |
| `oracle/LaggedTwapOracle.sol` | The anti-manipulation core. Records a rate-limited price for one Uniswap V2 pair and time-weights it. Holds no funds. |
| `config/RobinhoodChain.sol` | Verified on-chain addresses. Mirror of `packages/chain/src/addresses.ts`. |

Design rationale: [`DECISIONS.md`](../../../DECISIONS.md).
Full spec: [`MECHANISM-REFERENCE.md`](../../../MECHANISM-REFERENCE.md).
