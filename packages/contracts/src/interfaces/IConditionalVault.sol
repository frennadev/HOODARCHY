// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice A binary question whose outcome is decided by the Governor.
enum Outcome {
    Pass,
    Fail
}

enum QuestionState {
    None,
    Open,
    Resolved
}

interface IConditionalVault {
    error Unauthorized(address caller);
    error ZeroAddress();
    error ZeroAmount();
    error QuestionExists(bytes32 questionId);
    error QuestionNotOpen(bytes32 questionId);
    error QuestionNotResolved(bytes32 questionId);
    error UnderlyingNotRegistered(bytes32 questionId, address underlying);
    error UnderlyingAlreadyRegistered(bytes32 questionId, address underlying);
    error TransferMismatch(uint256 expected, uint256 received);
    error NothingToRedeem(address account);

    event QuestionOpened(bytes32 indexed questionId, address indexed governor);
    event UnderlyingRegistered(
        bytes32 indexed questionId, address indexed underlying, address passToken, address failToken
    );
    event Split(
        bytes32 indexed questionId,
        address indexed underlying,
        address indexed account,
        uint256 amount
    );
    event Merged(
        bytes32 indexed questionId,
        address indexed underlying,
        address indexed account,
        uint256 amount
    );
    event QuestionResolved(bytes32 indexed questionId, Outcome winner);
    event Redeemed(
        bytes32 indexed questionId,
        address indexed underlying,
        address indexed account,
        Outcome outcome,
        uint256 amount
    );

    function openQuestion(bytes32 questionId) external;
    function registerUnderlying(
        bytes32 questionId,
        address underlying,
        string calldata symbolPrefix
    ) external returns (address passToken, address failToken);
    function resolve(bytes32 questionId, Outcome winner) external;

    function split(bytes32 questionId, address underlying, uint256 amount) external;
    function merge(bytes32 questionId, address underlying, uint256 amount) external;
    function redeem(bytes32 questionId, address underlying) external returns (uint256 amount);

    function governor() external view returns (address);
    function stateOf(bytes32 questionId) external view returns (QuestionState);
    function winnerOf(bytes32 questionId) external view returns (Outcome);
    function conditionalTokens(bytes32 questionId, address underlying)
        external
        view
        returns (address passToken, address failToken);
    function lockedOf(bytes32 questionId, address underlying) external view returns (uint256);
}
