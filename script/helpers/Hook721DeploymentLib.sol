// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {stdJson} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import {SphinxConstants, NetworkInfo} from "@sphinx-labs/contracts/contracts/foundry/SphinxConstants.sol";

import {IJB721TiersHookDeployer} from "../../src/interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHookProjectDeployer} from "../../src/interfaces/IJB721TiersHookProjectDeployer.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";

struct Hook721Deployment {
    IJB721TiersHookDeployer hookDeployer;
    IJB721TiersHookProjectDeployer projectDeployer;
    IJB721TiersHookStore store;
}

library Hook721DeploymentLib {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    // forge-lint: disable-next-line(screaming-snake-case-const)
    Vm internal constant vm = Vm(VM_ADDRESS);

    function getDeployment(string memory path) internal returns (Hook721Deployment memory deployment) {
        // Match the current chain ID to the Sphinx network name used in deployment artifacts.
        uint256 chainId = block.chainid;

        // `SphinxConstants` exposes Sphinx's supported chain ID to network name mapping.
        SphinxConstants sphinxConstants = new SphinxConstants();
        NetworkInfo[] memory networks = sphinxConstants.getNetworkInfoArray();

        for (uint256 _i; _i < networks.length; _i++) {
            if (networks[_i].chainId == chainId) {
                return getDeployment({path: path, networkName: networks[_i].name});
            }
        }

        revert("ChainID is not (currently) supported by Sphinx.");
    }

    function getDeployment(
        string memory path,
        string memory networkName
    )
        internal
        view
        returns (Hook721Deployment memory deployment)
    {
        deployment.hookDeployer = IJB721TiersHookDeployer(
            _getDeploymentAddress({
                path: path,
                projectName: "nana-721-hook-v6",
                networkName: networkName,
                contractName: "JB721TiersHookDeployer"
            })
        );

        deployment.projectDeployer = IJB721TiersHookProjectDeployer(
            _getDeploymentAddress({
                path: path,
                projectName: "nana-721-hook-v6",
                networkName: networkName,
                contractName: "JB721TiersHookProjectDeployer"
            })
        );

        deployment.store = IJB721TiersHookStore(
            _getDeploymentAddress({
                path: path,
                projectName: "nana-721-hook-v6",
                networkName: networkName,
                contractName: "JB721TiersHookStore"
            })
        );
    }

    /// @notice Get the address of a contract that was deployed by the Deploy script.
    /// @dev Reverts if the contract was not found.
    /// @param path The path to the deployment file.
    /// @param contractName The name of the contract to get the address of.
    /// @return The address of the contract.
    function _getDeploymentAddress(
        string memory path,
        string memory projectName,
        string memory networkName,
        string memory contractName
    )
        internal
        view
        returns (address)
    {
        string memory deploymentJson =
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.readFile(string.concat(path, projectName, "/", networkName, "/", contractName, ".json"));
        return stdJson.readAddress({json: deploymentJson, key: ".address"});
    }
}
