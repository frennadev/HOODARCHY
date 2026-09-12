// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ConditionalToken} from "../../src/conditional/ConditionalToken.sol";
import {ConditionalVault} from "../../src/conditional/ConditionalVault.sol";
import {Outcome, QuestionState} from "../../src/interfaces/IConditionalVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice The surface the invariant fuzzer is allowed to drive.
///
/// @dev A handler exists so the fuzzer makes *plausible* calls rather than
///      random garbage that reverts on the first argument check. Every function
///      here is something a real participant can do, in an order nobody scripted
///      — which is the whole point: the hand-written tests only prove the
///      sequences we thought of.
///
///      This contract is the vault's governor, so it can open the question and
///      resolve it. Everything else it does as one of several actors.
contract ConditionalVaultHandler is Test {
    ConditionalVault public immutable VAULT;
    MockERC20 public immutable TOKEN;
    bytes32 public constant QID = keccak256("invariant-question");

    ConditionalToken public passToken;
    ConditionalToken public failToken;

    address[] public actors;
    address internal currentActor;

    // --- ghosts: what we believe happened, tracked independently of the vault
    uint256 public ghostSplit;
    uint256 public ghostMerged;
    uint256 public ghostRedeemed;
    uint256 public callsSplit;
    uint256 public callsMerge;
    uint256 public callsRedeem;
    uint256 public callsTransfer;
    bool public resolved;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(MockERC20 token_) {
        TOKEN = token_;
        VAULT = new ConditionalVault(address(this));

        VAULT.openQuestion(QID);
        (address p, address f) = VAULT.registerUnderlying(QID, address(token_), "TKN");
        passToken = ConditionalToken(p);
        failToken = ConditionalToken(f);

        for (uint256 i = 0; i < 5; i++) {
            actors.push(address(uint160(uint256(keccak256(abi.encode("actor", i))))));
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // ------------------------------------------------------------- actions

    function split(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        if (VAULT.stateOf(QID) != QuestionState.Open) return;
        amount = bound(amount, 1, 1_000_000e18);

        TOKEN.mint(currentActor, amount);
        TOKEN.approve(address(VAULT), amount);
        VAULT.split(QID, address(TOKEN), amount);

        ghostSplit += amount;
        callsSplit++;
    }

    function merge(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        if (VAULT.stateOf(QID) != QuestionState.Open) return;

        uint256 available =
            _min(passToken.balanceOf(currentActor), failToken.balanceOf(currentActor));
        if (available == 0) return;
        amount = bound(amount, 1, available);

        VAULT.merge(QID, address(TOKEN), amount);
        ghostMerged += amount;
        callsMerge++;
    }

    function redeem(uint256 actorSeed) external useActor(actorSeed) {
        if (VAULT.stateOf(QID) != QuestionState.Resolved) return;

        ConditionalToken winner = VAULT.winnerOf(QID) == Outcome.Pass ? passToken : failToken;
        uint256 bal = winner.balanceOf(currentActor);
        if (bal == 0) return;

        uint256 got = VAULT.redeem(QID, address(TOKEN));
        ghostRedeemed += got;
        callsRedeem++;
    }

    /// @dev Conditional tokens are plain ERC-20s, so holders move them around.
    ///      Worth driving: accounting that only holds while balances stay where
    ///      they were minted is accounting that does not hold.
    function transferConditional(uint256 fromSeed, uint256 toSeed, uint256 amount, bool passSide)
        external
        useActor(fromSeed)
    {
        ConditionalToken t = passSide ? passToken : failToken;
        uint256 bal = t.balanceOf(currentActor);
        if (bal == 0) return;

        address to = actors[bound(toSeed, 0, actors.length - 1)];
        t.transfer(to, bound(amount, 1, bal));
        callsTransfer++;
    }

    /// @dev Resolution is one-way and ends splitting, so it is gated behind a
    ///      number of *successful splits* rather than an amount.
    ///
    ///      The first version gated on total volume, which a single split could
    ///      clear — so the fuzzer resolved almost immediately and the remaining
    ///      calls in the run all no-opped. The suite passed having exercised
    ///      four splits and one merge across sixteen thousand calls. Counting
    ///      actions instead keeps the open phase alive long enough to be worth
    ///      fuzzing, and the call summary is what exposed the difference.
    function resolve(bool passWins) external {
        if (resolved) return;
        if (callsSplit < 8) return;

        VAULT.resolve(QID, passWins ? Outcome.Pass : Outcome.Fail);
        resolved = true;
    }

    // ------------------------------------------------------------- helpers

    function sumBalances(ConditionalToken t) external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += t.balanceOf(actors[i]);
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
