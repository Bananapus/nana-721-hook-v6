// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member allowOwnerMint A boolean indicating whether the contract's owner can mint NFTs from this tier
/// on-demand.
/// @custom:member transfersPausable A boolean indicating whether transfers for NFTs in this tier can be paused.
/// @custom:member cantBeRemoved A boolean indicating whether attempts to remove this tier will revert.
/// @custom:member cantIncreaseDiscountPercent If the tier cannot have its discount increased.
/// @custom:member cantBuyWithCredits If true, this tier cannot be purchased using accumulated pay credits.
struct JB721TierFlags {
    bool allowOwnerMint;
    bool transfersPausable;
    bool cantBeRemoved;
    bool cantIncreaseDiscountPercent;
    bool cantBuyWithCredits;
}
