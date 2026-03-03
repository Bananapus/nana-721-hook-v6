// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member price The price to buy an NFT in this tier, in terms of the currency in its `JBInitTiersConfig`.
/// @custom:member remainingSupply The remaining number of NFTs which can be minted from this tier.
/// @custom:member initialSupply The total number of NFTs which can be minted from this tier.
/// @custom:member votingUnits The number of votes that each NFT in this tier gets.
/// @custom:member category The category that NFTs in this tier belongs to. Used to group NFT tiers.
/// @custom:member discountPercent The discount that should be applied to the tier.
/// @custom:member reserveFrequency The frequency at which an extra NFT is minted for the `reserveBeneficiary` from this
/// tier. With a `reserveFrequency` of 5, an extra NFT will be minted for the `reserveBeneficiary` for every 5 NFTs
/// purchased.
/// @custom:member allowOwnerMint A boolean indicating whether the contract's owner can mint NFTs from this tier
/// on-demand.
/// @custom:member transfersPausable A boolean indicating whether transfers for NFTs in tier can be paused.
/// @custom:member useVotingUnits A boolean indicating whether the `votingUnits` should be used to calculate voting
/// power. If `useVotingUnits` is false, voting power is based on the tier's price.
/// @custom:member splitPercent The percentage of the tier's price that gets routed to the project's split group when
/// an NFT from this tier is minted. Out of `JBConstants.SPLITS_TOTAL_PERCENT`.
struct JBStored721Tier {
    uint104 price;
    uint32 remainingSupply;
    uint32 initialSupply;
    uint32 votingUnits;
    uint24 category;
    uint8 discountPercent;
    uint16 reserveFrequency;
    uint8 packedBools;
    uint32 splitPercent;
}
