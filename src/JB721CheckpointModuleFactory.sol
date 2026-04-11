// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LibClone} from "solady/src/utils/LibClone.sol";
import {JB721CheckpointModule} from "./JB721CheckpointModule.sol";
import {IJB721CheckpointModule} from "./interfaces/IJB721CheckpointModule.sol";
import {IJB721CheckpointModuleFactory} from "./interfaces/IJB721CheckpointModuleFactory.sol";
import {IJB721TiersHookStore} from "./interfaces/IJB721TiersHookStore.sol";

/// @title JB721CheckpointModuleFactory
/// @notice Deploys EIP-1167 clones of JB721CheckpointModule for each JB721TiersHook instance.
/// @dev The implementation is deployed once in the constructor. Each `deploy()` call clones it (~45k gas) and
/// initializes the clone with the hook and store references.
contract JB721CheckpointModuleFactory is IJB721CheckpointModuleFactory {
    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The checkpoint module implementation that clones delegate to.
    address public immutable override MODULE_IMPLEMENTATION;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor() {
        MODULE_IMPLEMENTATION = address(new JB721CheckpointModule());
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Deploys a new checkpoint module clone for the given hook.
    /// @param hook The hook address the module will serve.
    /// @param store The store that holds tier data for the hook's NFTs.
    /// @return module The newly deployed and initialized checkpoint module.
    function deploy(
        address hook,
        IJB721TiersHookStore store
    )
        external
        override
        returns (IJB721CheckpointModule module)
    {
        module = IJB721CheckpointModule(LibClone.clone(MODULE_IMPLEMENTATION));
        module.initialize(hook, store);
    }
}
