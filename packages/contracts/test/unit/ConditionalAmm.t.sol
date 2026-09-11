// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ConditionalAmm} from "../../src/amm/ConditionalAmm.sol";
import {LaggedTwapOracle} from "../../src/oracle/LaggedTwapOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice This pool holds real money, which is the thing D4 wanted to avoid and
///         D19 accepted deliberately. So the tests are about the two properties
///         that justify that choice: the constant product cannot be drained, and
///         the whole donation bug class that broke Capital DAO is absent rather
///         than merely defended.
contract ConditionalAmmTest is Test {
    ConditionalAmm internal amm;
    MockERC20 internal pToken; // 18dp, like a project token
    MockERC20 internal pUsdg; // 6dp, like the real USDG

    address internal governor = makeAddr("governor");
    address internal seeder = makeAddr("seeder");
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant WAD = 1e18;

    function setUp() public {
        vm.warp(1_000_000);
        pToken = new MockERC20("PASS Token", "pTKN", 18);
        pUsdg = new MockERC20("PASS USDG", "pUSDG", 6);
        amm = new ConditionalAmm(address(pToken), address(pUsdg), governor);

        for (uint256 i = 0; i < 4; i++) {
            address who = [seeder, alice, attacker, governor][i];
            pToken.mint(who, 1_000_000e18);
            pUsdg.mint(who, 1_000_000e6);
            vm.startPrank(who);
            pToken.approve(address(amm), type(uint256).max);
            pUsdg.approve(address(amm), type(uint256).max);
            vm.stopPrank();
        }
    }

    /// @dev Seeds at 1 token = 2 USDG.
    function _seed() internal {
        vm.prank(seeder);
        amm.addLiquidity(1000e18, 2000e6);
    }

    function _k() internal view returns (uint256) {
        return amm.reserveBase() * amm.reserveQuote();
    }

    // ------------------------------------------------------------- liquidity

    function test_FirstDepositSetsThePriceAndLocksMinimumShares() public {
        _seed();
        assertEq(amm.reserveBase(), 1000e18);
        assertEq(amm.reserveQuote(), 2000e6);
        assertEq(amm.sharesOf(address(0)), 1000, "minimum shares not locked");
        // 1 token costs 2 USDG; USDG has 6dp, so 2e6 per 1e18 of base.
        assertEq(amm.spotPrice(), 2e6);
    }

    function test_LiquidityRoundTripsWithoutLoss() public {
        _seed();
        uint256 shares = amm.sharesOf(seeder);

        vm.prank(seeder);
        (uint256 baseOut, uint256 quoteOut) = amm.removeLiquidity(shares);

        // The locked minimum keeps a sliver behind; everything else comes back.
        assertApproxEqRel(baseOut, 1000e18, 1e15, "base not returned");
        assertApproxEqRel(quoteOut, 2000e6, 1e15, "quote not returned");
        assertEq(amm.sharesOf(seeder), 0);
    }

    function test_SecondProviderCannotDiluteTheFirst() public {
        _seed();
        uint256 seederShares = amm.sharesOf(seeder);

        vm.prank(alice);
        amm.addLiquidity(1000e18, 2000e6);

        assertEq(amm.sharesOf(seeder), seederShares, "existing shares changed");
        assertApproxEqRel(
            amm.sharesOf(alice), seederShares, 1e15, "unequal shares for equal deposit"
        );
        assertEq(amm.spotPrice(), 2e6, "proportional deposit moved the price");
    }

    // ------------------------------------------------------------------ swaps

    function test_SwapMovesThePriceAndGrowsTheProduct() public {
        _seed();
        uint256 kBefore = _k();

        vm.prank(alice);
        uint256 out = amm.swapExactBaseForQuote(10e18, 0);

        assertGt(out, 0);
        assertGt(_k(), kBefore, "fee must leave the product no smaller");
        assertLt(amm.spotPrice(), 2e6, "selling base should lower its price");
    }

    function test_QuoteMatchesTheExecutedSwap() public {
        _seed();
        uint256 quoted = amm.quoteSwap(true, 10e18);
        vm.prank(alice);
        uint256 actual = amm.swapExactBaseForQuote(10e18, 0);
        assertEq(quoted, actual, "quote disagreed with execution");
    }

    function test_SlippageGuardStopsABadFill() public {
        _seed();
        uint256 quoted = amm.quoteSwap(true, 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(ConditionalAmm.SlippageExceeded.selector, quoted, quoted + 1)
        );
        vm.prank(alice);
        amm.swapExactBaseForQuote(10e18, quoted + 1);
    }

    /// @dev The pool must never let anyone take out more than the curve allows,
    ///      whatever the trade size or direction.
    function testFuzz_ConstantProductNeverShrinks(uint128 amountSeed, bool direction) public {
        _seed();
        uint256 amountIn = bound(amountSeed, 1e6, 100_000e6);
        if (direction) amountIn = bound(amountSeed, 1e15, 100_000e18);

        uint256 kBefore = _k();
        vm.prank(alice);
        if (direction) amm.swapExactBaseForQuote(amountIn, 0);
        else amm.swapExactQuoteForBase(amountIn, 0);

        assertGe(_k(), kBefore, "constant product shrank - value leaked out of the pool");
    }

    /// @dev Reserves must always be backed by tokens actually held.
    function testFuzz_ReservesAreNeverMoreThanTheTokensHeld(uint128 amountSeed) public {
        _seed();
        uint256 amountIn = bound(amountSeed, 1e15, 100_000e18);

        vm.prank(alice);
        amm.swapExactBaseForQuote(amountIn, 0);

        assertLe(amm.reserveBase(), pToken.balanceOf(address(amm)), "base reserve unbacked");
        assertLe(amm.reserveQuote(), pUsdg.balanceOf(address(amm)), "quote reserve unbacked");
    }

    // ------------------------------------------------- the donation bug class

    /// @dev The whole reason this contract exists rather than a Uniswap pool.
    ///      On V2 this is audit finding H-1: a donation is promoted to a reserve
    ///      and moves the price. Here it is not counted at all.
    function test_ATTACK_DonationCannotMoveThePrice() public {
        _seed();
        uint256 priceBefore = amm.spotPrice();

        vm.prank(attacker);
        pUsdg.transfer(address(amm), 500_000e6); // a very expensive no-op

        assertEq(amm.spotPrice(), priceBefore, "a donation moved the price");
        assertEq(amm.reserveQuote(), 2000e6, "a donation entered the reserves");
    }

    /// @dev And it cannot block the pool from being set up either, which is the
    ///      form that bricked a Capital DAO raise permanently.
    function test_ATTACK_DonationBeforeSeedingCannotBlockTheFirstDeposit() public {
        vm.prank(attacker);
        pUsdg.transfer(address(amm), 3); // three units, the original attack size

        _seed();

        assertEq(amm.reserveQuote(), 2000e6, "donation contaminated the opening price");
        assertEq(amm.spotPrice(), 2e6, "opening price was not exactly as intended");
    }

    function test_DonatedTokensAreRecoverableAsSurplus() public {
        _seed();
        vm.prank(attacker);
        pUsdg.transfer(address(amm), 1000e6);

        (, uint256 quoteSurplus) = amm.surplus();
        assertEq(quoteSurplus, 1000e6);

        vm.prank(governor);
        amm.skimSurplus(governor);

        (, uint256 afterSkim) = amm.surplus();
        assertEq(afterSkim, 0);
        assertEq(amm.reserveQuote(), 2000e6, "skim touched the reserves");
    }

    function test_SkimCannotReachReserves() public {
        _seed();
        vm.prank(governor);
        amm.skimSurplus(governor); // nothing donated

        assertEq(amm.reserveBase(), 1000e18);
        assertEq(amm.reserveQuote(), 2000e6);
    }

    // ----------------------------------------------------------------- oracle

    function _attachOracle() internal returns (LaggedTwapOracle o) {
        // Sized so doubling the observation takes ~35 minutes, as in D8.
        o = new LaggedTwapOracle(address(amm), uint256(2e6) / 2100, 24 hours, 5 minutes);
        vm.prank(governor);
        amm.setOracle(address(o));
        o.start(2e6);
    }

    function test_TradingUpdatesTheSlowPriceWithoutACrank() public {
        _seed();
        LaggedTwapOracle o = _attachOracle();
        uint256 last = o.lastUpdate();

        skip(60);
        vm.prank(alice);
        amm.swapExactBaseForQuote(10e18, 0);

        assertGt(o.lastUpdate(), last, "a trade did not update the observation");
    }

    /// @dev The ordering property. The observation is taken before the trade is
    ///      applied, so a trader cannot move the price and capture the movement
    ///      in the same transaction.
    function test_ATTACK_CannotMoveThePriceAndBankItInOneTransaction() public {
        _seed();
        LaggedTwapOracle o = _attachOracle();

        skip(5 minutes);
        vm.prank(attacker);
        amm.swapExactQuoteForBase(500_000e6, 0); // slam the price up hard

        // The observation saw only the pre-trade price, so it has not moved.
        assertEq(o.observation(), 2e6, "observation captured the attacker's own trade");
    }

    function test_PoolTradesBeforeTheOracleIsStarted() public {
        _seed();
        LaggedTwapOracle o = new LaggedTwapOracle(address(amm), 1e3, 24 hours, 5 minutes);
        vm.prank(governor);
        amm.setOracle(address(o));
        // Deliberately not started.

        vm.prank(alice);
        amm.swapExactBaseForQuote(10e18, 0); // must not revert
        assertEq(o.startedAt(), 0);
    }

    // ------------------------------------------------------------ access etc.

    function test_OnlyGovernorSetsTheOracleAndOnlyOnce() public {
        LaggedTwapOracle o = new LaggedTwapOracle(address(amm), 1e3, 24 hours, 5 minutes);

        vm.expectRevert(abi.encodeWithSelector(ConditionalAmm.Unauthorized.selector, alice));
        vm.prank(alice);
        amm.setOracle(address(o));

        vm.prank(governor);
        amm.setOracle(address(o));

        vm.expectRevert(ConditionalAmm.OracleAlreadySet.selector);
        vm.prank(governor);
        amm.setOracle(address(o));
    }

    function test_OnlyGovernorSkims() public {
        _seed();
        vm.expectRevert(abi.encodeWithSelector(ConditionalAmm.Unauthorized.selector, alice));
        vm.prank(alice);
        amm.skimSurplus(alice);
    }

    function test_SwapsRevertOnAnEmptyPool() public {
        vm.expectRevert(ConditionalAmm.InsufficientLiquidity.selector);
        vm.prank(alice);
        amm.swapExactBaseForQuote(1e18, 0);
    }

    function test_EmptyPoolReportsNoPrice() public view {
        assertEq(amm.spotPrice(), 0);
    }

    function test_ConstructorRejectsADegeneratePair() public {
        vm.expectRevert(ConditionalAmm.IdenticalTokens.selector);
        new ConditionalAmm(address(pToken), address(pToken), governor);

        vm.expectRevert(ConditionalAmm.ZeroAddress.selector);
        new ConditionalAmm(address(0), address(pUsdg), governor);
    }
}
