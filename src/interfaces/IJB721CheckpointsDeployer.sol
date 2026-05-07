// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJB721Checkpoints} from "./IJB721Checkpoints.sol";
import {IJB721TiersHookStore} from "./IJB721TiersHookStore.sol";

/// @notice Deploys JB721Checkpoints clones for JB721TiersHook instances.
interface IJB721CheckpointsDeployer {
    /// @notice The implementation contract that clones are based on.
    /// @return The implementation address.
    // forge-lint: disable-next-line(mixed-case-function)
    function IMPLEMENTATION() external view returns (address);

    /// @notice The store that holds tier and voting data for each hook's NFTs.
    /// @return The store contract.
    // forge-lint: disable-next-line(mixed-case-function)
    function STORE() external view returns (IJB721TiersHookStore);

    /// @notice Deploys a new deterministic checkpoint clone for the given hook.
    /// @dev Uses CREATE2 with the hook address as salt so the clone address is the same across chains.
    /// @param hook The hook address the module will serve.
    /// @return module The newly deployed and initialized checkpoint module.
    function deploy(address hook) external returns (IJB721Checkpoints module);
}
