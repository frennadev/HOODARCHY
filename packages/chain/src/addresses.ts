/**
 * Robinhood Chain mainnet (4663) contract addresses.
 *
 * VERIFIED column = we called `eth_getCode` and got non-empty bytecode on
 * 2026-07-26 at block ~20,097,802. Anything marked UNVERIFIED was NOT found
 * on-chain at the address the docs/marketing imply — do not integrate against
 * it until someone confirms it. Run `pnpm chain:check` to re-verify.
 */

export const CHAIN_ID = 4663 as const;

export const tokens = {
  /** VERIFIED — codesize 2202, symbol "WETH", 18 decimals. */
  WETH: "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73",

  /**
   * VERIFIED — codesize 170 (a proxy), symbol "USDG", **6 decimals**.
   *
   * ⚠️ 6 decimals, not 18. This is the single most likely source of a
   * catastrophic off-by-10^12 bug in this codebase. Every price, market
   * quote, and treasury accounting path that touches USDG must scale
   * explicitly. Never assume 18.
   */
  USDG: "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168",
} as const;

export const infra = {
  /** VERIFIED — codesize 3808. Canonical CREATE2 deployment, same as most chains. */
  MULTICALL3: "0xcA11bde05977b3631167028862bE2a173976CA11",

  /** VERIFIED — codesize 3339. Robinhood's own documented L2 multicall. */
  L2_MULTICALL: "0x2cAC2D899eCC914d704FeaAE33ac1bF36277DaD1",

  /** VERIFIED — codesize 9152. Canonical Permit2, same address as every chain. */
  PERMIT2: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
} as const;

/**
 * Uniswap v3 — all VERIFIED on-chain. This is the DEX layer we should build
 * against today.
 */
export const uniswapV3 = {
  FACTORY: "0x1f7d7550b1b028f7571e69a784071f0205fd2efa", // codesize 24535
  SWAP_ROUTER_02: "0xcaf681a66d020601342297493863e78c959e5cb2", // codesize 24497
  UNIVERSAL_ROUTER: "0x8876789976decbfcbbbe364623c63652db8c0904", // codesize 24546
  NONFUNGIBLE_POSITION_MANAGER: "0x73991a25c818bf1f1128deaab1492d45638de0d3", // codesize 24384
  QUOTER_V2: "0x33e885ed0ec9bf04ecfb19341582aadcb4c8a9e7", // codesize 8273
  TICK_LENS: "0x7dfd4f31be6814d2906bde155c3e1b146eac1468",
  INTERFACE_MULTICALL: "0x282a3c4d320cc7f0d5eaf56b8029e4b88338f0a3",
} as const;

/** Fee tier -> tick spacing. Confirmed on-chain: factory returns 60 for 3000. */
export const uniswapV3FeeTiers = {
  LOWEST: 100,
  LOW: 500,
  MEDIUM: 3000,
  HIGH: 10000,
} as const;

/**
 * ✅ CONFIRMED LIVE — re-probed 2026-09-08 at block 57,906,854.
 *
 * Uniswap v2 IS deployed, contrary to the 2026-07-26 note that only v3 could be
 * confirmed. The Capital DAO raise factory seeds v2 pools on mainnet through
 * this router, and the factory reports 41,375 pairs.
 *
 * RH Futarchy uses v2 for per-proposal conditional pools (decision D5): a v2
 * pair is two token balances, which splits cleanly into complete sets for
 * shared liquidity, and is trivial for the lagged-observation oracle to read.
 */
export const uniswapV2 = {
  FACTORY: "0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f",
  ROUTER: "0x89e5DB8B5aA49aA85AC63f691524311AEB649eba",
} as const;

/**
 * ✅ CONFIRMED LIVE — 2026-09-09, at a NON-CANONICAL address.
 *
 * The 2026-07-26 note concluded v4 was absent after probing the two canonical
 * PoolManager addresses. That conclusion was invalid: v4 deploys to a different
 * address on every chain, so absence at known addresses proves nothing.
 *
 * Verified: PositionManager.poolManager() returns the PoolManager below, so the
 * two are a matched deployment rather than unrelated bytecode.
 */
export const uniswapV4 = {
  POOL_MANAGER: "0x8366a39CC670B4001A1121B8F6A443A643e40951",
  POSITION_MANAGER: "0x58daec3116aae6D93017bAAea7749052E8a04fA7",
  STATE_VIEW: null, // not yet located
} as const;

/**
 * ⚠️ UNVERIFIED — placeholder.
 *
 * Chainlink is the chain's announced official oracle, but we have not yet
 * confirmed specific feed addresses (ETH/USD etc.) or whether the deployment
 * is Data Feeds, Data Streams, or both. The market resolver depends entirely
 * on this, so resolving these addresses is a blocking task before any
 * settlement code is written. See docs/10-architecture.md.
 */
export const chainlink = {
  ETH_USD_FEED: null,
  FEED_REGISTRY: null,
} as const;

/** Our own deployments. Populated by the deploy scripts, per network. */
export const capitalDao = {
  4663: {
    // filled in at deploy time
  },
  46630: {
    // filled in at deploy time
  },
} as const;
