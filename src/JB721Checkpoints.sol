// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

import {IJB721Checkpoints} from "./interfaces/IJB721Checkpoints.sol";
import {IJB721TiersHook} from "./interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookStore} from "./interfaces/IJB721TiersHookStore.sol";

/// @title JB721Checkpoints
/// @notice Provides IVotes-compatible checkpointed voting power for a JB721TiersHook. Deployed as an EIP-1167 clone
/// via JB721CheckpointsDeployer — one module per hook. The hook calls `onTransfer` on every NFT transfer to
/// maintain accurate vote checkpoints.
/// @dev EIP712 on clones: OZ stores name/version as immutables (accessible via DELEGATECALL). The storage cache
/// (`_cachedThis`) is uninitialized on clones, so `domainSeparatorV4()` always rebuilds using the clone's
/// `address(this)` — correct behavior, tiny gas overhead.
contract JB721Checkpoints is Votes, IJB721Checkpoints {
    using Checkpoints for Checkpoints.Trace160;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JB721Checkpoints_AlreadyInitialized();
    error JB721Checkpoints_Unauthorized();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The store that holds tier and voting data for the hook's NFTs.
    IJB721TiersHookStore public immutable override STORE;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The hook that this module tracks voting power for.
    address public override HOOK;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice Checkpointed token owners for historical reward eligibility after first transfer.
    /// @custom:param tokenId The token ID to get historical owner checkpoints for.
    mapping(uint256 tokenId => Checkpoints.Trace160) internal _ownerCheckpointsOf;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @dev The implementation contract is initialized in the constructor to prevent direct use. Clones are initialized
    /// via `initialize()`.
    /// @param store The store that holds tier data for each hook's NFTs.
    constructor(IJB721TiersHookStore store) EIP712("JB721Checkpoints", "1") {
        STORE = store;
        HOOK = address(1);
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Initializes a cloned module with its hook reference.
    /// @dev Can only be called once. Called by the deployer after cloning.
    /// @param hook The hook this module serves.
    function initialize(address hook) external override {
        if (HOOK != address(0)) revert JB721Checkpoints_AlreadyInitialized();
        // `hook` cannot be zero when called through the deployer because `msg.sender` must equal `hook`.
        // slither-disable-next-line missing-zero-check
        HOOK = hook;
    }

    /// @notice Called by the hook after every NFT transfer to update checkpointed voting power.
    /// @dev Only callable by the HOOK. Looks up the token's tier voting units from the store.
    /// @param from The previous owner (address(0) on mint).
    /// @param to The new owner (address(0) on burn).
    /// @param tokenId The token ID being transferred.
    function onTransfer(address from, address to, uint256 tokenId) external override {
        if (msg.sender != HOOK) revert JB721Checkpoints_Unauthorized();

        if (from != address(0)) {
            // forge-lint: disable-next-line(unsafe-typecast)
            // slither-disable-next-line unused-return
            _ownerCheckpointsOf[tokenId].push({key: uint96(block.number), value: uint160(to)});
        }

        // Look up this token's tier to get its voting units.
        uint256 votingUnits = STORE.tierOfTokenId({hook: HOOK, tokenId: tokenId, includeResolvedUri: false}).votingUnits;

        // Move checkpointed voting power from the previous owner to the new owner.
        _transferVotingUnits({from: from, to: to, amount: votingUnits});
    }

    //*********************************************************************//
    // ----------------------- external views ---------------------------- //
    //*********************************************************************//

    /// @notice The owner of an NFT at a past block.
    /// @dev Mints do not write per-token checkpoint storage. Until a token's first non-mint transfer, ownership is
    /// inferred from the hook's `firstOwnerOf`.
    /// @param tokenId The token ID of the NFT to get the historical owner of.
    /// @param blockNumber The block number to look up.
    /// @return The owner of the token at `blockNumber`, or zero if the token has no known owner.
    function ownerOfAt(uint256 tokenId, uint256 blockNumber) external view override returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint96 blockNumber96 = uint96(blockNumber);

        Checkpoints.Trace160 storage checkpoints = _ownerCheckpointsOf[tokenId];
        uint256 checkpointCount = checkpoints.length();

        // Before the first transfer/burn checkpoint, the mint owner is implicit in the hook's first-owner tracking.
        if (checkpointCount == 0 || checkpoints.at(0)._key > blockNumber96) {
            return IJB721TiersHook(HOOK).firstOwnerOf(tokenId);
        }

        return address(uint160(checkpoints.upperLookupRecent(blockNumber96)));
    }

    //*********************************************************************//
    // ----------------------- internal views ---------------------------- //
    //*********************************************************************//

    /// @notice Returns the total voting units held by an account (across all tiers).
    /// @dev Called by OZ Votes when re-delegating to compute the account's total voting units.
    /// @param account The address to get the voting units of.
    /// @return The total voting units the account holds.
    function _getVotingUnits(address account) internal view override returns (uint256) {
        return STORE.votingUnitsOf({hook: HOOK, account: account});
    }
}
