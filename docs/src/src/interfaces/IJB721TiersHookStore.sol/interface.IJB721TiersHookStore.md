# IJB721TiersHookStore
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/interfaces/IJB721TiersHookStore.sol)

Stores and manages data for 721 tiers hooks.


## Functions
### balanceOf

Get the number of NFTs that the specified address owns from the specified 721 contract.


```solidity
function balanceOf(address hook, address owner) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the balance within.|
|`owner`|`address`|The address to check the balance of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The number of NFTs the owner has from the 721 contract.|


### cashOutWeightOf

The combined cash out weight of the NFTs with the provided token IDs.


```solidity
function cashOutWeightOf(address hook, uint256[] calldata tokenIds) external view returns (uint256 weight);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract that the NFTs belong to.|
|`tokenIds`|`uint256[]`|The token IDs of the NFTs to get the cash out weight of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|The cash out weight.|


### defaultReserveBeneficiaryOf

The default reserve beneficiary for the provided 721 contract.


```solidity
function defaultReserveBeneficiaryOf(address hook) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the default reserve beneficiary of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The default reserve beneficiary address.|


### encodedIPFSUriOf

The encoded IPFS URI for the provided tier ID of the provided 721 contract.


```solidity
function encodedIPFSUriOf(address hook, uint256 tierId) external view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract that the tier belongs to.|
|`tierId`|`uint256`|The ID of the tier to get the encoded IPFS URI of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The encoded IPFS URI.|


### encodedTierIPFSUriOf

The encoded IPFS URI for the tier of the 721 with the provided token ID.


