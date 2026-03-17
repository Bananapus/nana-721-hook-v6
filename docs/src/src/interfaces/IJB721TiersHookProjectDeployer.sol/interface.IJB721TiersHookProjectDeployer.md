# IJB721TiersHookProjectDeployer
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/interfaces/IJB721TiersHookProjectDeployer.sol)

Deploys projects with 721 tiers hooks attached.


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


### HOOK_DEPLOYER

The 721 tiers hook deployer.


```solidity
function HOOK_DEPLOYER() external view returns (IJB721TiersHookDeployer);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IJB721TiersHookDeployer`|The hook deployer contract.|


### launchProjectFor

Launches a new project with a 721 tiers hook attached.


```solidity
function launchProjectFor(
    address owner,
    JBDeploy721TiersHookConfig memory deployTiersHookConfig,
    JBLaunchProjectConfig memory launchProjectConfig,
    IJBController controller,
    bytes32 salt
)
    external
    returns (uint256 projectId, IJB721TiersHook hook);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The address to set as the owner of the project.|
|`deployTiersHookConfig`|`JBDeploy721TiersHookConfig`|Configuration which dictates the behavior of the 721 tiers hook.|
|`launchProjectConfig`|`JBLaunchProjectConfig`|Configuration which dictates the behavior of the project.|
|`controller`|`IJBController`|The controller that the project's rulesets will be queued with.|
|`salt`|`bytes32`|A salt to use for the deterministic deployment.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the newly launched project.|
|`hook`|`IJB721TiersHook`|The 721 tiers hook that was deployed for the project.|


### launchRulesetsFor

Launches rulesets for a project with an attached 721 tiers hook.


```solidity
function launchRulesetsFor(
    uint256 projectId,
    JBDeploy721TiersHookConfig memory deployTiersHookConfig,
    JBLaunchRulesetsConfig memory launchRulesetsConfig,
    IJBController controller,
    bytes32 salt
)
    external
    returns (uint256 rulesetId, IJB721TiersHook hook);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project that rulesets are being launched for.|
|`deployTiersHookConfig`|`JBDeploy721TiersHookConfig`|Configuration which dictates the behavior of the 721 tiers hook.|
|`launchRulesetsConfig`|`JBLaunchRulesetsConfig`|Configuration which dictates the project's new rulesets.|
|`controller`|`IJBController`|The controller that the project's rulesets will be queued with.|
|`salt`|`bytes32`|A salt to use for the deterministic deployment.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`rulesetId`|`uint256`|The ID of the successfully created ruleset.|
|`hook`|`IJB721TiersHook`|The 721 tiers hook that was deployed for the project.|


### queueRulesetsOf

Queues rulesets for a project with an attached 721 tiers hook.


```solidity
function queueRulesetsOf(
    uint256 projectId,
    JBDeploy721TiersHookConfig memory deployTiersHookConfig,
    JBQueueRulesetsConfig memory queueRulesetsConfig,
    IJBController controller,
    bytes32 salt
)
    external
    returns (uint256 rulesetId, IJB721TiersHook hook);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`projectId`|`uint256`|The ID of the project that rulesets are being queued for.|
|`deployTiersHookConfig`|`JBDeploy721TiersHookConfig`|Configuration which dictates the behavior of the 721 tiers hook.|
|`queueRulesetsConfig`|`JBQueueRulesetsConfig`|Configuration which dictates the project's newly queued rulesets.|
|`controller`|`IJBController`|The controller that the project's rulesets will be queued with.|
|`salt`|`bytes32`|A salt to use for the deterministic deployment.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`rulesetId`|`uint256`|The ID of the successfully created ruleset.|
|`hook`|`IJB721TiersHook`|The 721 tiers hook that was deployed for the project.|


