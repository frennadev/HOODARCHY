// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ConditionalToken} from "../../src/conditional/ConditionalToken.sol";
import {ConditionalVault} from "../../src/conditional/ConditionalVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ConditionalVaultHandler} from "./ConditionalVaultHandler.sol";

/// @notice The conservation law during the phase that actually lasts.
///
/// @dev Resolution is deliberately excluded from the fuzzed selectors here.
///      A question is open for days and resolved for an instant, so a suite that
///      lets the fuzzer resolve early spends most of its budget on a state where
///      almost every action is a no-op — which is what the first version of this
///      did, exercising four splits across sixteen thousand calls.
///
///      Keeping this run permanently open means every one of those calls lands
///      on live split / merge / transfer paths. The sibling suite covers
///      resolution and redemption.
contract ConditionalVaultOpenPhaseInvariantTest is Test {
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

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = ConditionalVaultHandler.split.selector;
        selectors[1] = ConditionalVaultHandler.merge.selector;
        selectors[2] = ConditionalVaultHandler.transferConditional.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice `underlying held == PASS supply == FAIL supply`, after every call.
    function invariant_openPhaseConservation() public view {
        uint256 locked = vault.lockedOf(qid, address(token));

        assertEq(token.balanceOf(address(vault)), locked, "held != ledger");
        assertEq(handler.passToken().totalSupply(), locked, "PASS supply != underlying");
        assertEq(handler.failToken().totalSupply(), locked, "FAIL supply != underlying");
    }

    /// @notice A complete set is always worth exactly one underlying — so the two
    ///         supplies can never drift apart, whoever traded what.
    function invariant_theTwoSidesStayMatched() public view {
        assertEq(
            handler.passToken().totalSupply(),
            handler.failToken().totalSupply(),
            "PASS and FAIL supplies diverged"
        );
    }

    /// @notice Moving conditional tokens between holders changes nothing about
    ///         what the vault owes. Accounting that only survives tokens sitting
    ///         where they were minted is not accounting.
    function invariant_transfersDoNotAffectTheLedger() public view {
        ConditionalToken pass = handler.passToken();
        ConditionalToken fail = handler.failToken();

        assertEq(handler.sumBalances(pass), pass.totalSupply(), "PASS balances != supply");
        assertEq(handler.sumBalances(fail), fail.totalSupply(), "FAIL balances != supply");
    }

    function invariant_ledgerMatchesGhosts() public view {
        assertEq(
            vault.lockedOf(qid, address(token)),
            handler.ghostSplit() - handler.ghostMerged(),
            "ledger drifted from split - merged"
        );
    }

    /// @dev Proves the run did work. A green invariant suite that no-opped is
    ///      indistinguishable from a real one without this.
    function invariant_openPhaseCallSummary() public view {
        console2.log("split    ", handler.callsSplit());
        console2.log("merge    ", handler.callsMerge());
        console2.log("transfer ", handler.callsTransfer());
        assertFalse(handler.resolved(), "resolution should be unreachable in this suite");
    }
}
