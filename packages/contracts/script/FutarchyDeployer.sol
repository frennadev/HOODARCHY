// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {FutarchyExecutor} from "../src/governance/FutarchyExecutor.sol";
import {FutarchyGovernor} from "../src/governance/FutarchyGovernor.sol";
import {MarketFactory} from "../src/governance/MarketFactory.sol";

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

interface ISafeDeploy {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);

    function enableModule(address module) external;
    function swapOwner(address prevOwner, address oldOwner, address newOwner) external;
    function isModuleEnabled(address module) external view returns (bool);
    function getOwners() external view returns (address[] memory);
}

/// @title FutarchyDeployer
/// @notice The wiring for one project: markets, governor, treasury, executor.
///
/// @dev Shared by the deploy script and by the fork test that rehearses it, so
///      the sequence which runs on a real chain is the sequence that was tested.
///      A deployment that only exists inside a script is a deployment nobody has
///      ever run until the day it matters.
///
///      **Ordering is the security-relevant part.** The treasury must end up
///      reachable only through the Executor, and there is a window during setup
///      where that is not yet true: a Safe needs a real owner to enable its first
///      module, because only the Safe itself may do so. The deployer therefore
///      holds the keys briefly and hands them to an address nobody controls as
///      the final step. `verify` exists to prove that step actually happened.
library FutarchyDeployer {
    struct Config {
        address safeSingleton;
        address safeProxyFactory;
        address baseToken;
        address quoteToken;
        address guardian;
        /// @dev Where ownership goes once the module is live. Must be an address
        ///      with no known key; the Safe is then module-only forever.
        address unheldOwner;
        uint256 baseToStake;
        uint256 maxChangePerSecond;
        uint64 delay;
        uint64 window;
        uint64 maxStepElapsed;
        uint256 saltNonce;
    }

    struct Deployment {
        address safe;
        address governor;
        address vault;
        address executor;
        address marketFactory;
    }

    /// @dev Sentinel that heads Safe's owner linked list.
    address internal constant SENTINEL_OWNERS = address(0x1);

    error ModuleNotEnabled();
    error OwnerNotHandedOver();
    error SafeTransactionFailed();

    /// @param deployer The address broadcasting; briefly the Safe's owner.
    function deploy(Config memory cfg, address deployer) internal returns (Deployment memory d) {
        MarketFactory marketFactory = new MarketFactory();

        FutarchyGovernor governor = new FutarchyGovernor(
            cfg.baseToken,
            cfg.quoteToken,
            address(marketFactory),
            cfg.guardian,
            cfg.baseToStake,
            cfg.maxChangePerSecond,
            cfg.delay,
            cfg.window,
            cfg.maxStepElapsed
        );

        // The Safe starts owned by the deployer, because only an owner can turn
        // on the first module. This is the one moment the treasury is not yet
        // market-controlled, and it is closed before this function returns.
        address[] memory owners = new address[](1);
        owners[0] = deployer;
        bytes memory initializer = abi.encodeCall(
            ISafeDeploy.setup,
            (owners, 1, address(0), "", address(0), address(0), 0, payable(address(0)))
        );
        ISafeDeploy safe = ISafeDeploy(
            ISafeProxyFactory(cfg.safeProxyFactory)
                .createProxyWithNonce(cfg.safeSingleton, initializer, cfg.saltNonce)
        );

        FutarchyExecutor executor = new FutarchyExecutor(address(safe), address(governor));

        _asOwner(safe, deployer, abi.encodeCall(ISafeDeploy.enableModule, (address(executor))));
        _asOwner(
            safe,
            deployer,
            abi.encodeCall(ISafeDeploy.swapOwner, (SENTINEL_OWNERS, deployer, cfg.unheldOwner))
        );

        d = Deployment({
            safe: address(safe),
            governor: address(governor),
            vault: address(governor.VAULT()),
            executor: address(executor),
            marketFactory: address(marketFactory)
        });

        verify(d, cfg.unheldOwner, deployer);
    }

    /// @dev Asserts the treasury ended up where it was supposed to. Deployment
    ///      scripts that do not check their own result are how a Safe stays
    ///      quietly owned by whoever ran them.
    function verify(Deployment memory d, address unheldOwner, address deployer) internal view {
        ISafeDeploy safe = ISafeDeploy(d.safe);

        if (!safe.isModuleEnabled(d.executor)) revert ModuleNotEnabled();

        address[] memory owners = safe.getOwners();
        if (owners.length != 1 || owners[0] != unheldOwner || owners[0] == deployer) {
            revert OwnerNotHandedOver();
        }
    }

    /// @dev Safe accepts a "pre-approved hash" signature from an owner calling in
    ///      directly: v = 1, r = the owner, s = 0. That avoids needing a real
    ///      ECDSA signature during deployment, which a script cannot produce
    ///      without handling the key itself.
    function _asOwner(ISafeDeploy safe, address owner, bytes memory data) private {
        bytes memory sig = abi.encodePacked(bytes32(uint256(uint160(owner))), bytes32(0), uint8(1));
        bool ok = safe.execTransaction(
            address(safe), 0, data, 0, 0, 0, 0, address(0), payable(address(0)), sig
        );
        if (!ok) revert SafeTransactionFailed();
    }
}
