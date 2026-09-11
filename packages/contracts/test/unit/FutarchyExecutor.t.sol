// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

import {FutarchyExecutor, IExecutionSource} from "../../src/governance/FutarchyExecutor.sol";
import {Operation} from "../../src/interfaces/ISafe.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockSafe} from "../mocks/MockSafe.sol";

/// @notice Answers the Executor's one question, so these tests need no Governor.
contract MockGovernor is IExecutionSource {
    mapping(bytes32 => bool) public approved;
    mapping(bytes32 => bytes32) public hashes;

    function approve(bytes32 proposalId, bytes32 actionsHash) external {
        approved[proposalId] = true;
        hashes[proposalId] = actionsHash;
    }

    function executionApproval(bytes32 proposalId) external view returns (bool, bytes32) {
        return (approved[proposalId], hashes[proposalId]);
    }
}

/// @notice The Executor is the only thing that can spend a treasury, so these
///         tests are mostly about the ways a passed proposal might try to become
///         something other than what the market approved.
contract FutarchyExecutorTest is Test {
    FutarchyExecutor internal executor;
    MockSafe internal safe;
    MockGovernor internal governor;
    MockERC20 internal usdg;

    address internal recipient = makeAddr("recipient");
    address internal anyone = makeAddr("anyone");

    bytes32 internal constant PID = keccak256("proposal-1");

    function setUp() public {
        safe = new MockSafe();
        governor = new MockGovernor();
        executor = new FutarchyExecutor(address(safe), address(governor));
        safe.enableModule(address(executor));

        usdg = new MockERC20("Mock USDG", "USDG", 6);
        usdg.mint(address(safe), 1_000_000e6);
        vm.deal(address(safe), 100 ether);
    }

    function _payout(uint256 amount) internal view returns (FutarchyExecutor.Call[] memory calls) {
        calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({
            target: address(usdg),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (recipient, amount))
        });
    }

    function _approve(FutarchyExecutor.Call[] memory calls) internal {
        governor.approve(PID, _hash(calls));
    }

    /// @dev `hashActions` takes calldata, so route through an external call.
    function _hash(FutarchyExecutor.Call[] memory calls) internal view returns (bytes32) {
        return this.hashHelper(PID, calls);
    }

    function hashHelper(bytes32 pid, FutarchyExecutor.Call[] calldata calls)
        external
        view
        returns (bytes32)
    {
        return executor.hashActions(pid, calls);
    }

    // ------------------------------------------------------------ happy path

    function test_ApprovedBatchSpendsTheTreasury() public {
        FutarchyExecutor.Call[] memory calls = _payout(50_000e6);
        _approve(calls);

        vm.prank(anyone); // deliberately permissionless
        executor.execute(PID, calls);

        assertEq(usdg.balanceOf(recipient), 50_000e6);
        assertTrue(executor.executed(PID));
    }

    function test_MultiCallBatchRunsInOrder() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](3);
        for (uint256 i = 0; i < 3; i++) {
            calls[i] = FutarchyExecutor.Call({
                target: address(usdg),
                value: 0,
                data: abi.encodeCall(IERC20.transfer, (recipient, 1_000e6))
            });
        }
        _approve(calls);
        executor.execute(PID, calls);

        assertEq(usdg.balanceOf(recipient), 3_000e6);
        assertEq(safe.callCount(), 3);
    }

    function test_BatchCanMoveNativeValue() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({target: recipient, value: 1 ether, data: ""});
        _approve(calls);

        executor.execute(PID, calls);
        assertEq(recipient.balance, 1 ether);
    }

    // ----------------------------------------------- escaping futarchy: rule 1

    /// @dev The attack that matters most. `enableModule` is an ordinary call to
    ///      the Safe's own address, so without this rule a single passed proposal
    ///      attaches a second module and the treasury answers to nobody, forever.
    function test_ATTACK_BatchCannotCallTheSafeToAddAnotherModule() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({
            target: address(safe),
            value: 0,
            data: abi.encodeCall(MockSafe.enableModule, (address(0xBAD)))
        });
        _approve(calls);

        vm.expectRevert(abi.encodeWithSelector(FutarchyExecutor.CannotCallTheSafe.selector, 0));
        executor.execute(PID, calls);

        assertFalse(safe.isModuleEnabled(address(0xBAD)), "a second module was attached");
    }

    /// @dev Hiding the Safe call behind honest ones must not work either.
    function test_ATTACK_ASafeCallSmuggledLaterInTheBatchIsCaught() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](3);
        calls[0] = FutarchyExecutor.Call({
            target: address(usdg), value: 0, data: abi.encodeCall(IERC20.transfer, (recipient, 1e6))
        });
        calls[1] = FutarchyExecutor.Call({
            target: address(usdg), value: 0, data: abi.encodeCall(IERC20.transfer, (recipient, 1e6))
        });
        calls[2] = FutarchyExecutor.Call({
            target: address(safe),
            value: 0,
            data: abi.encodeCall(MockSafe.enableModule, (address(0xBAD)))
        });
        _approve(calls);

        vm.expectRevert(abi.encodeWithSelector(FutarchyExecutor.CannotCallTheSafe.selector, 2));
        executor.execute(PID, calls);

        // Atomic: the two honest transfers are rolled back with the third.
        assertEq(usdg.balanceOf(recipient), 0, "partial batch survived");
        assertFalse(executor.executed(PID), "proposal marked executed despite reverting");
    }

    // ----------------------------------------------- escaping futarchy: rule 2

    /// @dev Rule 1 alone is not enough: a delegatecall to any contract runs in
    ///      the Safe's own storage and can rewrite the module list without the
    ///      Safe ever being named as a target. The operation is not a parameter,
    ///      so the proof is that the Safe is only ever handed `Call`.
    function test_ATTACK_ExecutorNeverDelegatecalls() public {
        FutarchyExecutor.Call[] memory calls = _payout(1e6);
        _approve(calls);
        executor.execute(PID, calls);

        assertEq(uint256(safe.lastOperation()), uint256(Operation.Call));
        assertFalse(safe.sawDelegateCall(), "executor handed the Safe a delegatecall");
    }

    // ------------------------------------------------------- binding + replay

    function test_ATTACK_TamperedBatchIsRejected() public {
        FutarchyExecutor.Call[] memory approvedCalls = _payout(1_000e6);
        _approve(approvedCalls);

        // Same shape, bigger number.
        FutarchyExecutor.Call[] memory tampered = _payout(900_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                FutarchyExecutor.WrongActions.selector, _hash(approvedCalls), _hash(tampered)
            )
        );
        executor.execute(PID, tampered);
        assertEq(usdg.balanceOf(recipient), 0);
    }

    function test_ATTACK_BatchCannotBeReplayed() public {
        FutarchyExecutor.Call[] memory calls = _payout(50_000e6);
        _approve(calls);
        executor.execute(PID, calls);

        vm.expectRevert(abi.encodeWithSelector(FutarchyExecutor.AlreadyExecuted.selector, PID));
        executor.execute(PID, calls);

        assertEq(usdg.balanceOf(recipient), 50_000e6, "paid out twice");
    }

    /// @dev A batch approved for one proposal must not run under another, even
    ///      though the calls are byte-identical — the proposal id is hashed in.
    function test_ATTACK_BatchApprovedForOneProposalCannotRunUnderAnother() public {
        FutarchyExecutor.Call[] memory calls = _payout(50_000e6);
        _approve(calls);

        bytes32 other = keccak256("proposal-2");
        governor.approve(other, _hash(calls)); // same hash, different proposal

        vm.expectRevert(); // WrongActions: the id is part of the fingerprint
        executor.execute(other, calls);
    }

    function test_UnapprovedProposalCannotExecute() public {
        FutarchyExecutor.Call[] memory calls = _payout(1_000e6);
        // Never approved.
        vm.expectRevert(abi.encodeWithSelector(FutarchyExecutor.NotApproved.selector, PID));
        executor.execute(PID, calls);
    }

    // ------------------------------------------------------------- behaviour

    function test_FailingCallRevertsTheWholeBatch() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](2);
        calls[0] = FutarchyExecutor.Call({
            target: address(usdg),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (recipient, 1_000e6))
        });
        // More than the Safe holds.
        calls[1] = FutarchyExecutor.Call({
            target: address(usdg),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (recipient, 10_000_000e6))
        });
        _approve(calls);

        vm.expectRevert();
        executor.execute(PID, calls);
        assertEq(usdg.balanceOf(recipient), 0, "half a treasury instruction happened");
    }

    function test_EmptyBatchIsRejected() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](0);
        vm.expectRevert(FutarchyExecutor.EmptyBatch.selector);
        executor.execute(PID, calls);
    }

    function test_ReportsWhetherTheSafeHasEnabledIt() public {
        assertTrue(executor.isEnabled());

        FutarchyExecutor stray = new FutarchyExecutor(address(safe), address(governor));
        assertFalse(stray.isEnabled(), "an unenabled module claimed to be enabled");
    }

    function test_ConstructorRejectsZeroAddresses() public {
        vm.expectRevert(FutarchyExecutor.ZeroAddress.selector);
        new FutarchyExecutor(address(0), address(governor));

        vm.expectRevert(FutarchyExecutor.ZeroAddress.selector);
        new FutarchyExecutor(address(safe), address(0));
    }
}
