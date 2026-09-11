// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ConditionalAmm} from "../amm/ConditionalAmm.sol";
import {LaggedTwapOracle} from "../oracle/LaggedTwapOracle.sol";

/// @title MarketFactory
/// @notice Builds one side of a proposal: a pool and the slow-price recorder
///         reading it, wired together.
///
/// @dev This exists for a dull reason worth stating. A contract that deploys
///      another embeds that contract's full creation code in its own bytecode.
///      The Governor stands up two pools and two recorders per proposal, so
///      doing it inline would carry four contracts' worth of creation code and
///      push it past the 24KB limit. Holding a factory address instead keeps the
///      Governor small enough to deploy and to read.
///
///      The pool is created owned by the Governor rather than by this factory,
///      so the factory never holds power over a market it built. Attaching the
///      oracle is therefore the Governor's job, one call later in the same
///      transaction — there is no block in which the pool is tradeable without
///      its recorder.
contract MarketFactory {
    event MarketCreated(address indexed amm, address indexed oracle, address base, address quote);

    /// @param base Conditional project token for this outcome (pTOKEN or fTOKEN).
    /// @param quote Conditional quote token for this outcome (pUSDG or fUSDG).
    /// @param owner The Governor: the only address that may seed or resolve.
    function createMarket(
        address base,
        address quote,
        address owner,
        uint256 maxChangePerSecond,
        uint64 delay,
        uint64 maxStepElapsed,
        uint64 window
    ) external returns (ConditionalAmm amm, LaggedTwapOracle oracle) {
        amm = new ConditionalAmm(base, quote, owner);
        oracle =
            new LaggedTwapOracle(address(amm), maxChangePerSecond, delay, maxStepElapsed, window);

        emit MarketCreated(address(amm), address(oracle), base, quote);
    }
}
