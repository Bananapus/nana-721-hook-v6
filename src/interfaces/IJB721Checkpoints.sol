// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IJB721TiersHookStore} from "./IJB721TiersHookStore.sol";

/// @notice A checkpoint module that provides IVotes-compatible checkpointed voting power for a JB721TiersHook.
/// @dev Deployed as a clone via JB721CheckpointsDeployer during hook initialization. One module per hook.
/// Pass this address to JBTokenDistributor as the IVotes token.
interface IJB721Checkpoints is IERC5805 {
    /// @notice Called by the hook after every NFT transfer to update checkpointed voting power.
    /// @dev Looks up the token's tier voting units from the store internally.
    /// Auto-self-delegates on first receive so checkpoints work without manual delegation.
    /// @param from The previous owner (address(0) on mint).
    /// @param to The new owner (address(0) on burn).
    /// @param tokenId The token ID being transferred (used to look up tier voting units).
    function onTransfer(address from, address to, uint256 tokenId) external;

    /// @notice Initializes a cloned module with its hook and store references.
    /// @dev Can only be called once. Called by the deployer after cloning.
    /// @param hook The hook this module serves.
    /// @param store The store that holds tier data for the hook's NFTs.
    function initialize(address hook, IJB721TiersHookStore store) external;

    /// @notice The hook that this module tracks voting power for.
    /// @return The hook address.
    // forge-lint: disable-next-line(mixed-case-function)
    function HOOK() external view returns (address);

    /// @notice The store that holds tier and voting data for the hook's NFTs.
    /// @return The store contract.
    // forge-lint: disable-next-line(mixed-case-function)
    function STORE() external view returns (IJB721TiersHookStore);
}
