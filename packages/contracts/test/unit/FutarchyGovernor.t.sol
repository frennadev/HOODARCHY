// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, Vm} from "forge-std/Test.sol";

import {ConditionalAmm} from "../../src/amm/ConditionalAmm.sol";
import {ConditionalVault} from "../../src/conditional/ConditionalVault.sol";
import {FutarchyExecutor} from "../../src/governance/FutarchyExecutor.sol";
import {FutarchyGovernor} from "../../src/governance/FutarchyGovernor.sol";
import {MarketFactory} from "../../src/governance/MarketFactory.sol";
import {Outcome, QuestionState} from "../../src/interfaces/IConditionalVault.sol";
import {LaggedTwapOracle} from "../../src/oracle/LaggedTwapOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockSafe} from "../mocks/MockSafe.sol";

/// @notice The Governor is the only piece that makes the others a system, so
///         these tests run whole proposals rather than poking at functions:
///         submit, open the markets, trade them, let the clock run out, and see
///         whether the treasury moves.
contract FutarchyGovernorTest is Test {
    FutarchyGovernor internal governor;
    MarketFactory internal factory;
    ConditionalVault internal vault;
    FutarchyExecutor internal executor;
    MockSafe internal safe;

    MockERC20 internal token; // project token, 18dp
    MockERC20 internal usdg; // quote, 6dp — never assume 18

    address internal proposer = makeAddr("proposer");
    address internal seeder = makeAddr("seeder");
    address internal trader = makeAddr("trader");
    address internal guardian = makeAddr("guardian");
    address internal payee = makeAddr("payee");

    uint64 internal constant DELAY = 24 hours;
    uint64 internal constant WINDOW = 72 hours;
    uint64 internal constant MAX_STEP = 5 minutes;
    uint256 internal constant STAKE = 1_000e18;

    uint256 internal constant SEED_BASE = 1_000e18;
    uint256 internal constant SEED_QUOTE = 2_000e6; // opens at 2 USDG per token
    uint256 internal constant ANCHOR = 2e6;

    /// @dev Sized so the observation can double in ~35 minutes (D8).
    uint256 internal constant RATE = ANCHOR / 2100;

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockERC20("Project", "PRJ", 18);
        usdg = new MockERC20("Mock USDG", "USDG", 6);

        factory = new MarketFactory();
        governor = new FutarchyGovernor(
            address(token),
            address(usdg),
            address(factory),
            guardian,
            STAKE,
            RATE,
            DELAY,
            WINDOW,
            MAX_STEP
        );
        vault = governor.VAULT();

        safe = new MockSafe();
        executor = new FutarchyExecutor(address(safe), address(governor));
        safe.enableModule(address(executor));
        usdg.mint(address(safe), 500_000e6);

        for (uint256 i = 0; i < 3; i++) {
            address who = [proposer, seeder, trader][i];
            token.mint(who, 1_000_000e18);
            usdg.mint(who, 1_000_000e6);
            vm.startPrank(who);
            token.approve(address(governor), type(uint256).max);
            usdg.approve(address(governor), type(uint256).max);
            token.approve(address(vault), type(uint256).max);
            usdg.approve(address(vault), type(uint256).max);
            vm.stopPrank();
        }
    }

    // ------------------------------------------------------------- helpers

    function _propose(bool teamSponsored) internal returns (bytes32 id) {
        vm.prank(proposer);
        id = governor.propose(
            "ipfs://description", keccak256("description"), keccak256("actions"), teamSponsored
        );
    }

    function _launch(bytes32 id) internal {
        vm.prank(seeder);
        governor.launch(id, SEED_BASE, SEED_QUOTE);
    }

    function _markets(bytes32 id)
        internal
        view
        returns (
            ConditionalAmm passAmm,
            ConditionalAmm failAmm,
            LaggedTwapOracle po,
            LaggedTwapOracle fo
        )
    {
        (address a, address b, address c, address d) = governor.marketsOf(id);
        return (ConditionalAmm(a), ConditionalAmm(b), LaggedTwapOracle(c), LaggedTwapOracle(d));
    }

    /// @dev Mints the trader a complete set of both underlyings so they can
    ///      trade either market, which is how a real participant gets exposure.
    function _splitFor(address who, bytes32 id, uint256 baseAmt, uint256 quoteAmt) internal {
        vm.startPrank(who);
        vault.split(id, address(token), baseAmt);
        vault.split(id, address(usdg), quoteAmt);
        vm.stopPrank();
    }

    function _crank(bytes32 id, uint64 duration) internal {
        (,, LaggedTwapOracle po, LaggedTwapOracle fo) = _markets(id);
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

    /// @dev Buys the pass token, which is what "this proposal is good" looks
    ///      like as a trade.
    function _buyPass(bytes32 id, uint256 quoteIn) internal {
        (ConditionalAmm passAmm,,,) = _markets(id);
        _splitFor(trader, id, 1e18, quoteIn);
        vm.startPrank(trader);
        IERC20(passAmm.quote()).approve(address(passAmm), quoteIn);
        passAmm.swapExactQuoteForBase(quoteIn, 0);
        vm.stopPrank();
    }

    /// @dev Redeems only when there is something to redeem. The vault reverts
    ///      on an empty redemption on purpose — it tells a holder of only the
    ///      losing side that they have nothing, rather than quietly succeeding
    ///      with a zero transfer — so a caller sweeping positions has to ask.
    function _redeemIfHolding(address who, bytes32 id, address underlying) internal {
        (address pass, address fail) = vault.conditionalTokens(id, underlying);
        address winner = vault.winnerOf(id) == Outcome.Pass ? pass : fail;
        if (IERC20(winner).balanceOf(who) == 0) return;
        vm.prank(who);
        vault.redeem(id, underlying);
    }

    // --------------------------------------------------------------- propose

    function test_ProposeLocksTheStake() public {
        uint256 before = token.balanceOf(proposer);
        bytes32 id = _propose(false);

        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Proposed));
        assertEq(token.balanceOf(proposer), before - STAKE, "stake not taken");
        assertEq(token.balanceOf(address(governor)), STAKE);
    }

    function test_ProposalIdsAreUnique() public {
        bytes32 a = _propose(false);
        bytes32 b = _propose(false); // identical content
        assertTrue(a != b, "identical proposals collided");
    }

    // ---------------------------------------------------------------- launch

    function test_LaunchOpensBothMarketsAtTheSamePrice() public {
        bytes32 id = _propose(false);
        _launch(id);

        (ConditionalAmm passAmm, ConditionalAmm failAmm, LaggedTwapOracle po, LaggedTwapOracle fo) =
            _markets(id);

        assertEq(passAmm.spotPrice(), ANCHOR, "pass market opened off-anchor");
        assertEq(failAmm.spotPrice(), ANCHOR, "fail market opened off-anchor");
        assertEq(po.observation(), ANCHOR);
        assertEq(fo.observation(), ANCHOR);
        assertEq(uint256(vault.stateOf(id)), uint256(QuestionState.Open));
    }

    /// @dev The point of complete sets: one deposit funds both books to equal
    ///      depth. Seeding two separate markets would cost twice as much and
    ///      leave each half as deep.
    function test_OneSeedFundsBothBooksEqually() public {
        bytes32 id = _propose(false);
        uint256 seederBaseBefore = token.balanceOf(seeder);
        _launch(id);

        (ConditionalAmm passAmm, ConditionalAmm failAmm,,) = _markets(id);
        assertEq(passAmm.reserveBase(), SEED_BASE);
        assertEq(failAmm.reserveBase(), SEED_BASE, "fail book is thinner than pass");
        assertEq(passAmm.reserveQuote(), SEED_QUOTE);
        assertEq(failAmm.reserveQuote(), SEED_QUOTE);

        // Only one lot of capital left the seeder, not two.
        assertEq(token.balanceOf(seeder), seederBaseBefore - SEED_BASE);
    }

    function test_LaunchReturnsTheStake() public {
        bytes32 id = _propose(false);
        uint256 before = token.balanceOf(proposer);
        _launch(id);
        assertEq(token.balanceOf(proposer), before + STAKE, "stake not returned at launch");
    }

    function test_CannotLaunchTwice() public {
        bytes32 id = _propose(false);
        _launch(id);
        vm.prank(seeder);
        vm.expectRevert();
        governor.launch(id, SEED_BASE, SEED_QUOTE);
    }

    // -------------------------------------------------------------- finalize

    function test_CannotFinalizeBeforeTheWindowCloses() public {
        bytes32 id = _propose(false);
        _launch(id);
        _crank(id, DELAY + WINDOW - 1 hours);

        vm.expectRevert(abi.encodeWithSelector(FutarchyGovernor.MarketsNotSettled.selector, id));
        governor.finalize(id);
    }

    function test_ProposalPassesWhenThePassMarketIsClearlyHigher() public {
        bytes32 id = _propose(false);
        _launch(id);

        _crank(id, DELAY); // dark period
        _buyPass(id, 600e6); // the market says yes
        _crank(id, WINDOW);

        governor.finalize(id);

        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Passed));
        assertEq(uint256(vault.winnerOf(id)), uint256(Outcome.Pass));
        (bool approved,) = governor.executionApproval(id);
        assertTrue(approved, "executor not unlocked");
    }

    /// @dev An external proposal that merely ties must lose: it has to clear the
    ///      fail market by 3%, not match it.
    function test_ExternalProposalFailsWhenTheMarketsAgree() public {
        bytes32 id = _propose(false);
        _launch(id);
        _crank(id, DELAY + WINDOW); // nobody trades: both sides stay at anchor

        governor.finalize(id);

        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Failed));
        assertEq(uint256(vault.winnerOf(id)), uint256(Outcome.Fail));
        (bool approved,) = governor.executionApproval(id);
        assertFalse(approved, "a tie unlocked the treasury");
    }

    /// @dev Same markets, same prices, opposite outcome — the only difference is
    ///      who sponsored it. This is the thumb on the scale from §3.4, and it is
    ///      worth seeing plainly rather than trusting a constant.
    function test_TeamSponsoredProposalPassesOnTheSameNumbers() public {
        bytes32 id = _propose(true);
        _launch(id);
        _crank(id, DELAY + WINDOW);

        governor.finalize(id);
        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Passed));
    }

    function test_ThresholdMathMatchesThePolicy() public view {
        // External: must beat the fail market by 3%.
        assertEq(governor.thresholdFor(1_000e6, false), 1_030e6);
        // Team-sponsored: survives unless the fail market is 3% higher.
        assertEq(governor.thresholdFor(1_000e6, true), 970e6);
    }

    function test_CannotFinalizeTwice() public {
        bytes32 id = _propose(false);
        _launch(id);
        _crank(id, DELAY + WINDOW);
        governor.finalize(id);

        vm.expectRevert();
        governor.finalize(id);
    }

    // -------------------------------------------------- end to end, with money

    /// @dev The whole system in one test: a proposal is submitted, markets open,
    ///      traders price it, the clock runs out, and the treasury pays someone
    ///      — with no human signature anywhere in the path.
    function test_EndToEnd_AMarketDecisionSpendsTheTreasury() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({
            target: address(usdg),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (payee, 120_000e6))
        });
        bytes32 actionsHash = this.hashHelper(calls);

        vm.prank(proposer);
        bytes32 id = governor.propose(
            "ipfs://pay-the-contributor", keccak256("pay the contributor"), actionsHash, false
        );

        _launch(id);
        _crank(id, DELAY); // nothing counts during the quiet period
        _buyPass(id, 600e6); // the market decides this is worth doing
        _crank(id, WINDOW);

        // Nothing has moved yet, and nothing can until the markets settle.
        assertEq(usdg.balanceOf(payee), 0);

        governor.finalize(id);
        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Passed));

        // Anyone may push the button; the decision was made by the market.
        vm.prank(trader);
        executor.execute(id, calls);

        assertEq(usdg.balanceOf(payee), 120_000e6, "the treasury did not pay out");
        assertEq(usdg.balanceOf(address(safe)), 500_000e6 - 120_000e6);
    }

    /// @dev The mirror image: the same batch, a market that says no, and a
    ///      treasury that stays shut.
    function test_EndToEnd_ARejectedProposalCannotSpendAnything() public {
        FutarchyExecutor.Call[] memory calls = new FutarchyExecutor.Call[](1);
        calls[0] = FutarchyExecutor.Call({
            target: address(usdg),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (payee, 120_000e6))
        });
        bytes32 actionsHash = this.hashHelper(calls);

        vm.prank(proposer);
        bytes32 id = governor.propose(
            "ipfs://pay-the-contributor", keccak256("pay the contributor"), actionsHash, false
        );

        _launch(id);
        _crank(id, DELAY + WINDOW); // the market is unconvinced
        governor.finalize(id);

        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Failed));

        vm.expectRevert(abi.encodeWithSelector(FutarchyExecutor.NotApproved.selector, id));
        executor.execute(id, calls);
        assertEq(usdg.balanceOf(payee), 0, "a rejected proposal still spent money");
    }

    function hashHelper(FutarchyExecutor.Call[] calldata calls) external view returns (bytes32) {
        return executor.hashActions(calls);
    }

    // ------------------------------------------------------- indexability

    /// @notice An indexer sees events, not storage. If a proposal cannot be
    ///         rebuilt from its logs alone, every frontend needs an archive node
    ///         and a pile of `eth_call`s to show a list of proposals.
    ///
    /// @dev These assertions are deliberately about the *event payloads* rather
    ///      than about behaviour: they are the contract this backend offers to
    ///      whoever builds on top of it, and they are easy to break by accident.
    function test_AProposalIsFullyReconstructibleFromEventsAlone() public {
        vm.recordLogs();

        bytes32 id = _propose(false);
        _launch(id);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool sawProposed;
        bool sawLaunched;

        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0]
                    == keccak256("Proposed(bytes32,address,string,bytes32,bytes32,bool)")
            ) {
                sawProposed = true;
                assertEq(logs[i].topics[1], id, "proposal id not indexed");
                (string memory uri,,, bool team) =
                    abi.decode(logs[i].data, (string, bytes32, bytes32, bool));
                // Without this a reader can verify a description they were
                // handed, but can never find one. §3.3: no hidden proposals.
                assertEq(uri, "ipfs://description", "description uri missing from the log");
                assertFalse(team);
            }

            if (
                logs[i].topics[0]
                    == keccak256(
                        "Launched(bytes32,address,address,address,address,address,uint256,uint64,uint64)"
                    )
            ) {
                sawLaunched = true;
                _assertLaunchedPayload(id, logs[i].data);
            }
        }

        assertTrue(sawProposed, "no Proposed event");
        assertTrue(sawLaunched, "no Launched event");
    }

    function _assertLaunchedPayload(bytes32 id, bytes memory data) internal view {
        (
            address passAmm,
            address failAmm,
            address passOracle,
            address failOracle,
            uint256 anchor,
            uint64 opensAt,
            uint64 closesAt
        ) = abi.decode(data, (address, address, address, address, uint256, uint64, uint64));

        (address ea, address eb, address eo, address ef) = governor.marketsOf(id);
        assertEq(passAmm, ea, "pass market wrong in log");
        assertEq(failAmm, eb, "fail market wrong in log");
        assertEq(passOracle, eo, "pass oracle missing from log");
        assertEq(failOracle, ef, "fail oracle missing from log");
        assertEq(anchor, ANCHOR);

        // "When does this close?" is the first thing any UI asks, and it used to
        // require reading an immutable over RPC.
        assertEq(opensAt, uint64(block.timestamp) + DELAY, "trading open time wrong");
        assertEq(closesAt, opensAt + WINDOW, "trading close time wrong");
    }

    /// @dev Reserves are emitted on liquidity changes as well as swaps, so an
    ///      indexer reads pool state rather than accumulating deltas — the
    ///      latter drifts permanently the moment one event is missed.
    function test_LiquidityEventsCarryResultingReserves() public {
        bytes32 id = _propose(false);
        vm.recordLogs();
        _launch(id);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 seen;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0]
                    == keccak256("LiquidityAdded(address,uint256,uint256,uint256,uint256,uint256)")
            ) {
                (,,, uint256 rb, uint256 rq) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256));
                assertEq(rb, SEED_BASE, "reserveBase missing from LiquidityAdded");
                assertEq(rq, SEED_QUOTE, "reserveQuote missing from LiquidityAdded");
                seen++;
            }
        }
        assertEq(seen, 2, "expected one LiquidityAdded per market");
    }

    // ---------------------------------------------------------------- cancel

    function test_GuardianCanCancelALiveProposal() public {
        bytes32 id = _propose(false);
        _launch(id);

        vm.prank(guardian);
        governor.cancel(id);

        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Cancelled));
        // Resolved to Fail so holders can still redeem rather than being stranded.
        assertEq(uint256(vault.winnerOf(id)), uint256(Outcome.Fail));

        (bool approved,) = governor.executionApproval(id);
        assertFalse(approved);
    }

    function test_ProposerCanWithdrawBeforeLaunchAndGetsTheStakeBack() public {
        bytes32 id = _propose(false);
        uint256 before = token.balanceOf(proposer);

        vm.prank(proposer);
        governor.cancel(id);

        assertEq(token.balanceOf(proposer), before + STAKE);
        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Cancelled));
    }

    function test_StrangersCannotCancel() public {
        bytes32 id = _propose(false);
        _launch(id);

        vm.expectRevert(abi.encodeWithSelector(FutarchyGovernor.Unauthorized.selector, trader));
        vm.prank(trader);
        governor.cancel(id);
    }

    /// @dev §6.6's line: the guardian is a brake, never a spender.
    function test_GuardianCannotMakeAProposalPass() public {
        bytes32 id = _propose(false);
        _launch(id);
        vm.prank(guardian);
        governor.cancel(id);

        (bool approved,) = governor.executionApproval(id);
        assertFalse(approved, "guardian unlocked the treasury");
    }

    // ------------------------------------------------------------ seed return

    function test_SeederGetsTheirCapitalBack() public {
        bytes32 id = _propose(false);
        uint256 baseBefore = token.balanceOf(seeder);
        uint256 quoteBefore = usdg.balanceOf(seeder);

        _launch(id);
        _crank(id, DELAY + WINDOW);
        governor.finalize(id);

        vm.prank(seeder);
        governor.reclaimSeed(id);

        // Untraded markets return almost exactly what went in; the locked
        // minimum shares keep a sliver behind.
        assertApproxEqRel(token.balanceOf(seeder), baseBefore, 1e15, "base not returned");
        assertApproxEqRel(usdg.balanceOf(seeder), quoteBefore, 1e15, "quote not returned");
    }

    /// @notice Reclaiming after the markets have actually been traded.
    ///
    /// @dev Every other reclaim test cranks with nobody trading, so the pools
    ///      come back holding exactly what went in and the arithmetic is
    ///      trivial. After real trading the LP position has rebalanced — less of
    ///      one side, more of the other — and the winning conditionals have to
    ///      be redeemed while the losing ones are worthless. That is the path
    ///      that moves real money, and it had never executed.
    function test_SeedIsRecoverableAfterTheMarketsHaveTraded() public {
        bytes32 id = _propose(false);
        uint256 baseBefore = token.balanceOf(seeder);
        uint256 quoteBefore = usdg.balanceOf(seeder);

        _launch(id);
        _crank(id, DELAY);
        _buyPass(id, 600e6); // someone takes a real position
        _crank(id, WINDOW);
        governor.finalize(id);
        assertEq(uint256(governor.stateOf(id)), uint256(FutarchyGovernor.State.Passed));

        vm.prank(seeder);
        (uint256 baseOut, uint256 quoteOut) = governor.reclaimSeed(id);

        assertGt(baseOut, 0, "seeder recovered no base at all");
        assertGt(quoteOut, 0, "seeder recovered no quote at all");

        // The trader bought the pass token with pass-quote, so the winning pool
        // ends holding less base and more quote than it opened with. The seeder
        // wears that as an LP, exactly as they would in any pool.
        assertLt(baseOut, SEED_BASE, "base should have fallen: the trader bought it");
        assertGt(quoteOut, SEED_QUOTE, "quote should have risen: the trader paid it in");

        assertEq(token.balanceOf(seeder), baseBefore - SEED_BASE + baseOut);
        assertEq(usdg.balanceOf(seeder), quoteBefore - SEED_QUOTE + quoteOut);
    }

    /// @notice After every holder redeems, only dust remains — and the dust has
    ///         a known cause.
    ///
    /// @dev This test originally asserted an exact zero and failed, which turned
    ///      out to be correct behaviour nobody had written down. `ConditionalAmm`
    ///      locks 1,000 MINIMUM_SHARES to address(0) on the first deposit, the
    ///      standard first-depositor protection. The inventory backing those
    ///      shares can never be withdrawn, so its conditional tokens are never
    ///      redeemed, so that much underlying stays locked in the vault forever.
    ///
    ///      It is genuinely tiny — the dead fraction is MINIMUM_SHARES divided by
    ///      sqrt(base * quote), about 7e-13 here, so roughly 7e-10 of a token per
    ///      proposal. Worth asserting a bound rather than deleting the test: if
    ///      this residue ever becomes large, something has gone wrong with share
    ///      accounting and this is where it shows.
    function test_OnlyDustRemainsOnceEveryoneHasRedeemed() public {
        bytes32 id = _propose(false);
        _launch(id);
        _crank(id, DELAY);
        _buyPass(id, 600e6);
        _crank(id, WINDOW);
        governor.finalize(id);

        vm.prank(seeder);
        governor.reclaimSeed(id);

        _redeemIfHolding(trader, id, address(token));
        _redeemIfHolding(trader, id, address(usdg));

        uint256 baseLeft = vault.lockedOf(id, address(token));
        uint256 quoteLeft = vault.lockedOf(id, address(usdg));

        // A billionth of the seed is a generous ceiling on "dust". The real
        // figure is a thousand times smaller again.
        assertLt(baseLeft, SEED_BASE / 1e9, "far more base stranded than the locked shares explain");
        assertLt(
            quoteLeft, SEED_QUOTE / 1e6, "far more quote stranded than the locked shares explain"
        );

        // Whatever is left must still be honestly backed, not phantom.
        assertEq(
            token.balanceOf(address(vault)), baseLeft, "vault holdings disagree with its ledger"
        );
        assertEq(
            usdg.balanceOf(address(vault)), quoteLeft, "vault holdings disagree with its ledger"
        );
    }

    /// @notice The same, when the market says no. The losing side's inventory is
    ///         worthless, and the seeder recovers through the fail pool instead.
    function test_SeedIsRecoverableWhenTheProposalFails() public {
        bytes32 id = _propose(false);
        _launch(id);
        _crank(id, DELAY);
        _buyPass(id, 600e6); // not enough to clear the 3% margin on its own
        _crank(id, WINDOW);
        governor.finalize(id);

        vm.prank(seeder);
        (uint256 baseOut, uint256 quoteOut) = governor.reclaimSeed(id);
        assertGt(baseOut + quoteOut, 0, "seeder recovered nothing");
    }

    function test_OnlyTheSeederReclaims() public {
        bytes32 id = _propose(false);
        _launch(id);
        _crank(id, DELAY + WINDOW);
        governor.finalize(id);

        vm.expectRevert(abi.encodeWithSelector(FutarchyGovernor.Unauthorized.selector, trader));
        vm.prank(trader);
        governor.reclaimSeed(id);
    }

    function test_SeedCannotBeReclaimedTwice() public {
        bytes32 id = _propose(false);
        _launch(id);
        _crank(id, DELAY + WINDOW);
        governor.finalize(id);

        vm.startPrank(seeder);
        governor.reclaimSeed(id);
        vm.expectRevert(abi.encodeWithSelector(FutarchyGovernor.AlreadyReclaimed.selector, id));
        governor.reclaimSeed(id);
        vm.stopPrank();
    }

    // ------------------------------------------------------------ vault wiring

    function test_OnlyTheGovernorControlsTheVault() public {
        bytes32 id = _propose(false);
        _launch(id);

        vm.expectRevert();
        vm.prank(trader);
        vault.resolve(id, Outcome.Pass);
    }

    function test_VaultBelongsToThisGovernor() public view {
        assertEq(vault.governor(), address(governor));
    }
}
