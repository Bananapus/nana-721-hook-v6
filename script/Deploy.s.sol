// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CoreDeployment, CoreDeploymentLib} from "@bananapus/core-v6/script/helpers/CoreDeploymentLib.sol";
import {
    AddressRegistryDeployment,
    AddressRegistryDeploymentLib
} from "@bananapus/address-registry-v6/script/helpers/AddressRegistryDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {JB721CheckpointsDeployer} from "../src/JB721CheckpointsDeployer.sol";
import {IJB721CheckpointsDeployer} from "../src/interfaces/IJB721CheckpointsDeployer.sol";
import {JB721TiersHookDeployer} from "../src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "../src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "../src/JB721TiersHookStore.sol";
import {JB721TiersHook} from "../src/JB721TiersHook.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the address registry for the chain we are deploying to.
    AddressRegistryDeployment registry;

    /// @notice The address that is allowed to forward calls to the terminal and controller on a users behalf.
    address private trustedForwarder;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 private constant _HOOK_SALT = "JB721TiersHookV6_";
    bytes32 private constant _HOOK_DEPLOYER_SALT = "JB721TiersHookDeployerV6_";
    bytes32 private constant _HOOK_STORE_SALT = "JB721TiersHookStoreV6_";
    bytes32 private constant _PROJECT_DEPLOYER_SALT = "JB721TiersHookProjectDeployerV6";
    bytes32 private constant _CHECKPOINTS_DEPLOYER_SALT = "JB721CheckpointsDeployerV6";

    function configureSphinx() public override {
        sphinxConfig.projectName = "nana-721-hook-v6";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core-v6/deployments/"))
        );

        // We use the same trusted forwarder as the core deployment.
        trustedForwarder = core.permissions.trustedForwarder();

        registry = AddressRegistryDeploymentLib.getDeployment(
            vm.envOr(
                "NANA_ADDRESS_REGISTRY_DEPLOYMENT_PATH",
                string("node_modules/@bananapus/address-registry-v6/deployments/")
            )
        );
        // Perform the deployment transactions.
        deploy();
    }

    /// @notice each contract here will be deployed it if needs to be (re)deployed.
    /// It will deploy if the contracts bytecode changes or if any constructor arguments change.
    /// Since all the contract dependencies are passed in using the constructor args,
    // this makes it so that if any dependency contract (address) changes the contract will be redeployed.
    function deploy() public sphinx {
        JB721TiersHookStore store;
        {
            // Perform the check for the store.
            (address _store, bool _storeIsDeployed) = _isDeployed({
                salt: _HOOK_STORE_SALT, creationCode: type(JB721TiersHookStore).creationCode, arguments: ""
            });

            // Deploy it if it has not been deployed yet.
            store = !_storeIsDeployed ? new JB721TiersHookStore{salt: _HOOK_STORE_SALT}() : JB721TiersHookStore(_store);
        }

        JB721CheckpointsDeployer checkpointsDeployer;
        {
            // Perform the check for the deployer.
            (address _deployer, bool _deployerIsDeployed) = _isDeployed({
                salt: _CHECKPOINTS_DEPLOYER_SALT,
                creationCode: type(JB721CheckpointsDeployer).creationCode,
                arguments: abi.encode(store)
            });

            // Deploy it if it has not been deployed yet.
            checkpointsDeployer = !_deployerIsDeployed
                ? new JB721CheckpointsDeployer{salt: _CHECKPOINTS_DEPLOYER_SALT}(store)
                : JB721CheckpointsDeployer(_deployer);
        }

        JB721TiersHook hook;
        {
            // Perform the check for the registry.
            (address _hook, bool _hookIsDeployed) = _isDeployed({
                salt: _HOOK_SALT,
                creationCode: type(JB721TiersHook).creationCode,
                arguments: abi.encode(
                    core.directory,
                    core.permissions,
                    core.prices,
                    core.rulesets,
                    store,
                    core.splits,
                    checkpointsDeployer,
                    trustedForwarder
                )
            });

            // Deploy it if it has not been deployed yet.
            hook = !_hookIsDeployed
                ? new JB721TiersHook{salt: _HOOK_SALT}({
                    directory: core.directory,
                    permissions: core.permissions,
                    prices: core.prices,
                    rulesets: core.rulesets,
                    store: store,
                    splits: core.splits,
                    checkpointsDeployer: IJB721CheckpointsDeployer(address(checkpointsDeployer)),
                    trustedForwarder: trustedForwarder
                })
                : JB721TiersHook(_hook);
        }

        JB721TiersHookDeployer hookDeployer;
        {
            // Perform the check for the registry.
            (address _hookDeployer, bool _hookDeployerIsDeployed) = _isDeployed({
                salt: _HOOK_DEPLOYER_SALT,
                creationCode: type(JB721TiersHookDeployer).creationCode,
                arguments: abi.encode(hook, store, registry.registry, trustedForwarder)
            });

            hookDeployer = !_hookDeployerIsDeployed
                ? new JB721TiersHookDeployer{salt: _HOOK_DEPLOYER_SALT}({
                    hook: hook, store: store, addressRegistry: registry.registry, trustedForwarder: trustedForwarder
                })
                : JB721TiersHookDeployer(_hookDeployer);
        }

        JB721TiersHookProjectDeployer projectDeployer;
        {
            // Perform the check for the registry.
            (address _projectDeployer, bool _projectDeployerIsdeployed) = _isDeployed({
                salt: _PROJECT_DEPLOYER_SALT,
                creationCode: type(JB721TiersHookProjectDeployer).creationCode,
                arguments: abi.encode(core.directory, core.permissions, hookDeployer, trustedForwarder)
            });

            projectDeployer = !_projectDeployerIsdeployed
                ? new JB721TiersHookProjectDeployer{salt: _PROJECT_DEPLOYER_SALT}({
                    directory: core.directory,
                    permissions: core.permissions,
                    hookDeployer: hookDeployer,
                    trustedForwarder: trustedForwarder
                })
                : JB721TiersHookProjectDeployer(_projectDeployer);
        }
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (address, bool)
    {
        address _deployedTo = vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            // Arachnid/deterministic-deployment-proxy address.
            deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        });

        // Return if code is already present at this address.
        return (_deployedTo, address(_deployedTo).code.length != 0);
    }
}
