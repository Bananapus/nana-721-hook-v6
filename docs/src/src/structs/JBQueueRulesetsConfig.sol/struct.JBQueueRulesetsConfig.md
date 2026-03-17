# JBQueueRulesetsConfig
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JBQueueRulesetsConfig.sol)

**Notes:**
- member: projectId The ID of the project to queue rulesets for.

- member: rulesetConfigurations The ruleset configurations to queue.

- member: memo A memo to pass along to the emitted event.


```solidity
struct JBQueueRulesetsConfig {
uint56 projectId;
JBPayDataHookRulesetConfig[] rulesetConfigurations;
string memo;
}
```

