// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBPayDataHookRulesetConfig} from "./JBPayDataHookRulesetConfig.sol";

/// @custom:member projectId The ID of the project to queue rulesets for.
/// @custom:member rulesetConfigurations The ruleset configurations to queue.
/// @custom:member memo A memo to pass along to the emitted event.
// forge-lint: disable-next-line(pascal-case-struct)
struct JBQueueRulesetsConfig {
    uint56 projectId;
    JBPayDataHookRulesetConfig[] rulesetConfigurations;
    string memo;
}
