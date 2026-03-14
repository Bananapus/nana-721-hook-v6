// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member reservedPercent The reserved percent of the ruleset. This number is a percentage calculated out of
/// `JBConstants.MAX_RESERVED_PERCENT`.
/// @custom:member cashOutTaxRate The cash out tax rate of the ruleset. This number is a percentage calculated out of
/// `JBConstants.MAX_CASH_OUT_TAX_RATE`.
/// @custom:member baseCurrency The currency on which to base the ruleset's weight.
/// @custom:member pausePay A flag indicating if the pay functionality should be paused during the ruleset.
/// @custom:member pauseCreditTransfers A flag indicating if the project token transfer functionality should be paused
/// during the funding cycle.
/// @custom:member allowOwnerMinting A flag indicating if the project owner or an operator with the `MINT_TOKENS`
/// permission from the owner should be allowed to mint project tokens on demand during this ruleset.
/// @custom:member allowSetCustomToken A flag indicating if the project owner can set the project's token to a custom
/// ERC-20.
/// @custom:member allowTerminalMigration A flag indicating if migrating terminals should be allowed during this
/// ruleset.
/// @custom:member allowSetTerminals A flag indicating if a project's terminals can be added or removed.
/// @custom:member allowSetController A flag indicating if a project's controller can be changed.
/// @custom:member allowAddAccountingContext A flag indicating if a project can add new accounting contexts for its
/// terminals to use.
/// @custom:member allowAddPriceFeed A flag indicating if a project can add new price feeds to calculate exchange rates
/// between its tokens.
/// @custom:member holdFees A flag indicating if fees should be held during this ruleset.
/// @custom:member useTotalSurplusForCashOut A flag indicating if cash outs should use the project's balance held
/// in all terminals instead of the project's local terminal balance from which the cash out is being fulfilled.
/// @custom:member useDataHookForCashOuts A flag indicating if the data hook should be used for cash out transactions
/// during
/// this ruleset.
/// @custom:member metadata Metadata of the metadata, up to uint8 in size.
// forge-lint: disable-next-line(pascal-case-struct)
struct JBPayDataHookRulesetMetadata {
    uint16 reservedPercent;
    uint16 cashOutTaxRate;
    uint32 baseCurrency;
    bool pausePay;
    bool pauseCreditTransfers;
    bool allowOwnerMinting;
    bool allowSetCustomToken;
    bool allowTerminalMigration;
    bool allowSetTerminals;
    bool allowSetController;
    bool allowAddAccountingContext;
    bool allowAddPriceFeed;
    bool ownerMustSendPayouts;
    bool holdFees;
    bool useTotalSurplusForCashOuts;
    bool useDataHookForCashOut;
    uint16 metadata;
}
