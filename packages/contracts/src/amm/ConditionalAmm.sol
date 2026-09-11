// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPriceSource} from "../interfaces/IPriceSource.sol";
import {LaggedTwapOracle} from "../oracle/LaggedTwapOracle.sol";

/// @title ConditionalAmm
/// @notice The market for one side of one proposal: a constant-product pool
///         holding a matched pair of conditional tokens (pTOKEN/pUSDG, or
///         fTOKEN/fUSDG). A port of MetaDAO's conditional AMM, which is the
///         reference implementation this whole system models (D19).
///
/// @dev Deliberately not a general exchange. It has no router, no fee tiers, no
///      price ranges, no flash accounting and no external integrations. It holds
///      two throwaway tokens for the length of one proposal and is worthless
///      afterwards. That narrowness is the security argument: the surface is
///      small enough to read in one sitting.
///
///      **Reserves are stored, never inferred from balances.** This is the single
///      most important line in the contract. Uniswap V2 derives reserves from
///      `balanceOf`, which is why sending three cents to a pool could brick a
///      Capital DAO raise forever (audit H-1), and why the same trick threatened
///      every proposal here (D7, D18). A donated token here is simply not
///      counted: it cannot move the price, cannot change what an LP is owed, and
///      cannot block anything. The bug class is absent rather than defended.
contract ConditionalAmm is IPriceSource, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error Unauthorized(address caller);
    error ZeroAddress();
    error ZeroAmount();
    error IdenticalTokens();
    error OracleAlreadySet();
    error InsufficientLiquidity();
    error InsufficientShares(uint256 held, uint256 needed);
    error SlippageExceeded(uint256 got, uint256 minimum);

    event LiquidityAdded(
        address indexed provider, uint256 baseIn, uint256 quoteIn, uint256 sharesMinted
    );
    event LiquidityRemoved(
        address indexed provider, uint256 baseOut, uint256 quoteOut, uint256 sharesBurned
    );
    event Swapped(
        address indexed trader,
        bool baseForQuote,
        uint256 amountIn,
        uint256 amountOut,
        uint256 reserveBase,
        uint256 reserveQuote
    );
    event OracleSet(address oracle);

    uint256 private constant WAD = 1e18;
    uint256 private constant BPS = 10_000;

    /// @notice 25 bps, matching MetaDAO. Canonical parameters, §7.
    /// @dev The fee stays in the pool rather than being swept per swap. Since the
    ///      treasury is the dominant liquidity provider once shared liquidity is
    ///      seeded, it accrues to the treasury by holding shares — same
    ///      destination, without a token transfer to an external address on the
    ///      hot path of every trade.
    uint256 public constant FEE_BPS = 25;

    /// @dev Dead shares from the first deposit, so `totalShares` can never return
    ///      to zero while reserves remain and the share price cannot be
    ///      manipulated by emptying the pool.
    uint256 private constant MINIMUM_SHARES = 1000;

    IERC20 public immutable BASE_TOKEN;
    IERC20 public immutable QUOTE_TOKEN;
    address public immutable GOVERNOR;

    /// @notice The slow price this pool feeds. Set once, after deployment,
    ///         because the oracle needs this pool's address to read from.
    LaggedTwapOracle public oracle;

    uint256 public reserveBase;
    uint256 public reserveQuote;
    uint256 public totalShares;
    mapping(address provider => uint256) public sharesOf;

    modifier onlyGovernor() {
        _checkGovernor();
        _;
    }

    function _checkGovernor() private view {
        if (msg.sender != GOVERNOR) revert Unauthorized(msg.sender);
    }

    constructor(address base_, address quote_, address governor_) {
        if (base_ == address(0) || quote_ == address(0) || governor_ == address(0)) {
            revert ZeroAddress();
        }
        if (base_ == quote_) revert IdenticalTokens();

        BASE_TOKEN = IERC20(base_);
        QUOTE_TOKEN = IERC20(quote_);
        GOVERNOR = governor_;
    }

    /// @notice Attaches the oracle. One-time: the pair is fixed for the life of
    ///         the proposal, so a swappable oracle would only be a way to change
    ///         the answer after trading has begun.
    function setOracle(address oracle_) external onlyGovernor {
        if (oracle_ == address(0)) revert ZeroAddress();
        if (address(oracle) != address(0)) revert OracleAlreadySet();
        oracle = LaggedTwapOracle(oracle_);
        emit OracleSet(oracle_);
    }

    // -------------------------------------------------------------- liquidity

    /// @notice Deposits both sides and mints shares.
    /// @dev Callers after the first should supply amounts in the current reserve
    ///      ratio; shares are minted on the scarcer side and any excess is
    ///      donated to the pool. The seeder always supplies balanced amounts, and
    ///      quoting the right ratio is a caller's job here exactly as it is a
    ///      router's job on Uniswap.
    function addLiquidity(uint256 baseAmount, uint256 quoteAmount)
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (baseAmount == 0 || quoteAmount == 0) revert ZeroAmount();

        uint256 supply = totalShares;
        if (supply == 0) {
            shares = Math.sqrt(baseAmount * quoteAmount);
            if (shares <= MINIMUM_SHARES) revert InsufficientLiquidity();
            unchecked {
                shares -= MINIMUM_SHARES;
            }
            // Burned to a hole nobody controls.
            totalShares = MINIMUM_SHARES;
            sharesOf[address(0)] = MINIMUM_SHARES;
        } else {
            shares = Math.min(
                Math.mulDiv(baseAmount, supply, reserveBase),
                Math.mulDiv(quoteAmount, supply, reserveQuote)
            );
            if (shares == 0) revert InsufficientLiquidity();
        }

        // Effects before interactions.
        reserveBase += baseAmount;
        reserveQuote += quoteAmount;
        totalShares += shares;
        sharesOf[msg.sender] += shares;

        BASE_TOKEN.safeTransferFrom(msg.sender, address(this), baseAmount);
        QUOTE_TOKEN.safeTransferFrom(msg.sender, address(this), quoteAmount);

        emit LiquidityAdded(msg.sender, baseAmount, quoteAmount, shares);
    }

    /// @notice Burns shares and returns a proportional slice of both reserves.
    /// @dev Proportional withdrawal leaves the price untouched, so the oracle has
    ///      nothing to observe here. This is also how a complete set is recovered
    ///      after resolution: pull the inventory out, then merge it in the vault.
    function removeLiquidity(uint256 shares)
        external
        nonReentrant
        returns (uint256 baseOut, uint256 quoteOut)
    {
        if (shares == 0) revert ZeroAmount();
        uint256 held = sharesOf[msg.sender];
        if (held < shares) revert InsufficientShares(held, shares);

        uint256 supply = totalShares;
        baseOut = Math.mulDiv(shares, reserveBase, supply);
        quoteOut = Math.mulDiv(shares, reserveQuote, supply);
        if (baseOut == 0 && quoteOut == 0) revert InsufficientLiquidity();

        unchecked {
            sharesOf[msg.sender] = held - shares;
            totalShares = supply - shares;
            reserveBase -= baseOut;
            reserveQuote -= quoteOut;
        }

        if (baseOut > 0) BASE_TOKEN.safeTransfer(msg.sender, baseOut);
        if (quoteOut > 0) QUOTE_TOKEN.safeTransfer(msg.sender, quoteOut);

        emit LiquidityRemoved(msg.sender, baseOut, quoteOut, shares);
    }

    // ------------------------------------------------------------------ swaps

    function swapExactBaseForQuote(uint256 amountIn, uint256 minAmountOut)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        return _swap(true, amountIn, minAmountOut);
    }

    function swapExactQuoteForBase(uint256 amountIn, uint256 minAmountOut)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        return _swap(false, amountIn, minAmountOut);
    }

    function _swap(bool baseForQuote, uint256 amountIn, uint256 minAmountOut)
        private
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        if (reserveBase == 0 || reserveQuote == 0) revert InsufficientLiquidity();

        // Record the price that stood BEFORE this trade.
        //
        // Ordering is the security property. The observation steps toward the
        // pre-trade price, so moving the price and banking the movement cannot
        // happen in one transaction — you must move it and leave it moved, in the
        // open, where anyone can trade against you. That is precisely the cost
        // the whole design is built to impose (D4, D8).
        _touchOracle();

        (uint256 reserveIn, uint256 reserveOut) =
            baseForQuote ? (reserveBase, reserveQuote) : (reserveQuote, reserveBase);

        uint256 amountInAfterFee = Math.mulDiv(amountIn, BPS - FEE_BPS, BPS);
        amountOut = Math.mulDiv(amountInAfterFee, reserveOut, reserveIn + amountInAfterFee);

        if (amountOut == 0) revert InsufficientLiquidity();
        if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);

        // The full amountIn enters the reserves; the fee is the part that is not
        // credited toward the output, which is what leaves it with the LPs.
        if (baseForQuote) {
            reserveBase += amountIn;
            reserveQuote -= amountOut;
        } else {
            reserveQuote += amountIn;
            reserveBase -= amountOut;
        }

        (IERC20 tokenIn, IERC20 tokenOut) =
            baseForQuote ? (BASE_TOKEN, QUOTE_TOKEN) : (QUOTE_TOKEN, BASE_TOKEN);

        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenOut.safeTransfer(msg.sender, amountOut);

        emit Swapped(msg.sender, baseForQuote, amountIn, amountOut, reserveBase, reserveQuote);
    }

    /// @dev Updates the slow price if an oracle is attached and running. Silent
    ///      when it is not: markets may trade before the oracle is started, and a
    ///      pool that refuses trades because its oracle is not ready is a worse
    ///      failure than an observation that starts a little later.
    function _touchOracle() private {
        LaggedTwapOracle o = oracle;
        if (address(o) != address(0) && o.startedAt() != 0) o.poke();
    }

    // ------------------------------------------------------------------ views

    /// @inheritdoc IPriceSource
    /// @dev Reads the stored reserves, so a donation cannot shift it.
    function spotPrice() external view override returns (uint256) {
        uint256 b = reserveBase;
        if (b == 0 || reserveQuote == 0) return 0;
        return Math.mulDiv(reserveQuote, WAD, b);
    }

    function base() external view override returns (address) {
        return address(BASE_TOKEN);
    }

    function quote() external view override returns (address) {
        return address(QUOTE_TOKEN);
    }

    /// @notice Quotes a trade without executing it.
    function quoteSwap(bool baseForQuote, uint256 amountIn) external view returns (uint256) {
        if (amountIn == 0 || reserveBase == 0 || reserveQuote == 0) return 0;
        (uint256 reserveIn, uint256 reserveOut) =
            baseForQuote ? (reserveBase, reserveQuote) : (reserveQuote, reserveBase);
        uint256 amountInAfterFee = Math.mulDiv(amountIn, BPS - FEE_BPS, BPS);
        return Math.mulDiv(amountInAfterFee, reserveOut, reserveIn + amountInAfterFee);
    }

    /// @notice Tokens held beyond what the pool counts — donations, or dust from
    ///         a fee-on-transfer token. Recoverable by the governor precisely
    ///         because they were never part of the pool's accounting.
    function surplus() external view returns (uint256 baseSurplus, uint256 quoteSurplus) {
        baseSurplus = BASE_TOKEN.balanceOf(address(this)) - reserveBase;
        quoteSurplus = QUOTE_TOKEN.balanceOf(address(this)) - reserveQuote;
    }

    /// @notice Sweeps untracked tokens to the treasury.
    /// @dev Cannot touch reserves: it can only move the difference between the
    ///      real balance and the recorded reserve, which by construction is what
    ///      nobody deposited through `addLiquidity`.
    function skimSurplus(address to) external onlyGovernor nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 baseSurplus = BASE_TOKEN.balanceOf(address(this)) - reserveBase;
        uint256 quoteSurplus = QUOTE_TOKEN.balanceOf(address(this)) - reserveQuote;
        if (baseSurplus > 0) BASE_TOKEN.safeTransfer(to, baseSurplus);
        if (quoteSurplus > 0) QUOTE_TOKEN.safeTransfer(to, quoteSurplus);
    }
}
