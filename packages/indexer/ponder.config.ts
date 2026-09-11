import { createConfig, factory } from "ponder";
import { parseAbiItem } from "viem";

import {
  conditionalAmmAbi,
  conditionalVaultAbi,
  futarchyExecutorAbi,
  futarchyGovernorAbi,
  laggedTwapOracleAbi,
} from "@hoodarchy/chain";

/**
 * Robinhood Chain mainnet.
 *
 * Note this is the *second* deployment. The first emitted an older `Proposed`
 * signature — adding `descriptionUri` changed the event's topic hash, so an
 * indexer built from current ABIs simply cannot see those logs. Contracts and
 * consumers share the ABI as an interface; changing an event breaks a
 * deployment as surely as changing a function would.
 */
const START_BLOCK = 60_276_500;

const GOVERNOR = "0x1D346cd2d281bb2c07E7803Da98350ECb4e9e3eE";
const VAULT = "0xd80DF1C07252dA38C2928DD08D114BE3B92B8659";
const EXECUTOR = "0xB469cFdf1B62f9A7dBbb562b471f9bEd982a1Feb";
const MARKET_FACTORY = "0xDfE16dDC68aFd064573C68e68163DDE2d0BbbC03";

/**
 * Pools and oracles are created per proposal, so their addresses cannot be
 * listed in advance. `MarketFactory` announces both when it builds them, which
 * is what makes them discoverable — and is the reason that event carries the
 * oracle as well as the pool.
 */
const marketCreated = parseAbiItem(
  "event MarketCreated(address indexed amm, address indexed oracle, address base, address quote)",
);

export default createConfig({
  chains: {
    robinhood: {
      id: 4663,
      rpc: process.env.PONDER_RPC_URL_4663 ?? "https://rpc.mainnet.chain.robinhood.com",
    },
  },
  contracts: {
    FutarchyGovernor: {
      abi: futarchyGovernorAbi,
      chain: "robinhood",
      address: GOVERNOR,
      startBlock: START_BLOCK,
    },
    ConditionalVault: {
      abi: conditionalVaultAbi,
      chain: "robinhood",
      address: VAULT,
      startBlock: START_BLOCK,
    },
    FutarchyExecutor: {
      abi: futarchyExecutorAbi,
      chain: "robinhood",
      address: EXECUTOR,
      startBlock: START_BLOCK,
    },
    ConditionalAmm: {
      abi: conditionalAmmAbi,
      chain: "robinhood",
      address: factory({
        address: MARKET_FACTORY,
        event: marketCreated,
        parameter: "amm",
      }),
      startBlock: START_BLOCK,
    },
    LaggedTwapOracle: {
      abi: laggedTwapOracleAbi,
      chain: "robinhood",
      address: factory({
        address: MARKET_FACTORY,
        event: marketCreated,
        parameter: "oracle",
      }),
      startBlock: START_BLOCK,
    },
  },
});
