// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";

import {IJB721TiersHook} from "./IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "./IJB721TiersHookDeployer.sol";
import {JBDeploy721TiersHookConfig} from "../structs/JBDeploy721TiersHookConfig.sol";
import {JBLaunchProjectConfig} from "../structs/JBLaunchProjectConfig.sol";
import {JBLaunchRulesetsConfig} from "../structs/JBLaunchRulesetsConfig.sol";
import {JBQueueRulesetsConfig} from "../structs/JBQueueRulesetsConfig.sol";

/// @notice Deploys projects with 721 tiers hooks attached.
interface IJB721TiersHookProjectDeployer {
    /// @notice The directory of terminals and controllers for projects.
    /// @return The directory contract.
    function DIRECTORY() external view returns (IJBDirectory);

    /// @notice The 721 tiers hook deployer.
    /// @return The hook deployer contract.
    function HOOK_DEPLOYER() external view returns (IJB721TiersHookDeployer);

    /// @notice Launches a new project with a 721 tiers hook attached.
    /// @param owner The address to set as the owner of the project.
    /// @param deployTiersHookConfig Configuration which dictates the behavior of the 721 tiers hook.
    /// @param launchProjectConfig Configuration which dictates the behavior of the project.
    /// @param controller The controller that the project's rulesets will be queued with.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return projectId The ID of the newly launched project.
    /// @return hook The 721 tiers hook that was deployed for the project.
    function launchProjectFor(
        address owner,
        JBDeploy721TiersHookConfig memory deployTiersHookConfig,
        JBLaunchProjectConfig memory launchProjectConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        returns (uint256 projectId, IJB721TiersHook hook);

    /// @notice Launches rulesets for a project with an attached 721 tiers hook.
    /// @param projectId The ID of the project that rulesets are being launched for.
    /// @param deployTiersHookConfig Configuration which dictates the behavior of the 721 tiers hook.
    /// @param launchRulesetsConfig Configuration which dictates the project's new rulesets.
    /// @param controller The controller that the project's rulesets will be queued with.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return rulesetId The ID of the successfully created ruleset.
    /// @return hook The 721 tiers hook that was deployed for the project.
    function launchRulesetsFor(
        uint256 projectId,
        JBDeploy721TiersHookConfig memory deployTiersHookConfig,
        JBLaunchRulesetsConfig memory launchRulesetsConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        returns (uint256 rulesetId, IJB721TiersHook hook);

    /// @notice Queues rulesets for a project with an attached 721 tiers hook.
    /// @param projectId The ID of the project that rulesets are being queued for.
    /// @param deployTiersHookConfig Configuration which dictates the behavior of the 721 tiers hook.
    /// @param queueRulesetsConfig Configuration which dictates the project's newly queued rulesets.
    /// @param controller The controller that the project's rulesets will be queued with.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return rulesetId The ID of the successfully created ruleset.
    /// @return hook The 721 tiers hook that was deployed for the project.
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
