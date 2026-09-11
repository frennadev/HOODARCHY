// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {LaggedTwapOracle} from "../../src/oracle/LaggedTwapOracle.sol";
import {UniswapV4PriceSource} from "../../src/oracle/sources/UniswapV4PriceSource.sol";
import {MockV4PoolManager} from "../mocks/MockV4PoolManager.sol";

/// @notice A price source feeding a decision market has one job: report a real
///         price, or report nothing. Reporting a plausible-looking wrong number
///         is the failure that costs a proposal, so most of this file is about
///         the cases where it must refuse to answer.
contract UniswapV4PriceSourceTest is Test {
    MockV4PoolManager internal manager;
    UniswapV4PriceSource internal source; // base == currency0
    UniswapV4PriceSource internal inverted; // base == currency1

    address internal constant C0 = address(0x1111);
    address internal constant C1 = address(0x2222);
    uint24 internal constant FEE = 500;
    int24 internal constant TICK_SPACING = 10;
    address internal constant HOOKS = address(0);

    uint256 internal constant WAD = 1e18;
    uint160 internal constant SQRT_ONE = uint160(1) << 96; // price == 1.0

    function setUp() public {
        manager = new MockV4PoolManager();
        source = new UniswapV4PriceSource(address(manager), C0, C1, FEE, TICK_SPACING, HOOKS, C0);
        inverted = new UniswapV4PriceSource(address(manager), C0, C1, FEE, TICK_SPACING, HOOKS, C1);
    }

    function _setPool(uint160 sqrtPriceX96, uint128 liquidity) internal {
        manager.setPool(source.POOL_ID(), sqrtPriceX96, liquidity);
    }

    // --------------------------------------------------------------- reading

    function test_PriceOfOneIsExactlyOneWad() public {
        _setPool(SQRT_ONE, 1e18);
        assertEq(source.spotPrice(), WAD);
        assertEq(inverted.spotPrice(), WAD);
    }

    /// @dev sqrtPrice 2x => price 4x, and the inverse source must say 1/4.
    function test_PriceAndItsInverseAgree() public {
        _setPool(uint160(2) * SQRT_ONE, 1e18);
        assertEq(source.spotPrice(), 4 * WAD);
        assertEq(inverted.spotPrice(), WAD / 4);
    }

    /// @dev slot0's upper bits hold tick and fee data. If they leaked into the
    ///      price the number would be astronomically wrong, so the mock writes
    ///      dirty upper bits deliberately.
    function test_UpperSlot0BitsAreMaskedOff() public {
        _setPool(SQRT_ONE, 1e18);
        assertEq(source.spotPrice(), WAD, "tick/fee bits leaked into the price");
    }

    /// @dev The real ETH/USDG 0.05% pool on Robinhood Chain, at the value read
    ///      live on 2026-09-09. ETH is 18dp and USDG is 6dp, so a correct
    ///      reading lands near 2,500 USDG per ETH expressed in USDG's own units.
    ///      Asserted as a band, because the exact figure moves with the market.
    function test_RealWorldValueProducesASaneEthPrice() public {
        _setPool(3_959_846_575_392_628_940_713_522, 23_061_050_873_533_084);
        uint256 price = source.spotPrice();
        assertGt(price, 1_000e6, "implausibly low ETH price - check decimal scaling");
        assertLt(price, 10_000e6, "implausibly high ETH price - check decimal scaling");
    }

    // ------------------------------------------------------- refusing to answer

    /// @dev The case that motivated the liquidity check. Robinhood Chain carries
    ///      a real V4 pool, initialised and never funded, parked at the maximum
    ///      representable price. Its slot0 is a well-formed number and a totally
    ///      fictional price. Liquidity is what tells the two apart.
    function test_EmptyPoolAtMaxPriceReportsNoPrice() public {
        // Leading 00 so the compiler reads this as a number, not an address.
        _setPool(uint160(0x00fffd8963efd1fc6a506488495d951d5263988d25), 0);
        assertEq(source.spotPrice(), 0, "an unfunded pool must not report a price");
    }

    function test_UninitialisedPoolReportsNoPrice() public view {
        // Nothing written for this pool at all.
        assertEq(source.spotPrice(), 0);
    }

    function test_PoolWithLiquidityButNoPriceReportsNoPrice() public {
        _setPool(0, 1e18);
        assertEq(source.spotPrice(), 0);
    }

    /// @dev The V4-specific one. Flash accounting lets a single transaction
    ///      unlock the manager, shove a pool anywhere, read it, and put it back
    ///      before settling — a price no other trader could have faded. The
    ///      oracle's time cap bounds the damage; refusing to answer removes it.
    function test_ATTACK_PriceIsWithheldWhileTheManagerIsUnlocked() public {
        _setPool(SQRT_ONE, 1e18);
        assertEq(source.spotPrice(), WAD, "sanity: readable while settled");

        manager.setUnlocked(true);
        assertEq(source.spotPrice(), 0, "served a price from inside an unlock");

        manager.setUnlocked(false);
        assertEq(source.spotPrice(), WAD, "should read normally once settled again");
    }

    /// @dev A withheld price must not read as "the price is zero". The oracle
    ///      treats 0 as "hold what you have", so a pool going quiet freezes the
    ///      observation instead of dragging it to nothing.
    function test_WithheldPriceFreezesTheOracleRatherThanCrashingIt() public {
        _setPool(SQRT_ONE, 1e18);
        LaggedTwapOracle oracle =
            new LaggedTwapOracle(address(source), WAD / 2100, 24 hours, 5 minutes, 72 hours);
        oracle.start(WAD);

        manager.setUnlocked(true);
        skip(10 minutes);
        oracle.poke();

        assertEq(oracle.observation(), WAD, "observation moved on a withheld price");
    }

    // ------------------------------------------------------------ construction

    function test_ConstructorRejectsUnsortedCurrencies() public {
        vm.expectRevert(UniswapV4PriceSource.TokensNotOrdered.selector);
        new UniswapV4PriceSource(address(manager), C1, C0, FEE, TICK_SPACING, HOOKS, C0);
    }

    function test_ConstructorRejectsATokenOutsideThePool() public {
        vm.expectRevert(UniswapV4PriceSource.TokenNotInPool.selector);
        new UniswapV4PriceSource(
            address(manager), C0, C1, FEE, TICK_SPACING, HOOKS, address(0xDEAD)
        );
    }

    function test_ConstructorRejectsZeroManager() public {
        vm.expectRevert(UniswapV4PriceSource.ZeroAddress.selector);
        new UniswapV4PriceSource(address(0), C0, C1, FEE, TICK_SPACING, HOOKS, C0);
    }

    function test_BaseAndQuoteAreReportedFromThePoolKey() public view {
        assertEq(source.base(), C0);
        assertEq(source.quote(), C1);
        assertEq(inverted.base(), C1);
        assertEq(inverted.quote(), C0);
    }

    /// @dev Native ETH is currency0 as address(0), which must not be mistaken
    ///      for an unset address by the constructor's validation.
    function test_NativeEthIsAValidCurrency() public {
        UniswapV4PriceSource ethSource = new UniswapV4PriceSource(
            address(manager), address(0), C1, FEE, TICK_SPACING, HOOKS, address(0)
        );
        assertEq(ethSource.base(), address(0));
        assertEq(ethSource.quote(), C1);
    }

    // -------------------------------------------------------------------- fuzz

    /// @dev Whatever the price, the two directions must remain reciprocal. Loose
    ///      tolerance because each direction rounds independently.
    function testFuzz_PriceAndInverseStayReciprocal(uint96 seed) public {
        uint160 sqrtPriceX96 = uint160(bound(seed, SQRT_ONE / 1e6, uint256(SQRT_ONE) * 1e6));
        _setPool(sqrtPriceX96, 1e18);

        uint256 p = source.spotPrice();
        uint256 q = inverted.spotPrice();
        vm.assume(p > 0 && q > 0);

        assertApproxEqRel(p * q, WAD * WAD, 1e12, "price and inverse are not reciprocal");
    }
}
