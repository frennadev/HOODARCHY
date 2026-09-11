/**
 * Our own deployed contracts, per network.
 *
 * Mirrors DEPLOYMENTS.md, which carries the narrative — what each run was for,
 * how it behaved, and what it does not do. This file is the machine-readable
 * half; read the markdown before trusting an address with anything.
 */

import { CHAIN_ID } from "./addresses.js";

export const TESTNET_CHAIN_ID = 46630 as const;

/** How much a deployment should be trusted. */
export type DeploymentKind =
  /** Throwaway tokens, compressed windows, ownership not handed over. */
  | "smoke-test"
  /** Real tokens, canonical parameters, treasury owned by nobody. */
  | "production";

export interface FutarchyDeployment {
  kind: DeploymentKind;
  deployedAt: string;
  governor: `0x${string}`;
  vault: `0x${string}`;
  executor: `0x${string}`;
  marketFactory: `0x${string}`;
  safe: `0x${string}`;
  baseToken: `0x${string}`;
  quoteToken: `0x${string}`;
  /** Seconds observations are ignored after launch. */
  delaySeconds: number;
  /** Seconds the average accumulates, after the delay. */
  windowSeconds: number;
  /**
   * Whether the treasury is genuinely market-only. False means a human key can
   * still move the funds — see `caveats`.
   */
  treasuryIsMarketOnly: boolean;
  readonly caveats: readonly string[];
}

/**
 * ⚠️ The mainnet entry is a **smoke test**, not a product.
 *
 * It exists to show the mechanism works on a real chain: a market decided a
 * proposal and the treasury paid out. It uses throwaway tokens, windows
 * compressed from 24h/72h to 60s/300s, and — importantly — the treasury's
 * ownership was never handed to an unheld address, so the deployer key can
 * still move those funds directly.
 *
 * Do not point a frontend at this as though it were live governance, and do not
 * put anything of value in it.
 */
export const deployments = {
  [CHAIN_ID]: {
    kind: "smoke-test",
    deployedAt: "2026-09-11",
    governor: "0x597d97EF05f0c6C8D554E7bA9bdb138b42ADD044",
    vault: "0xd85f0C05D0Ecd4eF649D05310c528873b71b8718",
    executor: "0x67BE25fBE43AeA5204C15335954932838B5755CA",
    marketFactory: "0x7962047FE25ef414b9fD83e9e1f0Fb1788820f27",
    safe: "0xBeB4ED388302Ee7e91B828865Ca8810CA42b693c",
    baseToken: "0xC634E3d67a37E4bc59e3aE6d69e99De5A763eBB0", // FTT, 18dp, throwaway
    quoteToken: "0xC58C3A43B2c3Fa5981222633B9422Ede6B4f53A8", // tUSDG, 6dp, throwaway
    delaySeconds: 60,
    windowSeconds: 300,
    treasuryIsMarketOnly: false,
    caveats: [
      "Smoke test. Throwaway tokens, not real USDG.",
      "Windows compressed to 60s/300s; production is 24h/72h.",
      "Treasury ownership was NOT handed over — a human key can still move funds.",
      "Contracts are unaudited.",
    ],
  },
} as const satisfies Record<number, FutarchyDeployment>;

/** The first proposal ever run end to end, kept as a reference fixture. */
export const firstProposal = {
  chainId: CHAIN_ID,
  id: "0x4d12e83540d009ae1dd0fbc7038e9be81c0f259a2f3e0e332a7df86eee96aab3",
  passAmm: "0x7827bEF4D4d7d31cC5c52CefE02A4106c735760C",
  failAmm: "0x225124a2873846aA01361E3638150cFe6D7AeD4E",
  passOracle: "0xae9Df5D7b65B6b60bf67a7a9Fe3Ce1A155Ab70D8",
  failOracle: "0x686f2e9B5CE385C897C7EA1cEbCC2BE2028154d7",
  /** Settled: pass 2_721_374 vs threshold 2_060_000. Passed. */
  outcome: "passed",
} as const;

export function deploymentFor(chainId: number): FutarchyDeployment | undefined {
  return (deployments as Record<number, FutarchyDeployment>)[chainId];
}
