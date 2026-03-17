# IJB721TiersHook
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/interfaces/IJB721TiersHook.sol)

**Inherits:**
[IJB721Hook](/src/interfaces/IJB721Hook.sol/interface.IJB721Hook.md)

A 721 tiers hook that mints tiered NFTs for payments and tracks their cash out weight.


## Functions
### baseURI

The base URI for the NFT `tokenUris`.


```solidity
function baseURI() external view returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The base URI string.|


### contractURI

This contract's metadata URI.


```solidity
function contractURI() external view returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The contract URI string.|


### firstOwnerOf

The first owner of an NFT.


```solidity
function firstOwnerOf(uint256 tokenId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The token ID of the NFT to get the first owner of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the NFT's first owner.|


### payCreditsOf

The amount of NFT credits the address has.


```solidity
function payCreditsOf(address addr) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`addr`|`address`|The address to get the NFT credits balance of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of credits the address has.|


### pricingContext

Context for the pricing of this hook's tiers.


```solidity
function pricingContext() external view returns (uint256 currency, uint256 decimals);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`currency`|`uint256`|The currency used for tier prices.|
|`decimals`|`uint256`|The amount of decimals being used in tier prices.|


### PRICES

The contract that exposes price feeds for currency conversions.


```solidity
function PRICES() external view returns (IJBPrices);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IJBPrices`|The prices contract.|


### RULESETS

The contract storing and managing project rulesets.


```solidity
function RULESETS() external view returns (IJBRulesets);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IJBRulesets`|The rulesets contract.|


### STORE

The contract that stores and manages data for this contract's NFTs.


```solidity
function STORE() external view returns (IJB721TiersHookStore);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IJB721TiersHookStore`|The store contract.|


### SPLITS

The contract that stores and manages splits.


```solidity
function SPLITS() external view returns (IJBSplits);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IJBSplits`|The splits contract.|


### adjustTiers

Add or remove tiers.


```solidity
function adjustTiers(JB721TierConfig[] calldata tiersToAdd, uint256[] calldata tierIdsToRemove) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tiersToAdd`|`JB721TierConfig[]`|The tiers to add, as an array of `JB721TierConfig` structs.|
|`tierIdsToRemove`|`uint256[]`|The tiers to remove, as an array of tier IDs.|


### executeSplitPayout

Execute a single split payout. Called by the library via `this.executeSplitPayout()` so that
try/catch can wrap the external call.

May only be called by this contract itself (i.e., the library running via DELEGATECALL).


```solidity
function executeSplitPayout(
    JBSplit calldata split,
    address token,
    uint256 amount,
    uint256 projectId,
    uint256 groupId,
    uint256 decimals
)
    external
    payable
    returns (bool sent);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`split`|`JBSplit`|The split to pay.|
