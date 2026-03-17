# JB721TiersHookLib
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/libraries/JB721TiersHookLib.sol)

External library for JB721TiersHook operations extracted to stay within the EIP-170 contract size limit.

Handles tier adjustments, split calculations, price normalization, and split fund distribution.


## Functions
### adjustTiersFor

Handles the full tier adjustment logic: removes tiers, adds tiers, emits events, and sets splits.

Called via DELEGATECALL from the hook, so events are emitted from the hook's address.


```solidity
function adjustTiersFor(
    IJB721TiersHookStore store,
    IJBSplits splits,
    uint256 projectId,
    address hookAddress,
    address caller,
    JB721TierConfig[] calldata tiersToAdd,
    uint256[] calldata tierIdsToRemove
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`store`|`IJB721TiersHookStore`|The 721 tiers hook store.|
|`splits`|`IJBSplits`|The splits contract to register tier split groups in.|
|`projectId`|`uint256`|The project ID.|
|`hookAddress`|`address`|The hook address.|
|`caller`|`address`|The msg.sender of the original call (for event emission).|
|`tiersToAdd`|`JB721TierConfig[]`|The tier configs to add.|
|`tierIdsToRemove`|`uint256[]`|The tier IDs to remove.|


### recordAddTiersFor

Records new tiers, emits events, and sets their split groups.

Used during initialization when tier configs are in memory.


```solidity
function recordAddTiersFor(
    IJB721TiersHookStore store,
    IJBSplits splits,
    uint256 projectId,
    address hookAddress,
    address caller,
    JB721TierConfig[] memory tiersToAdd
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`store`|`IJB721TiersHookStore`|The 721 tiers hook store.|
|`splits`|`IJBSplits`|The splits contract to register tier split groups in.|
|`projectId`|`uint256`|The project ID.|
|`hookAddress`|`address`|The hook address.|
|`caller`|`address`|The msg.sender of the original call (for event emission).|
|`tiersToAdd`|`JB721TierConfig[]`|The tier configs to add.|


### normalizePaymentValue

Normalizes a payment value based on the packed pricing context.


```solidity
function normalizePaymentValue(
    uint256 packedPricingContext,
    IJBPrices prices,
    uint256 projectId,
    uint256 amountValue,
    uint256 amountCurrency,
    uint256 amountDecimals
)
    external
    view
    returns (uint256 value, bool valid);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`packedPricingContext`|`uint256`|The packed pricing context (currency, decimals).|
|`prices`|`IJBPrices`|The prices contract used for currency conversion.|
|`projectId`|`uint256`|The project ID.|
|`amountValue`|`uint256`|The payment amount value.|
|`amountCurrency`|`uint256`|The payment amount currency.|
|`amountDecimals`|`uint256`|The payment amount decimals.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`value`|`uint256`|The normalized value.|
|`valid`|`bool`|Whether the value is valid (false means no prices contract and currencies differ).|


### calculateSplitAmounts

Calculates per-tier split amounts for a pay event.


```solidity
function calculateSplitAmounts(
    IJB721TiersHookStore store,
    address hook,
    address metadataIdTarget,
    bytes calldata metadata
)
    external
    view
    returns (uint256 totalSplitAmount, bytes memory hookMetadata);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`store`|`IJB721TiersHookStore`|The 721 tiers hook store.|
|`hook`|`address`|The hook address.|
|`metadataIdTarget`|`address`|The metadata ID target for resolving pay metadata.|
|`metadata`|`bytes`|The payer metadata.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalSplitAmount`|`uint256`|The total amount to forward for splits.|
|`hookMetadata`|`bytes`|Encoded per-tier breakdown (tierIds, amounts) for afterPay.|


### convertSplitAmounts

Converts split amounts from tier pricing denomination to payment token denomination.

Called after `calculateSplitAmounts` when the payment currency differs from the tier pricing currency.


```solidity
function convertSplitAmounts(
    uint256 totalSplitAmount,
    bytes memory splitMetadata,
    uint256 packedPricingContext,
    IJBPrices prices,
    uint256 projectId,
    uint256 amountCurrency,
    uint256 amountDecimals
)
    external
    view
    returns (uint256 convertedTotal, bytes memory convertedMetadata);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`totalSplitAmount`|`uint256`|The total split amount in tier pricing denomination.|
|`splitMetadata`|`bytes`|The encoded per-tier breakdown (tierIds, amounts) from calculateSplitAmounts.|
|`packedPricingContext`|`uint256`|The packed pricing context (currency, decimals).|
|`prices`|`IJBPrices`|The prices contract used for currency conversion.|
|`projectId`|`uint256`|The project ID.|
|`amountCurrency`|`uint256`|The payment amount currency.|
|`amountDecimals`|`uint256`|The payment amount decimals.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`convertedTotal`|`uint256`|The total split amount converted to payment token denomination.|
|`convertedMetadata`|`bytes`|The re-encoded per-tier breakdown with converted amounts.|


### calculateWeight

Calculates the weight for token minting after accounting for tier split amounts.

Extracted from the hook to keep mulDiv's bytecode out of the hook (EIP-170 compliance).


```solidity
function calculateWeight(
    uint256 contextWeight,
    uint256 amountValue,
    uint256 totalSplitAmount,
    bool issueTokensForSplits
)
    external
    pure
    returns (uint256 weight);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contextWeight`|`uint256`|The original weight from the payment context.|
|`amountValue`|`uint256`|The payment amount value.|
|`totalSplitAmount`|`uint256`|The total amount routed to tier splits.|
|`issueTokensForSplits`|`bool`|Whether to issue tokens for the full payment regardless of splits.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|The adjusted weight for token minting.|


### _setSplitGroupsFor

Sets split groups in JBSplits for tiers that have splits configured.


```solidity
function _setSplitGroupsFor(
    IJBSplits splits,
    uint256 projectId,
    address hookAddress,
    JB721TierConfig[] memory tiersToAdd,
    uint256[] memory tierIdsAdded
)
    private;
```

### distributeAll

Pulls ERC-20 tokens from the terminal (if needed) and distributes forwarded funds to tier splits.

For ERC-20 tokens, pulls from the terminal using the allowance it granted via _beforeTransferTo.


```solidity
function distributeAll(
    IJBDirectory directory,
    IJBSplits splits,
    uint256 projectId,
    address hookAddress,
    address token,
    uint256 amount,
    uint256 decimals,
    bytes calldata encodedSplitData
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`directory`|`IJBDirectory`|The directory to look up terminals.|
|`splits`|`IJBSplits`|The splits contract to read tier split groups from.|
|`projectId`|`uint256`|The project ID of the hook.|
|`hookAddress`|`address`|The hook address (for computing split group IDs).|
|`token`|`address`|The token being distributed.|
|`amount`|`uint256`|The total amount to distribute.|
|`decimals`|`uint256`||
|`encodedSplitData`|`bytes`|The encoded per-tier breakdown from hookMetadata.|


### _distributeSingleSplit

Distributes funds for a single tier's split group.

Uses this.executeSplitPayout() + try/catch so that a single reverting split recipient does not block
distribution for the entire tier. Failed splits' funds stay in leftoverAmount and route to the project's
balance.


```solidity
function _distributeSingleSplit(
    IJBDirectory directory,
    IJBSplits splitsContract,
    uint256 projectId,
    address token,
    uint256 groupId,
    uint256 amount,
    uint256 decimals
)
    private;
```

### _trySplitPayout

Attempts a single split payout via an external self-call wrapped in try/catch.

Since this library runs via DELEGATECALL, `address(this)` is the hook contract.


```solidity
function _trySplitPayout(
    JBSplit memory split,
    address token,
    uint256 amount,
    uint256 projectId,
    uint256 groupId,
    uint256 decimals
)
    private
    returns (bool sent);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sent`|`bool`|Whether the payout succeeded and funds were transferred.|


### _addToBalance

If no primary terminal exists for the token, funds remain in the hook's balance rather than being
forwarded. They are not lost — they stay in the terminal that originally received them.


```solidity
function _addToBalance(
    IJBDirectory directory,
    uint256 projectId,
    address token,
    uint256 amount,
    bool isNativeToken
)
    private;
```

### _terminalAddToBalance


```solidity
function _terminalAddToBalance(
    IJBTerminal terminal,
    uint256 projectId,
    address token,
    uint256 amount,
    bool isNativeToken
)
    private;
```

### resolveTokenURI

Resolves the token URI for a given NFT token ID.

Extracted to the library to keep JBIpfsDecoder bytecode out of the hook contract (EIP-170 compliance).


```solidity
function resolveTokenURI(
    IJB721TiersHookStore store,
    address hook,
    string memory baseUri,
    uint256 tokenId
)
    external
    view
    returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`store`|`IJB721TiersHookStore`|The 721 tiers hook store.|
|`hook`|`address`|The hook address.|
|`baseUri`|`string`|The base URI for IPFS-based token URIs.|
|`tokenId`|`uint256`|The token ID to resolve the URI for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The resolved token URI string.|


## Events
### AddTier

```solidity
event AddTier(uint256 indexed tierId, JB721TierConfig tier, address caller);
```

### RemoveTier

```solidity
event RemoveTier(uint256 indexed tierId, address caller);
```

### SplitPayoutReverted

```solidity
event SplitPayoutReverted(uint256 indexed projectId, JBSplit split, uint256 amount, bytes reason, address caller);
```

