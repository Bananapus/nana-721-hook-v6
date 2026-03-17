# JB721Hook
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/abstract/JB721Hook.sol)

**Inherits:**
[ERC721](/src/abstract/ERC721.sol/abstract.ERC721.md), [IJB721Hook](/src/interfaces/IJB721Hook.sol/interface.IJB721Hook.md)

**Title:**
JB721Hook

When a project which uses this hook is paid, this hook may mint NFTs to the payer, depending on this hook's
setup, the amount paid, and information specified by the payer. The project's owner can enable NFT cash outs
through this hook, allowing the NFT holders to burn their NFTs to reclaim funds from the project (in proportion to
the NFT's price).


## State Variables
### DIRECTORY
The directory of terminals and controllers for projects.


```solidity
IJBDirectory public immutable override DIRECTORY
```


### METADATA_ID_TARGET
The ID used when parsing metadata.


```solidity
address public immutable override METADATA_ID_TARGET
```


### PROJECT_ID
The ID of the project that this contract is associated with.


```solidity
uint256 public override PROJECT_ID
```


## Functions
### constructor


```solidity
constructor(IJBDirectory directory) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`directory`|`IJBDirectory`|A directory of terminals and controllers for projects.|


### beforeCashOutRecordedWith

The data calculated before a cash out is recorded in the terminal store. This data is provided to the
terminal's `cashOutTokensOf(...)` transaction.

Sets this contract as the cash out hook. Part of `IJBRulesetDataHook`.

This function is used for NFT cash outs, and will only be called if the project's ruleset has
`useDataHookForCashOut` set to `true`.


```solidity
function beforeCashOutRecordedWith(JBBeforeCashOutRecordedContext calldata context)
    public
    view
    virtual
    override
    returns (
        uint256 cashOutTaxRate,
        uint256 cashOutCount,
        uint256 totalSupply,
        JBCashOutHookSpecification[] memory hookSpecifications
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBBeforeCashOutRecordedContext`|The cash out context passed to this contract by the `cashOutTokensOf(...)` function.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`cashOutTaxRate`|`uint256`|The cash out tax rate influencing the reclaim amount.|
|`cashOutCount`|`uint256`|The amount of tokens that should be considered cashed out.|
|`totalSupply`|`uint256`|The total amount of tokens that are considered to be existing.|
|`hookSpecifications`|`JBCashOutHookSpecification[]`|The amount and data to send to cash out hooks (this contract) instead of returning to the beneficiary.|


### beforePayRecordedWith

The data calculated before a payment is recorded in the terminal store. This data is provided to the
terminal's `pay(...)` transaction.

Sets this contract as the pay hook. Part of `IJBRulesetDataHook`.


```solidity
function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
    public
    view
    virtual
    override
    returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBBeforePayRecordedContext`|The payment context passed to this contract by the `pay(...)` function.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`weight`|`uint256`|The new `weight` to use, overriding the ruleset's `weight`.|
|`hookSpecifications`|`JBPayHookSpecification[]`|The amount and data to send to pay hooks (this contract) instead of adding to the terminal's balance.|


### hasMintPermissionFor

Required by the IJBRulesetDataHook interfaces. Return false to not leak any permissions.


```solidity
function hasMintPermissionFor(uint256, JBRuleset memory, address) external pure returns (bool);
```

### cashOutWeightOf

Returns the cumulative cash out weight of the specified token IDs relative to the
`totalCashOutWeight`.


```solidity
function cashOutWeightOf(uint256[] memory tokenIds) public view virtual returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|The NFT token IDs to calculate the cumulative cash out weight of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The cumulative cash out weight of the specified token IDs.|


### supportsInterface

Indicates if this contract adheres to the specified interface.

See [IERC165-supportsInterface](/src/JB721TiersHook.sol/contract.JB721TiersHook.md#supportsinterface).


```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`interfaceId`|`bytes4`|The ID of the interface to check for adherence to.|


### totalCashOutWeight

Calculates the cumulative cash out weight of all NFT token IDs.


```solidity
function totalCashOutWeight() public view virtual returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total cumulative cash out weight of all NFT token IDs.|


### afterCashOutRecordedWith

Burns the specified NFTs upon token holder cash out, reclaiming funds from the project's balance for
`context.beneficiary`. Part of `IJBCashOutHook`.

Reverts if the calling contract is not one of the project's terminals.


```solidity
function afterCashOutRecordedWith(JBAfterCashOutRecordedContext calldata context)
    external
    payable
    virtual
    override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBAfterCashOutRecordedContext`|The cash out context passed in by the terminal.|


### afterPayRecordedWith

Mints one or more NFTs to the `context.beneficiary` upon payment if conditions are met. Part of
`IJBPayHook`.

Reverts if the calling contract is not one of the project's terminals.


```solidity
function afterPayRecordedWith(JBAfterPayRecordedContext calldata context) external payable virtual override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBAfterPayRecordedContext`|The payment context passed in by the terminal.|


### _didBurn

Executes after NFTs have been burned via cash out.


```solidity
function _didBurn(uint256[] memory tokenIds) internal virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenIds`|`uint256[]`|The token IDs of the NFTs that were burned.|


### _initialize

Initializes the contract by associating it with a project and adding ERC721 details.


```solidity
function _initialize(uint256 projectId, string memory name, string memory symbol) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project that this contract is associated with.|
|`name`|`string`|The name of the NFT collection.|
|`symbol`|`string`|The symbol representing the NFT collection.|


### _processPayment

Process a received payment.


```solidity
function _processPayment(JBAfterPayRecordedContext calldata context) internal virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`context`|`JBAfterPayRecordedContext`|The payment context passed in by the terminal.|


## Errors
### JB721Hook_InvalidCashOut

```solidity
error JB721Hook_InvalidCashOut();
```

### JB721Hook_InvalidPay

```solidity
error JB721Hook_InvalidPay();
```

### JB721Hook_UnauthorizedToken

```solidity
error JB721Hook_UnauthorizedToken(uint256 tokenId, address holder);
```

### JB721Hook_UnexpectedTokenCashedOut

```solidity
error JB721Hook_UnexpectedTokenCashedOut();
```

