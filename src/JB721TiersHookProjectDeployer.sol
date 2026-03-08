// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {JBPermissioned} from "@bananapus/core-v6/src/abstract/JBPermissioned.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {JBRulesetConfig} from "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import {JBOwnable} from "@bananapus/ownable-v6/src/JBOwnable.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {IJB721TiersHook} from "./interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "./interfaces/IJB721TiersHookDeployer.sol";
import {IJB721TiersHookProjectDeployer} from "./interfaces/IJB721TiersHookProjectDeployer.sol";
import {JBDeploy721TiersHookConfig} from "./structs/JBDeploy721TiersHookConfig.sol";
import {JBLaunchProjectConfig} from "./structs/JBLaunchProjectConfig.sol";
import {JBLaunchRulesetsConfig} from "./structs/JBLaunchRulesetsConfig.sol";
import {JBPayDataHookRulesetConfig} from "./structs/JBPayDataHookRulesetConfig.sol";
import {JBQueueRulesetsConfig} from "./structs/JBQueueRulesetsConfig.sol";

/// @title JB721TiersHookProjectDeployer
/// @notice Deploys a project and a 721 tiers hook for it. Can be used to queue rulesets for the project if given
/// `JBPermissionIds.QUEUE_RULESETS`.
contract JB721TiersHookProjectDeployer is ERC2771Context, JBPermissioned, IJB721TiersHookProjectDeployer {
    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The 721 tiers hook deployer.
    IJB721TiersHookDeployer public immutable override HOOK_DEPLOYER;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param directory The directory of terminals and controllers for projects.
    /// @param permissions A contract storing permissions.
    /// @param hookDeployer The 721 tiers hook deployer.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJB721TiersHookDeployer hookDeployer,
        address trustedForwarder
    )
        JBPermissioned(permissions)
        ERC2771Context(trustedForwarder)
    {
        DIRECTORY = directory;
        HOOK_DEPLOYER = hookDeployer;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Launches a new project with a 721 tiers hook attached.
    /// @param owner The address to set as the owner of the project. The ERC-721 which confers this project's ownership
    /// will be sent to this address.
    /// @param deployTiersHookConfig Configuration which dictates the behavior of the 721 tiers hook which is being
    /// deployed.
    /// @param launchProjectConfig Configuration which dictates the behavior of the project which is being launched.
    /// @param controller The controller that the project's rulesets will be queued with.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return projectId The ID of the newly launched project.
    /// @return hook The 721 tiers hook that was deployed for the project.
    function launchProjectFor(
        address owner,
        JBDeploy721TiersHookConfig calldata deployTiersHookConfig,
        JBLaunchProjectConfig calldata launchProjectConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        override
        returns (uint256 projectId, IJB721TiersHook hook)
    {
        // Get the project's ID, optimistically knowing it will be one greater than the current number of projects.
        projectId = DIRECTORY.PROJECTS().count() + 1;

        // Deploy the hook.
        hook = HOOK_DEPLOYER.deployHookFor({
            projectId: projectId,
            deployTiersHookConfig: deployTiersHookConfig,
            salt: salt == bytes32(0) ? bytes32(0) : keccak256(abi.encode(_msgSender(), salt))
        });

        // Launch the project.
        _launchProjectFor({
            owner: owner, launchProjectConfig: launchProjectConfig, dataHook: hook, controller: controller
        });

        // Transfer the hook's ownership to the project.
        JBOwnable(address(hook)).transferOwnershipToProject(projectId);
    }

    /// @notice Launches rulesets for a project with an attached 721 tiers hook.
    /// @dev Only a project's owner or an operator with the `QUEUE_RULESETS & SET_TERMINALS` permission can launch its
    /// rulesets.
    /// @param projectId The ID of the project that rulesets are being launched for.
    /// @param deployTiersHookConfig Configuration which dictates the behavior of the 721 tiers hook which is being
    /// deployed.
    /// @param launchRulesetsConfig Configuration which dictates the project's new rulesets.
    /// @param controller The controller that the project's rulesets will be queued with.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return rulesetId The ID of the successfully created ruleset.
    /// @return hook The 721 tiers hook that was deployed for the project.
    function launchRulesetsFor(
        uint256 projectId,
        JBDeploy721TiersHookConfig calldata deployTiersHookConfig,
        JBLaunchRulesetsConfig calldata launchRulesetsConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        override
        returns (uint256 rulesetId, IJB721TiersHook hook)
    {
        // Get the project's projects contract.
        IJBProjects PROJECTS = DIRECTORY.PROJECTS();

        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId), projectId: projectId, permissionId: JBPermissionIds.QUEUE_RULESETS
        });

        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId), projectId: projectId, permissionId: JBPermissionIds.SET_TERMINALS
        });

        // Deploy the hook.
        hook = HOOK_DEPLOYER.deployHookFor({
            projectId: projectId,
            deployTiersHookConfig: deployTiersHookConfig,
            salt: salt == bytes32(0) ? bytes32(0) : keccak256(abi.encode(_msgSender(), salt))
        });

        // Transfer the hook's ownership to the project.
        JBOwnable(address(hook)).transferOwnershipToProject(projectId);

        // Launch the rulesets.
        rulesetId = _launchRulesetsFor({
            projectId: projectId, launchRulesetsConfig: launchRulesetsConfig, dataHook: hook, controller: controller
        });
    }

    /// @notice Queues rulesets for a project with an attached 721 tiers hook.
    /// @dev Only a project's owner or an operator with the `QUEUE_RULESETS` permission can queue its rulesets.
    /// @param projectId The ID of the project that rulesets are being queued for.
    /// @param deployTiersHookConfig Configuration which dictates the behavior of the 721 tiers hook which is being
    /// deployed.
    /// @param queueRulesetsConfig Configuration which dictates the project's newly queued rulesets.
    /// @param controller The controller that the project's rulesets will be queued with.
    /// @param salt A salt to use for the deterministic deployment.
    /// @return rulesetId The ID of the successfully created ruleset.
    /// @return hook The 721 tiers hook that was deployed for the project.
    function queueRulesetsOf(
        uint256 projectId,
        JBDeploy721TiersHookConfig calldata deployTiersHookConfig,
        JBQueueRulesetsConfig calldata queueRulesetsConfig,
        IJBController controller,
        bytes32 salt
    )
        external
        override
        returns (uint256 rulesetId, IJB721TiersHook hook)
    {
        // Enforce permissions.
        _requirePermissionFrom({
            account: DIRECTORY.PROJECTS().ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.QUEUE_RULESETS
        });

        // Deploy the hook.
        hook = HOOK_DEPLOYER.deployHookFor({
            projectId: projectId,
            deployTiersHookConfig: deployTiersHookConfig,
            salt: salt == bytes32(0) ? bytes32(0) : keccak256(abi.encode(_msgSender(), salt))
        });

        // Transfer the hook's ownership to the project.
        JBOwnable(address(hook)).transferOwnershipToProject(projectId);

        // Queue the rulesets.
        rulesetId = _queueRulesetsOf({
            projectId: projectId, queueRulesetsConfig: queueRulesetsConfig, dataHook: hook, controller: controller
        });
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @dev ERC-2771 specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view virtual override(ERC2771Context, Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }

    /// @notice The calldata. Preferred to use over `msg.data`.
    /// @return calldata The `msg.data` of this call.
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice The message's sender. Preferred to use over `msg.sender`.
    /// @return sender The address which sent this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice Launches a project.
    /// @param owner The address that will own the project.
    /// @param launchProjectConfig Configuration which dictates the behavior of the project which is being launched.
    /// @param dataHook The data hook to use for the project.
    /// @param controller The controller that the project's rulesets will be queued with.
    function _launchProjectFor(
        address owner,
        JBLaunchProjectConfig memory launchProjectConfig,
        IJB721TiersHook dataHook,
        IJBController controller
    )
        internal
    {
        // Initialize an array of ruleset configurations.
        JBRulesetConfig[] memory rulesetConfigurations =
            new JBRulesetConfig[](launchProjectConfig.rulesetConfigurations.length);

        // Set the data hook to be active for pay transactions for each ruleset configuration.
        for (uint256 i; i < launchProjectConfig.rulesetConfigurations.length; i++) {
            // Set the pay data ruleset config being iterated on.
            JBPayDataHookRulesetConfig memory payDataRulesetConfig = launchProjectConfig.rulesetConfigurations[i];

            // Add the ruleset config.
            rulesetConfigurations[i] = JBRulesetConfig({
                mustStartAtOrAfter: payDataRulesetConfig.mustStartAtOrAfter,
                duration: payDataRulesetConfig.duration,
                weight: payDataRulesetConfig.weight,
                weightCutPercent: payDataRulesetConfig.weightCutPercent,
                approvalHook: payDataRulesetConfig.approvalHook,
                metadata: JBRulesetMetadata({
                    reservedPercent: payDataRulesetConfig.metadata.reservedPercent,
                    cashOutTaxRate: payDataRulesetConfig.metadata.cashOutTaxRate,
                    baseCurrency: payDataRulesetConfig.metadata.baseCurrency,
                    pausePay: payDataRulesetConfig.metadata.pausePay,
                    pauseCreditTransfers: payDataRulesetConfig.metadata.pauseCreditTransfers,
                    allowOwnerMinting: payDataRulesetConfig.metadata.allowOwnerMinting,
                    allowSetCustomToken: false,
                    allowTerminalMigration: payDataRulesetConfig.metadata.allowTerminalMigration,
                    allowSetTerminals: payDataRulesetConfig.metadata.allowSetTerminals,
                    allowSetController: payDataRulesetConfig.metadata.allowSetController,
                    allowAddAccountingContext: payDataRulesetConfig.metadata.allowAddAccountingContext,
                    allowAddPriceFeed: payDataRulesetConfig.metadata.allowAddPriceFeed,
                    ownerMustSendPayouts: payDataRulesetConfig.metadata.ownerMustSendPayouts,
                    holdFees: payDataRulesetConfig.metadata.holdFees,
                    useTotalSurplusForCashOuts: payDataRulesetConfig.metadata.useTotalSurplusForCashOuts,
                    useDataHookForPay: true,
                    useDataHookForCashOut: payDataRulesetConfig.metadata.useDataHookForCashOut,
                    dataHook: address(dataHook),
                    metadata: payDataRulesetConfig.metadata.metadata
                }),
                splitGroups: payDataRulesetConfig.splitGroups,
                fundAccessLimitGroups: payDataRulesetConfig.fundAccessLimitGroups
            });
        }

        // Launch the project.
        // slither-disable-next-line unused-return
        controller.launchProjectFor({
            owner: owner,
            projectUri: launchProjectConfig.projectUri,
            rulesetConfigurations: rulesetConfigurations,
            terminalConfigurations: launchProjectConfig.terminalConfigurations,
            memo: launchProjectConfig.memo
        });
    }

    /// @notice Launches rulesets for a project.
    /// @param projectId The ID of the project to launch rulesets for.
    /// @param launchRulesetsConfig Configuration which dictates the behavior of the project's rulesets.
    /// @param dataHook The data hook to use for the project.
    /// @param controller The controller that the project's rulesets will be queued with.
    /// @return rulesetId The ID of the successfully created ruleset.
    function _launchRulesetsFor(
        uint256 projectId,
        JBLaunchRulesetsConfig memory launchRulesetsConfig,
        IJB721TiersHook dataHook,
        IJBController controller
    )
        internal
        returns (uint256)
    {
        // Initialize an array of ruleset configurations.
        JBRulesetConfig[] memory rulesetConfigurations =
            new JBRulesetConfig[](launchRulesetsConfig.rulesetConfigurations.length);

        // Set the data hook to be active for pay transactions for each ruleset configuration.
        for (uint256 i; i < launchRulesetsConfig.rulesetConfigurations.length; i++) {
            // Set the pay data ruleset config being iterated on.
            JBPayDataHookRulesetConfig memory payDataRulesetConfig = launchRulesetsConfig.rulesetConfigurations[i];

            // Add the ruleset config.
            rulesetConfigurations[i] = JBRulesetConfig({
                mustStartAtOrAfter: payDataRulesetConfig.mustStartAtOrAfter,
                duration: payDataRulesetConfig.duration,
                weight: payDataRulesetConfig.weight,
                weightCutPercent: payDataRulesetConfig.weightCutPercent,
                approvalHook: payDataRulesetConfig.approvalHook,
                metadata: JBRulesetMetadata({
                    reservedPercent: payDataRulesetConfig.metadata.reservedPercent,
                    cashOutTaxRate: payDataRulesetConfig.metadata.cashOutTaxRate,
                    baseCurrency: payDataRulesetConfig.metadata.baseCurrency,
                    pausePay: payDataRulesetConfig.metadata.pausePay,
                    pauseCreditTransfers: payDataRulesetConfig.metadata.pauseCreditTransfers,
                    allowOwnerMinting: payDataRulesetConfig.metadata.allowOwnerMinting,
                    allowSetCustomToken: false,
                    allowTerminalMigration: payDataRulesetConfig.metadata.allowTerminalMigration,
                    allowSetTerminals: payDataRulesetConfig.metadata.allowSetTerminals,
                    allowSetController: payDataRulesetConfig.metadata.allowSetController,
                    allowAddAccountingContext: payDataRulesetConfig.metadata.allowAddAccountingContext,
                    allowAddPriceFeed: payDataRulesetConfig.metadata.allowAddPriceFeed,
                    ownerMustSendPayouts: payDataRulesetConfig.metadata.ownerMustSendPayouts,
                    holdFees: payDataRulesetConfig.metadata.holdFees,
                    useTotalSurplusForCashOuts: payDataRulesetConfig.metadata.useTotalSurplusForCashOuts,
                    useDataHookForPay: true,
                    useDataHookForCashOut: payDataRulesetConfig.metadata.useDataHookForCashOut,
                    dataHook: address(dataHook),
                    metadata: payDataRulesetConfig.metadata.metadata
                }),
                splitGroups: payDataRulesetConfig.splitGroups,
                fundAccessLimitGroups: payDataRulesetConfig.fundAccessLimitGroups
            });
        }

        // Launch the rulesets.
        return controller.launchRulesetsFor({
            projectId: projectId,
            rulesetConfigurations: rulesetConfigurations,
            terminalConfigurations: launchRulesetsConfig.terminalConfigurations,
            memo: launchRulesetsConfig.memo
        });
    }

    /// @notice Queues rulesets for a project.
    /// @param projectId The ID of the project to queue rulesets for.
    /// @param queueRulesetsConfig Configuration which dictates the behavior of the project's rulesets.
    /// @param dataHook The data hook to use for the project.
    /// @param controller The controller that the project's rulesets will be queued with.
    /// @return The ID of the successfully created ruleset.
    function _queueRulesetsOf(
        uint256 projectId,
        JBQueueRulesetsConfig memory queueRulesetsConfig,
        IJB721TiersHook dataHook,
        IJBController controller
    )
        internal
        returns (uint256)
    {
        // Initialize an array of ruleset configurations.
        JBRulesetConfig[] memory rulesetConfigurations =
            new JBRulesetConfig[](queueRulesetsConfig.rulesetConfigurations.length);

        // Set the data hook to be active for pay transactions for each ruleset configuration.
        for (uint256 i; i < queueRulesetsConfig.rulesetConfigurations.length; i++) {
            // Set the pay data ruleset config being iterated on.
            JBPayDataHookRulesetConfig memory payDataRulesetConfig = queueRulesetsConfig.rulesetConfigurations[i];

            // Add the ruleset config.
            rulesetConfigurations[i] = JBRulesetConfig({
                mustStartAtOrAfter: payDataRulesetConfig.mustStartAtOrAfter,
                duration: payDataRulesetConfig.duration,
                weight: payDataRulesetConfig.weight,
                weightCutPercent: payDataRulesetConfig.weightCutPercent,
                approvalHook: payDataRulesetConfig.approvalHook,
                metadata: JBRulesetMetadata({
                    reservedPercent: payDataRulesetConfig.metadata.reservedPercent,
                    cashOutTaxRate: payDataRulesetConfig.metadata.cashOutTaxRate,
                    baseCurrency: payDataRulesetConfig.metadata.baseCurrency,
                    pausePay: payDataRulesetConfig.metadata.pausePay,
                    pauseCreditTransfers: payDataRulesetConfig.metadata.pauseCreditTransfers,
                    allowOwnerMinting: payDataRulesetConfig.metadata.allowOwnerMinting,
                    allowSetCustomToken: false,
                    allowTerminalMigration: payDataRulesetConfig.metadata.allowTerminalMigration,
                    allowSetTerminals: payDataRulesetConfig.metadata.allowSetTerminals,
                    allowSetController: payDataRulesetConfig.metadata.allowSetController,
                    allowAddAccountingContext: payDataRulesetConfig.metadata.allowAddAccountingContext,
                    allowAddPriceFeed: payDataRulesetConfig.metadata.allowAddPriceFeed,
                    ownerMustSendPayouts: payDataRulesetConfig.metadata.ownerMustSendPayouts,
                    holdFees: payDataRulesetConfig.metadata.holdFees,
                    useTotalSurplusForCashOuts: payDataRulesetConfig.metadata.useTotalSurplusForCashOuts,
                    useDataHookForPay: true,
                    useDataHookForCashOut: payDataRulesetConfig.metadata.useDataHookForCashOut,
                    dataHook: address(dataHook),
                    metadata: payDataRulesetConfig.metadata.metadata
                }),
                splitGroups: payDataRulesetConfig.splitGroups,
                fundAccessLimitGroups: payDataRulesetConfig.fundAccessLimitGroups
            });
        }

        // Queue the rulesets.
        return controller.queueRulesetsOf({
            projectId: projectId, rulesetConfigurations: rulesetConfigurations, memo: queueRulesetsConfig.memo
        });
    }
}
