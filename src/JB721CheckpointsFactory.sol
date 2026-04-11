// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LibClone} from "solady/src/utils/LibClone.sol";
import {JB721Checkpoints} from "./JB721Checkpoints.sol";
import {IJB721Checkpoints} from "./interfaces/IJB721Checkpoints.sol";
import {IJB721CheckpointsFactory} from "./interfaces/IJB721CheckpointsFactory.sol";
import {IJB721TiersHookStore} from "./interfaces/IJB721TiersHookStore.sol";

/// @title JB721CheckpointsFactory
/// @notice Deploys EIP-1167 clones of JB721Checkpoints for each JB721TiersHook instance.
/// @dev The implementation is deployed once in the constructor. Each `deploy()` call clones it (~45k gas) and
/// initializes the clone with the hook and store references.
contract JB721CheckpointsFactory is IJB721CheckpointsFactory {
    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The checkpoint module implementation that clones delegate to.
    address public immutable override MODULE_IMPLEMENTATION;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor() {
        MODULE_IMPLEMENTATION = address(new JB721Checkpoints());
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Deploys a new checkpoint module clone for the given hook.
    /// @param hook The hook address the module will serve.
    /// @param store The store that holds tier data for the hook's NFTs.
    /// @return module The newly deployed and initialized checkpoint module.
    function deploy(address hook, IJB721TiersHookStore store) external override returns (IJB721Checkpoints module) {
        module = IJB721Checkpoints(LibClone.clone(MODULE_IMPLEMENTATION));
        module.initialize({hook: hook, store: store});
    }
}
