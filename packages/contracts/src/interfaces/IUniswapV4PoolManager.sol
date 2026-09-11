// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice The reads we need from the Uniswap V4 singleton.
/// @dev Declared locally rather than pulling in the v4-core submodule. This is
///      the whole surface a read-only price source touches, and vendoring a
///      large dependency to obtain two function signatures would add build
///      weight and audit surface for nothing.
///
///      V4 keeps every pool's state inside one contract and exposes it as raw
///      storage, so a reader derives the slot it wants and loads it directly
///      rather than calling a getter on a per-pool contract.
interface IUniswapV4PoolManager {
    /// @notice Reads one word of the manager's persistent storage.
    function extsload(bytes32 slot) external view returns (bytes32 value);

    /// @notice Reads one word of the manager's transient storage.
    /// @dev Used to tell whether the manager is currently unlocked — i.e.
    ///      whether we are being asked for a price from inside somebody's
    ///      in-flight callback.
    function exttload(bytes32 slot) external view returns (bytes32 value);
}
