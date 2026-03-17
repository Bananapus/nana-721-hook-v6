# IJB721TiersHookDeployer
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/interfaces/IJB721TiersHookDeployer.sol)

Deploys 721 tiers hooks for projects.


## Functions
### deployHookFor

Deploys a 721 tiers hook for the specified project.


```solidity
function deployHookFor(
    uint256 projectId,
    JBDeploy721TiersHookConfig memory deployTiersHookConfig,
    bytes32 salt
)
    external
    returns (IJB721TiersHook newHook);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project to deploy the hook for.|
|`deployTiersHookConfig`|`JBDeploy721TiersHookConfig`|The config to deploy the hook with.|
|`salt`|`bytes32`|A salt to use for the deterministic deployment.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`newHook`|`IJB721TiersHook`|The address of the newly deployed hook.|


## Events
### HookDeployed
Emitted when a 721 tiers hook is deployed for a project.


```solidity
event HookDeployed(uint256 indexed projectId, IJB721TiersHook hook, address caller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project the hook was deployed for.|
|`hook`|`IJB721TiersHook`|The deployed hook contract.|
|`caller`|`address`|The address that called the function.|

