// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPriceSource} from "../interfaces/IPriceSource.sol";

/// @title LaggedTwapOracle
/// @notice Records a deliberately slow price for one Uniswap V2 pair, and
///         time-weights it into an average that a decision can be settled on.
///
/// @dev This is the entire anti-manipulation model, so it is worth stating what
///      it does and does not claim.
///
///      A raw spot price is worthless as a decision input: on a single-sequencer
///      chain anyone who can land one transaction at the right moment can print
///      any price they like. Instead of averaging spot, this contract keeps an
///      `observation` that is only permitted to chase spot at a bounded *rate*.
///      A spike of any magnitude therefore moves it by almost nothing; to shift
///      the recorded price an attacker must hold a false price for a large
///      fraction of the window, in public, against everyone who can trade
///      against them. Cost scales with time and depth, not with a single block.
///
///      Two ordering rules matter more than they look (decision D8):
///
///      1. Time is credited to the accumulator BEFORE the observation moves, at
///         the OLD observation. Otherwise an attacker could suppress cranking,
///         shove spot, crank once, and have a long quiet period retroactively
///         credited at their manipulated price.
///      2. The elapsed time used to size the permitted step is capped. A long
///         gap — an outage, or a sequencer stalling cranks — must not bank up
///         into one enormous jump. Accrual still uses the true elapsed time; only
///         the step budget is capped.
///
///      The contract holds no funds and can move none. Its worst failure is a
///      wrong decision, never a theft.
contract LaggedTwapOracle {
    error ZeroAddress();
    error InvalidConfig();
    error NotStarted();
    error AlreadyStarted();
    error NoObservationYet();

    event Started(uint64 startedAt, uint64 twapActiveFrom, uint256 initialObservation);
    event Observed(uint256 observation, uint256 spot, uint64 elapsed, uint64 stepElapsed);

    /// @notice Price is expressed as quote units per WAD of base.
    uint256 internal constant WAD = 1e18;

    /// @notice Where spot comes from. Swappable, so the Uniswap version in use
    ///         is not a property of the security core.
    IPriceSource public immutable SOURCE;
    /// @notice How far the observation may move per second, in WAD price units.
    uint256 public immutable MAX_CHANGE_PER_SECOND;
    /// @notice Observations do not enter the average until this long after start.
    uint64 public immutable DELAY;
    /// @notice Largest elapsed time that may fund a single step, in seconds.
    uint64 public immutable MAX_STEP_ELAPSED;

    uint64 public startedAt;
    uint64 public lastUpdate;
    /// @notice The slow price. Never moves faster than MAX_CHANGE_PER_SECOND.
    uint256 public observation;
    /// @notice Sum of observation * seconds, once past DELAY.
    uint256 public accumulator;
    /// @notice When accumulation began, i.e. startedAt + DELAY.
    uint64 public twapActiveFrom;

    constructor(
        address source_,
        uint256 maxChangePerSecond_,
        uint64 delay_,
        uint64 maxStepElapsed_
    ) {
        if (source_ == address(0)) revert ZeroAddress();
        if (maxChangePerSecond_ == 0 || maxStepElapsed_ == 0) revert InvalidConfig();

        SOURCE = IPriceSource(source_);
        MAX_CHANGE_PER_SECOND = maxChangePerSecond_;
        DELAY = delay_;
        MAX_STEP_ELAPSED = maxStepElapsed_;
    }

    /// @notice Begins observation, anchored at an explicit initial price.
    /// @dev The anchor is supplied rather than read from the pair so that a pool
    ///      dusted before launch cannot set the starting point. It should be the
    ///      price the pool is seeded at.
    function start(uint256 initialObservation) external {
        if (startedAt != 0) revert AlreadyStarted();
        if (initialObservation == 0) revert InvalidConfig();

        uint64 nowTs = uint64(block.timestamp);
        startedAt = nowTs;
        lastUpdate = nowTs;
        twapActiveFrom = nowTs + DELAY;
        observation = initialObservation;

        emit Started(nowTs, twapActiveFrom, initialObservation);
    }

    /// @notice Credits elapsed time and lets the observation step toward spot.
    /// @dev Permissionless and safe to call at any frequency, including every
    ///      block. Calling it more often makes the observation track spot more
    ///      closely; calling it rarely is not exploitable, because accrual uses
    ///      the old value and the step budget is capped.
    function poke() public {
        uint64 nowTs = uint64(block.timestamp);
        uint64 last = lastUpdate;
        if (last == 0) revert NotStarted();
        if (nowTs == last) return;

        uint64 elapsed = nowTs - last;

        // 1. Accrue FIRST, at the OLD observation, over the TRUE elapsed time.
        _accrue(last, nowTs);

        // 2. Only then step, with a budget capped by MAX_STEP_ELAPSED.
        uint64 stepElapsed = elapsed > MAX_STEP_ELAPSED ? MAX_STEP_ELAPSED : elapsed;
        uint256 spot = spotPrice();
        if (spot != 0) {
            uint256 budget = MAX_CHANGE_PER_SECOND * uint256(stepElapsed);
            uint256 current = observation;
            if (spot > current) {
                uint256 gap = spot - current;
                observation = current + (gap > budget ? budget : gap);
            } else if (spot < current) {
                uint256 gap = current - spot;
                observation = current - (gap > budget ? budget : gap);
            }
        }

        lastUpdate = nowTs;
        emit Observed(observation, spot, elapsed, stepElapsed);
    }

    /// @notice The time-weighted average of the observation since DELAY expired.
    /// @dev Includes time elapsed since the last poke, valued at the current
    ///      observation, so a caller cannot gain by choosing when to read.
    function currentTwap() public view returns (uint256) {
        uint64 from = twapActiveFrom;
        if (from == 0) revert NotStarted();
        uint64 nowTs = uint64(block.timestamp);
        if (nowTs <= from) revert NoObservationYet();

        uint256 acc = accumulator;
        uint64 last = lastUpdate;
        if (nowTs > last) {
            uint64 chargeFrom = last > from ? last : from;
            acc += observation * uint256(nowTs - chargeFrom);
        }
        return acc / uint256(nowTs - from);
    }

    /// @notice Instantaneous price from the configured source.
    function spotPrice() public view returns (uint256) {
        return SOURCE.spotPrice();
    }

    /// @dev Credits [max(from, twapActiveFrom), to) at the current observation.
    function _accrue(uint64 from, uint64 to) private {
        uint64 activeFrom = twapActiveFrom;
        if (to <= activeFrom) return;
        uint64 chargeFrom = from > activeFrom ? from : activeFrom;
        if (to <= chargeFrom) return;
        accumulator += observation * uint256(to - chargeFrom);
    }
}
