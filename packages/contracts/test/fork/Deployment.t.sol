// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FutarchyDeployer} from "../../script/FutarchyDeployer.sol";
import {console2} from "forge-std/console2.sol";

import {BaseTest} from "../BaseTest.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ConditionalAmm} from "@capdao/amm/ConditionalAmm.sol";
import {RobinhoodChain} from "@capdao/config/RobinhoodChain.sol";
import {FutarchyExecutor} from "@capdao/governance/FutarchyExecutor.sol";
import {FutarchyGovernor} from "@capdao/governance/FutarchyGovernor.sol";
import {LaggedTwapOracle} from "@capdao/oracle/LaggedTwapOracle.sol";

/// @notice A full rehearsal: deploy the whole system against a real Safe on a
///         forked chain, then run a proposal through it until the treasury pays.
///
/// @dev This exists because the deploy script cannot otherwise be run before the
///      day it matters. Every other test builds its world with mocks and
///      convenient pranks; this one goes through the real proxy factory, the real
///      Safe, and the same ordering the script uses — including the awkward part
///      where the deployer must briefly own the treasury in order to switch the
///      module on, and must then hand ownership to nobody.
contract DeploymentForkTest is BaseTest {
    using FutarchyDeployer for FutarchyDeployer.Config;

    FutarchyDeployer.Deployment internal d;
    FutarchyGovernor internal governor;
    FutarchyExecutor internal executor;

    MockERC20 internal token;
    MockERC20 internal quoteToken;

    address internal constant UNHELD_OWNER = address(0xdead);
    address internal guardian = makeAddr("guardian");
    address internal payee = makeAddr("payee");
    address internal trader = makeAddr("trader");

    uint64 internal constant DELAY = 24 hours;
    uint64 internal constant WINDOW = 72 hours;
    uint64 internal constant MAX_STEP = 5 minutes;
    uint256 internal constant SEED_BASE = 1_000e18;
    uint256 internal constant SEED_QUOTE = 2_000e6;
    uint256 internal constant ANCHOR = 2e6;
    uint256 internal constant RATE = ANCHOR / 2100;

    function setUp() public {
        _forkMainnet();

        token = new MockERC20("Project", "PRJ", 18);
        quoteToken = new MockERC20("Mock USDG", "USDG", 6);

        FutarchyDeployer.Config memory cfg = FutarchyDeployer.Config({
            safeSingleton: RobinhoodChain.SAFE_SINGLETON_L2,
            safeProxyFactory: RobinhoodChain.SAFE_PROXY_FACTORY,
            baseToken: address(token),
            quoteToken: address(quoteToken),
            guardian: guardian,
            unheldOwner: UNHELD_OWNER,
            baseToStake: 1_000e18,
            maxChangePerSecond: RATE,
            delay: DELAY,
            window: WINDOW,
            maxStepElapsed: MAX_STEP,
            saltNonce: uint256(keccak256("rehearsal"))
        });

        // `deploy` verifies its own result and reverts if the handover failed.
        d = cfg.deploy(address(this));
        governor = FutarchyGovernor(d.governor);
        executor = FutarchyExecutor(d.executor);

        quoteToken.mint(d.safe, 500_000e6); // the treasury
        token.mint(address(this), 1_000_000e18);
        quoteToken.mint(address(this), 1_000_000e6);
        token.mint(trader, 1_000_000e18);
        quoteToken.mint(trader, 1_000_000e6);

        token.approve(d.governor, type(uint256).max);
        quoteToken.approve(d.governor, type(uint256).max);
        vm.startPrank(trader);
        token.approve(address(governor.VAULT()), type(uint256).max);
        quoteToken.approve(address(governor.VAULT()), type(uint256).max);
        vm.stopPrank();
    }

    // ------------------------------------------------------------- the wiring

    function test_theTreasuryIsReachableOnlyThroughTheExecutor() public view {
        (bool okModule,) =
            d.safe.staticcall(abi.encodeWithSignature("isModuleEnabled(address)", d.executor));
        assertTrue(okModule);
        assertTrue(executor.isEnabled(), "executor is not an enabled module");

        (, bytes memory ownersRaw) = d.safe.staticcall(abi.encodeWithSignature("getOwners()"));
        address[] memory owners = abi.decode(ownersRaw, (address[]));
        assertEq(owners.length, 1, "more than one owner survived deployment");
        assertEq(owners[0], UNHELD_OWNER, "deployer still owns the treasury");
        assertTrue(owners[0] != address(this), "deployer kept the keys");
    }

    function test_theVaultAnswersOnlyToTheGovernor() public view {
        assertEq(governor.VAULT().governor(), d.governor);
        assertEq(d.vault, address(governor.VAULT()));
    }

    /// @dev The handover is the step most likely to be silently skipped, so the
    ///      deployer must genuinely have lost the ability to move funds.
    function test_theDeployerCannotSpendAfterHandover() public {
        bytes memory payout = abi.encodeCall(IERC20.transfer, (payee, 100_000e6));
        bytes memory sig =
            abi.encodePacked(bytes32(uint256(uint160(address(this)))), bytes32(0), uint8(1));

        (bool ok,) = d.safe
            .call(
                abi.encodeWithSignature(
                    "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)",
                    address(quoteToken),
                    uint256(0),
                    payout,
                    uint8(0),
                    uint256(0),
                    uint256(0),
                    uint256(0),
                    address(0),
                    address(0),
                    sig
                )
            );
        assertFalse(ok, "the deployer could still move treasury funds");
        assertEq(quoteToken.balanceOf(payee), 0);
    }

    // -------------------------------------------------- a proposal, for real

    function test_aProposalRunsEndToEndOnTheDeployedSystem() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({
            target: address(quoteToken),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (payee, 120_000e6))
        });

        bytes32 id = governor.propose(
            "ipfs://pay-the-contributor",
            keccak256("pay the contributor"),
            this.hashHelper(calls),
            false
        );
        governor.launch(id, SEED_BASE, SEED_QUOTE);

        _crank(id, DELAY);
        _buyPass(id, 600e6);
        _crank(id, WINDOW);

        governor.finalize(id);
        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Passed));

        executor.execute(id, calls);
        assertEq(quoteToken.balanceOf(payee), 120_000e6, "the deployed treasury did not pay out");
    }

    /// @notice What a real deployment costs, measured rather than guessed.
    /// @dev Also a guard: if the system grows past what a deployer can afford to
    ///      put on chain, that should fail here rather than be discovered with a
    ///      half-deployed treasury.
    function test_measureDeploymentGas() public {
        FutarchyDeployer.Config memory cfg = FutarchyDeployer.Config({
            safeSingleton: RobinhoodChain.SAFE_SINGLETON_L2,
            safeProxyFactory: RobinhoodChain.SAFE_PROXY_FACTORY,
            baseToken: address(token),
            quoteToken: address(quoteToken),
            guardian: guardian,
            unheldOwner: UNHELD_OWNER,
            baseToStake: 1_000e18,
            maxChangePerSecond: RATE,
            delay: DELAY,
            window: WINDOW,
            maxStepElapsed: MAX_STEP,
            saltNonce: uint256(keccak256("gas-measurement"))
        });

        uint256 before = gasleft();
        FutarchyDeployer.deploy(cfg, address(this));
        uint256 used = before - gasleft();

        console2.log("deployment gas used:", used);
        console2.log("  at 0.01 gwei (testnet), wei:", used * 10_000_000);
        console2.log("  at 0.115 gwei (mainnet), wei:", used * 115_000_000);

        assertLt(used, 30_000_000, "deployment has grown beyond a sane budget");
    }

    /// @notice What using the system costs, phase by phase. The launch is the
    ///         expensive one: it deploys two pools, two recorders and four
    ///         conditional tokens in a single transaction.
    function test_measureProposalGas() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({
            target: address(quoteToken),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (payee, 1e6))
        });

        uint256 g = gasleft();
        bytes32 id = governor.propose("ipfs://d", keccak256("d"), this.hashHelper(calls), false);
        console2.log("propose      :", g - gasleft());

        g = gasleft();
        governor.launch(id, SEED_BASE, SEED_QUOTE);
        console2.log("launch       :", g - gasleft());

        (, LaggedTwapOracle po,) = _markets(id);
        vm.warp(block.timestamp + 300);
        g = gasleft();
        po.poke();
        console2.log("one poke     :", g - gasleft());

        _crank(id, DELAY);
        _buyPass(id, 600e6); // the market has to actually say yes
        _crank(id, WINDOW);

        g = gasleft();
        governor.finalize(id);
        console2.log("finalize     :", g - gasleft());

        g = gasleft();
        executor.execute(id, calls);
        console2.log("execute      :", g - gasleft());
    }

    // ------------------------------------------------------------- helpers

    function hashHelper(FutarchyExecutor.Call[] calldata calls) external view returns (bytes32) {
        return executor.hashActions(calls);
    }

    function _markets(bytes32 id)
        internal
        view
        returns (ConditionalAmm passAmm, LaggedTwapOracle po, LaggedTwapOracle fo)
    {
        (address a,, address c, address dd) = governor.marketsOf(id);
        return (ConditionalAmm(a), LaggedTwapOracle(c), LaggedTwapOracle(dd));
    }

    function _crank(bytes32 id, uint64 duration) internal {
        (, LaggedTwapOracle po, LaggedTwapOracle fo) = _markets(id);
        uint64 end = uint64(block.timestamp) + duration;
        while (block.timestamp + MAX_STEP <= end) {
            vm.warp(block.timestamp + MAX_STEP);
            po.poke();
            fo.poke();
        }
        vm.warp(end);
        po.poke();
        fo.poke();
    }

    function _buyPass(bytes32 id, uint256 quoteIn) internal {
        (ConditionalAmm passAmm,,) = _markets(id);
        vm.startPrank(trader);
        governor.VAULT().split(id, address(token), 1e18);
        governor.VAULT().split(id, address(quoteToken), quoteIn);
        IERC20(passAmm.quote()).approve(address(passAmm), quoteIn);
        passAmm.swapExactQuoteForBase(quoteIn, 0);
        vm.stopPrank();
    }
}