|`token`|`address`|The token being paid out.|
|`amount`|`uint256`|The amount to pay out.|
|`projectId`|`uint256`|The project ID the split belongs to.|
|`groupId`|`uint256`|The split group ID.|
|`decimals`|`uint256`|The token decimals.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sent`|`bool`|Whether the funds were actually sent.|


### initialize

Initializes a cloned copy of the original `JB721TiersHook` contract.


```solidity
function initialize(
    uint256 projectId,
    string memory name,
    string memory symbol,
    string memory baseUri,
    IJB721TokenUriResolver tokenUriResolver,
    string memory contractUri,
    JB721InitTiersConfig memory tiersConfig,
    JB721TiersHookFlags memory flags
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project this hook is associated with.|
|`name`|`string`|The name of the NFT collection.|
|`symbol`|`string`|The symbol representing the NFT collection.|
|`baseUri`|`string`|The URI to use as a base for full NFT `tokenUri`s.|
|`tokenUriResolver`|`IJB721TokenUriResolver`|An optional contract responsible for resolving the token URI for each NFT.|
|`contractUri`|`string`|A URI where this contract's metadata can be found.|
|`tiersConfig`|`JB721InitTiersConfig`|The NFT tiers and pricing context to initialize the hook with.|
|`flags`|`JB721TiersHookFlags`|A set of additional options which dictate how the hook behaves.|


### mintFor

Manually mint NFTs from the provided tiers.


```solidity
function mintFor(uint16[] calldata tierIds, address beneficiary) external returns (uint256[] memory tokenIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierIds`|`uint16[]`|The IDs of the tiers to mint from.|
|`beneficiary`|`address`|The address to mint to.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|The IDs of the newly minted tokens.|


### mintPendingReservesFor

Mint pending reserved NFTs based on the provided information.


```solidity
function mintPendingReservesFor(JB721TiersMintReservesConfig[] calldata reserveMintConfigs) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`reserveMintConfigs`|`JB721TiersMintReservesConfig[]`|Contains information about how many reserved tokens to mint for each tier.|


### mintPendingReservesFor

Mint pending reserved NFTs for a specific tier.


```solidity
function mintPendingReservesFor(uint256 tierId, uint256 count) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier to mint reserved NFTs from.|
|`count`|`uint256`|The number of reserved NFTs to mint.|


### setDiscountPercentOf

Set the discount percent for a tier.


```solidity
function setDiscountPercentOf(uint256 tierId, uint256 discountPercent) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier to set the discount of.|
|`discountPercent`|`uint256`|The discount percent to set.|


### setDiscountPercentsOf

Set the discount percent for multiple tiers.


```solidity
function setDiscountPercentsOf(JB721TiersSetDiscountPercentConfig[] calldata configs) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`configs`|`JB721TiersSetDiscountPercentConfig[]`|The configs to set the discount percent for.|


### setMetadata

Update this hook's metadata properties.


```solidity
function setMetadata(
    string calldata name,
    string calldata symbol,
    string calldata baseUri,
    string calldata contractUri,
    IJB721TokenUriResolver tokenUriResolver,
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 encodedIPFSUriTierId,
    // forge-lint: disable-next-line(mixed-case-variable)
    bytes32 encodedIPFSUri
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|The new collection name. Send empty to leave unchanged.|
|`symbol`|`string`|The new collection symbol. Send empty to leave unchanged.|
|`baseUri`|`string`|The new base URI.|
|`contractUri`|`string`|The new contract URI.|
|`tokenUriResolver`|`IJB721TokenUriResolver`|The new URI resolver.|
|`encodedIPFSUriTierId`|`uint256`|The ID of the tier to set the encoded IPFS URI of.|
|`encodedIPFSUri`|`bytes32`|The encoded IPFS URI to set.|


## Events
### AddPayCredits
Emitted when pay credits are added for an account.


```solidity
event AddPayCredits(
    uint256 indexed amount, uint256 indexed newTotalCredits, address indexed account, address caller
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The amount of credits added.|
|`newTotalCredits`|`uint256`|The new total credits balance for the account.|
|`account`|`address`|The account that received the credits.|
|`caller`|`address`|The address that called the function.|

### AddTier
Emitted when a new tier is added.


```solidity
event AddTier(uint256 indexed tierId, JB721TierConfig tier, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier that was added.|
|`tier`|`JB721TierConfig`|The configuration of the tier that was added.|
|`caller`|`address`|The address that called the function.|

### Mint
Emitted when an NFT is minted from a payment.


```solidity
event Mint(
    uint256 indexed tokenId,
    uint256 indexed tierId,
    address indexed beneficiary,
    uint256 totalAmountPaid,
    address caller
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The token ID of the minted NFT.|
|`tierId`|`uint256`|The ID of the tier the NFT was minted from.|
|`beneficiary`|`address`|The address that received the NFT.|
|`totalAmountPaid`|`uint256`|The total amount paid in the transaction.|
|`caller`|`address`|The address that called the function.|

### MintReservedNft
Emitted when a reserved NFT is minted.


```solidity
event MintReservedNft(uint256 indexed tokenId, uint256 indexed tierId, address indexed beneficiary, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The token ID of the minted reserved NFT.|
|`tierId`|`uint256`|The ID of the tier the reserved NFT was minted from.|
|`beneficiary`|`address`|The address that received the reserved NFT.|
|`caller`|`address`|The address that called the function.|

### RemoveTier
Emitted when a tier is removed.


```solidity
event RemoveTier(uint256 indexed tierId, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier that was removed.|
|`caller`|`address`|The address that called the function.|

### SplitPayoutReverted
Emitted when a split payout reverts. The funds stay in the project's balance.


```solidity
event SplitPayoutReverted(uint256 indexed projectId, JBSplit split, uint256 amount, bytes reason, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The project ID the split belongs to.|
|`split`|`JBSplit`|The split that reverted.|
|`amount`|`uint256`|The amount that was being paid out.|
|`reason`|`bytes`|The revert reason bytes.|
|`caller`|`address`|The address that called the function.|

### SetName
Emitted when the collection name is set.


```solidity
event SetName(string indexed name, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|The new collection name.|
|`caller`|`address`|The address that called the function.|

### SetSymbol
Emitted when the collection symbol is set.


```solidity
event SetSymbol(string indexed symbol, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`symbol`|`string`|The new collection symbol.|
|`caller`|`address`|The address that called the function.|

### SetBaseUri
Emitted when the base URI is set.


```solidity
event SetBaseUri(string indexed baseUri, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`baseUri`|`string`|The new base URI.|
|`caller`|`address`|The address that called the function.|

### SetContractUri
Emitted when the contract URI is set.


```solidity
event SetContractUri(string indexed uri, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`uri`|`string`|The new contract URI.|
|`caller`|`address`|The address that called the function.|

### SetDiscountPercent
Emitted when a tier's discount percent is set.


```solidity
event SetDiscountPercent(uint256 indexed tierId, uint256 discountPercent, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier whose discount percent was set.|
|`discountPercent`|`uint256`|The new discount percent.|
|`caller`|`address`|The address that called the function.|

### SetEncodedIPFSUri
Emitted when a tier's encoded IPFS URI is set.


```solidity
event SetEncodedIPFSUri(uint256 indexed tierId, bytes32 encodedUri, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier whose encoded IPFS URI was set.|
|`encodedUri`|`bytes32`|The new encoded IPFS URI.|
|`caller`|`address`|The address that called the function.|

### SetTokenUriResolver
Emitted when the token URI resolver is set.


```solidity
event SetTokenUriResolver(IJB721TokenUriResolver indexed resolver, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`resolver`|`IJB721TokenUriResolver`|The new token URI resolver.|
|`caller`|`address`|The address that called the function.|

### UsePayCredits
Emitted when pay credits are used by an account.


```solidity
event UsePayCredits(
    uint256 indexed amount, uint256 indexed newTotalCredits, address indexed account, address caller
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The amount of credits used.|
|`newTotalCredits`|`uint256`|The new total credits balance for the account.|
|`account`|`address`|The account that used the credits.|
|`caller`|`address`|The address that called the function.|

