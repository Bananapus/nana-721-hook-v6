// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBCashOutHook} from "@bananapus/core-v6/src/interfaces/IJBCashOutHook.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPayHook} from "@bananapus/core-v6/src/interfaces/IJBPayHook.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";

/// @notice A 721 hook that integrates with Juicebox as a data hook, pay hook, and cash out hook.
interface IJB721Hook is IJBRulesetDataHook, IJBPayHook, IJBCashOutHook {
    /// @notice The directory of terminals and controllers for projects.
    /// @return The directory contract.
    function DIRECTORY() external view returns (IJBDirectory);

    /// @notice The ID used when parsing metadata.
    /// @return The address of the metadata ID target.
    function METADATA_ID_TARGET() external view returns (address);

    /// @notice The ID of the project that this contract is associated with.
    /// @return The project ID.
    function PROJECT_ID() external view returns (uint256);
}
