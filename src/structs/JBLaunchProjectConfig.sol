// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";

import {JBPayDataHookRulesetConfig} from "./JBPayDataHookRulesetConfig.sol";

/// @custom:member projectUri Metadata URI to associate with the project. This can be updated any time by the owner of
/// the project.
/// @custom:member rulesetConfigurations The ruleset configurations to queue.
/// @custom:member terminalConfigurations The terminal configurations to add for the project.
/// @custom:member memo A memo to pass along to the emitted event.
// forge-lint: disable-next-line(pascal-case-struct)
struct JBLaunchProjectConfig {
    string projectUri;
    JBPayDataHookRulesetConfig[] rulesetConfigurations;
    JBTerminalConfig[] terminalConfigurations;
    string memo;
}
