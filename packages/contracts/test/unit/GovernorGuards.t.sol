// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {FutarchyGovernor} from "../../src/governance/FutarchyGovernor.sol";
import {MarketFactory} from "../../src/governance/MarketFactory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice The Governor's defensive checks, firing.
///
/// @dev Separate from FutarchyGovernor.t.sol because that contract is already
///      at the initcode limit — it embeds the creation code of everything it
///      deploys, and adding more tests to it eventually stops compiling.
contract GovernorGuardsTest is Test {
    FutarchyGovernor internal governor;
    MarketFactory internal factory;
    MockERC20 internal base;
    MockERC20 internal quote;

    address internal guardian = makeAddr("guardian");
    address internal proposer = makeAddr("proposer");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        vm.warp(1_000_000);
        base = new MockERC20("Base", "BASE", 18);
        quote = new MockERC20("Quote", "QUOTE", 6);
        factory = new MarketFactory();

        governor = new FutarchyGovernor(
            address(base),
            address(quote),
            address(factory),
            guardian,
            0,
            1e3,
            1 hours,
            2 hours,
            5 minutes
        );

        base.mint(proposer, 1_000_000e18);
        quote.mint(proposer, 1_000_000e6);
        vm.startPrank(proposer);
        base.approve(address(governor), type(uint256).max);
        quote.approve(address(governor), type(uint256).max);
        vm.stopPrank();
    }

    function _propose() internal returns (bytes32) {
        vm.prank(proposer);
        return governor.propose("ipfs://x", keccak256("d"), keccak256("a"), false);
    }

    // --------------------------------------------------------- construction

    function test_TheGovernorRefusesADegenerateConstruction() public {
        vm.expectRevert(FutarchyGovernor.ZeroAddress.selector);
        new FutarchyGovernor(
            address(0), address(quote), address(factory), guardian, 0, 1e3, 1, 1, 1
        );

        vm.expectRevert(FutarchyGovernor.ZeroAddress.selector);
        new FutarchyGovernor(address(base), address(0), address(factory), guardian, 0, 1e3, 1, 1, 1);

        vm.expectRevert(FutarchyGovernor.ZeroAddress.selector);
        new FutarchyGovernor(address(base), address(quote), address(0), guardian, 0, 1e3, 1, 1, 1);
    }

    // ---------------------------------------------------------------- launch

    /// @dev Seeding nothing would open a market with no book at all, whose price
    ///      is undefined and whose oracle would have nothing to anchor to.
    function test_LaunchingWithNothingToSeedIsRefused() public {
        bytes32 id = _propose();
        vm.startPrank(proposer);
        vm.expectRevert(FutarchyGovernor.ZeroAmount.selector);
        governor.launch(id, 0, 2_000e6);
        vm.expectRevert(FutarchyGovernor.ZeroAmount.selector);
        governor.launch(id, 1_000e18, 0);
        vm.stopPrank();
    }

    function test_LaunchingAnUnknownProposalIsRefused() public {
        bytes32 ghost = keccak256("never proposed");
        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                FutarchyGovernor.WrongState.selector, ghost, FutarchyGovernor.State.None
            )
        );
        governor.launch(ghost, 1_000e18, 2_000e6);
    }

    // ---------------------------------------------------------------- cancel

    /// @dev Before launch, only the proposer or the guardian may withdraw it.
    ///      Anyone else cancelling would be a free denial of service on the
    ///      whole proposal queue.
    function test_AStrangerCannotCancelAProposalBeforeLaunch() public {
        bytes32 id = _propose();
        vm.expectRevert(abi.encodeWithSelector(FutarchyGovernor.Unauthorized.selector, stranger));
        vm.prank(stranger);
        governor.cancel(id);
    }

    function test_TheGuardianCanCancelBeforeLaunchToo() public {
        bytes32 id = _propose();
        vm.prank(guardian);
        governor.cancel(id);
        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Cancelled));
    }

    /// @dev Cancelling something already finished is a no-op at best and a state
    ///      corruption at worst, so it is refused outright.
    function test_ASettledProposalCannotBeCancelled() public {
        bytes32 id = _propose();
        vm.prank(proposer);
        governor.cancel(id);

        vm.expectRevert(
            abi.encodeWithSelector(
                FutarchyGovernor.WrongState.selector, id, FutarchyGovernor.State.Cancelled
            )
        );
        vm.prank(guardian);
        governor.cancel(id);
    }

    // ----------------------------------------------------------- reclaimSeed

    function test_SeedCannotBeReclaimedBeforeTheProposalSettles() public {
        bytes32 id = _propose();
        vm.expectRevert(
            abi.encodeWithSelector(
                FutarchyGovernor.WrongState.selector, id, FutarchyGovernor.State.Proposed
            )
        );
        vm.prank(proposer);
        governor.reclaimSeed(id);
    }

    // ------------------------------------------------------------------ views

    /// @dev `proposalOf` is the whole record in one call — what an indexer or a
    ///      frontend reads. Never exercised until now, which means nothing
    ///      guaranteed it even decoded.
    function test_ProposalOfReturnsTheWholeRecord() public {
        bytes32 id = _propose();
        FutarchyGovernor.Proposal memory p = governor.proposalOf(id);

        assertEq(uint256(p.state), uint256(FutarchyGovernor.State.Proposed));
        assertEq(p.proposer, proposer);
        assertEq(p.descriptionHash, keccak256("d"));
        assertEq(p.actionsHash, keccak256("a"));
        assertFalse(p.teamSponsored);
        assertEq(p.seeder, address(0), "nobody has seeded yet");
        assertEq(address(p.passAmm), address(0), "no markets before launch");
    }

    function test_ThresholdIsPureAndSymmetricAroundTheFailPrice() public view {
        // External: must clear the fail market by 3%.
        assertEq(governor.thresholdFor(0, false), 0, "zero should stay zero");
        assertEq(governor.thresholdFor(1_000e6, false), 1_030e6);
        // Team-sponsored: survives unless the fail market is 3% higher.
        assertEq(governor.thresholdFor(1_000e6, true), 970e6);
    }
}
