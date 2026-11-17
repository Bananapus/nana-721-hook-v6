// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

/// @notice One held tier split payout, as the arguments of `processHeldPayoutOf`.
/// @custom:member token The token of the payout.
/// @custom:member tierId The tier whose split group the split belongs to.
/// @custom:member decimals The decimals of `token`, as emitted in `HoldPayout`.
/// @custom:member split The held split, as emitted in `HoldPayout`.
struct JB721HeldPayout {
    address token;
    uint16 tierId;
    uint256 decimals;
    JBSplit split;
}
