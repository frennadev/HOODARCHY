// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPriceSource} from "../../interfaces/IPriceSource.sol";
import {IUniswapV4PoolManager} from "../../interfaces/IUniswapV4PoolManager.sol";

/// @title UniswapV4PriceSource
/// @notice Reads spot price for one Uniswap V4 pool, for the lagged oracle to
///         chase. Read-only, holds no funds, and swappable for the V2 source
///         without the oracle noticing (decision D15).
///
/// @dev V4 keeps every pool inside one singleton and exposes its storage through
///      `extsload`, so this contract derives the pool's storage slot once and
///      reads it directly. There is no per-pool contract to call.
///
///      Two guards matter more here than they did on V2, and both return 0 —
///      the interface's "no usable price, hold the observation" signal — rather
///      than reverting, so a dead pool can never stall the crank.
contract UniswapV4PriceSource is IPriceSource {
    error ZeroAddress();
    error TokensNotOrdered();
    error TokenNotInPool();

    uint256 private constant WAD = 1e18;
    uint256 private constant Q96 = 1 << 96;

    /// @dev `PoolManager.pools` is the 7th declared slot. Confirmed against the
    ///      deployed bytecode on Robinhood Chain, not assumed: reading
    ///      `keccak256(abi.encode(poolId, 6)) + 3` returns a liquidity that
    ///      matches live pools and zero for an empty one. Pinned by a fork test
    ///      so an upgraded PoolManager with a different layout fails loudly
    ///      instead of quietly returning a wrong price.
    uint256 private constant POOLS_SLOT = 6;

    /// @dev Offsets within `Pool.State`: slot0 packs sqrtPriceX96 in its low 160
    ///      bits; liquidity is the fourth field.
    uint256 private constant SLOT0_OFFSET = 0;
    uint256 private constant LIQUIDITY_OFFSET = 3;

    /// @dev `bytes32(uint256(keccak256("Unlocked")) - 1)`, V4's transient
    ///      re-entrancy flag. Verified: keccak256("Unlocked") ends ...ab24.
    bytes32 private constant IS_UNLOCKED_SLOT =
        0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;

    IUniswapV4PoolManager public immutable POOL_MANAGER;

    /// @dev Storage slot of this pool's `Pool.State`, derived once at deploy.
    bytes32 public immutable POOL_STATE_SLOT;
    bytes32 public immutable POOL_ID;

    address private immutable BASE;
    address private immutable QUOTE;
    bool private immutable BASE_IS_CURRENCY0;

    /// @param currency0 Lower-sorted token. `address(0)` means native ETH.
    /// @param currency1 Higher-sorted token.
    /// @param base_ Which of the two is being priced; the other becomes quote.
    constructor(
        address poolManager_,
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        address base_
    ) {
        if (poolManager_ == address(0)) revert ZeroAddress();
        // V4 requires sorted currencies; an unsorted key hashes to a pool that
        // cannot exist, which would look like "empty pool" forever.
        if (uint160(currency0) >= uint160(currency1)) revert TokensNotOrdered();
        if (base_ != currency0 && base_ != currency1) revert TokenNotInPool();

        POOL_MANAGER = IUniswapV4PoolManager(poolManager_);
        POOL_ID = keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks));
        POOL_STATE_SLOT = keccak256(abi.encode(POOL_ID, POOLS_SLOT));

        BASE = base_;
        BASE_IS_CURRENCY0 = base_ == currency0;
        QUOTE = base_ == currency0 ? currency1 : currency0;
    }

    /// @inheritdoc IPriceSource
    function spotPrice() external view override returns (uint256) {
        // Guard 1 — never price a pool mid-flight.
        //
        // V4's flash accounting lets one transaction unlock the manager, move a
        // pool to any price, act on it, and restore it before settling. A price
        // observed inside that window is one nobody else could have traded
        // against, which is precisely what the oracle's security argument
        // assumes is impossible: that moving the recorded price means holding a
        // false price in the open where others can profit by fading it.
        //
        // The oracle's time-based cap already bounds what a single poke can do,
        // so this is defence in depth rather than the only line. But refusing to
        // serve a price that exists only inside someone's callback is cheap, and
        // it keeps the D4 argument intact on V4 rather than merely bounded.
        if (uint256(POOL_MANAGER.exttload(IS_UNLOCKED_SLOT)) != 0) return 0;

        // Guard 2 — an initialised pool is not necessarily a real one.
        //
        // Robinhood Chain carries V4 pools that were initialised and never
        // funded; at least one sits at the maximum representable price with zero
        // liquidity. Its slot0 reads as a perfectly well-formed number that is
        // astronomically wrong. Liquidity is what separates a price from a
        // leftover.
        uint256 liquidity = uint256(POOL_MANAGER.extsload(_offset(LIQUIDITY_OFFSET)));
        if (liquidity == 0) return 0;

        // slot0 packs, from the low bits: sqrtPriceX96 (160) | tick (24) |
        // protocolFee (24) | lpFee (24). Only the price is needed here.
        uint256 sqrtPriceX96 =
            uint256(POOL_MANAGER.extsload(_offset(SLOT0_OFFSET))) & type(uint160).max;
        if (sqrtPriceX96 == 0) return 0;

        // price(currency1 per currency0), as a Q96 fixed-point number.
        // Split across two mulDivs because sqrtPriceX96^2 alone overflows 256
        // bits at the top of the representable range.
        uint256 priceQ96 = Math.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (priceQ96 == 0) return 0;

        return BASE_IS_CURRENCY0
            ? Math.mulDiv(priceQ96, WAD, Q96)  // quote per 1e18 base
            : Math.mulDiv(WAD, Q96, priceQ96); // inverted: base is currency1
    }

    function base() external view override returns (address) {
        return BASE;
    }

    function quote() external view override returns (address) {
        return QUOTE;
    }

    function _offset(uint256 index) private view returns (bytes32) {
        return bytes32(uint256(POOL_STATE_SLOT) + index);
    }
}
