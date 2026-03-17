# IJB721Hook
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/interfaces/IJB721Hook.sol)

**Inherits:**
IJBRulesetDataHook, IJBPayHook, IJBCashOutHook

A 721 hook that integrates with Juicebox as a data hook, pay hook, and cash out hook.


## Functions
### DIRECTORY

The directory of terminals and controllers for projects.


```solidity
function DIRECTORY() external view returns (IJBDirectory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IJBDirectory`|The directory contract.|


### METADATA_ID_TARGET

The ID used when parsing metadata.


```solidity
function METADATA_ID_TARGET() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the metadata ID target.|


### PROJECT_ID

The ID of the project that this contract is associated with.


```solidity
function PROJECT_ID() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The project ID.|


