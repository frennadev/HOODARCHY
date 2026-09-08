// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {BaseTest} from "../BaseTest.sol";
import {RobinhoodChain} from "@capdao/config/RobinhoodChain.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/// @notice Environment smoke test.
///
/// This asserts nothing about Capital DAO's own logic — it exists to prove the
/// toolchain, RPC, remappings, and address constants are all wired correctly,
/// and to fail loudly the day one of our assumptions about the chain stops
/// being true (a token gets redeployed, a decimals value changes, v4 lands).
///
/// Run:
///   forge test --match-path 'test/fork/*' -vv
///
/// Requires RH_MAINNET_RPC_URL. The public RPC works but is rate limited; use
/// an Alchemy key if these start flaking.
contract RobinhoodChainForkTest is BaseTest {
    uint256 internal fork;

    /// @dev The public RPC is NOT an archive node. Measured 2026-07-26: state at
    ///      ~20k blocks back still resolves, state at ~100k back returns
    ///      `metadata is not found`. So we cannot pin a fixed historical block
    ///      here the way you normally would — it silently rots within days.
    ///
    ///      Default: fork at latest. Set FORK_BLOCK to pin, which is what you
    ///      should do once an archive provider (Alchemy) is configured, because
    ///      unpinned forks make tests depend on state that moves under you.
    function setUp() public {
        string memory rpc = vm.envString("RH_MAINNET_RPC_URL");
        uint256 pinned = vm.envOr("FORK_BLOCK", uint256(0));

        fork = pinned == 0 ? vm.createSelectFork(rpc) : vm.createSelectFork(rpc, pinned);
    }

    function test_forkIsRobinhoodChain() public view {
        assertEq(block.chainid, RobinhoodChain.CHAIN_ID, "wrong chain");
        assertEq(vm.activeFork(), fork, "fork not selected");
    }

    /// @dev USDG being 6 decimals is load-bearing for every price and treasury
    ///      calculation we will write. Pin it in a test so nobody "fixes" a
    ///      scaling factor later by assuming 18.
    function test_usdgIsSixDecimals() public view {
        IERC20Metadata t = IERC20Metadata(RobinhoodChain.USDG);
        assertEq(t.decimals(), 6, "USDG decimals changed");
        assertEq(t.symbol(), "USDG", "USDG symbol changed");
        assertEq(t.decimals(), RobinhoodChain.USDG_DECIMALS, "constant out of sync");
    }

    function test_wethIsEighteenDecimals() public view {
        IERC20Metadata t = IERC20Metadata(RobinhoodChain.WETH);
        assertEq(t.decimals(), 18, "WETH decimals changed");
        assertEq(t.symbol(), "WETH", "WETH symbol changed");
    }

    /// @dev Confirms the v3 factory is real and behaves like a v3 factory.
    function test_uniswapV3FactoryIsLive() public view {
        IUniswapV3Factory factory = IUniswapV3Factory(RobinhoodChain.UNIV3_FACTORY);
        assertEq(factory.feeAmountTickSpacing(RobinhoodChain.FEE_MEDIUM), 60, "0.30% spacing");
        assertEq(factory.feeAmountTickSpacing(RobinhoodChain.FEE_LOW), 10, "0.05% spacing");
        assertEq(factory.feeAmountTickSpacing(RobinhoodChain.FEE_HIGH), 200, "1.00% spacing");
    }

    /// @dev Every address we depend on must actually hold bytecode.
    function test_coreAddressesHaveCode() public view {
        address[7] memory required = [
            RobinhoodChain.WETH,
            RobinhoodChain.USDG,
            RobinhoodChain.PERMIT2,
            RobinhoodChain.MULTICALL3,
            RobinhoodChain.UNIV3_FACTORY,
            RobinhoodChain.UNIV3_SWAP_ROUTER_02,
            RobinhoodChain.UNIV3_POSITION_MANAGER
        ];

        for (uint256 i = 0; i < required.length; i++) {
            assertGt(required[i].code.length, 0, "dependency has no code");
        }
    }

    /// @dev We deliberately record that v4 is absent. When this test starts
    ///      failing, Uniswap v4 has been deployed and the conditional-pool
    ///      design can move to hooks. That is a feature, not a broken test.
    function test_uniswapV4StillNotDeployedAtCanonicalAddresses() public view {
        assertEq(
            address(0x000000000004444c5dc75cB358380D2e3dE08A90).code.length,
            0,
            "Uniswap v4 PoolManager may now exist - update addresses.ts and revisit the AMM design"
        );
    }
}
