// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {LaggedTwapOracle} from "../../src/oracle/LaggedTwapOracle.sol";
import {UniswapV2PriceSource} from "../../src/oracle/sources/UniswapV2PriceSource.sol";
import {MockV2Pair} from "../mocks/MockV2Pair.sol";

/// @notice The manipulation tests. If an attacker can move the settled average
///         with a short burst, futarchy does not work and nothing else matters.
contract LaggedTwapOracleTest is Test {
    LaggedTwapOracle internal oracle;
    MockV2Pair internal pair;

    address internal constant BASE = address(0xBA5E);
    address internal constant QUOTE = address(0x0075);

    uint256 internal constant ONE = 1e18; // price 1.0
    uint64 internal constant DELAY = 24 hours;
    uint64 internal constant WINDOW = 72 hours;
    uint64 internal constant MAX_STEP_ELAPSED = 5 minutes;

    /// @dev Sized so doubling the observation takes ~35 minutes of unbroken
    ///      pressure: 1e18 of movement spread over 2,100 seconds.
    uint256 internal constant RATE = ONE / 2100;

    function setUp() public {
        vm.warp(1_000_000);
        pair = new MockV2Pair(BASE, QUOTE);
        _setPrice(ONE);
        oracle = new LaggedTwapOracle(
            address(new UniswapV2PriceSource(address(pair), BASE)), RATE, DELAY, MAX_STEP_ELAPSED
        );
        oracle.start(ONE);
    }

    /// @dev Reserves chosen so quote/base == price, at 18 decimals both sides.
    ///      Base is kept small enough that any price in the fuzz range still
    ///      leaves the quote side inside uint112.
    function _setPrice(uint256 price) internal {
        uint112 baseReserve = 1_000e18;
        uint256 quoteReserve = (uint256(baseReserve) * price) / ONE;
        require(quoteReserve <= type(uint112).max, "test: quote reserve overflows uint112");
        // forge-lint: disable-next-line(unsafe-typecast) — bounded by the require above
        pair.setReserves(baseReserve, uint112(quoteReserve));
    }

    /// @dev Crank every `interval` seconds for `duration`, as the bot would.
    function _crank(uint64 duration, uint64 interval) internal {
        uint64 end = uint64(block.timestamp) + duration;
        while (block.timestamp + interval <= end) {
            vm.warp(block.timestamp + interval);
            oracle.poke();
        }
        if (block.timestamp < end) {
            vm.warp(end);
            oracle.poke();
        }
    }

    // ---------------------------------------------------------------- attacks

    /// @notice THE test. A 100x spike held for one block must not move the
    ///         settled average enough to flip a decision.
    function test_ATTACK_OneBlockSpikeCannotMoveTheAverage() public {
        _crank(DELAY, 60); // burn the dark period at the honest price
        _crank(12 hours, 60);

        uint256 twapBefore = oracle.currentTwap();

        // Attacker slams spot 100x for a single 2-second block, then it reverts.
        _setPrice(100 * ONE);
        vm.warp(block.timestamp + 2);
        oracle.poke();
        _setPrice(ONE);

        _crank(60 hours, 60); // rest of the window, honest again

        uint256 twapAfter = oracle.currentTwap();
        uint256 drift = twapAfter > ONE ? twapAfter - ONE : ONE - twapAfter;

        // A 100x spike buys less than a tenth of a percent on the average.
        assertLt(drift, ONE / 1000, "one-block spike moved the average too far");
        assertApproxEqRel(twapAfter, twapBefore, 0.001e18);
    }

    /// @notice Moving the average requires holding a false price in public for a
    ///         long time. This pins roughly how long.
    function test_ATTACK_DoublingTheObservationTakesAboutThirtyFiveMinutes() public {
        _crank(DELAY, 60);
        assertApproxEqRel(oracle.observation(), ONE, 0.001e18);

        _setPrice(100 * ONE); // push as hard as possible
        _crank(35 minutes, 60);

        // ~35 minutes of unbroken pressure to merely double it, despite spot
        // sitting at 100x the whole time.
        assertApproxEqRel(oracle.observation(), 2 * ONE, 0.05e18);
    }

    /// @notice Suppressing the crank then poking once must not retroactively
    ///         value the quiet period at the manipulated price (decision D8.1).
    function test_ATTACK_StarvingTheCrankDoesNotBackdateTheManipulation() public {
        _crank(DELAY, 60);
        _crank(1 hours, 60);

        uint256 accBefore = oracle.accumulator();
        uint256 obsBefore = oracle.observation();

        // Nobody cranks for an hour while spot sits at 100x.
        _setPrice(100 * ONE);
        vm.warp(block.timestamp + 1 hours);
        oracle.poke();

        // The silent hour was credited at the OLD observation, not the new one.
        uint256 credited = oracle.accumulator() - accBefore;
        assertEq(credited, obsBefore * 1 hours, "quiet time was not credited at the old price");
    }

    /// @notice A long gap must not bank up into one huge step (decision D8.2).
    function test_ATTACK_LongGapDoesNotBankAGiantStep() public {
        _crank(DELAY, 60);
        uint256 obsBefore = oracle.observation();

        _setPrice(100 * ONE);
        vm.warp(block.timestamp + 30 days); // outage, or a stalling sequencer
        oracle.poke();

        // The step is capped by MAX_STEP_ELAPSED, not by the 30 days elapsed.
        uint256 maxStep = RATE * MAX_STEP_ELAPSED;
        assertLe(oracle.observation() - obsBefore, maxStep, "gap banked more than one capped step");
    }

    // ----------------------------------------------------------- correctness

    function test_ObservationsDoNotCountDuringTheDarkPeriod() public {
        _setPrice(50 * ONE);
        _crank(DELAY - 1 minutes, 60);
        assertEq(oracle.accumulator(), 0, "accumulated before the delay expired");

        vm.expectRevert(LaggedTwapOracle.NoObservationYet.selector);
        oracle.currentTwap();
    }

    function test_AverageTracksAHonestlyStablePrice() public {
        _crank(DELAY, 60);
        _crank(WINDOW, 60);
        assertApproxEqRel(oracle.currentTwap(), ONE, 0.001e18);
    }

    /// @dev The reader must not be able to gain by choosing when to read: time
    ///      since the last poke is valued at the current observation.
    function test_ReadingIsNotGameableByWaiting() public {
        _crank(DELAY, 60);
        _crank(6 hours, 60);

        uint256 immediate = oracle.currentTwap();
        vm.warp(block.timestamp + 3 hours); // no poke at all
        uint256 later = oracle.currentTwap();

        assertApproxEqRel(later, immediate, 0.001e18);
    }

    function test_PokeIsPermissionlessAndIdempotentWithinABlock() public {
        _crank(DELAY, 60);
        uint256 obs = oracle.observation();
        vm.prank(makeAddr("anyone"));
        oracle.poke(); // same timestamp, no-op
        assertEq(oracle.observation(), obs);
    }

    function test_StartAnchorsThePriceRatherThanReadingADustedPool() public {
        MockV2Pair fresh = new MockV2Pair(BASE, QUOTE);
        fresh.setReserves(uint112(1e18), uint112(999_999e18)); // dusted to a silly price
        LaggedTwapOracle o = new LaggedTwapOracle(
            address(new UniswapV2PriceSource(address(fresh), BASE)), RATE, DELAY, MAX_STEP_ELAPSED
        );

        o.start(ONE); // anchor is supplied, not read
        assertEq(o.observation(), ONE);

        vm.expectRevert(LaggedTwapOracle.AlreadyStarted.selector);
        o.start(ONE);
    }

    function test_PokeBeforeStartReverts() public {
        LaggedTwapOracle o = new LaggedTwapOracle(
            address(new UniswapV2PriceSource(address(pair), BASE)), RATE, DELAY, MAX_STEP_ELAPSED
        );
        vm.expectRevert(LaggedTwapOracle.NotStarted.selector);
        o.poke();
    }

    /// @dev However spot moves, the observation can never outrun its rate limit.
    function testFuzz_ObservationNeverOutrunsItsRateLimit(uint128 priceSeed, uint32 gapSeed)
        public
    {
        _crank(DELAY, 60);

        uint256 price = bound(priceSeed, 1, 1_000_000e18);
        uint64 gap = uint64(bound(gapSeed, 1, 7 days));

        uint256 before = oracle.observation();
        _setPrice(price);
        vm.warp(block.timestamp + gap);
        oracle.poke();

        uint64 charged = gap > MAX_STEP_ELAPSED ? MAX_STEP_ELAPSED : gap;
        uint256 maxStep = RATE * charged;
        uint256 moved = oracle.observation() > before
            ? oracle.observation() - before
            : before - oracle.observation();
        assertLe(moved, maxStep);
    }
}
