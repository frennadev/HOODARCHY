// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

import {ConditionalAmm} from "../../src/amm/ConditionalAmm.sol";
import {ConditionalVault} from "../../src/conditional/ConditionalVault.sol";
import {FutarchyGovernor} from "../../src/governance/FutarchyGovernor.sol";
import {MarketFactory} from "../../src/governance/MarketFactory.sol";
import {Outcome} from "../../src/interfaces/IConditionalVault.sol";
import {LaggedTwapOracle} from "../../src/oracle/LaggedTwapOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Can somebody other than the launcher deepen a proposal's books?
///
/// @dev Shared liquidity has been on the "not built" list since the start, and
///      §5.2 describes a specific mechanism for it — borrowing from a parent
///      pool — that turned out to be impossible against a Uniswap parent, since
///      those reserves belong to its LPs.
///
///      But `ConditionalAmm.addLiquidity` has no access control, and a complete
///      set is obtainable by anyone. So the capability may already exist, just
///      unergonomically and untested. This file establishes what actually works
///      today before anything gets built on top of it — the alternative is
///      writing a convenience layer over a path that turns out to be broken.
contract SharedLiquidityTest is Test {
    FutarchyGovernor internal governor;
    ConditionalVault internal vault;
    MockERC20 internal base;
    MockERC20 internal quote;

    address internal launcher = makeAddr("launcher");
    address internal helper = makeAddr("helper"); // a stranger who wants deeper books
    address internal trader = makeAddr("trader");

    uint64 internal constant DELAY = 24 hours;
    uint64 internal constant WINDOW = 72 hours;
    uint64 internal constant MAX_STEP = 5 minutes;
    uint256 internal constant SEED_BASE = 1_000e18;
    uint256 internal constant SEED_QUOTE = 2_000e6;
    uint256 internal constant ANCHOR = 2e6;

    function setUp() public {
        vm.warp(1_000_000);
        base = new MockERC20("Project", "PRJ", 18);
        quote = new MockERC20("Mock USDG", "USDG", 6);

        governor = new FutarchyGovernor(
            address(base),
            address(quote),
            address(new MarketFactory()),
            address(0),
            0,
            ANCHOR / 2100,
            DELAY,
            WINDOW,
            MAX_STEP
        );
        vault = governor.VAULT();

        for (uint256 i = 0; i < 3; i++) {
            address who = [launcher, helper, trader][i];
            base.mint(who, 10_000_000e18);
            quote.mint(who, 10_000_000e6);
            vm.startPrank(who);
            base.approve(address(governor), type(uint256).max);
            quote.approve(address(governor), type(uint256).max);
            base.approve(address(vault), type(uint256).max);
            quote.approve(address(vault), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _launch() internal returns (bytes32 id) {
        vm.startPrank(launcher);
        id = governor.propose("ipfs://p", keccak256("d"), keccak256("a"), false);
        governor.launch(id, SEED_BASE, SEED_QUOTE);
        vm.stopPrank();
    }

    function _markets(bytes32 id) internal view returns (ConditionalAmm p, ConditionalAmm f) {
        (address a, address b,,) = governor.marketsOf(id);
        return (ConditionalAmm(a), ConditionalAmm(b));
    }

    function _crank(bytes32 id, uint64 duration) internal {
        (,, address po, address fo) = governor.marketsOf(id);
        uint64 end = uint64(block.timestamp) + duration;
        while (block.timestamp + MAX_STEP <= end) {
            vm.warp(block.timestamp + MAX_STEP);
            LaggedTwapOracle(po).poke();
            LaggedTwapOracle(fo).poke();
        }
        vm.warp(end);
        LaggedTwapOracle(po).poke();
        LaggedTwapOracle(fo).poke();
    }

    /// @dev What a would-be liquidity provider actually has to do today: split
    ///      once into a complete set, then fund both books with it. One deposit
    ///      of collateral, two markets deepened — which is the property that
    ///      makes this cheap, and the reason the fail book is never the thin one.
    function _deepenBoth(address who, bytes32 id, uint256 baseAmt, uint256 quoteAmt) internal {
        (ConditionalAmm p, ConditionalAmm f) = _markets(id);

        vm.startPrank(who);
        vault.split(id, address(base), baseAmt);
        vault.split(id, address(quote), quoteAmt);

        IERC20(p.base()).approve(address(p), baseAmt);
        IERC20(p.quote()).approve(address(p), quoteAmt);
        p.addLiquidity(baseAmt, quoteAmt);

        IERC20(f.base()).approve(address(f), baseAmt);
        IERC20(f.quote()).approve(address(f), quoteAmt);
        f.addLiquidity(baseAmt, quoteAmt);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ tests

    /// @notice A stranger can already deepen both books on a live proposal.
    function test_AnyoneCanDeepenBothBooksOnALiveProposal() public {
        bytes32 id = _launch();
        (ConditionalAmm p, ConditionalAmm f) = _markets(id);

        assertEq(p.reserveBase(), SEED_BASE);
        assertEq(f.reserveBase(), SEED_BASE);

        _deepenBoth(helper, id, 3_000e18, 6_000e6);

        assertEq(p.reserveBase(), SEED_BASE + 3_000e18, "pass book did not deepen");
        assertEq(f.reserveBase(), SEED_BASE + 3_000e18, "fail book did not deepen");
        assertEq(p.spotPrice(), ANCHOR, "deepening moved the pass price");
        assertEq(f.spotPrice(), ANCHOR, "deepening moved the fail price");

        assertGt(p.sharesOf(helper), 0, "helper holds no pass shares");
        assertGt(f.sharesOf(helper), 0, "helper holds no fail shares");
    }

    /// @notice Deeper books mean a given trade moves the price less. This is the
    ///         entire point — manipulation cost scales with depth.
    function test_DepthReducesWhatAGivenTradeCanDoToThePrice() public {
        bytes32 thin = _launch();
        (ConditionalAmm thinPass,) = _markets(thin);

        vm.startPrank(trader);
        vault.split(thin, address(quote), 600e6);
        IERC20(thinPass.quote()).approve(address(thinPass), 600e6);
        thinPass.swapExactQuoteForBase(600e6, 0);
        vm.stopPrank();
        uint256 thinPrice = thinPass.spotPrice();

        // Same proposal shape, but four times the depth before the same trade.
        bytes32 deep = _launch();
        (ConditionalAmm deepPass,) = _markets(deep);
        _deepenBoth(helper, deep, 3_000e18, 6_000e6);

        vm.startPrank(trader);
        vault.split(deep, address(quote), 600e6);
        IERC20(deepPass.quote()).approve(address(deepPass), 600e6);
        deepPass.swapExactQuoteForBase(600e6, 0);
        vm.stopPrank();
        uint256 deepPrice = deepPass.spotPrice();

        assertGt(thinPrice, deepPrice, "the deeper book moved at least as much");
        emit log_named_uint("thin book, price after 600 quote", thinPrice);
        emit log_named_uint("deep book, price after 600 quote", deepPrice);
    }

    /// @notice And the helper gets their capital back afterwards, through the
    ///         ordinary AMM and vault paths — no privileged route needed.
    function test_AHelperRecoversTheirCapitalAfterResolution() public {
        bytes32 id = _launch();
        _deepenBoth(helper, id, 3_000e18, 6_000e6);

        uint256 baseBefore = base.balanceOf(helper);
        uint256 quoteBefore = quote.balanceOf(helper);

        _crank(id, DELAY + WINDOW);
        governor.finalize(id);
        assertEq(uint256(vault.winnerOf(id)), uint256(Outcome.Fail), "untraded markets should tie");

        (ConditionalAmm p, ConditionalAmm f) = _markets(id);
        vm.startPrank(helper);
        p.removeLiquidity(p.sharesOf(helper));
        f.removeLiquidity(f.sharesOf(helper));
        vault.redeem(id, address(base));
        vault.redeem(id, address(quote));
        vm.stopPrank();

        // Untraded, so they should get back what they put in bar the locked
        // minimum shares.
        assertApproxEqRel(base.balanceOf(helper), baseBefore + 3_000e18, 1e15, "base not recovered");
        assertApproxEqRel(
            quote.balanceOf(helper), quoteBefore + 6_000e6, 1e15, "quote not recovered"
        );
    }

    /// @notice The launcher's own reclaim still works with a second LP present —
    ///         it must take its share, not the whole pool.
    function test_TheLauncherReclaimIsUnaffectedByOtherProviders() public {
        bytes32 id = _launch();
        _deepenBoth(helper, id, 3_000e18, 6_000e6);

        _crank(id, DELAY + WINDOW);
        governor.finalize(id);

        vm.prank(launcher);
        (uint256 baseOut, uint256 quoteOut) = governor.reclaimSeed(id);

        // Roughly its own seed back, not the helper's as well.
        assertApproxEqRel(baseOut, SEED_BASE, 1e15, "launcher took the wrong share of base");
        assertApproxEqRel(quoteOut, SEED_QUOTE, 1e15, "launcher took the wrong share of quote");

        // And the helper can still get theirs.
        (ConditionalAmm p, ConditionalAmm f) = _markets(id);
        assertGt(p.sharesOf(helper), 0, "helper's shares were consumed");
        assertGt(f.sharesOf(helper), 0, "helper's shares were consumed");
    }
}
