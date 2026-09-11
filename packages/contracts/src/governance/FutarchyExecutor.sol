// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ISafe, Operation} from "../interfaces/ISafe.sol";

/// @notice What the Executor needs to know from the Governor, and nothing more.
/// @dev One question, asked once. Keeping the surface this narrow means the
///      Executor can be written, tested and reasoned about before the Governor
///      exists, and that a change to proposal mechanics cannot alter what the
///      treasury is willing to do.
interface IExecutionSource {
    /// @param proposalId The proposal to ask about.
    /// @return approved Whether the market decided this should run.
    /// @return actionsHash The exact batch the market decided on.
    function executionApproval(bytes32 proposalId)
        external
        view
        returns (bool approved, bytes32 actionsHash);
}

/// @title FutarchyExecutor
/// @notice The only thing that can spend a project's treasury. A Safe module
///         that runs one batch of calls, once, after the market approved that
///         exact batch.
///
/// @dev This is MetaDAO's execution layer ported to EVM. There, the treasury is
///      a Squads 1-of-1 whose sole signer is the futarchy program, and a
///      proposal's payload is a Squads transaction the program merely
///      *approves* — the governance program never executes arbitrary code
///      itself. Solana programs can sign for addresses natively; EVM contracts
///      cannot, so a Safe module is the equivalent: modules bypass owner
///      signatures, which lets a contract move funds no human can.
///
///      The same split is kept here. The Governor decides and records a hash.
///      This contract executes, and knows nothing about markets, TWAPs or
///      proposals beyond a single yes/no and a hash to match.
///
///      **Two rules stop a passed proposal from escaping futarchy entirely.**
///      Both close routes that exist on EVM and not on Solana, which is why
///      MetaDAO needs no equivalent:
///
///      1. A batch may not call the Safe. `enableModule`, `addOwnerWithThreshold`
///         and `swapOwner` are ordinary calls to the Safe's own address, so one
///         passed proposal could attach a second module — and that module would
///         answer to nobody. The treasury leaves futarchy permanently, by
///         majority vote, once.
///      2. A batch may never `delegatecall`. Rule 1 alone is not enough:
///         delegatecalling *any* contract runs its code in the Safe's storage,
///         so it can rewrite the module list without the Safe ever appearing as
///         a target. The operation is hard-coded rather than passed in.
contract FutarchyExecutor {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    error ZeroAddress();
    error EmptyBatch();
    error NotApproved(bytes32 proposalId);
    error WrongActions(bytes32 expected, bytes32 provided);
    error AlreadyExecuted(bytes32 proposalId);
    error CannotCallTheSafe(uint256 index);
    error CallFailed(uint256 index, bytes returnData);

    event Executed(bytes32 indexed proposalId, bytes32 indexed actionsHash, uint256 callCount);

    ISafe public immutable SAFE;
    IExecutionSource public immutable GOVERNOR;

    /// @notice Proposals whose batch has already run.
    /// @dev Keyed by proposal rather than by hash, so two proposals that happen
    ///      to carry identical calldata are still each allowed to execute once.
    ///      Keying by hash would let the first silently consume the second.
    mapping(bytes32 proposalId => bool) public executed;

    constructor(address safe_, address governor_) {
        if (safe_ == address(0) || governor_ == address(0)) revert ZeroAddress();
        SAFE = ISafe(safe_);
        GOVERNOR = IExecutionSource(governor_);
    }

    /// @notice Runs a proposal's batch through the Safe.
    /// @dev Deliberately permissionless. The batch is pinned to a hash the market
    ///      already approved, so there is nothing for a caller to choose; making
    ///      it permissioned would only add someone who could refuse to act.
    ///
    ///      All-or-nothing: any failing call reverts the whole batch. A treasury
    ///      instruction that half happened is worse than one that did not.
    function execute(bytes32 proposalId, Call[] calldata calls) external {
        if (calls.length == 0) revert EmptyBatch();

        (bool approved, bytes32 expected) = GOVERNOR.executionApproval(proposalId);
        if (!approved) revert NotApproved(proposalId);

        bytes32 provided = hashActions(calls);
        if (provided != expected) revert WrongActions(expected, provided);

        if (executed[proposalId]) revert AlreadyExecuted(proposalId);
        // Marked before any external call: a batch that re-enters must not be
        // able to run itself twice.
        executed[proposalId] = true;

        for (uint256 i = 0; i < calls.length; i++) {
            Call calldata c = calls[i];

            // Rule 1. See the contract notice — this is the difference between a
            // treasury a market controls and one that can vote itself away.
            if (c.target == address(SAFE)) revert CannotCallTheSafe(i);

            // Rule 2. `Operation.Call` is a constant here, never a parameter.
            (bool ok, bytes memory ret) =
                SAFE.execTransactionFromModuleReturnData(c.target, c.value, c.data, Operation.Call);
            if (!ok) revert CallFailed(i, ret);
        }

        emit Executed(proposalId, expected, calls.length);
    }

    /// @notice The fingerprint of one exact batch.
    ///
    /// @dev The proposal id is deliberately **not** part of this hash, and the
    ///      reason is worth recording because the first version got it wrong.
    ///      Binding the id in looks stricter, but a proposal's id is derived
    ///      from the actions hash it was submitted with — so computing one
    ///      requires the other, and neither can be produced first. The stricter
    ///      hash was simply impossible to use.
    ///
    ///      Nothing is lost. The binding that matters is the Governor's, which
    ///      records one hash per proposal; this contract only checks that the
    ///      batch it was handed is the batch that proposal recorded. Reusing a
    ///      batch under a second proposal requires that proposal to have passed
    ///      with the same hash — which is the market authorising it again, not
    ///      an attacker replaying it. Replay *within* a proposal is stopped by
    ///      `executed`.
    function hashActions(Call[] calldata calls) public pure returns (bytes32) {
        return keccak256(abi.encode(calls));
    }

    /// @notice Whether the Safe has actually granted this module its powers.
    /// @dev Deploying the module is not enabling it. Worth checking explicitly
    ///      during setup, because a Safe with no working executor is a treasury
    ///      nobody can spend from — including the market.
    function isEnabled() external view returns (bool) {
        return SAFE.isModuleEnabled(address(this));
    }
}
