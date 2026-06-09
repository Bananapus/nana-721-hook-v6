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

    /// @notice Thrown when the caller tries to backfill a token they do not currently own.
    error JB721Checkpoints_NotOwner(uint256 tokenId, address caller);

    /// @notice Thrown when a hook-only function is called by an address other than the module's hook.
    error JB721Checkpoints_Unauthorized(address caller, address hook);

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The store that holds tier and voting data for the hook's NFTs.
    /// @dev All tier lookups are scoped by `hook`; this immutable only identifies the shared store contract.
    IJB721TiersHookStore public immutable override STORE;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The hook that this module tracks voting power for.
    /// @dev Clones set this once in `initialize`; the implementation uses `address(1)` as a locked sentinel.
    address public override hook;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice Checkpointed active voting units per account and tier.
    /// @dev Maintained only for units held by accounts with nonzero delegates. Undelegated custody is not checkpointed
    /// in this trace because those units are inactive for active-vote reward accounting.
    /// @custom:param account The account to get historical active tier voting units for.
    /// @custom:param tierId The tier to get historical active voting units for.
    mapping(address account => mapping(uint256 tierId => Checkpoints.Trace160)) internal _accountTierActiveVotesOf;

    /// @notice Checkpointed token owners for historical reward eligibility.
    /// @dev Mint and transfer hooks write this automatically; `delegate` only backfills missing pre-upgrade history.
    /// @custom:param tokenId The token ID to get historical owner checkpoints for.
    mapping(uint256 tokenId => Checkpoints.Trace160) internal _ownerCheckpointsOf;

    /// @notice Checkpointed total active voting units per tier.
    /// @dev Maintained when delegation changes activate/deactivate all of an account's tier units, and when transfers
    /// move one token's tier units between delegated and undelegated custody.
    /// @custom:param tierId The tier to get the historical delegated voting units for.
    mapping(uint256 tierId => Checkpoints.Trace160) internal _tierActiveSupplyCheckpointsOf;

    /// @notice Checkpointed total owner-tracked voting units per tier.
    /// @dev Increased on mint or backfill and decreased on burn. Transfers keep the total unchanged because the token
    /// still has a nonzero owner.
    /// @custom:param tierId The tier to get the historical owner-tracked voting units for.
    mapping(uint256 tierId => Checkpoints.Trace160) internal _tierEligibleUnitsOf;

    //*********************************************************************//
    // -------------------- private stored properties -------------------- //
    //*********************************************************************//

    /// @notice Checkpointed total voting units held by accounts with nonzero delegates.
    /// @dev Maintained by `_delegate` and `_transferVotingUnits` using the same clock as OZ `Votes`.
    Checkpoints.Trace208 private _activeSupplyCheckpoints;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @notice Initializes the checkpoint implementation and locks it against direct use.
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

    /// @notice Delegates voting power and backfills ownership history for listed tokens if needed.
    /// @dev Mint and transfer hooks normally write owner checkpoints automatically. The token ID list keeps
    /// pre-upgrade or otherwise uncheckpointed tokens recoverable while preserving the owner-only authorization check.
    /// @param delegatee The address to delegate voting power to. Use your own address for self-delegation.
    /// @param tokenIds The token IDs whose owner checkpoints should be backfilled if missing.
    function delegate(address delegatee, uint256[] calldata tokenIds) external override {
        // Delegate voting power (reuses OZ Votes internals).
        _delegate({account: msg.sender, delegatee: delegatee});

        // Write any missing per-token owner checkpoints for historical reward eligibility.
        for (uint256 i; i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];

            // Only the current owner can backfill their token's ownership checkpoint.
            if (IERC721(hook).ownerOf(tokenId) != msg.sender) {
                revert JB721Checkpoints_NotOwner({tokenId: tokenId, caller: msg.sender});
            }

            // Write an owner checkpoint if the token has none yet, and track its tier voting units.
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
        // No caller check is needed (and there is none): `JB721CheckpointsDeployer.deploy` creates this clone with
        // the hook as the CREATE2 salt and calls `initialize(hook)` atomically in the same call, so a clone can only
        // ever be bound to its salt-designated hook and there is no front-run window between cloning and init. The
        // implementation itself is locked against direct use by the `address(1)` sentinel set in its constructor.
        hook = hookAddress;
    }

    /// @notice Called by the hook after every NFT transfer to update checkpointed voting power.
    /// @dev Only callable by the hook. Looks up the token's tier voting units from the store.
    /// @param from The previous owner (address(0) on mint).
    /// @param to The new owner (address(0) on burn).
    /// @param tokenId The token ID to transfer.
    function onTransfer(address from, address to, uint256 tokenId) external override {
        if (msg.sender != hook) revert JB721Checkpoints_Unauthorized({caller: msg.sender, hook: hook});

        // Look up this token's tier ID and voting units once; both the owner and active traces need them.
        uint256 tierId = STORE.tierIdOfToken(tokenId);

        // Look up this token's tier voting units (lightweight getter — avoids full tier struct construction).
        uint256 votingUnits = STORE.tierVotingUnitsOfTokenId({hook: hook, tokenId: tokenId});

        // Keep a reference to the token's historical owner trace.
        Checkpoints.Trace160 storage ownerTrace = _ownerCheckpointsOf[tokenId];

        // Existing deployments may have tokens that predate mint checkpointing; detect the first written owner.
        bool wasEligible = ownerTrace.length() != 0;

        // Mints, transfers, and burns all write ownership history so reward claims can prove snapshot ownership.
        if (to != address(0) || from != address(0)) {
            // forge-lint: disable-next-line(unsafe-typecast)
            ownerTrace.push({key: uint96(block.number), value: uint160(to)});
        }

        if (from == address(0) && to != address(0)) {
            // Mint: add the token's tier units to the owner-tracked tier supply.
            _updateTierEligibleUnits({tierId: tierId, amount: votingUnits, increase: true});
        } else if (to == address(0)) {
            // Burn: remove the tier's units only if the token was already part of the owner-tracked supply.
            if (wasEligible) {
                _updateTierEligibleUnits({tierId: tierId, amount: votingUnits, increase: false});
            }
        } else if (!wasEligible) {
            // First transfer of a pre-upgrade uncheckpointed token makes its ownership history trackable.
            _updateTierEligibleUnits({tierId: tierId, amount: votingUnits, increase: true});
        }

        // The tier active total decreases if units leave an account that already has a nonzero delegate.
        bool decreaseTierActiveVotes = from != address(0) && delegates(from) != address(0);

        // The tier active total increases if units arrive at an account that already has a nonzero delegate.
        bool increaseTierActiveVotes = to != address(0) && delegates(to) != address(0);

        // Move checkpointed voting power from the previous owner to the new owner.
        _transferVotingUnits({from: from, to: to, amount: votingUnits});

        // If the sender was delegated, remove this token's tier units from the sender's active tier balance.
        if (decreaseTierActiveVotes) {
            _adjustAccountTierActiveVotes({account: from, tierId: tierId, amount: votingUnits, increase: false});
        }

        // If the receiver is delegated, add this token's tier units to the receiver's active tier balance.
        if (increaseTierActiveVotes) {
            _adjustAccountTierActiveVotes({account: to, tierId: tierId, amount: votingUnits, increase: true});
        }

        // If both sides are delegated or both sides are undelegated, this tier's active total is unchanged.
        if (decreaseTierActiveVotes != increaseTierActiveVotes) {
            // Otherwise apply the one-sided active-tier delta implied by the receiver's delegated status.
            _adjustTotalTierActiveVotes({tierId: tierId, amount: votingUnits, increase: increaseTierActiveVotes});
        }
    }

    //*********************************************************************//
    // ----------------------- external views ---------------------------- //
    //*********************************************************************//

    /// @notice The delegated voting units held by an account in a tier at a past block.
    /// @dev Counts only tier voting units held by `account` while `account` had a nonzero delegate.
    /// @param account The account to get the delegated tier voting units of.
    /// @param tierId The tier to get the delegated voting units of.
    /// @param blockNumber The past block number to look up.
    /// @return activeVotes The account's delegated tier voting units at `blockNumber`.
    function getPastAccountTierActiveVotes(
        address account,
        uint256 tierId,
        uint256 blockNumber
    )
        external
        view
        override
        returns (uint256 activeVotes)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        activeVotes =
            _accountTierActiveVotesOf[account][tierId].upperLookupRecent(uint96(_validateTimepoint(blockNumber)));
    }

    /// @notice The total owner-checkpointed voting units of a tier at a past block.
    /// @param tierId The tier to get the owner-checkpointed voting units of.
    /// @param blockNumber The block number to look up (must be strictly in the past).
    /// @return votingUnits The tier's owner-checkpointed voting units at `blockNumber`.
    function getPastTierVotingUnits(
        uint256 tierId,
        uint256 blockNumber
    )
        external
        view
        override
        returns (uint256 votingUnits)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        votingUnits = _tierEligibleUnitsOf[tierId].upperLookupRecent(uint96(_validateTimepoint(blockNumber)));
    }

    /// @notice The total delegated voting units at a past block.
    /// @dev This tracks delegated vote participation and is separate from tier reward eligibility.
    /// @param blockNumber The past block number to look up.
    /// @return activeVotes The total voting units delegated to nonzero delegates at `blockNumber`.
    function getPastTotalActiveVotes(uint256 blockNumber) external view override returns (uint256 activeVotes) {
        activeVotes = _activeSupplyCheckpoints.upperLookupRecent(_validateTimepoint(blockNumber));
    }

    /// @notice The total delegated voting units of a tier at a past block.
    /// @dev Counts only tier voting units held by accounts with a nonzero delegate.
    /// @param tierId The tier to get the delegated voting units of.
    /// @param blockNumber The past block number to look up.
    /// @return activeVotes The tier's delegated voting units at `blockNumber`.
    function getPastTotalTierActiveVotes(
        uint256 tierId,
        uint256 blockNumber
    )
        external
        view
        override
        returns (uint256 activeVotes)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        activeVotes = _tierActiveSupplyCheckpointsOf[tierId].upperLookupRecent(uint96(_validateTimepoint(blockNumber)));
    }

    /// @notice The current total delegated voting units.
    /// @dev This tracks delegated vote participation and is separate from tier reward eligibility.
    /// @return activeVotes The current total voting units delegated to nonzero delegates.
    function getTotalActiveVotes() external view override returns (uint256 activeVotes) {
        activeVotes = _activeSupplyCheckpoints.latest();
    }

    /// @notice The current total delegated voting units of a tier.
    /// @param tierId The tier to get the current delegated voting units of.
    /// @return activeVotes The tier's current delegated voting units.
    function getTotalTierActiveVotes(uint256 tierId) external view override returns (uint256 activeVotes) {
        activeVotes = _tierActiveSupplyCheckpointsOf[tierId].latest();
    }

    /// @notice The owner of an NFT at a past block.
    /// @dev Returns `address(0)` if no ownership checkpoint exists or the query predates the first checkpoint.
    /// @param tokenId The token ID of the NFT to get the historical owner of.
    /// @param blockNumber The block number to look up.
    /// @return owner The owner of the token at `blockNumber`, or zero if no owner is proven at that block.
    function ownerOfAt(uint256 tokenId, uint256 blockNumber) external view override returns (address owner) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint96 blockNumber96 = uint96(blockNumber);

        Checkpoints.Trace160 storage checkpoints = _ownerCheckpointsOf[tokenId];
        uint256 checkpointCount = checkpoints.length();

        // No checkpoints means no historical owner can be proven for this token.
        if (checkpointCount == 0) return address(0);

        // Query is before the first checkpoint, so this token had no proven owner at that block.
        if (checkpoints.at(0)._key > blockNumber96) return address(0);

        return address(uint160(checkpoints.upperLookupRecent(blockNumber96)));
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Track active-vote-total changes when an account changes its delegate.
    /// @dev Delegating to a nonzero address makes all of `account`'s voting units active. Clearing delegation removes
    /// all of `account`'s voting units from the active total. Redelegating between two nonzero delegates only moves
    /// votes inside OZ `Votes`, so the active total does not change.
    /// @param account The account whose delegation is changing.
    /// @param delegatee The new delegate. Use `address(0)` to clear delegation.
    function _delegate(address account, address delegatee) internal virtual override {
        // Read the current delegate before OZ mutates the delegate mapping.
        address oldDelegate = delegates(account);

        // Read the account's current voting units so any active-total delta matches the units OZ moves.
        uint256 votingUnits = _getVotingUnits(account);

        // Let OZ update the delegate mapping and the per-delegate vote checkpoints.
        super._delegate({account: account, delegatee: delegatee});

        // If the account had no delegate and now has one, its voting units just became active.
        if (oldDelegate == address(0) && delegatee != address(0)) {
            // Add the account's voting units to the checkpointed active total.
            _updateActiveVotes({amount: votingUnits, increase: true});

            // Add the account's voting units to each tier-level active total it currently contributes to.
            _applyAccountDelegationToTierActiveVotes({account: account, increase: true});
        } else if (oldDelegate != address(0) && delegatee == address(0)) {
            // If the account had a delegate and now has none, its voting units just became inactive.
            _updateActiveVotes({amount: votingUnits, increase: false});

            // Remove the account's voting units from each tier-level active total it currently contributes to.
            _applyAccountDelegationToTierActiveVotes({account: account, increase: false});
        }
    }

    /// @notice Track active-vote-total changes when voting units move between accounts.
    /// @dev Moving voting units between two accounts with the same delegation status does not change the active total.
    /// Moving voting units out of a delegated account and into an undelegated account decreases the active total, while
    /// moving voting units out of an undelegated account and into a delegated account increases it.
    /// @param from The account whose voting units are leaving. `address(0)` means the units are being minted.
    /// @param to The account whose voting units are arriving. `address(0)` means the units are being burned.
    /// @param amount The voting units moving between `from` and `to`.
    function _transferVotingUnits(address from, address to, uint256 amount) internal virtual override {
        // The active total decreases if units leave an account that already has a nonzero delegate.
        bool decreaseActiveVotes = from != address(0) && delegates(from) != address(0);

        // The active total increases if units arrive at an account that already has a nonzero delegate.
        bool increaseActiveVotes = to != address(0) && delegates(to) != address(0);

        // Let OZ update total voting-unit supply and per-delegate checkpoints first.
        super._transferVotingUnits({from: from, to: to, amount: amount});

        // If both sides are delegated or both sides are undelegated, the active total is unchanged.
        if (decreaseActiveVotes == increaseActiveVotes) return;

        // Otherwise apply the one-sided active-total delta implied by the receiver's delegated status.
        _updateActiveVotes({amount: amount, increase: increaseActiveVotes});
    }

    //*********************************************************************//
    // ----------------------- internal views ---------------------------- //
    //*********************************************************************//

    /// @notice Returns the total voting units held by an account (across all tiers).
    /// @dev Called by OZ Votes when re-delegating to compute the account's total voting units.
    /// @param account The address to get the voting units of.
    /// @return votingUnits The total voting units the account holds.
    function _getVotingUnits(address account) internal view override returns (uint256 votingUnits) {
        return STORE.votingUnitsOf({hook: hook, account: account});
    }

    //*********************************************************************//
    // ------------------------ private helpers -------------------------- //
    //*********************************************************************//

    /// @notice Add or remove units from an account's active-voting-units checkpoint for a tier at the current block.
    /// @param account The account whose active-voting-units trace should be updated.
    /// @param tierId The tier whose active-voting-units trace should be updated.
    /// @param amount The voting units to add or remove.
    /// @param increase Whether to add `amount`; if false, `amount` is removed.
    function _adjustAccountTierActiveVotes(address account, uint256 tierId, uint256 amount, bool increase) private {
        // Ignore zero-unit updates because they do not change the account's active tier total.
        if (amount == 0) return;

        // Keep a reference to the account's active-voting-units trace for this tier.
        Checkpoints.Trace160 storage trace = _accountTierActiveVotesOf[account][tierId];

        // Calculate the next account-tier active total from its latest checkpointed value.
        uint256 updated = increase ? trace.latest() + amount : trace.latest() - amount;

        // Write the new account-tier active total at the current block.
        // forge-lint: disable-next-line(unsafe-typecast)
        trace.push({key: uint96(block.number), value: uint160(updated)});
    }

    /// @notice Add or remove units from a tier's active-voting-units checkpoint at the current block.
    /// @param tierId The tier whose active-voting-units trace to update.
    /// @param amount The voting units to add or remove.
    /// @param increase Whether to add `amount`; if false, `amount` is removed.
    function _adjustTotalTierActiveVotes(uint256 tierId, uint256 amount, bool increase) private {
        // Ignore zero-unit updates because they do not change this tier's active total.
        if (amount == 0) return;

        // Keep a reference to the tier's active-voting-units trace.
        Checkpoints.Trace160 storage trace = _tierActiveSupplyCheckpointsOf[tierId];

        // Calculate the next tier active total by adding or subtracting from the latest checkpointed value.
        uint256 updated = increase ? trace.latest() + amount : trace.latest() - amount;

        // Write the new tier active total at the current block.
        // forge-lint: disable-next-line(unsafe-typecast)
        trace.push({key: uint96(block.number), value: uint160(updated)});
    }

    /// @notice Apply an account delegation change to every tier-level active total the account contributes to.
    /// @dev Delegation is account-wide in OZ Votes, so changing an account's delegate activates or deactivates every
    /// tier balance currently held by the account. Transfer hooks handle one-token tier deltas separately.
    /// @param account The account whose tier voting units should be added or removed.
    /// @param increase Whether to add `account`'s tier voting units; if false, they are removed.
    function _applyAccountDelegationToTierActiveVotes(address account, bool increase) private {
        // Read the largest tier ID once; tier IDs are sequential and 1-indexed for each hook.
        uint256 tierId = STORE.maxTierIdOf(hook);

        // Walk each tier from max to 1 so empty hooks skip cleanly when maxTierId is zero.
        while (tierId != 0) {
            // Read only this account's units for the tier; empty tiers return zero and are ignored below.
            uint256 tierVotingUnits = STORE.tierVotingUnitsOf({hook: hook, account: account, tierId: tierId});

            // Only write checkpoints for tiers whose active totals actually change.
            if (tierVotingUnits != 0) {
                _adjustTotalTierActiveVotes({tierId: tierId, amount: tierVotingUnits, increase: increase});
                _adjustAccountTierActiveVotes({
                    account: account, tierId: tierId, amount: tierVotingUnits, increase: increase
                });
            }

            unchecked {
                // The loop condition proves tierId is nonzero, so the decrement cannot underflow.
                --tierId;
            }
        }
    }

    /// @notice Update the checkpointed total of delegated voting units.
    /// @dev Writes at most one active-total checkpoint at the current OZ clock. A zero amount is ignored so zero-value
    /// delegation or transfer hooks do not create empty checkpoints.
    /// @param amount The amount of voting units to add or remove.
    /// @param increase Whether to add `amount`; if false, `amount` is removed.
    function _updateActiveVotes(uint256 amount, bool increase) private {
        // Ignore zero-unit updates because they do not change the active total.
        if (amount == 0) return;

        // Calculate the next active total by adding or subtracting from the latest checkpointed value.
        uint256 updated =
            increase ? _activeSupplyCheckpoints.latest() + amount : _activeSupplyCheckpoints.latest() - amount;

        // Write the new active total at the current ERC-6372 clock using the same uint208 width as OZ `Votes`.
        _activeSupplyCheckpoints.push({key: clock(), value: SafeCast.toUint208(updated)});
    }

    /// @notice Add or remove units from a tier's owner-tracked voting-units checkpoint at the current block.
    /// @param tierId The tier whose owner-tracked voting-units trace to update.
    /// @param amount The voting units to add or remove.
    /// @param increase Whether to add `amount`; if false, `amount` is removed.
    function _updateTierEligibleUnits(uint256 tierId, uint256 amount, bool increase) private {
        // Ignore zero-unit updates because they do not change this tier's owner-tracked total.
        if (amount == 0) return;

        // Keep a reference to the tier's owner-tracked voting-units trace.
        Checkpoints.Trace160 storage trace = _tierEligibleUnitsOf[tierId];

        // Calculate the next owner-tracked total by adding or subtracting from the latest checkpointed value.
        uint256 updated = increase ? trace.latest() + amount : trace.latest() - amount;

        // Write the new owner-tracked total at the current block.
        // forge-lint: disable-next-line(unsafe-typecast)
        trace.push({key: uint96(block.number), value: uint160(updated)});
    }
}
