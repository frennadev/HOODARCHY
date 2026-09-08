// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IConditionalVault, Outcome, QuestionState} from "../interfaces/IConditionalVault.sol";
import {ConditionalToken} from "./ConditionalToken.sol";

/// @title ConditionalVault
/// @notice Escrows an underlying asset and issues a matched pair of PASS/FAIL
///         ERC-20 claims against it. A complete set {PASS, FAIL} is always worth
///         exactly one unit of the underlying, in every world.
///
/// @dev The conservation law this contract exists to enforce, per question and
///      per underlying:
///
///          underlying held  ==  PASS supply  ==  FAIL supply
///
///      Every state-changing function preserves it. `split` raises all three by
///      the same amount, `merge` lowers all three, and `redeem` lowers the held
///      balance and the winning supply together while the losing supply is
///      simply abandoned as worthless.
contract ConditionalVault is IConditionalVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Question {
        QuestionState state;
        Outcome winner;
    }

    struct Pair {
        address passToken;
        address failToken;
    }

    address private immutable GOVERNOR;
    address private immutable TOKEN_IMPLEMENTATION;

    mapping(bytes32 questionId => Question) private _questions;
    mapping(bytes32 questionId => mapping(address underlying => Pair)) private _pairs;
    mapping(bytes32 questionId => mapping(address underlying => uint256)) private _locked;

    modifier onlyGovernor() {
        _checkGovernor();
        _;
    }

    function _checkGovernor() private view {
        if (msg.sender != GOVERNOR) revert Unauthorized(msg.sender);
    }

    constructor(address governor_) {
        if (governor_ == address(0)) revert ZeroAddress();
        GOVERNOR = governor_;
        TOKEN_IMPLEMENTATION = address(new ConditionalToken());
    }

    // -------------------------------------------------------------------------
    // Lifecycle — governor only
    // -------------------------------------------------------------------------

    function openQuestion(bytes32 questionId) external override onlyGovernor {
        if (_questions[questionId].state != QuestionState.None) revert QuestionExists(questionId);
        _questions[questionId].state = QuestionState.Open;
        emit QuestionOpened(questionId, msg.sender);
    }

    /// @notice Creates the PASS/FAIL token pair for one underlying of a question.
    /// @dev Clones are deterministic per (questionId, underlying), so the token
    ///      addresses — and therefore the Uniswap pair addresses derived from
    ///      them — are predictable before creation. That is exactly the surface
    ///      audit finding H-1 exploited on Capital DAO, so whatever seeds the
    ///      pools must absorb a pre-existing donation rather than refuse it
    ///      (decision D7). This contract holds no pool logic; the constraint is
    ///      recorded here because this is where the addresses become knowable.
    function registerUnderlying(
        bytes32 questionId,
        address underlying,
        string calldata symbolPrefix
    ) external override onlyGovernor returns (address passToken, address failToken) {
        if (_questions[questionId].state != QuestionState.Open) revert QuestionNotOpen(questionId);
        if (underlying == address(0)) revert ZeroAddress();
        if (_pairs[questionId][underlying].passToken != address(0)) {
            revert UnderlyingAlreadyRegistered(questionId, underlying);
        }

        uint8 dec = IERC20Metadata(underlying).decimals();

        passToken = Clones.cloneDeterministic(
            TOKEN_IMPLEMENTATION, _salt(questionId, underlying, Outcome.Pass)
        );
        failToken = Clones.cloneDeterministic(
            TOKEN_IMPLEMENTATION, _salt(questionId, underlying, Outcome.Fail)
        );

        ConditionalToken(passToken)
            .initialize(string.concat(symbolPrefix, " PASS"), string.concat("p", symbolPrefix), dec);
        ConditionalToken(failToken)
            .initialize(string.concat(symbolPrefix, " FAIL"), string.concat("f", symbolPrefix), dec);

        _pairs[questionId][underlying] = Pair({passToken: passToken, failToken: failToken});
        emit UnderlyingRegistered(questionId, underlying, passToken, failToken);
    }

    function resolve(bytes32 questionId, Outcome winner) external override onlyGovernor {
        if (_questions[questionId].state != QuestionState.Open) revert QuestionNotOpen(questionId);
        _questions[questionId].state = QuestionState.Resolved;
        _questions[questionId].winner = winner;
        emit QuestionResolved(questionId, winner);
    }

    // -------------------------------------------------------------------------
    // Open to anyone
    // -------------------------------------------------------------------------

    /// @notice Lock `amount` of underlying, receive `amount` of BOTH outcomes.
    function split(bytes32 questionId, address underlying, uint256 amount)
        external
        override
        nonReentrant
    {
        if (_questions[questionId].state != QuestionState.Open) {
            revert QuestionNotOpen(questionId);
        }
        if (amount == 0) revert ZeroAmount();
        Pair memory pair = _requirePair(questionId, underlying);

        _locked[questionId][underlying] += amount;
        _pullExact(underlying, msg.sender, amount);

        ConditionalToken(pair.passToken).mint(msg.sender, amount);
        ConditionalToken(pair.failToken).mint(msg.sender, amount);

        emit Split(questionId, underlying, msg.sender, amount);
    }

    /// @notice Burn `amount` of BOTH outcomes, recover `amount` of underlying.
    /// @dev Available while the question is open, so liquidity providers and
    ///      market makers can unwind without waiting for resolution.
    function merge(bytes32 questionId, address underlying, uint256 amount)
        external
        override
        nonReentrant
    {
        if (_questions[questionId].state != QuestionState.Open) {
            revert QuestionNotOpen(questionId);
        }
        if (amount == 0) revert ZeroAmount();
        Pair memory pair = _requirePair(questionId, underlying);

        _locked[questionId][underlying] -= amount;
        ConditionalToken(pair.passToken).burn(msg.sender, amount);
        ConditionalToken(pair.failToken).burn(msg.sender, amount);

        IERC20(underlying).safeTransfer(msg.sender, amount);
        emit Merged(questionId, underlying, msg.sender, amount);
    }

    /// @notice After resolution, burn the winning token 1:1 for underlying.
    /// @dev Redeems the caller's entire winning balance. The losing token is
    ///      worth zero and is left alone rather than burned, so a holder of only
    ///      the losing side is told plainly that there is nothing to redeem
    ///      instead of silently succeeding with a zero transfer.
    function redeem(bytes32 questionId, address underlying)
        external
        override
        nonReentrant
        returns (uint256 amount)
    {
        Question memory question = _questions[questionId];
        if (question.state != QuestionState.Resolved) revert QuestionNotResolved(questionId);
        Pair memory pair = _requirePair(questionId, underlying);

        address winningToken = question.winner == Outcome.Pass ? pair.passToken : pair.failToken;
        amount = ConditionalToken(winningToken).balanceOf(msg.sender);
        if (amount == 0) revert NothingToRedeem(msg.sender);

        _locked[questionId][underlying] -= amount;
        ConditionalToken(winningToken).burn(msg.sender, amount);

        IERC20(underlying).safeTransfer(msg.sender, amount);
        emit Redeemed(questionId, underlying, msg.sender, question.winner, amount);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    function governor() external view override returns (address) {
        return GOVERNOR;
    }

    function tokenImplementation() external view returns (address) {
        return TOKEN_IMPLEMENTATION;
    }

    function stateOf(bytes32 questionId) external view override returns (QuestionState) {
        return _questions[questionId].state;
    }

    function winnerOf(bytes32 questionId) external view override returns (Outcome) {
        return _questions[questionId].winner;
    }

    function conditionalTokens(bytes32 questionId, address underlying)
        external
        view
        override
        returns (address passToken, address failToken)
    {
        Pair memory pair = _pairs[questionId][underlying];
        return (pair.passToken, pair.failToken);
    }

    function lockedOf(bytes32 questionId, address underlying)
        external
        view
        override
        returns (uint256)
    {
        return _locked[questionId][underlying];
    }

    /// @notice Where a conditional token will live before it is created, so pool
    ///         addresses can be derived ahead of registration.
    function predictConditionalToken(bytes32 questionId, address underlying, Outcome outcome)
        external
        view
        returns (address)
    {
        return Clones.predictDeterministicAddress(
            TOKEN_IMPLEMENTATION, _salt(questionId, underlying, outcome)
        );
    }

    // -------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------

    function _requirePair(bytes32 questionId, address underlying)
        private
        view
        returns (Pair memory pair)
    {
        pair = _pairs[questionId][underlying];
        if (pair.passToken == address(0)) revert UnderlyingNotRegistered(questionId, underlying);
    }

    /// @dev Plain keccak256 over abi.encode. forge-lint suggests inline assembly
    ///      here; declined deliberately — hand-rolled hashing is a readability and
    ///      safety regression for a few gas, and this contract guards the
    ///      conservation law.
    function _salt(bytes32 questionId, address underlying, Outcome outcome)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(questionId, underlying, outcome));
    }

    /// @dev Balance-delta checked, so a fee-on-transfer or rebasing underlying
    ///      cannot break the conservation law by delivering less than it claims.
    function _pullExact(address underlying, address from, uint256 amount) private {
        IERC20 token = IERC20(underlying);
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - before;
        if (received != amount) revert TransferMismatch(amount, received);
    }
}
