// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title ConditionalToken
/// @notice A minimal ERC-20 representing one outcome of one underlying, for one
///         question. Deployed as an EIP-1167 clone by the vault, which is the
///         only address that may mint or burn.
/// @dev Deliberately a plain ERC-20 rather than ERC-1155 (decision D6). Uniswap
///      pools only hold ERC-20, every wallet renders it, and there is no
///      receive-hook callback for an attacker to re-enter through.
contract ConditionalToken is IERC20, IERC20Metadata {
    error Unauthorized(address caller);
    error AlreadyInitialized();
    error ZeroAddress();
    error InsufficientBalance(address account, uint256 balance, uint256 needed);
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    address public vault;
    uint8 private _decimals;
    string private _name;
    string private _symbol;

    uint256 public override totalSupply;
    mapping(address account => uint256) public override balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public override allowance;

    /// @dev Clones start with all storage zeroed, so `vault == address(0)` is the
    ///      uninitialised marker and initialisation can only ever happen once.
    function initialize(string memory name_, string memory symbol_, uint8 decimals_) external {
        if (vault != address(0)) revert AlreadyInitialized();
        if (msg.sender == address(0)) revert ZeroAddress();
        vault = msg.sender;
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    /// @notice Mirrors the underlying's decimals so a conditional unit is always
    ///         one underlying unit. USDG is 6, not 18 — never assume.
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != vault) revert Unauthorized(msg.sender);
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != vault) revert Unauthorized(msg.sender);
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance(from, balance, amount);
        unchecked {
            balanceOf[from] = balance - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        override
        returns (bool)
    {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance(msg.sender, allowed, amount);
            unchecked {
                allowance[from][msg.sender] = allowed - amount;
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance(from, balance, amount);
        unchecked {
            balanceOf[from] = balance - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}
