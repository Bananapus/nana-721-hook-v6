# JBPayDataHookRulesetMetadata
[Git Source](https://github.com/Bananapus/nana-721-hook-v6/blob/2d965352774f2f9c4a660a86beafc9f8172805e3/src/structs/JBPayDataHookRulesetMetadata.sol)

**Notes:**
- member: reservedPercent The reserved percent of the ruleset. This number is a percentage calculated out of
`JBConstants.MAX_RESERVED_PERCENT`.

- member: cashOutTaxRate The cash out tax rate of the ruleset. This number is a percentage calculated out of
`JBConstants.MAX_CASH_OUT_TAX_RATE`.

- member: baseCurrency The currency on which to base the ruleset's weight.

- member: pausePay A flag indicating if the pay functionality should be paused during the ruleset.

- member: pauseCreditTransfers A flag indicating if the project token transfer functionality should be paused
during the funding cycle.

- member: allowOwnerMinting A flag indicating if the project owner or an operator with the `MINT_TOKENS`
permission from the owner should be allowed to mint project tokens on demand during this ruleset.

- member: allowSetCustomToken A flag indicating if the project owner can set the project's token to a custom
ERC-20.

- member: allowTerminalMigration A flag indicating if migrating terminals should be allowed during this
ruleset.

- member: allowSetTerminals A flag indicating if a project's terminals can be added or removed.

- member: allowSetController A flag indicating if a project's controller can be changed.

- member: allowAddAccountingContext A flag indicating if a project can add new accounting contexts for its
terminals to use.

- member: allowAddPriceFeed A flag indicating if a project can add new price feeds to calculate exchange rates
between its tokens.

- member: holdFees A flag indicating if fees should be held during this ruleset.

- member: useTotalSurplusForCashOut A flag indicating if cash outs should use the project's balance held
in all terminals instead of the project's local terminal balance from which the cash out is being fulfilled.

- member: useDataHookForCashOuts A flag indicating if the data hook should be used for cash out transactions
during
this ruleset.

- member: metadata Metadata of the metadata, up to uint8 in size.


```solidity
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
```

