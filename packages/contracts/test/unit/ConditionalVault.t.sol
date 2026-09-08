// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ConditionalToken} from "../../src/conditional/ConditionalToken.sol";
import {ConditionalVault} from "../../src/conditional/ConditionalVault.sol";
import {IConditionalVault, Outcome} from "../../src/interfaces/IConditionalVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice The conservation law is the vault's whole job:
///
///         underlying held == PASS supply == FAIL supply
///
///         Everything here exists to prove no sequence of calls breaks it.
contract ConditionalVaultTest is Test {
    ConditionalVault internal vault;
    MockERC20 internal usdg;
    address internal governor = makeAddr("governor");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant QID = keccak256("proposal-1");

    function setUp() public {
        vault = new ConditionalVault(governor);
        usdg = new MockERC20("Mock USDG", "USDG", 6); // 6 decimals, like the real thing

        vm.startPrank(governor);
        vault.openQuestion(QID);
        vault.registerUnderlying(QID, address(usdg), "USDG");
        vm.stopPrank();

        usdg.mint(alice, 1_000_000e6);
        usdg.mint(bob, 1_000_000e6);
    }

    function _tokens() internal view returns (ConditionalToken pass, ConditionalToken fail) {
        (address p, address f) = vault.conditionalTokens(QID, address(usdg));
        return (ConditionalToken(p), ConditionalToken(f));
    }

    function _assertConservation() internal view {
        (ConditionalToken pass, ConditionalToken fail) = _tokens();
        uint256 held = usdg.balanceOf(address(vault));
        assertEq(held, vault.lockedOf(QID, address(usdg)), "held != ledger");
        assertEq(pass.totalSupply(), held, "PASS supply != held");
        assertEq(fail.totalSupply(), held, "FAIL supply != held");
    }

    function _split(address who, uint256 amount) internal {
        vm.startPrank(who);
        usdg.approve(address(vault), amount);
        vault.split(QID, address(usdg), amount);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ core

    function test_SplitMintsBothSidesAndConserves() public {
        _split(alice, 100e6);
        (ConditionalToken pass, ConditionalToken fail) = _tokens();

        assertEq(pass.balanceOf(alice), 100e6);
        assertEq(fail.balanceOf(alice), 100e6);
        assertEq(usdg.balanceOf(alice), 1_000_000e6 - 100e6);
        _assertConservation();
    }

    function test_ConditionalsInheritUnderlyingDecimals() public view {
        (ConditionalToken pass, ConditionalToken fail) = _tokens();
        assertEq(pass.decimals(), 6);
        assertEq(fail.decimals(), 6);
        assertEq(pass.symbol(), "pUSDG");
        assertEq(fail.symbol(), "fUSDG");
    }

    /// @dev split-then-merge must be the identity, for any amount.
    function testFuzz_SplitThenMergeIsIdentity(uint128 amountSeed) public {
        uint256 amount = bound(amountSeed, 1, 1_000_000e6);
        uint256 before = usdg.balanceOf(alice);

        _split(alice, amount);
        vm.prank(alice);
        vault.merge(QID, address(usdg), amount);

        assertEq(usdg.balanceOf(alice), before);
        (ConditionalToken pass, ConditionalToken fail) = _tokens();
        assertEq(pass.balanceOf(alice), 0);
        assertEq(fail.balanceOf(alice), 0);
        _assertConservation();
    }

    /// @dev After resolution the winner is made whole to the wei and the loser
    ///      gets nothing — the two sides together return exactly what went in.
    function testFuzz_WinnerRedeemsExactlyWhatWasLocked(
        uint128 aliceSeed,
        uint128 bobSeed,
        bool passWins
    ) public {
        uint256 a = bound(aliceSeed, 1, 500_000e6);
        uint256 b = bound(bobSeed, 1, 500_000e6);
        _split(alice, a);
        _split(bob, b);
        _assertConservation();

        Outcome winner = passWins ? Outcome.Pass : Outcome.Fail;
        vm.prank(governor);
        vault.resolve(QID, winner);

        vm.prank(alice);
        uint256 aOut = vault.redeem(QID, address(usdg));
        vm.prank(bob);
        uint256 bOut = vault.redeem(QID, address(usdg));

        assertEq(aOut, a);
        assertEq(bOut, b);
        assertEq(usdg.balanceOf(address(vault)), 0, "vault should be emptied exactly");
        assertEq(vault.lockedOf(QID, address(usdg)), 0);
    }

    function test_LosingSideRedeemsNothing() public {
        _split(alice, 100e6);
        (ConditionalToken pass, ConditionalToken fail) = _tokens();

        // Alice keeps only the losing side.
        vm.prank(alice);
        assertTrue(pass.transfer(bob, 100e6));

        vm.prank(governor);
        vault.resolve(QID, Outcome.Pass);

        vm.expectRevert(abi.encodeWithSelector(IConditionalVault.NothingToRedeem.selector, alice));
        vm.prank(alice);
        vault.redeem(QID, address(usdg));

        vm.prank(bob);
        assertEq(vault.redeem(QID, address(usdg)), 100e6);
        assertEq(fail.balanceOf(alice), 100e6); // worthless, but still held
    }

    // ------------------------------------------------------------- access

    function test_OnlyGovernorControlsLifecycle() public {
        bytes32 other = keccak256("proposal-2");

        vm.expectRevert(abi.encodeWithSelector(IConditionalVault.Unauthorized.selector, alice));
        vm.prank(alice);
        vault.openQuestion(other);

        vm.expectRevert(abi.encodeWithSelector(IConditionalVault.Unauthorized.selector, alice));
        vm.prank(alice);
        vault.resolve(QID, Outcome.Pass);

        vm.expectRevert(abi.encodeWithSelector(IConditionalVault.Unauthorized.selector, alice));
        vm.prank(alice);
        vault.registerUnderlying(QID, address(usdg), "X");
    }

    function test_OnlyVaultCanMintOrBurnConditionals() public {
        _split(alice, 100e6);
        (ConditionalToken pass,) = _tokens();

        vm.expectRevert(abi.encodeWithSelector(ConditionalToken.Unauthorized.selector, alice));
        vm.prank(alice);
        pass.mint(alice, 1e6);

        vm.expectRevert(abi.encodeWithSelector(ConditionalToken.Unauthorized.selector, alice));
        vm.prank(alice);
        pass.burn(alice, 1e6);
    }

    function test_ConditionalTokenCannotBeReinitialized() public {
        (ConditionalToken pass,) = _tokens();
        vm.expectRevert(ConditionalToken.AlreadyInitialized.selector);
        pass.initialize("Evil", "EVIL", 18);
    }

    // ------------------------------------------------------------- states

    function test_SplitAndMergeClosedAfterResolution() public {
        _split(alice, 100e6);
        vm.prank(governor);
        vault.resolve(QID, Outcome.Pass);

        vm.startPrank(alice);
        usdg.approve(address(vault), 1e6);
        vm.expectRevert(abi.encodeWithSelector(IConditionalVault.QuestionNotOpen.selector, QID));
        vault.split(QID, address(usdg), 1e6);
        vm.expectRevert(abi.encodeWithSelector(IConditionalVault.QuestionNotOpen.selector, QID));
        vault.merge(QID, address(usdg), 1e6);
        vm.stopPrank();
    }

    function test_RedeemClosedBeforeResolution() public {
        _split(alice, 100e6);
        vm.expectRevert(abi.encodeWithSelector(IConditionalVault.QuestionNotResolved.selector, QID));
        vm.prank(alice);
        vault.redeem(QID, address(usdg));
    }

    function test_PredictedTokenAddressMatchesTheDeployedOne() public {
        bytes32 other = keccak256("proposal-3");
        address predictedPass = vault.predictConditionalToken(other, address(usdg), Outcome.Pass);
        address predictedFail = vault.predictConditionalToken(other, address(usdg), Outcome.Fail);

        vm.startPrank(governor);
        vault.openQuestion(other);
        (address pass, address fail) = vault.registerUnderlying(other, address(usdg), "USDG");
        vm.stopPrank();

        // Predictable by design, so pool addresses are knowable in advance —
        // which is exactly why seeding must absorb a pre-existing donation (D7).
        assertEq(pass, predictedPass);
        assertEq(fail, predictedFail);
    }
}
