// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Minimal stand-in for the Uniswap V4 singleton: raw slot storage plus
///         the unlock flag, which is the whole surface a price source reads.
/// @dev Slots are set directly rather than by simulating swaps, so a test can
///      place a pool in states a real one reaches rarely — empty, uninitialised,
///      or parked at the maximum representable price.
contract MockV4PoolManager {
    mapping(bytes32 slot => bytes32 value) private _storage;
    mapping(bytes32 slot => bytes32 value) private _transient;

    uint256 private constant POOLS_SLOT = 6;
    uint256 private constant LIQUIDITY_OFFSET = 3;

    bytes32 private constant IS_UNLOCKED_SLOT =
        0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;

    function extsload(bytes32 slot) external view returns (bytes32) {
        return _storage[slot];
    }

    function exttload(bytes32 slot) external view returns (bytes32) {
        return _transient[slot];
    }

    // ----------------------------------------------------------------- setters

    /// @notice Writes a pool's price and liquidity at the real storage layout.
    function setPool(bytes32 poolId, uint160 sqrtPriceX96, uint128 liquidity) external {
        bytes32 stateSlot = keccak256(abi.encode(poolId, POOLS_SLOT));
        // slot0 packs sqrtPriceX96 in the low 160 bits; the upper bits (tick and
        // fees) are left dirty on purpose so the source must mask rather than
        // pass a whole word through.
        _storage[stateSlot] = bytes32((uint256(0xdeadbeef) << 160) | uint256(sqrtPriceX96));
        _storage[bytes32(uint256(stateSlot) + LIQUIDITY_OFFSET)] = bytes32(uint256(liquidity));
    }

    /// @notice Simulates being mid-`unlock`, i.e. inside someone's callback.
    function setUnlocked(bool unlocked) external {
        _transient[IS_UNLOCKED_SLOT] = unlocked ? bytes32(uint256(1)) : bytes32(0);
    }
}
