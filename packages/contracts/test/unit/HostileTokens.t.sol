// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ConditionalToken} from "../../src/conditional/ConditionalToken.sol";
import {ConditionalVault} from "../../src/conditional/ConditionalVault.sol";
import {IConditionalVault, Outcome} from "../../src/interfaces/IConditionalVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockFeeOnTransferERC20} from "../mocks/MockFeeOnTransferERC20.sol";

/// @notice What happens when the underlying does not behave.
///
/// @dev The vault's conservation law assumes `transferFrom(x)` moves exactly
///      `x`. Fee-on-transfer and rebasing tokens break that assumption silently
///      — they return true and emit a normal event while delivering less. If the
///      vault credited the requested amount it would mint claims it cannot
///      honour, and the shortfall would be discovered by whoever redeemed last.
///
///      `_pullExact` measures the balance delta and reverts on a mismatch. That
///      guard was written, documented, and never once executed. These tests are
///      the evidence.
contract HostileTokensTest is Test {
    ConditionalVault internal vault;
    MockFeeOnTransferERC20 internal feeToken;

    address internal governor = makeAddr("governor");
    address internal alice = makeAddr("alice");

    bytes32 internal constant QID = keccak256("hostile");

    function setUp() public {
        vault = new ConditionalVault(governor);
        feeToken = new MockFeeOnTransferERC20("Fee Token", "FEE", 18, 100); // 1%

        vm.startPrank(governor);
        vault.openQuestion(QID);
        vault.registerUnderlying(QID, address(feeToken), "FEE");
        vm.stopPrank();

        feeToken.mint(alice, 1_000_000e18);
        vm.prank(alice);
        feeToken.approve(address(vault), type(uint256).max);
    }

    /// @notice The guard fires. A token that skims 1% cannot be split.
    /// @dev Rejecting is the only safe answer. Crediting the delivered amount
    ///      instead would look accommodating and quietly make the vault's
    ///      accounting depend on a token's good behaviour.
    function test_ATTACK_FeeOnTransferTokenIsRejected() public {
        uint256 asked = 1_000e18;
        uint256 delivered = asked - (asked * 100) / 10_000; // 1% skimmed

        vm.expectRevert(
            abi.encodeWithSelector(IConditionalVault.TransferMismatch.selector, asked, delivered)
        );
        vm.prank(alice);
        vault.split(QID, address(feeToken), asked);
    }

    /// @notice Nothing is left behind by the rejected attempt.
    function test_ARejectedSplitLeavesNoResidue() public {
        vm.expectRevert();
        vm.prank(alice);
        vault.split(QID, address(feeToken), 1_000e18);

        assertEq(feeToken.balanceOf(address(vault)), 0, "vault kept tokens from a failed split");
        assertEq(vault.lockedOf(QID, address(feeToken)), 0, "ledger moved on a failed split");

        (address pass, address fail) = vault.conditionalTokens(QID, address(feeToken));
        assertEq(ConditionalToken(pass).totalSupply(), 0, "claims were minted on a failed split");
        assertEq(ConditionalToken(fail).totalSupply(), 0, "claims were minted on a failed split");
    }

    /// @notice Proof the guard is doing the work, not the token being unusable.
    ///         With the fee switched off the identical call succeeds.
    /// @dev Without this, "the split reverted" could mean the mock is simply
    ///      broken, and the test would prove nothing about the vault.
    function test_TheSameTokenWorksOnceTheFeeIsZero() public {
        feeToken.setFeeBps(0);

        vm.prank(alice);
        vault.split(QID, address(feeToken), 1_000e18);

        assertEq(vault.lockedOf(QID, address(feeToken)), 1_000e18);
        assertEq(feeToken.balanceOf(address(vault)), 1_000e18);
    }

    /// @notice A token that starts honest and turns hostile mid-life is caught
    ///         on the transfer that turns.
    /// @dev The realistic shape of this: an upgradeable token whose owner
    ///         enables a fee later. Everything already in the vault stays
    ///         correctly backed; only new deposits are refused.
    function test_ATokenThatTurnsHostileLaterIsCaughtFromThatPointOn() public {
        feeToken.setFeeBps(0);
        vm.prank(alice);
        vault.split(QID, address(feeToken), 1_000e18);

        feeToken.setFeeBps(50); // the token starts skimming

        vm.expectRevert();
        vm.prank(alice);
        vault.split(QID, address(feeToken), 1_000e18);

        // The earlier deposit is untouched and still fully backed.
        assertEq(vault.lockedOf(QID, address(feeToken)), 1_000e18);
        assertEq(feeToken.balanceOf(address(vault)), 1_000e18, "existing deposit lost backing");
    }

    /// @notice Even a one-wei shortfall is refused.
    /// @dev The guard is exact equality on purpose. A tolerance would be a
    ///      slow leak: each deposit under-backed by a rounding error, and the
    ///      shortfall landing on whoever redeems last.
    function testFuzz_AnyShortfallIsRefused(uint256 feeBps, uint128 amountSeed) public {
        feeBps = bound(feeBps, 1, 10_000);
        uint256 amount = bound(amountSeed, 1, 100_000e18);
        feeToken.setFeeBps(feeBps);

        uint256 delivered = amount - (amount * feeBps) / 10_000;
        vm.assume(delivered != amount); // a fee too small to round to anything is not a shortfall

        vm.expectRevert();
        vm.prank(alice);
        vault.split(QID, address(feeToken), amount);
        assertEq(vault.lockedOf(QID, address(feeToken)), 0);
    }
}
