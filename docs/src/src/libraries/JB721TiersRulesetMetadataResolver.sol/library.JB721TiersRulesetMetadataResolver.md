# JB721TiersRulesetMetadataResolver
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/libraries/JB721TiersRulesetMetadataResolver.sol)

**Title:**
JB721TiersRulesetMetadataResolver

Utility library to parse and store ruleset metadata associated for the tiered 721 hook.

This library parses the `metadata` member of the `JBRulesetMetadata` struct.


## Functions
### transfersPaused

Check whether transfers are paused based on the packed ruleset metadata.


```solidity
function transfersPaused(uint256 data) internal pure returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`uint256`|The packed metadata to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether transfers are paused (bit 0).|


### mintPendingReservesPaused

Check whether minting pending reserves is paused based on the packed ruleset metadata.


```solidity
function mintPendingReservesPaused(uint256 data) internal pure returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`uint256`|The packed metadata to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether minting pending reserves is paused (bit 1).|


### pack721TiersRulesetMetadata

Pack the ruleset metadata for the 721 hook into a single `uint256`.


```solidity
function pack721TiersRulesetMetadata(JB721TiersRulesetMetadata memory metadata)
    internal
    pure
    returns (uint256 packed);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`metadata`|`JB721TiersRulesetMetadata`|The metadata to validate and pack.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`packed`|`uint256`|A `uint256` containing the packed metadata for the 721 hook.|


### expandMetadata

Expand packed ruleset metadata for the 721 hook.


```solidity
function expandMetadata(uint16 packedMetadata) internal pure returns (JB721TiersRulesetMetadata memory metadata);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`packedMetadata`|`uint16`|The packed metadata to expand.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`metadata`|`JB721TiersRulesetMetadata`|The metadata as a `JB721TiersRulesetMetadata` struct.|


