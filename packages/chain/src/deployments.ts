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
    governor: "0x1D346cd2d281bb2c07E7803Da98350ECb4e9e3eE",
    vault: "0xd80DF1C07252dA38C2928DD08D114BE3B92B8659",
    executor: "0xB469cFdf1B62f9A7dBbb562b471f9bEd982a1Feb",
    marketFactory: "0xDfE16dDC68aFd064573C68e68163DDE2d0BbbC03",
    safe: "0xBB9A6D7A932BA7062abd33df0Ea7670d98383e14",
    baseToken: "0xC634E3d67a37E4bc59e3aE6d69e99De5A763eBB0", // FTT, 18dp, throwaway
    quoteToken: "0xC58C3A43B2c3Fa5981222633B9422Ede6B4f53A8", // tUSDG, 6dp, throwaway
    delaySeconds: 60,
    windowSeconds: 300,
    treasuryIsMarketOnly: false,
    caveats: [
      "Smoke test. Throwaway tokens, not real USDG.",
      "Second deployment; the first is unreadable by current ABIs (see DEPLOYMENTS.md).",
      "Windows compressed to 60s/300s; production is 24h/72h.",
      "Treasury ownership was NOT handed over — a human key can still move funds.",
      "Contracts are unaudited.",
    ],
  },
} as const satisfies Record<number, FutarchyDeployment>;

/**
 * A proposal that ran end to end on this deployment, kept as a fixture for
 * anyone wiring up a frontend against real data.
 */
export const sampleProposal = {
  chainId: CHAIN_ID,
  id: "0x360a0080a24fec6f99dd21268414b7d18419c5159fb6aba648357a03a48556e8",
  passAmm: "0x1DFC1648598182a07e75bD3966d7AE7Cf3f9eC0f",
  failAmm: "0x7bB88BDBf6bf2685eb72F545bBAD91DA84bC7c96",
  passOracle: "0x0047779d0a869B2C6602c3Bf54042E6f7C916C21",
  failOracle: "0x7900BBeB81D7c99E40719cab830613D6101FA8EC",
  /** Settled: pass 3_246_626 vs threshold 2_060_000. Passed, and paid out. */
  outcome: "passed",
} as const;

/**
 * The first deployment, superseded. Adding `descriptionUri` to `Proposed`
 * changed its topic hash, so nothing built from current ABIs can read the
 * events it emitted. Kept only so an address seen in an old transaction can be
 * identified. See DEPLOYMENTS.md.
 */
export const supersededDeployments = {
  [CHAIN_ID]: ["0x597d97EF05f0c6C8D554E7bA9bdb138b42ADD044"],
} as const;

export function deploymentFor(chainId: number): FutarchyDeployment | undefined {
  return (deployments as Record<number, FutarchyDeployment>)[chainId];
}
