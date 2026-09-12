// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice A token that delivers less than it says it will.
///
/// @dev Fee-on-transfer and rebasing tokens break any contract that assumes
///      `transferFrom(x)` moves exactly `x`. The vault claims to be safe against
///      this — `_pullExact` measures the balance delta and reverts on a
///      shortfall — but that guard had never been exercised, so the claim rested
///      on reading the code rather than on evidence.
///
///      Deliberately a *silent* thief: it returns true and emits a normal
///      Transfer event. A token that reverted or returned false would be caught
///      by SafeERC20 long before reaching our check, and would prove nothing.
contract MockFeeOnTransferERC20 is ERC20 {
    uint8 private immutable DECIMALS;

    /// @notice Basis points skimmed from every transfer.
    uint256 public feeBps;

    constructor(string memory n, string memory s, uint8 d, uint256 feeBps_) ERC20(n, s) {
        DECIMALS = d;
        feeBps = feeBps_;
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFeeBps(uint256 feeBps_) external {
        feeBps = feeBps_;
    }

    /// @dev The fee is burned rather than sent anywhere, so total supply drops.
    ///      The recipient simply receives less than the caller asked to send.
    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0) || feeBps == 0) {
            super._update(from, to, value);
            return;
        }
        uint256 fee = (value * feeBps) / 10_000;
        super._update(from, to, value - fee);
        if (fee > 0) super._update(from, address(0), fee);
    }
}
