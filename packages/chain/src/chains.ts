/**
 * Robinhood Chain network definitions (viem-compatible).
 *
 * All values verified live against the RPC on 2026-07-26.
 * Robinhood Chain is an Arbitrum Orbit / Nitro L2 settling to Ethereum.
 */

import { defineChain } from "viem";

/** Mainnet — verified: eth_chainId returned 0x1237 (4663). */
export const robinhoodChain = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.mainnet.chain.robinhood.com"] },
  },
  blockExplorers: {
    default: {
      name: "Blockscout",
      url: "https://robinhoodchain.blockscout.com",
      apiUrl: "https://robinhoodchain.blockscout.com/api",
    },
  },
  contracts: {
    multicall3: {
      // Canonical Multicall3 — verified on-chain (codesize 3808).
      address: "0xcA11bde05977b3631167028862bE2a173976CA11",
    },
  },
});

/** Testnet — verified: eth_chainId returned 0xb626 (46630). */
export const robinhoodChainTestnet = defineChain({
  id: 46630,
  name: "Robinhood Chain Testnet",
  testnet: true,
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.testnet.chain.robinhood.com"] },
  },
  blockExplorers: {
    default: {
      name: "Blockscout",
      url: "https://explorer.testnet.chain.robinhood.com",
    },
  },
});

/**
 * Non-RPC endpoints. The sequencer feed is a websocket stream of ordered txs
 * before they are batched to L1 — useful for a low-latency market UI, since
 * waiting on block confirmation adds needless lag to price updates.
 */
export const endpoints = {
  mainnet: {
    publicRpc: "https://rpc.mainnet.chain.robinhood.com",
    sequencer: "https://sequencer.mainnet.chain.robinhood.com",
    sequencerFeed: "wss://feed.mainnet.chain.robinhood.com",
    alchemyRpc: (key: string) => `https://robinhood-mainnet.g.alchemy.com/v2/${key}`,
    alchemyWs: (key: string) => `wss://robinhood-mainnet.g.alchemy.com/v2/${key}`,
  },
  testnet: {
    publicRpc: "https://rpc.testnet.chain.robinhood.com",
    sequencer: "https://sequencer.testnet.chain.robinhood.com",
    sequencerFeed: "wss://feed.testnet.chain.robinhood.com",
    alchemyRpc: (key: string) => `https://robinhood-testnet.g.alchemy.com/v2/${key}`,
    alchemyWs: (key: string) => `wss://robinhood-testnet.g.alchemy.com/v2/${key}`,
  },
} as const;