```solidity
function encodedTierIPFSUriOf(address hook, uint256 tokenId) external view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract that the encoded IPFS URI belongs to.|
|`tokenId`|`uint256`|The token ID of the 721 to get the encoded tier IPFS URI of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The encoded IPFS URI.|


### flagsOf

Get the flags that dictate the behavior of the provided 721 contract.


```solidity
function flagsOf(address hook) external view returns (JB721TiersHookFlags memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the flags of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`JB721TiersHookFlags`|The flags.|


### isTierRemoved

Check if the provided tier has been removed from the provided 721 contract.


```solidity
function isTierRemoved(address hook, uint256 tierId) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract the tier belongs to.|
|`tierId`|`uint256`|The ID of the tier to check the removal status of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the tier has been removed.|


### maxTierIdOf

The largest tier ID currently used on the provided 721 contract.


```solidity
function maxTierIdOf(address hook) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the largest tier ID from.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The largest tier ID.|


### numberOfBurnedFor

The number of NFTs which have been burned from the provided tier ID.


```solidity
function numberOfBurnedFor(address hook, uint256 tierId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract that the tier belongs to.|
|`tierId`|`uint256`|The ID of the tier to get the burn count of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The number of burned NFTs.|


### numberOfPendingReservesFor

The number of pending reserve NFTs for the provided tier ID.


```solidity
function numberOfPendingReservesFor(address hook, uint256 tierId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to check for pending reserved NFTs.|
|`tierId`|`uint256`|The ID of the tier to get the number of pending reserves for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The number of pending reserved NFTs.|


### numberOfReservesMintedFor

The number of reserve NFTs which have been minted from the provided tier ID.


```solidity
function numberOfReservesMintedFor(address hook, uint256 tierId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract that the tier belongs to.|
|`tierId`|`uint256`|The ID of the tier to get the reserve mint count of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The number of reserve NFTs minted.|


### reserveBeneficiaryOf

The reserve beneficiary for the provided tier ID on the provided 721 contract.


```solidity
function reserveBeneficiaryOf(address hook, uint256 tierId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract that the tier belongs to.|
|`tierId`|`uint256`|The ID of the tier to get the reserve beneficiary of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The reserve beneficiary address.|


### tierBalanceOf

The number of NFTs the provided owner address owns from the provided tier.


```solidity
function tierBalanceOf(address hook, address owner, uint256 tierId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the balance from.|
|`owner`|`address`|The address to get the tier balance of.|
|`tierId`|`uint256`|The ID of the tier to get the balance for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The tier balance.|


### tierIdOfToken

The tier ID for the 721 with the provided token ID.


```solidity
function tierIdOfToken(uint256 tokenId) external pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The token ID of the 721 to get the tier ID of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The tier ID.|


### tierOf

Get the tier with the provided ID from the provided 721 contract.


```solidity
function tierOf(address hook, uint256 id, bool includeResolvedUri) external view returns (JB721Tier memory tier);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the tier from.|
|`id`|`uint256`|The ID of the tier to get.|
|`includeResolvedUri`|`bool`|If `true`, the resolved token URI will be included.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tier`|`JB721Tier`|The tier.|


### tierOfTokenId

Get the tier of the 721 with the provided token ID.


```solidity
function tierOfTokenId(
    address hook,
    uint256 tokenId,
    bool includeResolvedUri
)
    external
    view
    returns (JB721Tier memory tier);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract that the tier belongs to.|
|`tokenId`|`uint256`|The token ID of the 721 to get the tier of.|
|`includeResolvedUri`|`bool`|If `true`, the resolved token URI will be included.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tier`|`JB721Tier`|The tier.|


### tiersOf

Get an array of currently active 721 tiers for the provided 721 contract.


```solidity
function tiersOf(
    address hook,
    uint256[] calldata categories,
    bool includeResolvedUri,
    uint256 startingId,
    uint256 size
)
    external
    view
    returns (JB721Tier[] memory tiers);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the tiers of.|
|`categories`|`uint256[]`|An array of tier categories to get tiers from. Empty for all categories.|
|`includeResolvedUri`|`bool`|If `true`, the resolved token URIs will be included.|
|`startingId`|`uint256`|The ID of the first tier to get. Send 0 to get all active tiers.|
|`size`|`uint256`|The number of tiers to include.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tiers`|`JB721Tier[]`|An array of active 721 tiers.|


### tierVotingUnitsOf

The number of voting units an address has within the specified tier.


```solidity
function tierVotingUnitsOf(address hook, address account, uint256 tierId) external view returns (uint256 units);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract that the tier belongs to.|
|`account`|`address`|The address to get the voting units of within the tier.|
|`tierId`|`uint256`|The ID of the tier to get voting units within.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`units`|`uint256`|The voting units.|


### tokenUriResolverOf

The custom token URI resolver for the provided 721 contract.


```solidity
function tokenUriResolverOf(address hook) external view returns (IJB721TokenUriResolver);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the custom token URI resolver of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IJB721TokenUriResolver`|The token URI resolver.|


### totalCashOutWeight

The combined cash out weight for all NFTs from the provided 721 contract.


```solidity
function totalCashOutWeight(address hook) external view returns (uint256 weight);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the total cash out weight of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|The total cash out weight.|


### totalSupplyOf

The total number of NFTs minted from the provided 721 contract.


```solidity
function totalSupplyOf(address hook) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get a total supply of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total supply.|


### votingUnitsOf

The total number of voting units an address has for the provided 721 contract.


```solidity
function votingUnitsOf(address hook, address account) external view returns (uint256 units);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to get the voting units within.|
|`account`|`address`|The address to get the voting unit total of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`units`|`uint256`|The total voting units.|


### cleanTiers

Clean removed tiers from the tier sorting sequence.


```solidity
function cleanTiers(address hook) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract to clean tiers for.|


### recordAddTiers

Record newly added tiers.


```solidity
function recordAddTiers(JB721TierConfig[] calldata tiersToAdd) external returns (uint256[] memory tierIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tiersToAdd`|`JB721TierConfig[]`|The tiers to add.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tierIds`|`uint256[]`|The IDs of the tiers being added.|


### recordBurn

Record 721 burns.


```solidity
function recordBurn(uint256[] calldata tokenIds) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|The token IDs of the NFTs to burn.|


### recordFlags

Record newly set flags.


```solidity
function recordFlags(JB721TiersHookFlags calldata flags) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`flags`|`JB721TiersHookFlags`|The flags to set.|


### recordMint

Record 721 mints from the provided tiers.


```solidity
function recordMint(
    uint256 amount,
    uint16[] calldata tierIds,
    bool isOwnerMint
)
    external
    returns (uint256[] memory tokenIds, uint256 leftoverAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The amount being spent on NFTs.|
|`tierIds`|`uint16[]`|The IDs of the tiers to mint from.|
|`isOwnerMint`|`bool`|Whether this is a direct owner mint.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|The token IDs of the NFTs which were minted.|
|`leftoverAmount`|`uint256`|The amount remaining after minting.|


### recordMintReservesFor

Record reserve 721 minting for the provided tier ID.


```solidity
function recordMintReservesFor(uint256 tierId, uint256 count) external returns (uint256[] memory tokenIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier to mint reserves from.|
|`count`|`uint256`|The number of reserve NFTs to mint.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|The token IDs of the reserve NFTs which were minted.|


### recordRemoveTierIds

Record tiers being removed.


```solidity
function recordRemoveTierIds(uint256[] calldata tierIds) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierIds`|`uint256[]`|The IDs of the tiers being removed.|


### recordSetDiscountPercentOf

Record the setting of a discount for a tier.


```solidity
function recordSetDiscountPercentOf(uint256 tierId, uint256 discountPercent) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier to set the discount of.|
|`discountPercent`|`uint256`|The new discount percent being applied.|


### recordSetEncodedIPFSUriOf

Record a new encoded IPFS URI for a tier.


```solidity
function recordSetEncodedIPFSUriOf(uint256 tierId, bytes32 encodedIPFSUri) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier to set the encoded IPFS URI of.|
|`encodedIPFSUri`|`bytes32`|The encoded IPFS URI to set for the tier.|


### recordSetTokenUriResolver

Record a newly set token URI resolver.


```solidity
function recordSetTokenUriResolver(IJB721TokenUriResolver resolver) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`resolver`|`IJB721TokenUriResolver`|The resolver to set.|


### recordTransferForTier

Record an 721 transfer.


```solidity
function recordTransferForTier(uint256 tierId, address from, address to) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier that the 721 being transferred belongs to.|
|`from`|`address`|The address that the 721 is being transferred from.|
|`to`|`address`|The address that the 721 is being transferred to.|


## Events
### CleanTiers
Emitted when removed tiers are cleaned from the sorting sequence.


```solidity
event CleanTiers(address indexed hook, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract whose tiers were cleaned.|
|`caller`|`address`|The address that called the function.|

### SetDefaultReserveBeneficiary
Emitted when the default reserve beneficiary is changed.

This affects ALL tiers that do not have a tier-specific reserve beneficiary set.


```solidity
event SetDefaultReserveBeneficiary(address indexed hook, address indexed newBeneficiary, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`hook`|`address`|The 721 contract whose default reserve beneficiary was changed.|
|`newBeneficiary`|`address`|The new default reserve beneficiary address.|
|`caller`|`address`|The address that triggered the change.|

