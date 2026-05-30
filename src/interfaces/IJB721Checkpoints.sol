// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IJB721TiersHookStore} from "./IJB721TiersHookStore.sol";

/// @notice A checkpoint module that provides IVotes-compatible checkpointed voting power for a JB721TiersHook.
/// @dev Deployed as a clone via JB721CheckpointsDeployer during hook initialization. One module per hook.
/// Pass this address to JBTokenDistributor as the IVotes token.
interface IJB721Checkpoints is IERC5805 {
    /// @notice The total eligible voting units of a tier at a past block.
    /// @dev "Eligible" means a token has an owner checkpoint: it was enrolled via `delegate(address,uint256[])` or
    /// transferred at least once. Minted-but-unenrolled tokens are excluded, mirroring `ownerOfAt` eligibility, and
    /// mints never write to this trace. Distributors use this as the denominator for tier-scoped reward pots.
    /// @param tierId The tier to get the eligible voting units of.
    /// @param blockNumber The block number to look up (must be strictly in the past).
    /// @return The tier's eligible voting units at `blockNumber`.
    function getPastTierVotingUnits(uint256 tierId, uint256 blockNumber) external view returns (uint256);

    /// @notice The hook that this module tracks voting power for.
    /// @return The hook address.
    // forge-lint: disable-next-line(mixed-case-function)
    function hook() external view returns (address);

    /// @notice The owner of an NFT at a past block.
    /// @dev Returns `address(0)` for tokens that have never been enrolled (via `delegate(address, uint256[])`) or
    /// transferred. Unenrolled tokens are ineligible for snapshot-based distribution.
    /// @param tokenId The token ID of the NFT to get the historical owner of.
    /// @param blockNumber The block number to look up.
    /// @return The owner of the token at `blockNumber`, or zero if the token is unenrolled or has no known owner.
    function ownerOfAt(uint256 tokenId, uint256 blockNumber) external view returns (address);

    /// @notice The store that holds tier and voting data for the hook's NFTs.
    /// @return The store contract.
    // forge-lint: disable-next-line(mixed-case-function)
    function STORE() external view returns (IJB721TiersHookStore);

    /// @notice Delegates voting power and enrolls tokens for distribution eligibility.
    /// @dev Writes per-token owner checkpoints so `ownerOfAt` can prove ownership at past blocks.
    /// Only the current token owner can enroll. Tokens without checkpoints are ineligible for snapshot-based
    /// distribution.
    /// @param delegatee The address to delegate voting power to. Use your own address for self-delegation.
    /// @param tokenIds The token IDs to enroll for distribution eligibility.
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
