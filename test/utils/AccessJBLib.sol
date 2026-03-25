// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/libraries/JBCurrencyIds.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/libraries/JBConstants.sol";

contract AccessJBLib {
    // forge-lint: disable-next-line(mixed-case-function)
    function NATIVE() external pure returns (uint256) {
        return uint32(uint160(JBConstants.NATIVE_TOKEN));
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function USD() external pure returns (uint256) {
        return JBCurrencyIds.USD;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function NATIVE_TOKEN() external pure returns (address) {
        return JBConstants.NATIVE_TOKEN;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function MAX_FEE() external pure returns (uint256) {
        return JBConstants.MAX_FEE;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function MAX_RESERVED_PERCENT() external pure returns (uint256) {
        return JBConstants.MAX_RESERVED_PERCENT;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function MAX_CASH_OUT_TAX_RATE() external pure returns (uint256) {
        return JBConstants.MAX_CASH_OUT_TAX_RATE;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function MAX_WEIGHT_CUT_PERCENT() external pure returns (uint256) {
        return JBConstants.MAX_WEIGHT_CUT_PERCENT;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function SPLITS_TOTAL_PERCENT() external pure returns (uint256) {
        return JBConstants.SPLITS_TOTAL_PERCENT;
    }
}
