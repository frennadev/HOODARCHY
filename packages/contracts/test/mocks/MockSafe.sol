// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Operation} from "../../src/interfaces/ISafe.sol";

/// @notice Stand-in for a Safe: performs module transactions for real, and
///         records how it was asked to.
/// @dev Recording the operation matters. `FutarchyExecutor` is supposed to
///      hard-code `Call`, and the only way to show it never delegatecalls is to
///      have the Safe remember what it was handed.
///
///      A mock is not enough on its own — audit lesson §6.2(d) is that a mock
///      hid a real Uniswap failure once already — so there is a fork test
///      against a genuine Safe alongside these.
contract MockSafe {
    mapping(address module => bool) public isModuleEnabled;

    Operation public lastOperation;
    uint256 public callCount;
    bool public sawDelegateCall;

    address[] private _owners;
    uint256 private _threshold = 1;

    receive() external payable {}

    function enableModule(address module) external {
        isModuleEnabled[module] = true;
    }

    function setOwners(address[] calldata owners_, uint256 threshold_) external {
        _owners = owners_;
        _threshold = threshold_;
    }

    function getOwners() external view returns (address[] memory) {
        return _owners;
    }

    function getThreshold() external view returns (uint256) {
        return _threshold;
    }

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation
    ) external returns (bool success, bytes memory returnData) {
        require(isModuleEnabled[msg.sender], "MockSafe: module not enabled");

        lastOperation = operation;
        callCount++;
        if (operation == Operation.DelegateCall) sawDelegateCall = true;

        if (operation == Operation.DelegateCall) {
            // solhint-disable-next-line avoid-low-level-calls
            (success, returnData) = to.delegatecall(data);
        } else {
            // solhint-disable-next-line avoid-low-level-calls
            (success, returnData) = to.call{value: value}(data);
        }
    }
}
