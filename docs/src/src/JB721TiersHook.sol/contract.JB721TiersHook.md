# JB721TiersHook
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/JB721TiersHook.sol)

**Inherits:**
JBOwnable, ERC2771Context, [JB721Hook](/src/abstract/JB721Hook.sol/abstract.JB721Hook.md), [IJB721TiersHook](/src/interfaces/IJB721TiersHook.sol/interface.IJB721TiersHook.md)

**Title:**
JB721TiersHook

A Juicebox project can use this hook to sell tiered ERC-721 NFTs with different prices and metadata. When
the project is paid, the hook may mint NFTs to the payer, depending on the hook's setup, the amount paid, and
information specified by the payer. The project's owner can enable NFT cash outs through this hook, allowing
holders to burn their NFTs to reclaim funds from the project (in proportion to the NFT's price).


## State Variables
### PRICES
The contract that exposes price feeds for currency conversions.


```solidity
IJBPrices public immutable override PRICES
```


### RULESETS
The contract storing and managing project rulesets.


```solidity
IJBRulesets public immutable override RULESETS
```


### STORE
The contract that stores and manages data for this contract's NFTs.


```solidity
IJB721TiersHookStore public immutable override STORE
```


### SPLITS
The contract that stores and manages splits.


```solidity
IJBSplits public immutable override SPLITS
```


### baseURI
The base URI for the NFT `tokenUris`.


```solidity
string public override baseURI
```


### contractURI
This contract's metadata URI.


```solidity
string public override contractURI
```


### payCreditsOf
If an address pays more than the price of the NFT they received, the extra amount is stored as credits
which can be cashed out to mint NFTs.


```solidity
mapping(address addr => uint256) public override payCreditsOf
```


### _firstOwnerOf
The first owner of each token ID, stored on first transfer out.


```solidity
mapping(uint256 tokenId => address) internal _firstOwnerOf
```


### _packedPricingContext
Packed context for the pricing of this contract's tiers.

Packed into a uint256:
- currency in bits 0-31 (32 bits), and
- pricing decimals in bits 32-39 (8 bits).


```solidity
uint256 internal _packedPricingContext
```


## Functions
### constructor


```solidity
constructor(
    IJBDirectory directory,
    IJBPermissions permissions,
    IJBPrices prices,
    IJBRulesets rulesets,
    IJB721TiersHookStore store,
    IJBSplits splits,
    address trustedForwarder
)
    JBOwnable(permissions, directory.PROJECTS(), msg.sender, uint88(0))
    JB721Hook(directory)
    ERC2771Context(trustedForwarder);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`directory`|`IJBDirectory`|A directory of terminals and controllers for projects.|
|`permissions`|`IJBPermissions`|A contract storing permissions.|
|`prices`|`IJBPrices`|A contract that exposes price feeds for currency conversions.|
|`rulesets`|`IJBRulesets`|A contract storing and managing project rulesets.|
|`store`|`IJB721TiersHookStore`|The contract which stores the NFT's data.|
|`splits`|`IJBSplits`|The contract that stores and manages splits.|
|`trustedForwarder`|`address`|The trusted forwarder for the ERC2771Context.|


### firstOwnerOf

The first owner of an NFT.

This is generally the address which paid for the NFT.


```solidity
function firstOwnerOf(uint256 tokenId) external view override returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The token ID of the NFT to get the first owner of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the NFT's first owner.|


### pricingContext

Context for the pricing of this hook's tiers.


```solidity
function pricingContext() external view override returns (uint256 currency, uint256 decimals);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`currency`|`uint256`|The currency used for tier prices.|
|`decimals`|`uint256`|The amount of decimals being used in tier prices.|


### balanceOf

The total number of this hook's NFTs that an address holds (from all tiers).


```solidity
function balanceOf(address owner) public view override returns (uint256 balance);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The address to check the balance of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`balance`|`uint256`|The number of NFTs the address owns across this hook's tiers.|


### beforePayRecordedWith

The data calculated before a payment is recorded in the terminal store.

Overrides the base to calculate the split amount to forward based on tier split percentages.


```solidity
function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
    public
    view
    virtual
    override(JB721Hook, IJBRulesetDataHook)
    returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBBeforePayRecordedContext`|The payment context.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|The weight to use for token minting, adjusted down when tier splits route funds away from the project (unless `issueTokensForSplits` is set).|
|`hookSpecifications`|`JBPayHookSpecification[]`|The hook specifications, with the split amount to forward.|


### cashOutWeightOf

The combined cash out weight of the NFTs with the specified token IDs.

An NFT's cash out weight is its price.

To get their relative cash out weight, divide the result by the `totalCashOutWeight(...)`.


```solidity
function cashOutWeightOf(uint256[] memory tokenIds) public view virtual override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|The token IDs of the NFTs to get the cumulative cash out weight of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|weight The cash out weight of the tokenIds.|


### initialize

Initializes a cloned copy of the original hook contract.


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
    public
    override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project this this hook is associated with.|
|`name`|`string`|The name of the NFT collection.|
|`symbol`|`string`|The symbol representing the NFT collection.|
|`baseUri`|`string`|The URI to use as a base for full NFT `tokenUri`s.|
|`tokenUriResolver`|`IJB721TokenUriResolver`|An optional contract responsible for resolving the token URI for each NFT's token ID.|
|`contractUri`|`string`|A URI where this contract's metadata can be found.|
|`tiersConfig`|`JB721InitTiersConfig`|The NFT tiers and pricing context to initialize the hook with. The tiers must be sorted by category (from least to greatest).|
|`flags`|`JB721TiersHookFlags`|A set of additional options which dictate how the hook behaves.|


### supportsInterface

Indicates if this contract adheres to the specified interface.

See [IERC165-supportsInterface](/lib/forge-std/src/mocks/MockERC721.sol/contract.MockERC721.md#supportsinterface).


```solidity
function supportsInterface(bytes4 interfaceId) public view override(IERC165, JB721Hook) returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`interfaceId`|`bytes4`|The ID of the interface to check for adherence to.|


### tokenURI

The metadata URI of the NFT with the specified token ID.

Defers to the `tokenUriResolver` if it is set. Otherwise, use the `tokenUri` corresponding with the NFT's
tier.


```solidity
function tokenURI(uint256 tokenId) public view virtual override returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The token ID of the NFT to get the metadata URI of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The token URI from the `tokenUriResolver` if it is set. If it isn't set, the token URI for the NFT's tier.|


### totalCashOutWeight

The combined cash out weight of all outstanding NFTs.

An NFT's cash out weight is its price.


```solidity
function totalCashOutWeight() public view virtual override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|weight The total cash out weight.|


### adjustTiers

Add or delete tiers.

Only the contract's owner or an operator with the `ADJUST_TIERS` permission from the owner can adjust the
tiers.

Any added tiers must adhere to this hook's `JB721TiersHookFlags`.


```solidity
function adjustTiers(JB721TierConfig[] calldata tiersToAdd, uint256[] calldata tierIdsToRemove) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tiersToAdd`|`JB721TierConfig[]`|The tiers to add, as an array of `JB721TierConfig` structs`.|
|`tierIdsToRemove`|`uint256[]`|The tiers to remove, as an array of tier IDs.|


### executeSplitPayout

Execute a single split payout. Called by the library via `this.executeSplitPayout()` so that
try/catch can wrap the external call. If this reverts, all state changes inside (including token transfers)
roll back atomically, and the caller catches the failure.

May only be called by this contract itself (i.e., the library running via DELEGATECALL calling back).


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
    override
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


### mintFor

Manually mint NFTs from the provided tiers .


```solidity
function mintFor(
    uint16[] calldata tierIds,
    address beneficiary
)
    external
    override
    returns (uint256[] memory tokenIds);
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

"Pending" means that the NFTs have been reserved, but have not been minted yet.


```solidity
function mintPendingReservesFor(JB721TiersMintReservesConfig[] calldata reserveMintConfigs) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`reserveMintConfigs`|`JB721TiersMintReservesConfig[]`|Contains information about how many reserved tokens to mint for each tier.|


### setDiscountPercentOf

Allows the collection's owner to set the discount for a tier, if the tier allows it.

Only the contract's owner or an operator with the `SET_721_DISCOUNT_PERCENT` permission from the owner can
adjust the
tiers.


```solidity
function setDiscountPercentOf(uint256 tierId, uint256 discountPercent) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier to set the discount of.|
|`discountPercent`|`uint256`|The discount percent to set.|


### setDiscountPercentsOf

Allows the collection's owner to set the discount percent for multiple tiers.


```solidity
function setDiscountPercentsOf(JB721TiersSetDiscountPercentConfig[] calldata configs) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`configs`|`JB721TiersSetDiscountPercentConfig[]`|The configs to set the discount percent for.|


### setMetadata

Update this hook's metadata properties.

Only this contract's owner or an operator with the `SET_721_METADATA` permission can set the metadata.


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
    external
    override;
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


### mintPendingReservesFor

Mint reserved pending reserved NFTs within the provided tier.

"Pending" means that the NFTs have been reserved, but have not been minted yet.


```solidity
function mintPendingReservesFor(uint256 tierId, uint256 count) public override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier to mint reserved NFTs from.|
|`count`|`uint256`|The number of reserved NFTs to mint.|


### _contextSuffixLength

ERC-2771 specifies the context as being a single address (20 bytes).


```solidity
function _contextSuffixLength() internal view virtual override(ERC2771Context, Context) returns (uint256);
```

### _currentRulesetOf

The project's current ruleset.


```solidity
function _currentRulesetOf(uint256 projectId) internal view returns (JBRuleset memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`JBRuleset`|The project's current ruleset.|


### _msgData

Returns the calldata, preferred to use over `msg.data`


```solidity
function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|calldata the `msg.data` of this call|


### _msgSender

Returns the sender, preferred to use over `msg.sender`


```solidity
function _msgSender() internal view override(ERC2771Context, Context) returns (address sender);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sender`|`address`|the sender address of this call.|


### _didBurn

A function which gets called after NFTs have been cashed out and recorded by the terminal.


```solidity
function _didBurn(uint256[] memory tokenIds) internal virtual override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|The token IDs of the NFTs that were burned.|


### _mintAll

Mints one NFT from each of the specified tiers for the beneficiary.

The same tier can be specified more than once.


```solidity
function _mintAll(
    uint256 amount,
    uint16[] memory mintTierIds,
    address beneficiary
)
    internal
    returns (uint256 leftoverAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The amount to base the mints on. The total price of the NFTs being minted cannot be larger than this amount.|
|`mintTierIds`|`uint16[]`|An array of NFT tier IDs to be minted.|
|`beneficiary`|`address`|The address receiving the newly minted NFTs.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`leftoverAmount`|`uint256`|The `amount` leftover after minting.|


### _processPayment

Process a payment, minting NFTs and updating credits as necessary.

Pay credits are tracked per beneficiary, not per payer. When the payer differs from the beneficiary,
the payer's existing credits are NOT applied to the mint. Only the beneficiary's credits are combined with
the incoming payment value. Leftover funds after minting are stored as credits for the beneficiary.


```solidity
function _processPayment(JBAfterPayRecordedContext calldata context) internal virtual override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBAfterPayRecordedContext`|Payment context provided by the terminal after it has recorded the payment in the terminal store.|


### _recordSetTokenUriResolver

Record the setting of a new token URI resolver.


```solidity
function _recordSetTokenUriResolver(IJB721TokenUriResolver tokenUriResolver) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenUriResolver`|`IJB721TokenUriResolver`|The new token URI resolver.|


### _setDiscountPercentOf

Internal function to set the discount percent for a tier.


```solidity
function _setDiscountPercentOf(uint256 tierId, uint256 discountPercent) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tierId`|`uint256`|The ID of the tier to set the discount percent for.|
|`discountPercent`|`uint256`|The discount percent to set for the tier.|


### _terminalAddToBalance


```solidity
function _terminalAddToBalance(
    IJBTerminal terminal,
    uint256 projectId,
    address token,
    uint256 amount,
    bool isNativeToken
)
    internal;
```

### _terminalPay


```solidity
function _terminalPay(
    IJBTerminal terminal,
    uint256 projectId,
    address token,
    uint256 amount,
    address beneficiary,
    bool isNativeToken
)
    internal;
```

### _update

Before transferring an NFT, register its first owner (if necessary).


```solidity
function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address from);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|The address the NFT is being transferred to.|
|`tokenId`|`uint256`|The token ID of the NFT being transferred.|
|`auth`|`address`||


## Errors
### JB721TiersHook_AlreadyInitialized

```solidity
error JB721TiersHook_AlreadyInitialized(uint256 projectId);
```

### JB721TiersHook_CurrencyMismatch

```solidity
error JB721TiersHook_CurrencyMismatch(uint256 paymentCurrency, uint256 tierCurrency);
```

### JB721TiersHook_InvalidPricingDecimals

```solidity
error JB721TiersHook_InvalidPricingDecimals(uint256 decimals);
```

### JB721TiersHook_MintReserveNftsPaused

```solidity
error JB721TiersHook_MintReserveNftsPaused();
```

### JB721TiersHook_NoProjectId

```solidity
error JB721TiersHook_NoProjectId();
```

### JB721TiersHook_Overspending

```solidity
error JB721TiersHook_Overspending(uint256 leftoverAmount);
```

### JB721TiersHook_TierTransfersPaused

```solidity
error JB721TiersHook_TierTransfersPaused();
```

