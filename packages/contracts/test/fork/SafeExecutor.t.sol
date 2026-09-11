// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseTest} from "../BaseTest.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {RobinhoodChain} from "@capdao/config/RobinhoodChain.sol";
import {FutarchyExecutor, IExecutionSource} from "@capdao/governance/FutarchyExecutor.sol";

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

interface ISafeFull {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
    function enableModule(address module) external;
    function isModuleEnabled(address module) external view returns (bool);
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function VERSION() external view returns (string memory);
}

contract StubGovernor is IExecutionSource {
    bool private _approved;
    bytes32 private _hash;

    function approve(bytes32 h) external {
        _approved = true;
        _hash = h;
    }

    function executionApproval(bytes32) external view returns (bool, bytes32) {
        return (_approved, _hash);
    }
}

/// @notice The Executor against a **real Safe**, deployed through the real proxy
///         factory on mainnet.
///
/// @dev Audit lesson §6.2(d): "Mock AMMs hide real failures." Capital DAO's fix
///      for H-1 passed against a mock and reverted against real Uniswap, because
///      the mock did not model what the real contract actually did. A Safe module
///      is exactly the same kind of bet — our `MockSafe` implements what we
///      *believe* `execTransactionFromModuleReturnData` does. Only this file
///      checks that belief against the bytecode a treasury would really hold.
contract SafeExecutorForkTest is BaseTest {
    ISafeProxyFactory internal factory;
    ISafeFull internal safe;
    FutarchyExecutor internal executor;
    StubGovernor internal governor;
    MockERC20 internal token;

    address internal recipient = makeAddr("recipient");

    /// @dev Stands in for "an owner nobody controls" (D10). A real deployment
    ///      needs a key that provably does not exist; the point here is that the
    ///      owner never signs anything for the treasury to work.
    address internal constant UNHELD_OWNER = address(0xdead);

    bytes32 internal constant PID = keccak256("fork-proposal");

    function setUp() public {
        _forkMainnet();

        factory = ISafeProxyFactory(RobinhoodChain.SAFE_PROXY_FACTORY);

        address[] memory owners = new address[](1);
        owners[0] = UNHELD_OWNER;

        bytes memory initializer = abi.encodeCall(
            ISafeFull.setup,
            (owners, 1, address(0), "", address(0), address(0), 0, payable(address(0)))
        );
        safe = ISafeFull(
            factory.createProxyWithNonce(RobinhoodChain.SAFE_SINGLETON_L2, initializer, 0)
        );

        governor = new StubGovernor();
        executor = new FutarchyExecutor(address(safe), address(governor));

        // Only the Safe may enable its own modules. A real deployment does this
        // in `setup`, or via one owner-signed transaction before the keys are
        // discarded; neither is what this file is testing.
        vm.prank(address(safe));
        safe.enableModule(address(executor));

        token = new MockERC20("Treasury Token", "TRS", 6);
        token.mint(address(safe), 1_000_000e6);
        vm.deal(address(safe), 10 ether);
    }

    function _hash(FutarchyExecutor.Call[] calldata calls) external view returns (bytes32) {
        return executor.hashActions(calls);
    }

    function _approve(FutarchyExecutor.Call[] memory calls) internal {
        governor.approve(this._hash(calls));
    }

    function test_theSafeIsGenuine() public view {
        assertEq(safe.VERSION(), "1.4.1", "not a real Safe");
        assertTrue(safe.isModuleEnabled(address(executor)), "module not enabled");
        assertTrue(executor.isEnabled());
    }

    /// @dev D10 in one assertion: the treasury's only owner is an address nobody
    ///      holds, so the module is the sole route to the money.
    function test_theTreasuryHasNoUsableHumanSigner() public view {
        address[] memory owners = safe.getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], UNHELD_OWNER);
        assertEq(safe.getThreshold(), 1);
    }

    /// @dev The whole point: a market decision moves real money out of a real
    ///      Safe, with no human signature anywhere in the path.
    function test_anApprovedBatchMovesRealFundsThroughARealSafe() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](2);
        calls[0] = FutarchyExecutor.Call({
            target: address(token),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (recipient, 250_000e6))
        });
        calls[1] = FutarchyExecutor.Call({target: recipient, value: 1 ether, data: ""});
        _approve(calls);

        executor.execute(PID, calls);

        assertEq(token.balanceOf(recipient), 250_000e6, "token payout did not land");
        assertEq(recipient.balance, 1 ether, "native payout did not land");
        assertEq(token.balanceOf(address(safe)), 750_000e6);
    }

    /// @dev The escape route, attempted against the contract that really has
    ///      `enableModule`. The mock cannot prove this: it only rejects because
    ///      we told it to. Here the call would genuinely have worked.
    function test_ATTACK_cannotAttachASecondModuleToARealSafe() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({
            target: address(safe),
            value: 0,
            data: abi.encodeCall(ISafeFull.enableModule, (address(0xBAD)))
        });
        _approve(calls);

        vm.expectRevert(abi.encodeWithSelector(FutarchyExecutor.CannotCallTheSafe.selector, 0));
        executor.execute(PID, calls);

        assertFalse(safe.isModuleEnabled(address(0xBAD)), "treasury escaped futarchy");
    }

    /// @dev Proof the above is a real defence and not a Safe quirk: the same call
    ///      made directly by the Safe does attach the module. The rule is load
    ///      bearing.
    function test_theSameCallWouldHaveWorkedWithoutTheRule() public {
        vm.prank(address(safe));
        safe.enableModule(address(0xBAD));
        assertTrue(safe.isModuleEnabled(address(0xBAD)), "premise wrong: the call is a no-op");
    }

    function test_ATTACK_replayIsRejectedAgainstARealSafe() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({
            target: address(token),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (recipient, 100_000e6))
        });
        _approve(calls);

        executor.execute(PID, calls);
        vm.expectRevert(abi.encodeWithSelector(FutarchyExecutor.AlreadyExecuted.selector, PID));
        executor.execute(PID, calls);

        assertEq(token.balanceOf(recipient), 100_000e6, "paid twice");
    }

    /// @dev A module the Safe has not enabled must be inert, whatever the
    ///      Governor says.
    function test_anUnenabledModuleCannotSpend() public {
        FutarchyExecutor stray = new FutarchyExecutor(address(safe), address(governor));
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({
            target: address(token),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (recipient, 1e6))
        });
        governor.approve(this._hash(calls));

        assertFalse(stray.isEnabled());
        vm.expectRevert();
        stray.execute(PID, calls);
        assertEq(token.balanceOf(recipient), 0);
    }
}
