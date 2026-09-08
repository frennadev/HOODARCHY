// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Minimal stand-in for a Uniswap V2 pair: just the reserve surface the
///         oracle reads, with a setter so tests can move the price arbitrarily.
contract MockV2Pair {
    address public token0;
    address public token1;
    uint112 private _r0;
    uint112 private _r1;

    constructor(address t0, address t1) {
        token0 = t0;
        token1 = t1;
    }

    function setReserves(uint112 r0, uint112 r1) external {
        _r0 = r0;
        _r1 = r1;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (_r0, _r1, uint32(block.timestamp));
    }
}
