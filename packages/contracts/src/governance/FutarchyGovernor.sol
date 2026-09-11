// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ConditionalAmm} from "../amm/ConditionalAmm.sol";
import {ConditionalVault} from "../conditional/ConditionalVault.sol";
import {Outcome} from "../interfaces/IConditionalVault.sol";
import {LaggedTwapOracle} from "../oracle/LaggedTwapOracle.sol";
import {IExecutionSource} from "./FutarchyExecutor.sol";
import {MarketFactory} from "./MarketFactory.sol";

/// @title FutarchyGovernor
/// @notice Runs a proposal from submission to decision: takes the anti-spam
///         stake, stands up the two markets, waits out the clock, compares the
///         two settled prices, and tells the vault and the Executor what the
///         market decided.
///
/// @dev The keystone. Every other contract here is inert without it — the vault
///      answers only to this address, and the Executor asks only this address
///      whether it may spend.
///
///      **No parameter is settable.** Windows, the winning margin, the stake and
///      the rate limit are all fixed at deployment. §6.3.3 warns that a passed
///      proposal which sets the margin to -100% makes everything after it pass
///      automatically, and that a timelock only postpones that. The simplest
///      answer to a governance system that can rewrite its own rules is one that
///      cannot, so v1 does not try. When parameters do become changeable they
///      need hard bounds in code first, not merely a delay.
contract FutarchyGovernor is IExecutionSource, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum State {
        None,
        Proposed,
        Active,
        Passed,
        Failed,
        Cancelled
    }

    struct Proposal {
        State state;
        bool teamSponsored;
        bool seedReclaimed;
        address proposer;
        address seeder;
        uint64 launchedAt;
        uint256 stake;
        bytes32 descriptionHash;
        bytes32 actionsHash;
        ConditionalAmm passAmm;
        ConditionalAmm failAmm;
        LaggedTwapOracle passOracle;
        LaggedTwapOracle failOracle;
    }

    error ZeroAddress();
    error ZeroAmount();
    error Unauthorized(address caller);
    error WrongState(bytes32 proposalId, State actual);
    error MarketsNotSettled(bytes32 proposalId);
    error AlreadyReclaimed(bytes32 proposalId);

    /// @dev `descriptionUri` is emitted but never stored. The log is permanent
    ///      and readable, which is all an indexer or a reader needs, and keeping
    ///      a string out of storage keeps proposing cheap. `descriptionHash`
    ///      stays in storage as the commitment: fetch the URI, hash what you
    ///      get, and compare. Together they give "no hidden proposals" (§3.3)
    ///      *and* integrity — a hash alone lets you verify text you were handed
    ///      but never lets you find it.
    event Proposed(
        bytes32 indexed proposalId,
        address indexed proposer,
        string descriptionUri,
        bytes32 descriptionHash,
        bytes32 actionsHash,
        bool teamSponsored
    );

    /// @dev Carries the oracles as well as the pools. Without them an indexer
    ///      has to correlate `MarketFactory.MarketCreated` events by transaction
    ///      to learn where a proposal's prices are recorded, which is fragile
    ///      for the sake of two words.
    event Launched(
        bytes32 indexed proposalId,
        address indexed seeder,
        address passAmm,
        address failAmm,
        address passOracle,
        address failOracle,
        uint256 anchorPrice,
        uint64 tradingOpensAt,
        uint64 tradingClosesAt
    );
    event Finalized(
        bytes32 indexed proposalId,
        bool passed,
        uint256 twapPass,
        uint256 twapFail,
        uint256 threshold
    );
    event Cancelled(bytes32 indexed proposalId, address indexed by);
    event SeedReclaimed(bytes32 indexed proposalId, uint256 baseOut, uint256 quoteOut);

    uint256 private constant WAD = 1e18;
    uint256 private constant BPS = 10_000;

    /// @notice The winning margin, per §3.4: `pass > fail * (1 + tau)`, where
    ///         tau is +3% for an external proposal and -3% for a team-sponsored
    ///         one. So an outsider's proposal must clearly beat the fail market,
    ///         while the team's survives unless the fail market clearly beats it.
    ///
    /// @dev Stored as the multiplier rather than as a signed tau. The signed form
    ///      reads closer to the spec but forces a cast back to unsigned for the
    ///      arithmetic, and a cast that is only safe because two constants happen
    ///      to be small is the kind of thing that stops being true when someone
    ///      later makes them configurable.
    uint256 public constant PASS_MULTIPLIER_EXTERNAL_BPS = 10_300; // fail x 1.03
    uint256 public constant PASS_MULTIPLIER_TEAM_BPS = 9_700; // fail x 0.97

    ConditionalVault public immutable VAULT;
    MarketFactory public immutable MARKET_FACTORY;
    IERC20 public immutable BASE_TOKEN;
    IERC20 public immutable QUOTE_TOKEN;

    /// @notice May cancel a proposal that has not settled. May never spend.
    /// @dev §6.6: "A guardian that can execute is how you stop being a futarchy."
    address public immutable GUARDIAN;

    uint256 public immutable BASE_TO_STAKE;
    uint256 public immutable MAX_CHANGE_PER_SECOND;
    uint64 public immutable DELAY;
    uint64 public immutable WINDOW;
    uint64 public immutable MAX_STEP_ELAPSED;

    string public baseSymbol;
    string public quoteSymbol;

    uint256 public proposalCount;
    mapping(bytes32 proposalId => Proposal) private _proposals;

    constructor(
        address baseToken_,
        address quoteToken_,
        address marketFactory_,
        address guardian_,
        uint256 baseToStake_,
        uint256 maxChangePerSecond_,
        uint64 delay_,
        uint64 window_,
        uint64 maxStepElapsed_
    ) {
        if (baseToken_ == address(0) || quoteToken_ == address(0) || marketFactory_ == address(0)) revert ZeroAddress();

        BASE_TOKEN = IERC20(baseToken_);
        QUOTE_TOKEN = IERC20(quoteToken_);
        MARKET_FACTORY = MarketFactory(marketFactory_);
        GUARDIAN = guardian_; // zero is allowed: a DAO may choose no guardian
        BASE_TO_STAKE = baseToStake_;
        MAX_CHANGE_PER_SECOND = maxChangePerSecond_;
        DELAY = delay_;
        WINDOW = window_;
        MAX_STEP_ELAPSED = maxStepElapsed_;

        baseSymbol = IERC20Metadata(baseToken_).symbol();
        quoteSymbol = IERC20Metadata(quoteToken_).symbol();

        // Built here rather than passed in, so the vault's governor is this
        // contract by construction and cannot be pointed anywhere else.
        VAULT = new ConditionalVault(address(this));
    }

    // ------------------------------------------------------------- lifecycle

    /// @notice Submits a proposal and locks the anti-spam stake in one step.
    /// @param descriptionHash Fingerprint of the off-chain description.
    /// @param actionsHash Fingerprint of the batch the Executor will run. The
    ///        calls themselves stay off-chain until execution; binding the hash
    ///        is what makes the thing traded and the thing executed identical.
    /// @dev The stake is returned when trading starts, never slashed. It exists
    ///      so nobody can flood the queue, not to punish losing.
    /// @param descriptionUri Where to read the proposal. Emitted, not stored.
    /// @dev The URI is not part of the proposal id: the id commits to the
    ///      description's *hash*, so rehosting the text somewhere else cannot
    ///      change which proposal this is.
    function propose(
        string calldata descriptionUri,
        bytes32 descriptionHash,
        bytes32 actionsHash,
        bool teamSponsored
    ) external nonReentrant returns (bytes32 proposalId) {
        proposalId = keccak256(
            abi.encode(address(this), proposalCount++, msg.sender, descriptionHash, actionsHash)
        );

        Proposal storage p = _proposals[proposalId];
        p.state = State.Proposed;
        p.proposer = msg.sender;
        p.teamSponsored = teamSponsored;
        p.descriptionHash = descriptionHash;
        p.actionsHash = actionsHash;
        p.stake = BASE_TO_STAKE;

        if (BASE_TO_STAKE > 0) {
            BASE_TOKEN.safeTransferFrom(msg.sender, address(this), BASE_TO_STAKE);
        }

        emit Proposed(
            proposalId, msg.sender, descriptionUri, descriptionHash, actionsHash, teamSponsored
        );
    }

    /// @notice Opens the two markets and starts the clock.
    /// @dev Seeding both sides costs one complete set, not two. Splitting
    ///      `seedBase` yields that much pTOKEN *and* that much fTOKEN, so a
    ///      single deposit funds the pass market and the fail market to equal
    ///      depth. That is the property that makes both books deep rather than
    ///      one thin one and one thinner.
    function launch(bytes32 proposalId, uint256 seedBase, uint256 seedQuote) external nonReentrant {
        Proposal storage p = _proposals[proposalId];
        if (p.state != State.Proposed) revert WrongState(proposalId, p.state);
        if (seedBase == 0 || seedQuote == 0) revert ZeroAmount();

        p.state = State.Active;
        p.seeder = msg.sender;
        p.launchedAt = uint64(block.timestamp);

        (address pBase, address fBase, address pQuote, address fQuote) = _openQuestion(proposalId);
        _buildMarkets(p, pBase, fBase, pQuote, fQuote);

        // The opening price is computed from what we are about to seed, never
        // read from the pool (D12). A pool whose price could be read at launch
        // is a pool an attacker can set the starting point of.
        uint256 anchor = Math.mulDiv(seedQuote, WAD, seedBase);

        _seed(p, proposalId, pBase, fBase, pQuote, fQuote, seedBase, seedQuote);

        p.passOracle.start(anchor);
        p.failOracle.start(anchor);

        // Stake back at launch, as promised. Anti-spam, not a bond against losing.
        uint256 stake = p.stake;
        if (stake > 0) {
            p.stake = 0;
            BASE_TOKEN.safeTransfer(p.proposer, stake);
        }

        emit Launched(
            proposalId,
            msg.sender,
            address(p.passAmm),
            address(p.failAmm),
            address(p.passOracle),
            address(p.failOracle),
            anchor,
            p.passOracle.twapActiveFrom(),
            p.passOracle.twapEndsAt()
        );
    }

    /// @notice Reads both settled averages and decides.
    /// @dev Permissionless, and safe to be so only because both windows have
    ///      closed: the answer is frozen, so the caller cannot influence it by
    ///      choosing when to ask (D20). Before that fix this function was the
    ///      whole attack.
    function finalize(bytes32 proposalId) external nonReentrant {
        Proposal storage p = _proposals[proposalId];
        if (p.state != State.Active) revert WrongState(proposalId, p.state);
        if (!p.passOracle.isSettled() || !p.failOracle.isSettled()) {
            revert MarketsNotSettled(proposalId);
        }

        uint256 twapPass = p.passOracle.currentTwap();
        uint256 twapFail = p.failOracle.currentTwap();
        uint256 threshold = thresholdFor(twapFail, p.teamSponsored);

        bool passed = twapPass > threshold;
        p.state = passed ? State.Passed : State.Failed;

        VAULT.resolve(proposalId, passed ? Outcome.Pass : Outcome.Fail);

        emit Finalized(proposalId, passed, twapPass, twapFail, threshold);
    }

    /// @notice Stops a proposal that has not settled.
    /// @dev The guardian may cancel; the proposer may withdraw their own before
    ///      it launches. Neither can spend anything — that is the line §6.6
    ///      draws, and it is the difference between an emergency brake and a
    ///      veto over the market.
    ///
    ///      Cancelling a *live* proposal resolves it to Fail. That is the
    ///      honest reading — the instruction did not happen — but it is a real
    ///      power: anyone holding the pass side loses. The alternative, leaving
    ///      the question open forever, strands anyone who holds only one side,
    ///      which is worse.
    function cancel(bytes32 proposalId) external nonReentrant {
        Proposal storage p = _proposals[proposalId];
        bool isGuardian = GUARDIAN != address(0) && msg.sender == GUARDIAN;

        if (p.state == State.Proposed) {
            if (!isGuardian && msg.sender != p.proposer) revert Unauthorized(msg.sender);
            uint256 stake = p.stake;
            if (stake > 0) {
                p.stake = 0;
                BASE_TOKEN.safeTransfer(p.proposer, stake);
            }
        } else if (p.state == State.Active) {
            if (!isGuardian) revert Unauthorized(msg.sender);
            VAULT.resolve(proposalId, Outcome.Fail);
        } else {
            revert WrongState(proposalId, p.state);
        }

        p.state = State.Cancelled;
        emit Cancelled(proposalId, msg.sender);
    }

    /// @notice Returns the seed liquidity once the question has resolved.
    /// @dev Without this the capital that opened the markets is locked forever,
    ///      and nobody seeds a second proposal.
    function reclaimSeed(bytes32 proposalId) external nonReentrant returns (uint256, uint256) {
        Proposal storage p = _proposals[proposalId];
        if (p.state != State.Passed && p.state != State.Failed && p.state != State.Cancelled) {
            revert WrongState(proposalId, p.state);
        }
        if (p.seedReclaimed) revert AlreadyReclaimed(proposalId);
        if (msg.sender != p.seeder) revert Unauthorized(msg.sender);
        p.seedReclaimed = true;

        _withdrawAll(p.passAmm);
        _withdrawAll(p.failAmm);

        uint256 baseOut = _redeemIfAny(proposalId, address(BASE_TOKEN));
        uint256 quoteOut = _redeemIfAny(proposalId, address(QUOTE_TOKEN));

        if (baseOut > 0) BASE_TOKEN.safeTransfer(msg.sender, baseOut);
        if (quoteOut > 0) QUOTE_TOKEN.safeTransfer(msg.sender, quoteOut);

        emit SeedReclaimed(proposalId, baseOut, quoteOut);
        return (baseOut, quoteOut);
    }

    // ----------------------------------------------------------------- views

    /// @inheritdoc IExecutionSource
    function executionApproval(bytes32 proposalId) external view returns (bool, bytes32) {
        Proposal storage p = _proposals[proposalId];
        return (p.state == State.Passed, p.actionsHash);
    }

    /// @notice The number the pass market must beat.
    function thresholdFor(uint256 twapFail, bool teamSponsored) public pure returns (uint256) {
        uint256 multiplier = teamSponsored ? PASS_MULTIPLIER_TEAM_BPS : PASS_MULTIPLIER_EXTERNAL_BPS;
        return Math.mulDiv(twapFail, multiplier, BPS);
    }

    function stateOf(bytes32 proposalId) external view returns (State) {
        return _proposals[proposalId].state;
    }

    function proposalOf(bytes32 proposalId) external view returns (Proposal memory) {
        return _proposals[proposalId];
    }

    function marketsOf(bytes32 proposalId)
        external
        view
        returns (address passAmm, address failAmm, address passOracle, address failOracle)
    {
        Proposal storage p = _proposals[proposalId];
        return
            (address(p.passAmm), address(p.failAmm), address(p.passOracle), address(p.failOracle));
    }

    // ------------------------------------------------------------- internals

    function _openQuestion(bytes32 proposalId)
        private
        returns (address pBase, address fBase, address pQuote, address fQuote)
    {
        VAULT.openQuestion(proposalId);
        (pBase, fBase) = VAULT.registerUnderlying(proposalId, address(BASE_TOKEN), baseSymbol);
        (pQuote, fQuote) = VAULT.registerUnderlying(proposalId, address(QUOTE_TOKEN), quoteSymbol);
    }

    function _buildMarkets(
        Proposal storage p,
        address pBase,
        address fBase,
        address pQuote,
        address fQuote
    ) private {
        (ConditionalAmm passAmm, LaggedTwapOracle passOracle) = MARKET_FACTORY.createMarket(
            pBase, pQuote, address(this), MAX_CHANGE_PER_SECOND, DELAY, MAX_STEP_ELAPSED, WINDOW
        );
        (ConditionalAmm failAmm, LaggedTwapOracle failOracle) = MARKET_FACTORY.createMarket(
            fBase, fQuote, address(this), MAX_CHANGE_PER_SECOND, DELAY, MAX_STEP_ELAPSED, WINDOW
        );

        passAmm.setOracle(address(passOracle));
        failAmm.setOracle(address(failOracle));

        p.passAmm = passAmm;
        p.failAmm = failAmm;
        p.passOracle = passOracle;
        p.failOracle = failOracle;
    }

    function _seed(
        Proposal storage p,
        bytes32 proposalId,
        address pBase,
        address fBase,
        address pQuote,
        address fQuote,
        uint256 seedBase,
        uint256 seedQuote
    ) private {
        BASE_TOKEN.safeTransferFrom(msg.sender, address(this), seedBase);
        QUOTE_TOKEN.safeTransferFrom(msg.sender, address(this), seedQuote);

        BASE_TOKEN.forceApprove(address(VAULT), seedBase);
        QUOTE_TOKEN.forceApprove(address(VAULT), seedQuote);
        VAULT.split(proposalId, address(BASE_TOKEN), seedBase);
        VAULT.split(proposalId, address(QUOTE_TOKEN), seedQuote);

        IERC20(pBase).forceApprove(address(p.passAmm), seedBase);
        IERC20(pQuote).forceApprove(address(p.passAmm), seedQuote);
        p.passAmm.addLiquidity(seedBase, seedQuote);

        IERC20(fBase).forceApprove(address(p.failAmm), seedBase);
        IERC20(fQuote).forceApprove(address(p.failAmm), seedQuote);
        p.failAmm.addLiquidity(seedBase, seedQuote);
    }

    function _withdrawAll(ConditionalAmm amm) private {
        uint256 shares = amm.sharesOf(address(this));
        if (shares > 0) amm.removeLiquidity(shares);
    }

    /// @dev `redeem` reverts when there is nothing to redeem, which is a
    ///      perfectly ordinary outcome here — the market may have traded all of
    ///      the winning side away from us. Check first rather than revert the
    ///      whole reclaim.
    function _redeemIfAny(bytes32 proposalId, address underlying) private returns (uint256) {
        (address passToken, address failToken) = VAULT.conditionalTokens(proposalId, underlying);
        address winner = VAULT.winnerOf(proposalId) == Outcome.Pass ? passToken : failToken;
        if (IERC20(winner).balanceOf(address(this)) == 0) return 0;
        return VAULT.redeem(proposalId, underlying);
    }
}
