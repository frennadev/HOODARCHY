// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ConditionalToken} from "../../src/conditional/ConditionalToken.sol";
import {ConditionalVault} from "../../src/conditional/ConditionalVault.sol";
import {Outcome, QuestionState} from "../../src/interfaces/IConditionalVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ConditionalVaultHandler} from "./ConditionalVaultHandler.sol";

/// @notice The conservation law, against sequences nobody wrote.
///
/// @dev §8 of the spec lists invariant tests for split/merge/redeem as build
///      order step 1. They were skipped, and the unit tests that replaced them
///      prove the law holds for the orderings a human thought to type. This
///      proves it holds for orderings nobody did.
///
///      The distinction matters more than it sounds. A fuzz test varies the
///      arguments to one call. An invariant test varies the *sequence* — split,
///      transfer, merge, transfer, split, resolve, redeem, redeem — across five
///      actors, and checks the property after every single step.
contract ConditionalVaultInvariantTest is Test {
    ConditionalVaultHandler internal handler;
    ConditionalVault internal vault;
    MockERC20 internal token;

    bytes32 internal qid;

    function setUp() public {
        token = new MockERC20("Underlying", "TKN", 18);
        handler = new ConditionalVaultHandler(token);
        vault = handler.VAULT();
        qid = handler.QID();

        targetContract(address(handler));
    }

    /// @notice The whole reason the vault exists: every token it holds is backed
    ///         by exactly the claims it issued, and vice versa.
    ///
    /// @dev While the question is open, all three move together. After
    ///      resolution they deliberately separate — redeeming burns the winning
    ///      claim and releases the underlying together, while the losing claim is
    ///      abandoned rather than burned, because it is worth nothing and forcing
    ///      holders to burn it would strand anyone who only holds that side.
    function invariant_underlyingAlwaysBacksTheClaims() public view {
        uint256 held = token.balanceOf(address(vault));
        uint256 locked = vault.lockedOf(qid, address(token));

        assertEq(held, locked, "vault holds a different amount than its ledger says");

        ConditionalToken pass = handler.passToken();
        ConditionalToken fail = handler.failToken();

        if (vault.stateOf(qid) == QuestionState.Open) {
            assertEq(pass.totalSupply(), locked, "PASS supply diverged from the underlying");
            assertEq(fail.totalSupply(), locked, "FAIL supply diverged from the underlying");
        } else {
            ConditionalToken winner = vault.winnerOf(qid) == Outcome.Pass ? pass : fail;
            ConditionalToken loser = vault.winnerOf(qid) == Outcome.Pass ? fail : pass;

            // Redeem burns the winner and releases underlying in lockstep.
            assertEq(
                winner.totalSupply(), locked, "winning supply no longer matches the underlying"
            );
            // The loser is frozen at whatever it was, and is never worth less
            // than the remaining underlying — it simply stops being redeemable.
            assertGe(loser.totalSupply(), locked, "losing supply fell below the underlying");
        }
    }

    /// @notice No claim exists that somebody does not hold.
    /// @dev Catches a mint or burn that updates `totalSupply` without moving a
    ///      balance — the classic way conservation quietly breaks.
    function invariant_everyClaimIsHeldBySomebody() public view {
        ConditionalToken pass = handler.passToken();
        ConditionalToken fail = handler.failToken();

        assertEq(
            handler.sumBalances(pass), pass.totalSupply(), "PASS balances do not sum to supply"
        );
        assertEq(
            handler.sumBalances(fail), fail.totalSupply(), "FAIL balances do not sum to supply"
        );
    }

    /// @notice The ledger equals what actually happened, tracked independently.
    /// @dev The handler counts deposits and withdrawals as it makes them, from
    ///      outside the vault. If the vault's own arithmetic drifts from that
    ///      running total, the two disagree here.
    function invariant_ledgerMatchesTheGhostAccounting() public view {
        uint256 expected = handler.ghostSplit() - handler.ghostMerged() - handler.ghostRedeemed();
        assertEq(
            vault.lockedOf(qid, address(token)),
            expected,
            "vault ledger drifted from split - merged - redeemed"
        );
    }

    /// @notice Nobody can take out more than went in.
    function invariant_withdrawalsNeverExceedDeposits() public view {
        assertLe(
            handler.ghostMerged() + handler.ghostRedeemed(),
            handler.ghostSplit(),
            "more underlying left the vault than entered it"
        );
    }

    /// @dev Prints what the run actually exercised. An invariant suite that
    ///      passes because every call no-opped is worthless, and this is how you
    ///      notice that rather than trusting a green tick.
    function invariant_callSummary() public view {
        console2.log("split     ", handler.callsSplit());
        console2.log("merge     ", handler.callsMerge());
        console2.log("redeem    ", handler.callsRedeem());
        console2.log("transfer  ", handler.callsTransfer());
        console2.log("resolved  ", handler.resolved());
    }
}
