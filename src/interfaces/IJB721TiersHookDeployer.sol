// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJB721TiersHook} from "./IJB721TiersHook.sol";
import {JBDeploy721TiersHookConfig} from "../structs/JBDeploy721TiersHookConfig.sol";

/// @notice Deploys 721 tiers hooks for projects.
interface IJB721TiersHookDeployer {
    /// @notice Emitted when a 721 tiers hook is deployed for a project.
    /// @param projectId The ID of the project the hook was deployed for.
    /// @param hook The deployed hook contract.
    /// @param caller The address that called the function.
    event HookDeployed(uint256 indexed projectId, IJB721TiersHook hook, address caller);

    /// @notice Deploys a 721 tiers hook for the specified project.
    /// @param projectId The ID of the project to deploy the hook for.
    /// @param deployTiersHookConfig The config to deploy the hook with.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return newHook The address of the newly deployed hook.
    function deployHookFor(
        uint256 projectId,
        JBDeploy721TiersHookConfig memory deployTiersHookConfig,
        bytes32 salt
    )
        external
        returns (IJB721TiersHook newHook);
}
