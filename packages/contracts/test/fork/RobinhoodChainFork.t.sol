// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {BaseTest} from "../BaseTest.sol";
import {RobinhoodChain} from "@capdao/config/RobinhoodChain.sol";
import {UniswapV4PriceSource} from "@capdao/oracle/sources/UniswapV4PriceSource.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/// @notice Environment smoke test.
///
/// This asserts nothing about Capital DAO's own logic — it exists to prove the
/// toolchain, RPC, remappings, and address constants are all wired correctly,
/// and to fail loudly the day one of our assumptions about the chain stops
/// being true (a token gets redeployed, a decimals value changes, a DEX we
/// depend on moves).
///
/// Run:
///   forge test --match-path 'test/fork/*' -vv
///
/// Requires RH_MAINNET_RPC_URL. The public RPC works but is rate limited; use
/// an Alchemy key if these start flaking.
contract RobinhoodChainForkTest is BaseTest {
    uint256 internal fork;

    /// @dev Pinned by default now that an archive RPC is configured; see
    ///      `BaseTest._forkMainnet`. Run `pnpm test:fork:drift` to check the same
    ///      assumptions against the live chain.
    function setUp() public {
        fork = _forkMainnet();
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
        address[9] memory required = [
            RobinhoodChain.WETH,
            RobinhoodChain.USDG,
            RobinhoodChain.PERMIT2,
            RobinhoodChain.MULTICALL3,
            RobinhoodChain.UNIV3_FACTORY,
            RobinhoodChain.UNIV3_SWAP_ROUTER_02,
            RobinhoodChain.UNIV3_POSITION_MANAGER,
            RobinhoodChain.UNIV4_POOL_MANAGER,
            RobinhoodChain.UNIV4_POSITION_MANAGER
        ];

        for (uint256 i = 0; i < required.length; i++) {
            assertGt(required[i].code.length, 0, "dependency has no code");
        }
    }

    /// @dev This test replaces one that asserted v4 was *absent* by checking the
    ///      canonical PoolManager address. That address is still empty, so the
    ///      old test passed happily while its conclusion was false: v4 deploys to
    ///      a different address on every chain, so absence at an address we
    ///      happen to know proves nothing. A test that can only confirm what we
    ///      already believe is worse than no test.
    ///
    ///      Codesize alone is also not enough — any contract has code. What makes
    ///      this a real v4 deployment is that the two halves point at each other.
    function test_uniswapV4IsLiveAndInternallyConsistent() public view {
        assertEq(
            IUniV4PositionManager(RobinhoodChain.UNIV4_POSITION_MANAGER).poolManager(),
            RobinhoodChain.UNIV4_POOL_MANAGER,
            "PositionManager does not point at our PoolManager - addresses are not a matched pair"
        );

        // Ties the v4 deployment to constants we verified independently.
        assertEq(
            IUniV4PositionManager(RobinhoodChain.UNIV4_POSITION_MANAGER).permit2(),
            RobinhoodChain.PERMIT2,
            "v4 PositionManager wired to an unexpected Permit2"
        );
        assertEq(
            IUniV4PositionManager(RobinhoodChain.UNIV4_POSITION_MANAGER).WETH9(),
            RobinhoodChain.WETH,
            "v4 PositionManager wired to an unexpected WETH"
        );
    }

    /// @dev The UniversalRouter we verified in July is v4-capable and points at
    ///      the same PoolManager. The evidence that v4 existed was in our own
    ///      address list the whole time; nobody asked the router what it was
    ///      wired to. Kept as a test so the link is never dropped again.
    function test_universalRouterIsWiredToV4() public view {
        assertEq(
            IUniV4PositionManager(RobinhoodChain.UNIV3_UNIVERSAL_ROUTER).poolManager(),
            RobinhoodChain.UNIV4_POOL_MANAGER,
            "UniversalRouter no longer routes to the v4 PoolManager"
        );
    }

    /// @dev All v4 pools share one singleton, so its balances are the entire v4
    ///      TVL on this chain. Asserted loosely — the point is "this is a real,
    ///      used venue", not an exact figure that would rot within a day.
    function test_uniswapV4HoldsRealLiquidity() public view {
        uint256 usdg =
            IERC20Metadata(RobinhoodChain.USDG).balanceOf(RobinhoodChain.UNIV4_POOL_MANAGER);
        assertGt(usdg, 1_000_000e6, "v4 singleton holds less USDG than expected for a live venue");
    }

    /// @dev The one that actually matters. `UniswapV4PriceSource` derives a
    ///      pool's storage slot from an assumed `PoolManager` layout and reads it
    ///      raw. Unit tests prove the arithmetic against a mock that encodes the
    ///      same assumption, so only this test can catch the assumption itself
    ///      being wrong. If the deployed PoolManager ever changes layout, this
    ///      fails and the mock keeps passing — which is the point.
    function test_v4PriceSourceReadsTheRealEthUsdgPool() public {
        UniswapV4PriceSource src = new UniswapV4PriceSource(
            RobinhoodChain.UNIV4_POOL_MANAGER,
            address(0), // native ETH sorts first
            RobinhoodChain.USDG,
            500,
            10,
            address(0), // no hooks
            address(0) // price ETH, in USDG
        );

        // Derivation must land on the pool we located by scanning the chain.
        assertEq(
            src.POOL_ID(),
            0x387bf619da4d3fb62bb276482693dba1b9b3520f573cabdfe033384a24125982,
            "pool id derivation drifted from the live pool"
        );

        // USDG is 6dp, so this reads directly as dollars per ETH. Banded wide:
        // the assertion is "the decimal scaling is right", not a market call.
        uint256 price = src.spotPrice();
        assertGt(price, 500e6, "ETH price implausibly low - decimal scaling suspect");
        assertLt(price, 20_000e6, "ETH price implausibly high - decimal scaling suspect");
    }

    /// @dev A real, initialised, permanently empty pool on this chain, parked at
    ///      the maximum representable price. It is the live proof that reading
    ///      slot0 without checking liquidity would feed the oracle a fiction.
    function test_v4PriceSourceRefusesTheEmptyWethUsdgPool() public {
        UniswapV4PriceSource src = new UniswapV4PriceSource(
            RobinhoodChain.UNIV4_POOL_MANAGER,
            RobinhoodChain.WETH,
            RobinhoodChain.USDG,
            100,
            1,
            address(0),
            RobinhoodChain.WETH
        );

        assertEq(
            src.POOL_ID(),
            0x35d5055f7162c8e8e1742f0559f53376287e998c0e4845ffefd275d85cc1701a,
            "pool id derivation drifted"
        );
        assertEq(src.spotPrice(), 0, "reported a price for a pool with no liquidity");
    }
}

/// @dev Minimal shape of the v4 PositionManager / UniversalRouter accessors we
///      use to prove the deployment is coherent. Declared locally because the
///      v4-periphery submodule is not vendored.
interface IUniV4PositionManager {
    function poolManager() external view returns (address);
    function permit2() external view returns (address);
    function WETH9() external view returns (address);
}
