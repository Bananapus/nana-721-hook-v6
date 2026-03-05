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
/// @custom:member packedBools A packed uint8 containing boolean flags: bit 0 = allowOwnerMint, bit 1 =
/// transfersPausable, bit 2 = useVotingUnits, bit 3 = cannotBeRemoved, bit 4 = cannotIncreaseDiscountPercent.
struct JBStored721Tier {
    uint104 price;
    uint32 remainingSupply;
    uint32 initialSupply;
    uint32 votingUnits;
    uint24 category;
    uint8 discountPercent;
    uint16 reserveFrequency;
    uint8 packedBools;
}
