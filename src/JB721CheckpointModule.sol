// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {IJB721CheckpointModule} from "./interfaces/IJB721CheckpointModule.sol";
import {IJB721TiersHookStore} from "./interfaces/IJB721TiersHookStore.sol";

/// @title JB721CheckpointModule
/// @notice Provides IVotes-compatible checkpointed voting power for a JB721TiersHook. Deployed as an EIP-1167 clone
/// via JB721CheckpointModuleFactory — one module per hook. The hook calls `onTransfer` on every NFT transfer to
/// maintain accurate vote checkpoints.
/// @dev EIP712 on clones: OZ stores name/version as immutables (accessible via DELEGATECALL). The storage cache
/// (`_cachedThis`) is uninitialized on clones, so `domainSeparatorV4()` always rebuilds using the clone's
/// `address(this)` — correct behavior, tiny gas overhead.
contract JB721CheckpointModule is Votes, IJB721CheckpointModule {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JB721CheckpointModule_AlreadyInitialized();
    error JB721CheckpointModule_Unauthorized();

    //*********************************************************************//
    // --------------------- private stored properties ------------------ //
    //*********************************************************************//

    /// @notice Whether this contract has been initialized.
    bool private _initialized;

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice The hook that this module tracks voting power for.
    address public override HOOK;

    /// @notice The store that holds tier and voting data for the hook's NFTs.
    IJB721TiersHookStore public override STORE;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @dev Parameterless. The implementation contract is initialized in the constructor to prevent direct use.
    /// Clones are initialized via `initialize()`.
    constructor() EIP712("JB721CheckpointModule", "1") {
        _initialized = true;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Initializes a cloned module with its hook and store references.
    /// @dev Can only be called once. Called by the factory after cloning.
    /// @param hook The hook this module serves.
    /// @param store The store that holds tier data for the hook's NFTs.
    function initialize(address hook, IJB721TiersHookStore store) external override {
        if (_initialized) revert JB721CheckpointModule_AlreadyInitialized();
        _initialized = true;
        HOOK = hook;
        STORE = store;
    }

    /// @notice Called by the hook after every NFT transfer to update checkpointed voting power.
    /// @dev Only callable by the HOOK. Looks up the token's tier voting units from the store.
    /// @param from The previous owner (address(0) on mint).
    /// @param to The new owner (address(0) on burn).
    /// @param tokenId The token ID being transferred.
    function onTransfer(address from, address to, uint256 tokenId) external override {
        if (msg.sender != HOOK) revert JB721CheckpointModule_Unauthorized();

        // Look up this token's tier to get its voting units.
        uint256 votingUnits = STORE.tierOfTokenId(HOOK, tokenId, false).votingUnits;

        // Move checkpointed voting power from the previous owner to the new owner.
        _transferVotingUnits(from, to, votingUnits);
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice Returns the total voting units held by an account (across all tiers).
    /// @dev Called by OZ Votes when re-delegating to compute the account's total voting units.
    /// @param account The address to get the voting units of.
    /// @return The total voting units the account holds.
    function _getVotingUnits(address account) internal view override returns (uint256) {
        return STORE.votingUnitsOf(HOOK, account);
    }
}
