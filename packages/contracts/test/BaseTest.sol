// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {RobinhoodChain} from "@capdao/config/RobinhoodChain.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Shared base for Capital DAO tests.
/// @dev Inherit this rather than `Test` directly so every test gets the same
///      named actors and unit helpers. Keeps tests readable and stops each new
///      test file from inventing its own `alice`.
abstract contract BaseTest is Test {
    // --- actors ---------------------------------------------------------------

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal proposer = makeAddr("proposer");
    address internal treasury = makeAddr("treasury");
    address internal admin = makeAddr("admin");

    // --- unit helpers ---------------------------------------------------------
    //
    // USDG is 6 decimals and the ownership token will be 18. Mixing them up is
    // the most likely way to write a test that passes while the contract is
    // wrong, so always spell the unit out.

    /// @dev 1 USDG == 1e6.
    function usdg(uint256 whole) internal pure returns (uint256) {
        return whole * 10 ** RobinhoodChain.USDG_DECIMALS;
    }

    /// @dev 1 token == 1e18.
    function tokens(uint256 whole) internal pure returns (uint256) {
        return whole * 1e18;
    }

    /// @dev 1 ETH == 1e18.
    function eth(uint256 whole) internal pure returns (uint256) {
        return whole * 1e18;
    }

    // --- assertions -----------------------------------------------------------

    /// @dev Assert `a` and `b` are within `tolerance` basis points of each other.
    ///      Market math rarely lands on an exact wei; assert intent, not noise.
    function assertApproxEqBps(uint256 a, uint256 b, uint256 toleranceBps) internal pure {
        uint256 diff = a > b ? a - b : b - a;
        uint256 base = b == 0 ? 1 : b;
        assertLe((diff * 10_000) / base, toleranceBps, "values differ by more than tolerance");
    }
}
