// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {BaseTest} from "../BaseTest.sol";
import {RobinhoodChain} from "@hoodarchy/config/RobinhoodChain.sol";

/// @dev The slice of the V4 singleton this scenario needs.
interface IV4PoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function unlock(bytes calldata data) external returns (bytes memory);
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256 delta);
    function extsload(bytes32 slot) external view returns (bytes32);
}

/// @notice Stands in for the seeder. V4 only lets you touch a pool from inside
///         an `unlock` callback, so any correction has to happen in here.
contract SeedingHarness {
    IV4PoolManager public immutable PM;

    error NotManager();

    constructor(address pm) {
        PM = IV4PoolManager(pm);
    }

    /// @notice Drags a pool to `target`, whatever price it was left at.
    function resetPrice(IV4PoolManager.PoolKey calldata key, uint160 target, uint160 current)
        external
    {
        PM.unlock(abi.encode(key, target, current));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(PM)) revert NotManager();
        (IV4PoolManager.PoolKey memory key, uint160 target, uint160 current) =
            abi.decode(data, (IV4PoolManager.PoolKey, uint160, uint160));

        // Push toward the target and stop there. With no liquidity in the pool
        // there is nothing to trade against, so the swap should move the price
        // and move no tokens — which is the whole point.
        bool zeroForOne = target < current;
        PM.swap(
            key,
            IV4PoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -1e18, // exact input; never actually consumed
                sqrtPriceLimitX96: target
            }),
            ""
        );
        return "";
    }
}

/// @notice Can somebody brick every proposal on the platform for the price of
///         gas, the way three cents bricked a Capital DAO raise (audit H-1)?
///
///         V4 pool keys are derived from token addresses, and our conditional
///         token addresses are deliberately predictable (D13). `initialize` is
///         permissionless, needs no tokens, and refuses to run twice. So an
///         attacker can stake out a proposal's pool before it exists and pin it
///         at a nonsense price.
///
///         D7 says the answer is always to absorb the interference, never to
///         reject it. This works out what absorbing looks like on V4.
contract V4SeedingDefenceTest is BaseTest {
    IV4PoolManager internal pm;
    SeedingHarness internal harness;

    uint256 internal constant POOLS_SLOT = 6;
    uint160 internal constant SQRT_ONE = uint160(1) << 96; // price 1.0

    // Two sorted addresses standing in for a proposal's PASS conditional pair.
    // Deliberately code-free: the attack lands before the tokens are deployed.
    address internal constant P_TOKEN = address(0x1111111111111111111111111111111111111111);
    address internal constant P_USDG = address(0x2222222222222222222222222222222222222222);

    function setUp() public {
        _forkMainnet();
        pm = IV4PoolManager(RobinhoodChain.UNIV4_POOL_MANAGER);
        harness = new SeedingHarness(address(pm));
    }

    function _key() internal pure returns (IV4PoolManager.PoolKey memory) {
        return IV4PoolManager.PoolKey({
            currency0: P_TOKEN, currency1: P_USDG, fee: 3000, tickSpacing: 60, hooks: address(0)
        });
    }

    function _sqrtPrice(IV4PoolManager.PoolKey memory key) internal view returns (uint160) {
        bytes32 poolId = keccak256(
            abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks)
        );
        bytes32 stateSlot = keccak256(abi.encode(poolId, POOLS_SLOT));
        return uint160(uint256(pm.extsload(stateSlot)));
    }

    /// @dev The attack, start to finish.
    function test_ATTACK_AnyoneCanStakeOutAProposalsPoolBeforeItExists() public {
        IV4PoolManager.PoolKey memory key = _key();
        uint160 absurd = SQRT_ONE * 1000; // price is off by a factor of a million

        // Attacker, holding no tokens, paying only gas.
        vm.prank(address(0xBAD));
        pm.initialize(key, absurd);
        assertEq(_sqrtPrice(key), absurd, "attacker failed to pin the price");

        // The seeder now cannot create its own pool. On V2 this is where the
        // proposal dies permanently.
        vm.expectRevert(bytes4(0x7983c051)); // PoolAlreadyInitialized()
        pm.initialize(key, SQRT_ONE);
    }

    /// @dev The defence. An empty pool has nothing to trade against, so pushing
    ///      the price costs nothing and moves no tokens — the seeder can simply
    ///      take the price back and carry on.
    function test_DEFENCE_SeederAbsorbsThePreInitialisationForFree() public {
        IV4PoolManager.PoolKey memory key = _key();
        uint160 absurd = SQRT_ONE * 1000;

        vm.prank(address(0xBAD));
        pm.initialize(key, absurd);

        harness.resetPrice(key, SQRT_ONE, absurd);

        assertEq(_sqrtPrice(key), SQRT_ONE, "seeder could not reclaim the price");
    }

    /// @dev Works in the other direction too — an attacker pinning the price
    ///      absurdly *low* is the same problem mirrored.
    function test_DEFENCE_WorksWhenTheAttackerPinsThePriceLow() public {
        IV4PoolManager.PoolKey memory key = _key();
        uint160 tiny = SQRT_ONE / 1000;

        vm.prank(address(0xBAD));
        pm.initialize(key, tiny);

        harness.resetPrice(key, SQRT_ONE, tiny);

        assertEq(_sqrtPrice(key), SQRT_ONE, "seeder could not reclaim the price");
    }

    /// @dev And the ordinary path still works: an untouched pool initialises at
    ///      the intended price with no correction needed.
    function test_UncontestedPoolInitialisesNormally() public {
        IV4PoolManager.PoolKey memory key = _key();
        key.fee = 500; // a pool nobody has touched
        key.tickSpacing = 10;

        pm.initialize(key, SQRT_ONE);
        assertEq(_sqrtPrice(key), SQRT_ONE);
    }
}
