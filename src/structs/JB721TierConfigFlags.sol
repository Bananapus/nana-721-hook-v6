// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member allowOwnerMint A boolean indicating whether the contract's owner can mint NFTs from this tier
/// on-demand.
/// @custom:member useReserveBeneficiaryAsDefault A boolean indicating whether this tier's `reserveBeneficiary` should
/// be stored as the default beneficiary for all tiers. WARNING: Setting this to `true` overwrites the global
/// `defaultReserveBeneficiaryOf` for the hook, which affects ALL existing tiers that do not have a tier-specific
/// reserve beneficiary. Use with caution when calling `adjustTiers` on hooks with existing tiers.
/// @custom:member transfersPausable A boolean indicating whether transfers for NFTs in this tier can be paused.
/// @custom:member useVotingUnits A boolean indicating whether the `votingUnits` should be used to calculate voting
/// power. If `useVotingUnits` is false, voting power is based on the tier's price.
/// @custom:member cantBeRemoved If the tier cannot be removed once added.
/// @custom:member cantIncreaseDiscountPercent If the tier cannot have its discount increased.
/// @custom:member cantBuyWithCredits If true, this tier cannot be purchased using accumulated pay credits. Only fresh
/// payment value counts toward this tier's price.
// forge-lint: disable-next-line(pascal-case-struct)
struct JB721TierConfigFlags {
    bool allowOwnerMint;
    bool useReserveBeneficiaryAsDefault;
    bool transfersPausable;
    bool useVotingUnits;
    bool cantBeRemoved;
    bool cantIncreaseDiscountPercent;
    bool cantBuyWithCredits;
}
