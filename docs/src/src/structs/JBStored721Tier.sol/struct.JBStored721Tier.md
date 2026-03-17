# JBStored721Tier
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JBStored721Tier.sol)

**Notes:**
- member: price The price to buy an NFT in this tier, in terms of the currency in its `JBInitTiersConfig`.

- member: remainingSupply The remaining number of NFTs which can be minted from this tier.

- member: initialSupply The total number of NFTs which can be minted from this tier.

- member: splitPercent The percentage of the tier's price that gets routed to the tier's split group when
an NFT from this tier is minted. Out of `JBConstants.SPLITS_TOTAL_PERCENT`.

- member: category The category that NFTs in this tier belongs to. Used to group NFT tiers.

- member: discountPercent The discount that should be applied to the tier.

- member: reserveFrequency The frequency at which an extra NFT is minted for the `reserveBeneficiary` from this
tier. With a `reserveFrequency` of 5, an extra NFT will be minted for the `reserveBeneficiary` for every 5 NFTs
purchased.

- member: packedBools Packed boolean flags: allowOwnerMint, transfersPausable, useVotingUnits,
cannotBeRemoved, cannotIncreaseDiscountPercent.


```solidity
struct JBStored721Tier {
uint104 price;
uint32 remainingSupply;
uint32 initialSupply;
uint32 splitPercent;
uint24 category;
uint8 discountPercent;
uint16 reserveFrequency;
uint8 packedBools;
}
```

