// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice How a Safe performs a call on behalf of a module.
/// @dev `DelegateCall` runs the target's code inside the Safe's own storage. A
///      module that lets a proposal choose this has handed over the treasury:
///      delegatecalling any contract that calls `enableModule` rewrites the
///      Safe's module list directly, without ever naming the Safe as a target.
///      `FutarchyExecutor` therefore hard-codes `Call` and never accepts the
///      operation as a parameter.
enum Operation {
    Call,
    DelegateCall
}

/// @notice The slice of Safe our module touches.
/// @dev Declared locally rather than vendoring the Safe contracts. This is the
///      whole surface we use, and the project's rule is to copy patterns rather
///      than take dependencies (D2).
interface ISafe {
    /// @notice Performs a transaction as the Safe, bypassing owner signatures.
    /// @dev This is the mechanism the whole design rests on. A Solana program
    ///      can sign for an address natively, which is how MetaDAO makes the
    ///      futarchy program the treasury's sole signer. EVM contracts cannot,
    ///      so the equivalent is a module: modules skip the owner-signature
    ///      check entirely, letting a contract move funds no human can.
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation
    ) external returns (bool success, bytes memory returnData);

    function isModuleEnabled(address module) external view returns (bool);
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
}
