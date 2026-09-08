// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title RobinhoodChain
/// @notice Verified Robinhood Chain mainnet constants.
/// @dev Mirror of `packages/chain/src/addresses.ts`. If you change one, change
///      both — `pnpm chain:check` re-verifies the TS copy against a live RPC.
///
///      Every address below was confirmed to hold bytecode on 2026-07-26 at
///      block ~20,097,802. Addresses that are NOT verified live in the
///      `Unverified` section and are deliberately left as zero so that any
///      accidental use reverts loudly instead of silently doing nothing.
library RobinhoodChain {
    // -------------------------------------------------------------------------
    // Network
    // -------------------------------------------------------------------------

    uint256 internal constant CHAIN_ID = 4663;
    uint256 internal constant TESTNET_CHAIN_ID = 46_630;

    // -------------------------------------------------------------------------
    // Tokens
    // -------------------------------------------------------------------------

    /// @dev 18 decimals.
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    /// @dev **6 decimals.** Not 18. Scale every USDG amount explicitly.
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    uint8 internal constant USDG_DECIMALS = 6;
    uint8 internal constant WETH_DECIMALS = 18;

    // -------------------------------------------------------------------------
    // Infrastructure
    // -------------------------------------------------------------------------

    address internal constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address internal constant L2_MULTICALL = 0x2cAC2D899eCC914d704FeaAE33ac1bF36277DaD1;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @dev Arbitrum Nitro precompile. `arbOSVersion()` returned 116 => ArbOS 61.
    address internal constant ARB_SYS = 0x0000000000000000000000000000000000000064;

    // -------------------------------------------------------------------------
    // Uniswap v3 — the DEX layer that actually exists here today
    // -------------------------------------------------------------------------

    address internal constant UNIV3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address internal constant UNIV3_SWAP_ROUTER_02 = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address internal constant UNIV3_UNIVERSAL_ROUTER = 0x8876789976dEcBfCbBbe364623C63652db8C0904;
    address internal constant UNIV3_POSITION_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address internal constant UNIV3_QUOTER_V2 = 0x33e885eD0Ec9bF04EcfB19341582aADCb4c8A9E7;
    address internal constant UNIV3_TICK_LENS = 0x7DfD4F31be6814D2906BDE155c3e1B146EAc1468;

    uint24 internal constant FEE_LOWEST = 100;
    uint24 internal constant FEE_LOW = 500;
    uint24 internal constant FEE_MEDIUM = 3000;
    uint24 internal constant FEE_HIGH = 10_000;

    // -------------------------------------------------------------------------
    // Uniswap V2 — confirmed in production 2026-09-08
    // -------------------------------------------------------------------------

    /// @dev Confirmed live: 41,375 pairs at block 57,906,854. The Capital DAO
    ///      raise factory seeds V2 pools on mainnet through this router.
    ///      RH Futarchy uses V2 for per-proposal conditional pools (D5).
    address internal constant UNIV2_FACTORY = 0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f;
    address internal constant UNIV2_ROUTER = 0x89e5DB8B5aA49aA85AC63f691524311AEB649eba;

    // -------------------------------------------------------------------------
    // Unverified — resolve before use
    // -------------------------------------------------------------------------

    /// @dev Uniswap v4 is NOT deployed on this chain. Re-probed 2026-09-08 at
    ///      block 57,906,854: both canonical PoolManager addresses are empty,
    ///      and so are the twelve known PoolManager addresses from Ethereum,
    ///      Unichain, Base, Arbitrum, Optimism, Polygon, BNB, Avalanche, Blast,
    ///      Worldchain, Ink and Zora. Left zero on purpose.
    address internal constant UNIV4_POOL_MANAGER = address(0);

    /// @dev Chainlink feed addresses are not yet confirmed on this chain.
    ///      Market settlement depends on this; resolving it is a blocking task.
    address internal constant CHAINLINK_ETH_USD = address(0);
}
