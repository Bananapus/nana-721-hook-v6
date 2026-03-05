// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {JB721TiersRulesetMetadata} from "../structs/JB721TiersRulesetMetadata.sol";

/// @title JB721TiersRulesetMetadataResolver
/// @notice Utility library to parse and store ruleset metadata associated for the tiered 721 hook.
/// @dev This library parses the `metadata` member of the `JBRulesetMetadata` struct.
library JB721TiersRulesetMetadataResolver {
    /// @notice Check whether transfers are paused based on the packed ruleset metadata.
    /// @param data The packed metadata to check.
    /// @return Whether transfers are paused (bit 0).
    function transfersPaused(uint256 data) internal pure returns (bool) {
        return (data & 1) == 1;
    }

    /// @notice Check whether minting pending reserves is paused based on the packed ruleset metadata.
    /// @param data The packed metadata to check.
    /// @return Whether minting pending reserves is paused (bit 1).
    function mintPendingReservesPaused(uint256 data) internal pure returns (bool) {
        return ((data >> 1) & 1) == 1;
    }

    /// @notice Pack the ruleset metadata for the 721 hook into a single `uint256`.
    /// @param metadata The metadata to validate and pack.
    /// @return packed A `uint256` containing the packed metadata for the 721 hook.
    function pack721TiersRulesetMetadata(JB721TiersRulesetMetadata memory metadata)
        internal
        pure
        returns (uint256 packed)
    {
        // pause transfers in bit 0.
        if (metadata.pauseTransfers) packed |= 1;
        // pause mint reserves in bit 1.
        if (metadata.pauseMintPendingReserves) packed |= 1 << 1;
    }

    /// @notice Expand packed ruleset metadata for the 721 hook.
    /// @param packedMetadata The packed metadata to expand.
    /// @return metadata The metadata as a `JB721TiersRulesetMetadata` struct.
    function expandMetadata(uint16 packedMetadata) internal pure returns (JB721TiersRulesetMetadata memory metadata) {
        return JB721TiersRulesetMetadata(transfersPaused(packedMetadata), mintPendingReservesPaused(packedMetadata));
    }
}
