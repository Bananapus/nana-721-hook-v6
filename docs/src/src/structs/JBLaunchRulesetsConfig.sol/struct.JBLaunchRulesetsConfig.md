# JBLaunchRulesetsConfig
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JBLaunchRulesetsConfig.sol)

**Notes:**
- member: projectId The ID of the project to launch rulesets for.

- member: rulesetConfigurations The ruleset configurations to queue.

- member: terminalConfigurations The terminal configurations to add for the project.

- member: memo A memo to pass along to the emitted event.


```solidity
struct JBLaunchRulesetsConfig {
uint56 projectId;
JBPayDataHookRulesetConfig[] rulesetConfigurations;
JBTerminalConfig[] terminalConfigurations;
string memo;
}
```

