// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice `JB721TiersHook` options packed into each ruleset's `JBRulesetMetadata.metadata`.
/// @custom:member pauseTransfers A boolean indicating whether NFT transfers are paused during this ruleset.
/// @custom:member pauseMintPendingReserves A boolean indicating whether pending/outstanding NFT reserves can be minted
/// during this ruleset.
struct JB721TiersRulesetMetadata {
    bool pauseTransfers;
    bool pauseMintPendingReserves;
}
