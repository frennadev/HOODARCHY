// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

import {ConditionalAmm} from "../../src/amm/ConditionalAmm.sol";
import {ConditionalVault} from "../../src/conditional/ConditionalVault.sol";
import {FutarchyExecutor} from "../../src/governance/FutarchyExecutor.sol";
import {FutarchyGovernor} from "../../src/governance/FutarchyGovernor.sol";
import {MarketFactory} from "../../src/governance/MarketFactory.sol";
import {Outcome, QuestionState} from "../../src/interfaces/IConditionalVault.sol";
import {LaggedTwapOracle} from "../../src/oracle/LaggedTwapOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockSafe} from "../mocks/MockSafe.sol";

/// @notice Two proposals live at the same time.
///
/// @dev Every other governor test runs exactly one proposal, so nothing proved
///      two could coexist. They share a governor, a vault and a treasury, and
///      the vault keys everything by question id — which *should* keep them
///      apart. "Should" is the word doing the work, and a keying mistake would
///      be invisible in a single-proposal world while being catastrophic here:
///      one proposal's collateral paying out another's claims.
contract ConcurrentProposalsTest is Test {
    FutarchyGovernor internal governor;
    ConditionalVault internal vault;
    FutarchyExecutor internal executor;
    MockSafe internal safe;
    MockERC20 internal token;
    MockERC20 internal usdgToken;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal payeeA = makeAddr("payeeA");
    address internal payeeB = makeAddr("payeeB");

    uint64 internal constant DELAY = 24 hours;
    uint64 internal constant WINDOW = 72 hours;
    uint64 internal constant MAX_STEP = 5 minutes;
    uint256 internal constant SEED_BASE = 1_000e18;
    uint256 internal constant SEED_QUOTE = 2_000e6;
    uint256 internal constant ANCHOR = 2e6;

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockERC20("Project", "PRJ", 18);
        usdgToken = new MockERC20("Mock USDG", "USDG", 6);

        governor = new FutarchyGovernor(
            address(token),
            address(usdgToken),
            address(new MarketFactory()),
            address(0),
            0, // no stake: this file is about isolation, not the stake gate
            ANCHOR / 2100,
            DELAY,
            WINDOW,
            MAX_STEP
        );
        vault = governor.VAULT();

        safe = new MockSafe();
        executor = new FutarchyExecutor(address(safe), address(governor));
        safe.enableModule(address(executor));
        usdgToken.mint(address(safe), 1_000_000e6);

        for (uint256 i = 0; i < 2; i++) {
            address who = [alice, bob][i];
            token.mint(who, 10_000_000e18);
            usdgToken.mint(who, 10_000_000e6);
            vm.startPrank(who);
            token.approve(address(governor), type(uint256).max);
            usdgToken.approve(address(governor), type(uint256).max);
            token.approve(address(vault), type(uint256).max);
            usdgToken.approve(address(vault), type(uint256).max);
            vm.stopPrank();
        }
    }

    // ------------------------------------------------------------- helpers

    function _proposeAndLaunch(string memory uri, address who) internal returns (bytes32 id) {
        vm.startPrank(who);
        id = governor.propose(uri, keccak256(bytes(uri)), keccak256(bytes(uri)), false);
        governor.launch(id, SEED_BASE, SEED_QUOTE);
        vm.stopPrank();
    }

    function _oracles(bytes32 id) internal view returns (LaggedTwapOracle p, LaggedTwapOracle f) {
        (,, address po, address fo) = governor.marketsOf(id);
        return (LaggedTwapOracle(po), LaggedTwapOracle(fo));
    }

    function _passAmm(bytes32 id) internal view returns (ConditionalAmm) {
        (address a,,,) = governor.marketsOf(id);
        return ConditionalAmm(a);
    }

    /// @dev Cranks both proposals together, as a real crank bot would.
    function _crankBoth(bytes32 a, bytes32 b, uint64 duration) internal {
        (LaggedTwapOracle ap, LaggedTwapOracle af) = _oracles(a);
        (LaggedTwapOracle bp, LaggedTwapOracle bf) = _oracles(b);
        uint64 end = uint64(block.timestamp) + duration;
        while (block.timestamp + MAX_STEP <= end) {
            vm.warp(block.timestamp + MAX_STEP);
            ap.poke();
            af.poke();
            bp.poke();
            bf.poke();
        }
        vm.warp(end);
        ap.poke();
        af.poke();
        bp.poke();
        bf.poke();
    }

    function _buyPass(bytes32 id, address who, uint256 quoteIn) internal {
        ConditionalAmm amm = _passAmm(id);
        vm.startPrank(who);
        vault.split(id, address(token), 1e18);
        vault.split(id, address(usdgToken), quoteIn);
        IERC20(amm.quote()).approve(address(amm), quoteIn);
        amm.swapExactQuoteForBase(quoteIn, 0);
        vm.stopPrank();
    }

    // -------------------------------------------------------------- tests

    function test_TwoProposalsGetCompletelySeparateMarkets() public {
        bytes32 a = _proposeAndLaunch("ipfs://a", alice);
        bytes32 b = _proposeAndLaunch("ipfs://b", bob);

        assertTrue(a != b, "proposal ids collided");

        (address aPass, address aFail, address aPo, address aFo) = governor.marketsOf(a);
        (address bPass, address bFail, address bPo, address bFo) = governor.marketsOf(b);

        assertTrue(aPass != bPass && aPass != bFail, "markets shared between proposals");
        assertTrue(aFail != bPass && aFail != bFail, "markets shared between proposals");
        assertTrue(aPo != bPo && aFo != bFo, "oracles shared between proposals");

        // And separate conditional tokens for the same underlying.
        (address aPassTok,) = vault.conditionalTokens(a, address(token));
        (address bPassTok,) = vault.conditionalTokens(b, address(token));
        assertTrue(aPassTok != bPassTok, "conditional tokens shared between proposals");
    }

    /// @notice The ledgers do not mix. This is the one that would be
    ///         catastrophic and silent if the vault keyed by anything but the
    ///         question id.
    function test_CollateralIsAccountedPerProposal() public {
        bytes32 a = _proposeAndLaunch("ipfs://a", alice);
        bytes32 b = _proposeAndLaunch("ipfs://b", bob);

        assertEq(vault.lockedOf(a, address(token)), SEED_BASE);
        assertEq(vault.lockedOf(b, address(token)), SEED_BASE);

        // Alice deposits more into A only.
        vm.prank(alice);
        vault.split(a, address(token), 500e18);

        assertEq(vault.lockedOf(a, address(token)), SEED_BASE + 500e18, "A did not record it");
        assertEq(vault.lockedOf(b, address(token)), SEED_BASE, "B's ledger moved on A's deposit");

        // The vault holds both, summed.
        assertEq(token.balanceOf(address(vault)), 2 * SEED_BASE + 500e18);
    }

    /// @notice One proposal's claims are worthless in the other's market.
    /// @dev The pools are typed to specific conditional tokens, so this is
    ///      structurally impossible — but "structurally impossible" is what you
    ///      say right before someone finds the way.
    function test_ATTACK_ClaimsFromOneProposalCannotTradeInTheOther() public {
        bytes32 a = _proposeAndLaunch("ipfs://a", alice);
        bytes32 b = _proposeAndLaunch("ipfs://b", bob);

        vm.prank(alice);
        vault.split(a, address(usdgToken), 1_000e6);
        (address aPassQuote,) = vault.conditionalTokens(a, address(usdgToken));

        ConditionalAmm bMarket = _passAmm(b);
        assertTrue(aPassQuote != bMarket.quote(), "B's market accepts A's token");

        // Approving A's token to B's market buys nothing: the market only ever
        // pulls its own quote token, which alice does not hold.
        vm.startPrank(alice);
        IERC20(aPassQuote).approve(address(bMarket), type(uint256).max);
        vm.expectRevert();
        bMarket.swapExactQuoteForBase(1_000e6, 0);
        vm.stopPrank();
    }

    /// @notice Resolving one leaves the other untouched and still tradeable.
    function test_ResolvingOneProposalDoesNotDisturbTheOther() public {
        bytes32 a = _proposeAndLaunch("ipfs://a", alice);
        bytes32 b = _proposeAndLaunch("ipfs://b", bob);

        _crankBoth(a, b, DELAY);
        _buyPass(a, alice, 600e6); // only A gets a real market view
        _crankBoth(a, b, WINDOW);

        governor.finalize(a);

        assertEq(uint256(governor.stateOf(a)), uint256(FutarchyGovernor.State.Passed));
        assertEq(uint256(governor.stateOf(b)), uint256(FutarchyGovernor.State.Active), "B moved");
        assertEq(uint256(vault.stateOf(a)), uint256(QuestionState.Resolved));
        assertEq(
            uint256(vault.stateOf(b)), uint256(QuestionState.Open), "B's question resolved too"
        );

        // B is still a live market: splitting into it still works.
        vm.prank(bob);
        vault.split(b, address(token), 1e18);
    }

    /// @notice Opposite outcomes at the same time, and each executor approval
    ///         is bound to its own proposal.
    function test_OneCanPassWhileTheOtherFails() public {
        bytes32 a = _proposeAndLaunch("ipfs://a", alice);
        bytes32 b = _proposeAndLaunch("ipfs://b", bob);

        _crankBoth(a, b, DELAY);
        _buyPass(a, alice, 600e6); // A's market says yes; B's stays at anchor
        _crankBoth(a, b, WINDOW);

        governor.finalize(a);
        governor.finalize(b);

        assertEq(uint256(governor.stateOf(a)), uint256(FutarchyGovernor.State.Passed));
        assertEq(uint256(governor.stateOf(b)), uint256(FutarchyGovernor.State.Failed));
        assertEq(uint256(vault.winnerOf(a)), uint256(Outcome.Pass));
        assertEq(uint256(vault.winnerOf(b)), uint256(Outcome.Fail));

        (bool aApproved,) = governor.executionApproval(a);
        (bool bApproved,) = governor.executionApproval(b);
        assertTrue(aApproved, "the passing proposal was not unlocked");
        assertFalse(bApproved, "the failing proposal was unlocked");
    }

    /// @notice A passing proposal cannot be used to execute a failing one's
    ///         batch, even from the same governor and treasury.
    function test_ATTACK_APassingProposalCannotCarryAFailingOnesBatch() public {
        FutarchyExecutor.Call[] memory batch = new FutarchyExecutor.Call[](1);
        batch[0] = FutarchyExecutor.Call({
            target: address(usdgToken),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (payeeB, 100_000e6))
        });
        bytes32 wantedHash = this.hashOf(batch);

        // A is proposed with an unrelated batch hash; B wants the payout.
        vm.startPrank(alice);
        bytes32 a = governor.propose("ipfs://a", keccak256("a"), keccak256("unrelated"), false);
        governor.launch(a, SEED_BASE, SEED_QUOTE);
        vm.stopPrank();

        vm.startPrank(bob);
        bytes32 b = governor.propose("ipfs://b", keccak256("b"), wantedHash, false);
        governor.launch(b, SEED_BASE, SEED_QUOTE);
        vm.stopPrank();

        _crankBoth(a, b, DELAY);
        _buyPass(a, alice, 600e6); // A passes, B does not
        _crankBoth(a, b, WINDOW);
        governor.finalize(a);
        governor.finalize(b);

        assertEq(uint256(governor.stateOf(a)), uint256(FutarchyGovernor.State.Passed));
        assertEq(uint256(governor.stateOf(b)), uint256(FutarchyGovernor.State.Failed));

        // Under A: the hash does not match what A recorded.
        vm.expectRevert();
        executor.execute(a, batch);

        // Under B: B never passed.
        vm.expectRevert(abi.encodeWithSelector(FutarchyExecutor.NotApproved.selector, b));
        executor.execute(b, batch);

        assertEq(usdgToken.balanceOf(payeeB), 0, "the treasury paid a rejected proposal");
    }

    function hashOf(FutarchyExecutor.Call[] calldata calls) external view returns (bytes32) {
        return executor.hashActions(calls);
    }
}
