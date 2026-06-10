// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBActiveVotes} from "@bananapus/core-v6/src/interfaces/IJBActiveVotes.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";

import {JB721TierOwnerMatch} from "../enums/JB721TierOwnerMatch.sol";
import {IJB721TiersHookStore} from "./IJB721TiersHookStore.sol";

/// @notice A checkpoint module that provides IVotes-compatible checkpointed voting power for a JB721TiersHook.
/// @dev Deployed as a clone via JB721CheckpointsDeployer during hook initialization. One module per hook.
/// Pass this address to JBTokenDistributor as the IVotes token.
interface IJB721Checkpoints is IERC5805, IJBActiveVotes {
    /// @notice The store that holds tier and voting data for the hook's NFTs.
    /// @return store The store contract.
    // forge-lint: disable-next-line(mixed-case-function)
    function STORE() external view returns (IJB721TiersHookStore store);

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
        returns (uint256 activeVotes);

    /// @notice The total owner-checkpointed voting units of a tier at a past block.
    /// @dev Owner-checkpointed voting units are the tier's total owned units, regardless of delegation status.
    /// @param tierId The tier to get the owner-checkpointed voting units of.
    /// @param blockNumber The block number to look up (must be strictly in the past).
    /// @return votingUnits The tier's owner-checkpointed voting units at `blockNumber`.
    function getPastTierVotingUnits(uint256 tierId, uint256 blockNumber) external view returns (uint256 votingUnits);

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
        returns (uint256 activeVotes);

    /// @notice The current total delegated voting units of a tier.
    /// @param tierId The tier to get the current delegated voting units of.
    /// @return activeVotes The tier's current delegated voting units.
    function getTotalTierActiveVotes(uint256 tierId) external view returns (uint256 activeVotes);

    /// @notice Whether an owner held any or all of the provided tier IDs at a block.
    /// @dev Empty arrays return `false`. `blockNumber` may be the current block, but not a future block.
    /// @param account The account to check.
    /// @param tierIds The tier IDs to check.
    /// @param matchMode Whether to require any or all tier IDs to be held.
    /// @param blockNumber The block number to look up.
    /// @return hasTiers Whether the owner satisfies the requested tier match at `blockNumber`.
    function hasTiersOfAt(
        address account,
        uint256[] calldata tierIds,
        JB721TierOwnerMatch matchMode,
        uint256 blockNumber
    )
        external
        view
        returns (bool hasTiers);

    /// @notice The hook that this module tracks voting power for.
    /// @return hookAddress The hook address.
    // forge-lint: disable-next-line(mixed-case-function)
    function hook() external view returns (address hookAddress);

    /// @notice The owner of an NFT at a current or past block.
    /// @dev Returns `address(0)` if no ownership checkpoint exists or the query predates the first checkpoint.
    /// @param tokenId The token ID of the NFT to get the historical owner of.
    /// @param blockNumber The current or past block number to look up.
    /// @return owner The owner of the token at `blockNumber`, or zero if no owner is proven at that block.
    function ownerOfAt(uint256 tokenId, uint256 blockNumber) external view returns (address owner);

    /// @notice Delegates voting power and backfills ownership history for listed tokens if needed.
    /// @dev Mint and transfer hooks normally write owner checkpoints automatically. The token ID list keeps
    /// pre-upgrade or otherwise uncheckpointed tokens recoverable while preserving the owner-only authorization check.
    /// @param delegatee The address to delegate voting power to. Use your own address for self-delegation.
    /// @param tokenIds The token IDs whose owner checkpoints should be backfilled if missing.
    function delegate(address delegatee, uint256[] calldata tokenIds) external;

    /// @notice Initializes a cloned module with its hook reference.
    /// @dev Can only be called once. Called by the deployer after cloning.
    /// @param hookAddress The hook this module serves.
    function initialize(address hookAddress) external;

    /// @notice Called by the hook after every NFT transfer to update checkpointed voting power.
    /// @dev Looks up the token's tier voting units from the store internally.
    /// @param from The previous owner (address(0) on mint).
    /// @param to The new owner (address(0) on burn).
    /// @param tokenId The token ID to transfer (used to look up tier voting units).
    function onTransfer(address from, address to, uint256 tokenId) external;
}
