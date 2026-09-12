// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ConditionalAmm} from "../../src/amm/ConditionalAmm.sol";
import {ConditionalToken} from "../../src/conditional/ConditionalToken.sol";
import {ConditionalVault} from "../../src/conditional/ConditionalVault.sol";
import {IConditionalVault, Outcome} from "../../src/interfaces/IConditionalVault.sol";
import {LaggedTwapOracle} from "../../src/oracle/LaggedTwapOracle.sol";
import {UniswapV2PriceSource} from "../../src/oracle/sources/UniswapV2PriceSource.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockV2Pair} from "../mocks/MockV2Pair.sol";

/// @notice Every defensive check, actually firing.
///
/// @dev These are individually dull and collectively the point. Branch coverage
///      sat at 63% — 33% on the vault — not because logic was untested but
///      because the *revert side* of nearly every guard had never executed. A
///      guard that has never fired is an assumption, not a defence: it might
///      have the comparison backwards, name the wrong error, or have been made
///      unreachable by an earlier check, and nothing would say so.
///
///      Each test here answers one question: when this input is wrong, does the
///      contract actually refuse?
contract GuardsTest is Test {
    ConditionalVault internal vault;
    ConditionalAmm internal amm;
    MockERC20 internal base;
    MockERC20 internal quote;

    address internal governor = makeAddr("governor");
    address internal alice = makeAddr("alice");

    bytes32 internal constant QID = keccak256("guards");
    bytes32 internal constant UNOPENED = keccak256("never-opened");

    function setUp() public {
        base = new MockERC20("Base", "BASE", 18);
        quote = new MockERC20("Quote", "QUOTE", 6);

        vault = new ConditionalVault(governor);
        vm.startPrank(governor);
        vault.openQuestion(QID);
        vault.registerUnderlying(QID, address(base), "BASE");
        vm.stopPrank();

        amm = new ConditionalAmm(address(base), address(quote), governor);

        base.mint(alice, 1_000_000e18);
        quote.mint(alice, 1_000_000e6);
        vm.startPrank(alice);
        base.approve(address(vault), type(uint256).max);
        base.approve(address(amm), type(uint256).max);
        quote.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    // ------------------------------------------------------- vault lifecycle

    function test_VaultRejectsAZeroGovernor() public {
        vm.expectRevert(IConditionalVault.ZeroAddress.selector);
        new ConditionalVault(address(0));
    }

    function test_AQuestionCannotBeOpenedTwice() public {
        vm.expectRevert(abi.encodeWithSelector(IConditionalVault.QuestionExists.selector, QID));
        vm.prank(governor);
        vault.openQuestion(QID);
    }

    function test_CannotRegisterAnUnderlyingOnAnUnopenedQuestion() public {
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalVault.QuestionNotOpen.selector, UNOPENED)
        );
        vm.prank(governor);
        vault.registerUnderlying(UNOPENED, address(base), "BASE");
    }

    function test_CannotRegisterTheZeroAddressAsAnUnderlying() public {
        vm.expectRevert(IConditionalVault.ZeroAddress.selector);
        vm.prank(governor);
        vault.registerUnderlying(QID, address(0), "X");
    }

    /// @dev Re-registering would mint a second, unrelated pair of claims against
    ///      the same collateral — two sets of tokens believing they own it.
    function test_AnUnderlyingCannotBeRegisteredTwice() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConditionalVault.UnderlyingAlreadyRegistered.selector, QID, address(base)
            )
        );
        vm.prank(governor);
        vault.registerUnderlying(QID, address(base), "BASE");
    }

    function test_AQuestionCannotBeResolvedTwice() public {
        vm.startPrank(governor);
        vault.resolve(QID, Outcome.Pass);
        vm.expectRevert(abi.encodeWithSelector(IConditionalVault.QuestionNotOpen.selector, QID));
        vault.resolve(QID, Outcome.Fail);
        vm.stopPrank();
    }

    // --------------------------------------------------------- vault amounts

    function test_SplittingNothingIsRefused() public {
        vm.expectRevert(IConditionalVault.ZeroAmount.selector);
        vm.prank(alice);
        vault.split(QID, address(base), 0);
    }

    function test_MergingNothingIsRefused() public {
        vm.expectRevert(IConditionalVault.ZeroAmount.selector);
        vm.prank(alice);
        vault.merge(QID, address(base), 0);
    }

    function test_CannotSplitAnUnregisteredUnderlying() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IConditionalVault.UnderlyingNotRegistered.selector, QID, address(quote)
            )
        );
        vm.prank(alice);
        vault.split(QID, address(quote), 1e6);
    }

    // ------------------------------------------------------- conditional token

    function test_OnlyTheVaultCanBurn() public {
        (address pass,) = vault.conditionalTokens(QID, address(base));
        vm.expectRevert(abi.encodeWithSelector(ConditionalToken.Unauthorized.selector, alice));
        vm.prank(alice);
        ConditionalToken(pass).burn(alice, 1);
    }

    function test_TransferringMoreThanHeldIsRefused() public {
        vm.prank(alice);
        vault.split(QID, address(base), 100e18);
        (address pass,) = vault.conditionalTokens(QID, address(base));

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalToken.InsufficientBalance.selector, alice, 100e18, 100e18 + 1
            )
        );
        vm.prank(alice);
        ConditionalToken(pass).transfer(makeAddr("bob"), 100e18 + 1);
    }

    /// @dev Sending to the zero address would burn without touching
    ///      `totalSupply`, quietly breaking the conservation law.
    function test_TransferringToTheZeroAddressIsRefused() public {
        vm.prank(alice);
        vault.split(QID, address(base), 1e18);
        (address pass,) = vault.conditionalTokens(QID, address(base));

        vm.expectRevert(ConditionalToken.ZeroAddress.selector);
        vm.prank(alice);
        ConditionalToken(pass).transfer(address(0), 1);
    }

    function test_SpendingMoreThanAllowedIsRefused() public {
        vm.prank(alice);
        vault.split(QID, address(base), 100e18);
        (address pass,) = vault.conditionalTokens(QID, address(base));

        address spender = makeAddr("spender");
        vm.prank(alice);
        ConditionalToken(pass).approve(spender, 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalToken.InsufficientAllowance.selector, spender, 10e18, 10e18 + 1
            )
        );
        vm.prank(spender);
        ConditionalToken(pass).transferFrom(alice, spender, 10e18 + 1);
    }

    // ------------------------------------------------------------------- amm

    function test_AmmRejectsADegenerateConstruction() public {
        vm.expectRevert(ConditionalAmm.ZeroAddress.selector);
        new ConditionalAmm(address(base), address(0), governor);

        vm.expectRevert(ConditionalAmm.ZeroAddress.selector);
        new ConditionalAmm(address(base), address(quote), address(0));
    }

    function test_TheOracleCannotBeSetToZero() public {
        vm.expectRevert(ConditionalAmm.ZeroAddress.selector);
        vm.prank(governor);
        amm.setOracle(address(0));
    }

    function test_AddingZeroLiquidityIsRefused() public {
        vm.startPrank(alice);
        vm.expectRevert(ConditionalAmm.ZeroAmount.selector);
        amm.addLiquidity(0, 1e6);
        vm.expectRevert(ConditionalAmm.ZeroAmount.selector);
        amm.addLiquidity(1e18, 0);
        vm.stopPrank();
    }

    /// @dev A first deposit so small it mints no more than the locked minimum
    ///      would leave the pool with reserves and effectively no owner.
    function test_AFirstDepositTooSmallToClearTheMinimumIsRefused() public {
        vm.expectRevert(ConditionalAmm.InsufficientLiquidity.selector);
        vm.prank(alice);
        amm.addLiquidity(1, 1);
    }

    function test_RemovingZeroOrMoreSharesThanHeldIsRefused() public {
        vm.startPrank(alice);
        amm.addLiquidity(1_000e18, 2_000e6);
        uint256 held = amm.sharesOf(alice);

        vm.expectRevert(ConditionalAmm.ZeroAmount.selector);
        amm.removeLiquidity(0);

        vm.expectRevert(
            abi.encodeWithSelector(ConditionalAmm.InsufficientShares.selector, held, held + 1)
        );
        amm.removeLiquidity(held + 1);
        vm.stopPrank();
    }

    function test_SwappingNothingIsRefused() public {
        vm.startPrank(alice);
        amm.addLiquidity(1_000e18, 2_000e6);
        vm.expectRevert(ConditionalAmm.ZeroAmount.selector);
        amm.swapExactBaseForQuote(0, 0);
        vm.expectRevert(ConditionalAmm.ZeroAmount.selector);
        amm.swapExactQuoteForBase(0, 0);
        vm.stopPrank();
    }

    /// @dev An input so small it rounds to zero output must revert rather than
    ///      silently take the tokens and return nothing.
    function test_ASwapTooSmallToReturnAnythingIsRefused() public {
        vm.startPrank(alice);
        amm.addLiquidity(1_000e18, 2_000e6);
        vm.expectRevert(ConditionalAmm.InsufficientLiquidity.selector);
        amm.swapExactBaseForQuote(1, 0); // 1 wei of an 18dp token against a 6dp quote
        vm.stopPrank();
    }

    function test_QuotingAnEmptyPoolReturnsZeroRatherThanReverting() public view {
        assertEq(amm.quoteSwap(true, 1e18), 0, "an empty pool should quote nothing");
    }

    function test_SkimmingToTheZeroAddressIsRefused() public {
        vm.expectRevert(ConditionalAmm.ZeroAddress.selector);
        vm.prank(governor);
        amm.skimSurplus(address(0));
    }

    // ---------------------------------------------------------------- oracle

    function test_TheOracleCannotStartTwiceOrAtZero() public {
        LaggedTwapOracle o = new LaggedTwapOracle(
            address(
                new UniswapV2PriceSource(
                    address(new MockV2Pair(address(base), address(quote))), address(base)
                )
            ),
            1e3,
            1 hours,
            5 minutes,
            1 days
        );

        vm.expectRevert(LaggedTwapOracle.InvalidConfig.selector);
        o.start(0);

        o.start(1e18);
        vm.expectRevert(LaggedTwapOracle.AlreadyStarted.selector);
        o.start(1e18);
    }

    function test_ReadingAnUnstartedOracleReverts() public {
        LaggedTwapOracle o = new LaggedTwapOracle(
            address(
                new UniswapV2PriceSource(
                    address(new MockV2Pair(address(base), address(quote))), address(base)
                )
            ),
            1e3,
            1 hours,
            5 minutes,
            1 days
        );
        vm.expectRevert(LaggedTwapOracle.NotStarted.selector);
        o.currentTwap();
    }

    // --------------------------------------------------------- v2 price source

    function test_TheV2SourceRejectsADegenerateConstruction() public {
        MockV2Pair pair = new MockV2Pair(address(base), address(quote));

        vm.expectRevert(UniswapV2PriceSource.ZeroAddress.selector);
        new UniswapV2PriceSource(address(0), address(base));

        vm.expectRevert(UniswapV2PriceSource.TokenNotInPair.selector);
        new UniswapV2PriceSource(address(pair), makeAddr("stranger"));
    }

    /// @dev An empty pair has no price to give. Returning zero rather than
    ///      reverting is what lets the oracle hold its observation instead of
    ///      stalling the crank.
    function test_TheV2SourceReportsNoPriceForAnEmptyPair() public {
        MockV2Pair pair = new MockV2Pair(address(base), address(quote));
        UniswapV2PriceSource src = new UniswapV2PriceSource(address(pair), address(base));
        assertEq(src.spotPrice(), 0);

        pair.setReserves(1_000e18, 2_000e6);
        assertEq(src.spotPrice(), 2e6, "a funded pair should price normally");
        assertEq(src.base(), address(base));
        assertEq(src.quote(), address(quote));
    }
}
