// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LibClone} from "solady/src/utils/LibClone.sol";

import {JB721Checkpoints} from "./JB721Checkpoints.sol";
import {IJB721Checkpoints} from "./interfaces/IJB721Checkpoints.sol";
import {IJB721CheckpointsDeployer} from "./interfaces/IJB721CheckpointsDeployer.sol";
import {IJB721TiersHookStore} from "./interfaces/IJB721TiersHookStore.sol";

/// @title JB721CheckpointsDeployer
/// @notice Deploys EIP-1167 clones of JB721Checkpoints for each JB721TiersHook instance.
/// @dev The implementation is deployed once in the constructor. Each `deploy()` call clones it (~45k gas) and
/// initializes the clone with the hook and store references.
contract JB721CheckpointsDeployer is IJB721CheckpointsDeployer {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JB721CheckpointsDeployer_Unauthorized(address caller, address hook);

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The checkpoint module implementation that clones delegate to.
    address public immutable override IMPLEMENTATION;

    /// @notice The store that holds tier and voting data for each hook's NFTs.
    IJB721TiersHookStore public immutable override STORE;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param store The store that holds tier data for each hook's NFTs.
    constructor(IJB721TiersHookStore store) {
        STORE = store;
        IMPLEMENTATION = address(new JB721Checkpoints(store));
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Deploys a new deterministic checkpoint clone for the given hook.
    /// @dev Uses CREATE2 with the hook address as salt so the clone address is the same across chains.
    /// @param hook The hook address the module will serve.
    /// @return module The newly deployed and initialized checkpoint module.
    function deploy(address hook) external override returns (IJB721Checkpoints module) {
        if (msg.sender != hook) {
            revert JB721CheckpointsDeployer_Unauthorized({caller: msg.sender, hook: hook});
        }

        module = IJB721Checkpoints(
            LibClone.cloneDeterministic({implementation: IMPLEMENTATION, salt: bytes32(uint256(uint160(hook)))})
        );
        module.initialize(hook);
    }
}
