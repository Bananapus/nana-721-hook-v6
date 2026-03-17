# JBLaunchProjectConfig
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JBLaunchProjectConfig.sol)

**Notes:**
- member: projectUri Metadata URI to associate with the project. This can be updated any time by the owner of
the project.

- member: rulesetConfigurations The ruleset configurations to queue.

- member: terminalConfigurations The terminal configurations to add for the project.

- member: memo A memo to pass along to the emitted event.


```solidity
struct JBLaunchProjectConfig {
string projectUri;
JBPayDataHookRulesetConfig[] rulesetConfigurations;
JBTerminalConfig[] terminalConfigurations;
string memo;
}
```

