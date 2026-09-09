// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Supplies an instantaneous price for the oracle to chase.
/// @dev Deliberately the narrowest possible surface. The oracle does not care
///      which AMM the price comes from, only that it is a number it can step
///      toward — so the Uniswap version is a swappable detail rather than a
///      decision baked into the security core.
interface IPriceSource {
    /// @return price Quote units per 1e18 of base, or 0 when unavailable
    ///         (empty pool, uninitialised pool). A zero tells the oracle to hold
    ///         its current observation rather than treat it as a real price.
    function spotPrice() external view returns (uint256 price);

    /// @return base The token being priced.
    function base() external view returns (address base);

    /// @return quote The token it is priced in.
    function quote() external view returns (address quote);
}
