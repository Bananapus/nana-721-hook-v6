// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJB721Checkpoints} from "./IJB721Checkpoints.sol";
import {IJB721TiersHookStore} from "./IJB721TiersHookStore.sol";

/// @notice Deploys JB721Checkpoints clones for JB721TiersHook instances.
interface IJB721CheckpointsDeployer {
    /// @notice Thrown when the caller is not the hook that the checkpoint module is being deployed for.
    error JB721CheckpointsDeployer_Unauthorized();

    /// @notice The implementation contract that clones are based on.
    /// @return The implementation address.
    // forge-lint: disable-next-line(mixed-case-function)
    function IMPLEMENTATION() external view returns (address);

    /// @notice Deploys a new deterministic checkpoint clone for the given hook.
    /// @dev Uses CREATE2 with the hook address as salt so the clone address is the same across chains.
    /// @param hook The hook address the module will serve.
    /// @param store The store that holds tier data for the hook's NFTs.
    /// @return module The newly deployed and initialized checkpoint module.
    function deploy(address hook, IJB721TiersHookStore store) external returns (IJB721Checkpoints module);
}
