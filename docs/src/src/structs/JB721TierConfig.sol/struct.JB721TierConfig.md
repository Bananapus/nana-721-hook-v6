# JB721TierConfig
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JB721TierConfig.sol)

Config for a single NFT tier within a `JB721TiersHook`.

**Notes:**
- member: price The price to buy an NFT in this tier, in terms of the currency in its `JBInitTiersConfig`.

- member: initialSupply The total number of NFTs which can be minted from this tier.

- member: votingUnits The number of votes that each NFT in this tier gets if `useVotingUnits` is true.

- member: reserveFrequency The frequency at which an extra NFT is minted for the `reserveBeneficiary` from this
tier. With a `reserveFrequency` of 5, an extra NFT will be minted for the `reserveBeneficiary` for every 5 NFTs
purchased.

- member: reserveBeneficiary The address which receives any reserve NFTs from this tier. Overrides the default
reserve beneficiary if one is set.

- member: encodedIPFSUri The IPFS URI to use for each NFT in this tier.

- member: category The category that NFTs in this tier belongs to. Used to group NFT tiers.

- member: discountPercent The discount that should be applied to the tier.

- member: allowOwnerMint A boolean indicating whether the contract's owner can mint NFTs from this tier
on-demand.

- member: useReserveBeneficiaryAsDefault A boolean indicating whether this tier's `reserveBeneficiary` should
be stored as the default beneficiary for all tiers. WARNING: Setting this to `true` overwrites the global
`defaultReserveBeneficiaryOf` for the hook, which affects ALL existing tiers that do not have a tier-specific
reserve beneficiary. Use with caution when calling `adjustTiers` on hooks with existing tiers.

- member: transfersPausable A boolean indicating whether transfers for NFTs in tier can be paused.

- member: useVotingUnits A boolean indicating whether the `votingUnits` should be used to calculate voting
power. If `useVotingUnits` is false, voting power is based on the tier's price.

- member: cannotBeRemoved If the tier cannot be removed once added.

- member: cannotIncreaseDiscount If the tier cannot have its discount increased.

- member: splitPercent The percentage of the tier's price that gets routed to the tier's split group when
an NFT from this tier is minted. Out of `JBConstants.SPLITS_TOTAL_PERCENT`.

- member: splits The splits to use for this tier's split group. These define where the split portion of the
tier's price gets routed when an NFT from this tier is minted.


```solidity
struct JB721TierConfig {
uint104 price;
uint32 initialSupply;
uint32 votingUnits;
uint16 reserveFrequency;
address reserveBeneficiary;
// forge-lint: disable-next-line(mixed-case-variable)
bytes32 encodedIPFSUri;
uint24 category;
uint8 discountPercent;
bool allowOwnerMint;
bool useReserveBeneficiaryAsDefault;
bool transfersPausable;
bool useVotingUnits;
bool cannotBeRemoved;
bool cannotIncreaseDiscountPercent;
uint32 splitPercent;
JBSplit[] splits;
}
```

