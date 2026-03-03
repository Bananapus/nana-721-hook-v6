// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/core-v5/script/helpers/CoreDeploymentLib.sol";
import "@bananapus/address-registry-v5/script/helpers/AddressRegistryDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {JB721TiersHookDeployer} from "../src/JB721TiersHookDeployer.sol";
import {JB721TiersHookProjectDeployer} from "../src/JB721TiersHookProjectDeployer.sol";
import {JB721TiersHookStore} from "../src/JB721TiersHookStore.sol";
import {JB721TiersHook} from "../src/JB721TiersHook.sol";
import {IJBRulesets} from "@bananapus/core-v5/src/interfaces/IJBRulesets.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the deployment of the address registry for the chain we are deploying to.
    AddressRegistryDeployment registry;

    /// @notice The address that is allowed to forward calls to the terminal and controller on a users behalf.
    address private TRUSTED_FORWARDER;

    /// @notice the salts that are used to deploy the contracts.
    bytes32 HOOK_SALT = "JB721TiersHook_";
    bytes32 HOOK_DEPLOYER_SALT = "JB721TiersHookDeployer_";
    bytes32 HOOK_STORE_SALT = "JB721TiersHookStore_";
    bytes32 PROJECT_DEPLOYER_SALT = "JB721TiersHookProjectDeployer_";

    function configureSphinx() public override {
        sphinxConfig.projectName = "nana-721-hook-v5";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core-v5/deployments/"))
        );

        // We use the same trusted forwarder as the core deployment.
        TRUSTED_FORWARDER = core.permissions.trustedForwarder();

        registry = AddressRegistryDeploymentLib.getDeployment(
            vm.envOr(
                "NANA_ADDRESS_REGISTRY_DEPLOYMENT_PATH",
                string("node_modules/@bananapus/address-registry-v5/deployments/")
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
            (address _store, bool _storeIsDeployed) =
                _isDeployed(HOOK_STORE_SALT, type(JB721TiersHookStore).creationCode, "");

            // Deploy it if it has not been deployed yet.
            store = !_storeIsDeployed ? new JB721TiersHookStore{salt: HOOK_STORE_SALT}() : JB721TiersHookStore(_store);
        }

        JB721TiersHook hook;
        {
            // Perform the check for the registry.
            (address _hook, bool _hookIsDeployed) = _isDeployed(
                HOOK_SALT,
                type(JB721TiersHook).creationCode,
                abi.encode(
                    core.directory, core.permissions, IJBRulesets(address(core.rulesets5_1)), store, TRUSTED_FORWARDER
                )
            );

            // Deploy it if it has not been deployed yet.
            hook = !_hookIsDeployed
                ? new JB721TiersHook{salt: HOOK_SALT}(
                    core.directory, core.permissions, IJBRulesets(address(core.rulesets5_1)), store, TRUSTED_FORWARDER
                )
                : JB721TiersHook(_hook);
        }

        JB721TiersHookDeployer hookDeployer;
        {
            // Perform the check for the registry.
            (address _hookDeployer, bool _hookDeployerIsDeployed) = _isDeployed(
                HOOK_DEPLOYER_SALT,
                type(JB721TiersHookDeployer).creationCode,
                abi.encode(hook, store, registry.registry, TRUSTED_FORWARDER)
            );

            hookDeployer = !_hookDeployerIsDeployed
                ? new JB721TiersHookDeployer{salt: HOOK_DEPLOYER_SALT}(
                    hook, store, registry.registry, TRUSTED_FORWARDER
                )
                : JB721TiersHookDeployer(_hookDeployer);
        }

        JB721TiersHookProjectDeployer projectDeployer;
        {
            // Perform the check for the registry.
            (address _projectDeployer, bool _projectDeployerIsdeployed) = _isDeployed(
                PROJECT_DEPLOYER_SALT,
                type(JB721TiersHookProjectDeployer).creationCode,
                abi.encode(core.directory, core.permissions, hookDeployer, TRUSTED_FORWARDER)
            );

            projectDeployer = !_projectDeployerIsdeployed
                ? new JB721TiersHookProjectDeployer{salt: PROJECT_DEPLOYER_SALT}(
                    core.directory, core.permissions, hookDeployer, TRUSTED_FORWARDER
                )
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
