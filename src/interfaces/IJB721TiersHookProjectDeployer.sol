// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";

import {IJB721TiersHook} from "./IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "./IJB721TiersHookDeployer.sol";
import {JBDeploy721TiersHookConfig} from "../structs/JBDeploy721TiersHookConfig.sol";
import {JBLaunchProjectConfig} from "../structs/JBLaunchProjectConfig.sol";
import {JBLaunchRulesetsConfig} from "../structs/JBLaunchRulesetsConfig.sol";
import {JBQueueRulesetsConfig} from "../structs/JBQueueRulesetsConfig.sol";

interface IJB721TiersHookProjectDeployer {
    function DIRECTORY() external view returns (IJBDirectory);
    function HOOK_DEPLOYER() external view returns (IJB721TiersHookDeployer);

    function launchProjectFor(
        address owner,
        JBDeploy721TiersHookConfig memory deployTiersHookConfig,
        JBLaunchProjectConfig memory launchProjectConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        returns (uint256 projectId, IJB721TiersHook hook);

    function launchRulesetsFor(
        uint256 projectId,
        JBDeploy721TiersHookConfig memory deployTiersHookConfig,
        JBLaunchRulesetsConfig memory launchRulesetsConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        returns (uint256 rulesetId, IJB721TiersHook hook);

    function queueRulesetsOf(
        uint256 projectId,
        JBDeploy721TiersHookConfig memory deployTiersHookConfig,
        JBQueueRulesetsConfig memory queueRulesetsConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        returns (uint256 rulesetId, IJB721TiersHook hook);
}
