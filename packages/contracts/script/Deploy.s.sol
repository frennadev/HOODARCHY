// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {RobinhoodChain} from "../src/config/RobinhoodChain.sol";
import {FutarchyDeployer} from "./FutarchyDeployer.sol";

/// @notice A throwaway project token, for a testnet where no real one exists.
contract TestToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory n, string memory s, uint8 d, uint256 supply, address to) {
        name = n;
        symbol = s;
        decimals = d;
        totalSupply = supply;
        balanceOf[to] = supply;
        emit Transfer(address(0), to, supply);
    }

    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        emit Transfer(msg.sender, to, v);
        return true;
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        emit Approval(msg.sender, s, v);
        return true;
    }

    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        uint256 a = allowance[f][msg.sender];
        if (a != type(uint256).max) allowance[f][msg.sender] = a - v;
        balanceOf[f] -= v;
        balanceOf[t] += v;
        emit Transfer(f, t, v);
        return true;
    }
}

/// @title Deploy
/// @notice Stands up one futarchy-governed project.
///
/// @dev Rehearsed by `test/fork/Deployment.t.sol`, which runs this exact
///      sequence against a real Safe and then drives a proposal through it. The
///      wiring lives in `FutarchyDeployer` precisely so the tested path and the
///      broadcast path cannot drift apart.
///
///      Usage:
///        forge script script/Deploy.s.sol:Deploy \
///          --rpc-url $RH_TESTNET_RPC_URL --broadcast
///
///      Requires PRIVATE_KEY. On testnet it also deploys a throwaway project
///      token; on a real deployment set PROJECT_TOKEN and QUOTE_TOKEN instead.
contract Deploy is Script {
    /// @dev Canonical parameters, §7. Not settable after deployment (D22).
    uint64 internal constant DELAY = 24 hours;
    uint64 internal constant WINDOW = 72 hours;
    uint64 internal constant MAX_STEP_ELAPSED = 5 minutes;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // An address with no known key. The treasury is module-only once
        // ownership lands here, which is the point of the whole exercise (D10).
        address unheldOwner = vm.envOr("UNHELD_OWNER", address(0xdead));
        address guardian = vm.envOr("GUARDIAN", address(0));

        console2.log("chain id  ", block.chainid);
        console2.log("deployer  ", deployer);
        console2.log("balance   ", deployer.balance);
        require(deployer.balance > 0, "deployer has no gas; fund it first");

        vm.startBroadcast(pk);

        address quote = vm.envOr("QUOTE_TOKEN", address(0));
        address base = vm.envOr("PROJECT_TOKEN", address(0));

        if (quote == address(0)) {
            quote = block.chainid == RobinhoodChain.TESTNET_CHAIN_ID
                ? 0x58157811a8646424ca9633394a9985F44a92C58B  // testnet USDG
                : RobinhoodChain.USDG;
        }
        if (base == address(0)) {
            base = address(new TestToken("Futarchy Test", "FTT", 18, 10_000_000e18, deployer));
            console2.log("project token (new)", base);
        }

        FutarchyDeployer.Config memory cfg = FutarchyDeployer.Config({
            safeSingleton: RobinhoodChain.SAFE_SINGLETON_L2,
            safeProxyFactory: RobinhoodChain.SAFE_PROXY_FACTORY,
            baseToken: base,
            quoteToken: quote,
            guardian: guardian,
            unheldOwner: unheldOwner,
            baseToStake: vm.envOr("BASE_TO_STAKE", uint256(200_000e18)),
            // Sized so doubling the observation needs ~35 minutes of unbroken
            // pressure (D8). Scaled to the quote's decimals at the opening price.
            maxChangePerSecond: vm.envOr("MAX_CHANGE_PER_SECOND", uint256(1e6) / 2100),
            delay: DELAY,
            window: WINDOW,
            maxStepElapsed: MAX_STEP_ELAPSED,
            saltNonce: vm.envOr("SALT_NONCE", block.timestamp)
        });

        FutarchyDeployer.Deployment memory d = FutarchyDeployer.deploy(cfg, deployer);

        vm.stopBroadcast();

        console2.log("--- deployed ---");
        console2.log("safe          ", d.safe);
        console2.log("governor      ", d.governor);
        console2.log("vault         ", d.vault);
        console2.log("executor      ", d.executor);
        console2.log("marketFactory ", d.marketFactory);
        console2.log("quote token   ", quote);
        console2.log("project token ", base);
        console2.log("--- treasury owner is now ---");
        console2.log("unheld owner  ", unheldOwner);
    }
}
