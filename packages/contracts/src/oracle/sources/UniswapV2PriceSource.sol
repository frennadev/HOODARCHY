// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPriceSource} from "../../interfaces/IPriceSource.sol";
import {IUniswapV2Pair} from "../../interfaces/IUniswapV2Pair.sol";

/// @notice Reads spot price from a Uniswap V2 pair's reserves.
/// @dev Read-only and holds no funds. A V4 equivalent reading pool state through
///      StateView slots in here unchanged from the oracle's point of view.
contract UniswapV2PriceSource is IPriceSource {
    error ZeroAddress();
    error TokenNotInPair();

    uint256 private constant WAD = 1e18;

    IUniswapV2Pair public immutable PAIR;
    address private immutable BASE;
    address private immutable QUOTE;

    constructor(address pair_, address base_) {
        if (pair_ == address(0) || base_ == address(0)) revert ZeroAddress();
        IUniswapV2Pair p = IUniswapV2Pair(pair_);
        address t0 = p.token0();
        address t1 = p.token1();
        if (t0 != base_ && t1 != base_) revert TokenNotInPair();

        PAIR = p;
        BASE = base_;
        QUOTE = t0 == base_ ? t1 : t0;
    }

    function spotPrice() external view override returns (uint256) {
        (uint112 r0, uint112 r1,) = PAIR.getReserves();
        if (r0 == 0 || r1 == 0) return 0;
        (uint256 baseReserve, uint256 quoteReserve) =
            PAIR.token0() == BASE ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        return Math.mulDiv(quoteReserve, WAD, baseReserve);
    }

    function base() external view override returns (address) {
        return BASE;
    }

    function quote() external view override returns (address) {
        return QUOTE;
    }
}
