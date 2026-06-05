// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
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
    using Checkpoints for Checkpoints.Trace208;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    /// @notice Thrown when `initialize` is called on a module whose hook has already been set.
    error JB721Checkpoints_AlreadyInitialized(address hook);

    /// @notice Thrown when the caller tries to enroll a token they do not currently own.
    error JB721Checkpoints_NotOwner(uint256 tokenId, address caller);

    /// @notice Thrown when a hook-only function is called by an address other than the module's hook.
    error JB721Checkpoints_Unauthorized(address caller, address hook);

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The store that holds tier and voting data for the hook's NFTs.
    IJB721TiersHookStore public immutable override STORE;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The hook that this module tracks voting power for.
    address public override hook;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice Checkpointed token owners for historical reward eligibility. Written on enrollment or transfer.
    /// @custom:param tokenId The token ID to get historical owner checkpoints for.
    mapping(uint256 tokenId => Checkpoints.Trace160) internal _ownerCheckpointsOf;

    /// @notice Checkpointed total eligible voting units per tier. A token contributes its tier voting units from the
    /// block it first gains an owner checkpoint (enrollment or first transfer) until it is burned. Mints write
    /// nothing, mirroring `_ownerCheckpointsOf` eligibility. Distributors read this as the tier-scoped denominator.
    /// @custom:param tierId The tier to get the historical eligible voting units for.
    mapping(uint256 tierId => Checkpoints.Trace160) internal _tierEligibleUnitsOf;

    //*********************************************************************//
    // -------------------- private stored properties -------------------- //
    //*********************************************************************//

    /// @notice The total voting units currently delegated to nonzero delegates.
    Checkpoints.Trace208 private _activeSupplyCheckpoints;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @dev The implementation contract is initialized in the constructor to prevent direct use. Clones are initialized
    /// via `initialize()`.
    /// @param store The store that holds tier data for each hook's NFTs.
    constructor(IJB721TiersHookStore store) EIP712("JB721Checkpoints", "1") {
        STORE = store;
        hook = address(1);
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Delegates voting power and enrolls tokens for distribution eligibility.
    /// @dev Writes per-token owner checkpoints so `ownerOfAt` can prove ownership at past blocks.
    /// Only the current token owner can enroll. Tokens without checkpoints are ineligible for snapshot-based
    /// distribution. The existing `delegate(address)` from OZ Votes still works for pure delegation without enrollment.
    /// @param delegatee The address to delegate voting power to. Use your own address for self-delegation.
    /// @param tokenIds The token IDs to enroll for distribution eligibility.
    function delegate(address delegatee, uint256[] calldata tokenIds) external override {
        // Delegate voting power (reuses OZ Votes internals).
        _delegate({account: msg.sender, delegatee: delegatee});

        // Write per-token owner checkpoints for distribution eligibility.
        for (uint256 i; i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];

            // Only the current owner can enroll their tokens.
            if (IERC721(hook).ownerOf(tokenId) != msg.sender) {
                revert JB721Checkpoints_NotOwner({tokenId: tokenId, caller: msg.sender});
            }

            // Write an owner checkpoint if the token has none yet, and enroll its tier voting units.
            if (_ownerCheckpointsOf[tokenId].length() == 0) {
                // forge-lint: disable-next-line(unsafe-typecast)
                _ownerCheckpointsOf[tokenId].push({key: uint96(block.number), value: uint160(msg.sender)});
                _updateTierEligibleUnits({
                    tierId: STORE.tierIdOfToken(tokenId),
                    amount: STORE.tierVotingUnitsOfTokenId({hook: hook, tokenId: tokenId}),
                    increase: true
                });
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Initializes a cloned module with its hook reference.
    /// @dev Can only be called once. Called by the deployer after cloning.
    /// @param hookAddress The hook this module serves.
    function initialize(address hookAddress) external override {
        if (hook != address(0)) revert JB721Checkpoints_AlreadyInitialized({hook: hook});
        // `hook` cannot be zero when called through the deployer because `msg.sender` must equal `hook`.
        hook = hookAddress;
    }

    /// @notice Called by the hook after every NFT transfer to update checkpointed voting power.
    /// @dev Only callable by the hook. Looks up the token's tier voting units from the store.
    /// @param from The previous owner (address(0) on mint).
    /// @param to The new owner (address(0) on burn).
    /// @param tokenId The token ID to transfer.
    function onTransfer(address from, address to, uint256 tokenId) external override {
        if (msg.sender != hook) revert JB721Checkpoints_Unauthorized({caller: msg.sender, hook: hook});

        // Look up this token's tier voting units (lightweight getter — avoids full tier struct construction).
        uint256 votingUnits = STORE.tierVotingUnitsOfTokenId({hook: hook, tokenId: tokenId});

        // On mint (`from == 0`) nothing is checkpointed: the token is ineligible until enrolled or transferred,
        // so neither the owner trace nor the per-tier eligible-units trace is written.
        if (from != address(0)) {
            Checkpoints.Trace160 storage ownerTrace = _ownerCheckpointsOf[tokenId];
            bool wasEligible = ownerTrace.length() != 0;

            // forge-lint: disable-next-line(unsafe-typecast)
            ownerTrace.push({key: uint96(block.number), value: uint160(to)});

            if (to == address(0)) {
                // Burn: remove the tier's units only if the token was already eligible.
                if (wasEligible) {
                    _updateTierEligibleUnits({
                        tierId: STORE.tierIdOfToken(tokenId), amount: votingUnits, increase: false
                    });
                }
            } else if (!wasEligible) {
                // First transfer of a never-enrolled token makes it eligible: add the tier's units.
                _updateTierEligibleUnits({tierId: STORE.tierIdOfToken(tokenId), amount: votingUnits, increase: true});
            }
        }

        // Move checkpointed voting power from the previous owner to the new owner.
        _transferVotingUnits({from: from, to: to, amount: votingUnits});
    }

    //*********************************************************************//
    // ----------------------- external views ---------------------------- //
    //*********************************************************************//

    /// @notice The total eligible voting units of a tier at a past block.
    /// @param tierId The tier to get the eligible voting units of.
    /// @param blockNumber The block number to look up (must be strictly in the past).
    /// @return The tier's eligible voting units at `blockNumber`.
    function getPastTierVotingUnits(uint256 tierId, uint256 blockNumber) external view override returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return _tierEligibleUnitsOf[tierId].upperLookupRecent(uint96(_validateTimepoint(blockNumber)));
    }

    /// @notice The total delegated voting units at a past block.
    /// @dev This tracks delegated vote participation and is separate from tier reward eligibility.
    /// @param timepoint The past block number to look up.
    /// @return activeVotes The total voting units delegated to nonzero delegates at `timepoint`.
    function getPastTotalActiveVotes(uint256 timepoint) external view override returns (uint256 activeVotes) {
        activeVotes = _activeSupplyCheckpoints.upperLookupRecent(_validateTimepoint(timepoint));
    }

    /// @notice The current total delegated voting units.
    /// @dev This tracks delegated vote participation and is separate from tier reward eligibility.
    /// @return activeVotes The current total voting units delegated to nonzero delegates.
    function getTotalActiveVotes() external view override returns (uint256 activeVotes) {
        activeVotes = _activeSupplyCheckpoints.latest();
    }

    /// @notice The owner of an NFT at a past block.
    /// @dev Returns `address(0)` for tokens that have never been enrolled (via `delegate(address, uint256[])`) or
    /// transferred. Unenrolled tokens are ineligible for snapshot-based distribution.
    /// @param tokenId The token ID of the NFT to get the historical owner of.
    /// @param blockNumber The block number to look up.
    /// @return The owner of the token at `blockNumber`, or zero if the token is unenrolled or has no known owner.
    function ownerOfAt(uint256 tokenId, uint256 blockNumber) external view override returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint96 blockNumber96 = uint96(blockNumber);

        Checkpoints.Trace160 storage checkpoints = _ownerCheckpointsOf[tokenId];
        uint256 checkpointCount = checkpoints.length();

        // No checkpoints = not enrolled and never transferred. Not eligible.
        if (checkpointCount == 0) return address(0);

        // Query is before the first checkpoint — token not yet enrolled/transferred at this block.
        if (checkpoints.at(0)._key > blockNumber96) return address(0);

        return address(uint160(checkpoints.upperLookupRecent(blockNumber96)));
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Track active-supply changes when an account moves between undelegated and delegated states.
    function _delegate(address account, address delegatee) internal virtual override {
        address oldDelegate = delegates(account);
        uint256 votingUnits = _getVotingUnits(account);

        super._delegate({account: account, delegatee: delegatee});

        if (oldDelegate == address(0) && delegatee != address(0)) {
            _updateActiveVotes({amount: votingUnits, increase: true});
        } else if (oldDelegate != address(0) && delegatee == address(0)) {
            _updateActiveVotes({amount: votingUnits, increase: false});
        }
    }

    /// @notice Track active-supply changes when voting units move between delegated and undelegated accounts.
    function _transferVotingUnits(address from, address to, uint256 amount) internal virtual override {
        bool decreaseActiveVotes = from != address(0) && delegates(from) != address(0);
        bool increaseActiveVotes = to != address(0) && delegates(to) != address(0);

        super._transferVotingUnits({from: from, to: to, amount: amount});

        if (decreaseActiveVotes == increaseActiveVotes) return;
        _updateActiveVotes({amount: amount, increase: increaseActiveVotes});
    }

    //*********************************************************************//
    // ----------------------- internal views ---------------------------- //
    //*********************************************************************//

    /// @notice Returns the total voting units held by an account (across all tiers).
    /// @dev Called by OZ Votes when re-delegating to compute the account's total voting units.
    /// @param account The address to get the voting units of.
    /// @return The total voting units the account holds.
    function _getVotingUnits(address account) internal view override returns (uint256) {
        return STORE.votingUnitsOf({hook: hook, account: account});
    }

    //*********************************************************************//
    // ------------------------ private helpers -------------------------- //
    //*********************************************************************//

    /// @notice Update the checkpointed total of delegated voting units.
    /// @param amount The amount of voting units to add or remove.
    /// @param increase Whether to add `amount`; if false, `amount` is removed.
    function _updateActiveVotes(uint256 amount, bool increase) private {
        if (amount == 0) return;

        uint256 updated =
            increase ? _activeSupplyCheckpoints.latest() + amount : _activeSupplyCheckpoints.latest() - amount;

        _activeSupplyCheckpoints.push({key: clock(), value: SafeCast.toUint208(updated)});
    }

    /// @notice Add or remove units from a tier's eligible-voting-units checkpoint at the current block.
    /// @param tierId The tier whose eligible-voting-units trace to update.
    /// @param amount The voting units to add or remove.
    /// @param increase Whether to add `amount`; if false, `amount` is removed.
    function _updateTierEligibleUnits(uint256 tierId, uint256 amount, bool increase) private {
        Checkpoints.Trace160 storage trace = _tierEligibleUnitsOf[tierId];
        uint256 updated = increase ? trace.latest() + amount : trace.latest() - amount;
        // forge-lint: disable-next-line(unsafe-typecast)
        trace.push({key: uint96(block.number), value: uint160(updated)});
    }
}
