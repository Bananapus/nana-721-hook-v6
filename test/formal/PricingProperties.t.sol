// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import {JB721Constants} from "../../src/libraries/JB721Constants.sol";

/// @title PricingProperties
/// @notice Functional-correctness properties for the 721 hook's discount, split, weight and decimal-scaling math.
/// @dev These MIRROR the exact arithmetic in:
///       - `JB721TiersHookStore.recordMint` discount block (lines ~1275-1279),
///       - `JB721TiersHookLib._calculateSplitAmounts` discount + split math (lines ~561-569),
///       - `JB721TiersHookLib._calculateWeight` (lines ~607-616),
///       - `JB721TiersHookLib.normalizePaymentValue` same-currency decimal scaling (lines ~460-465).
///      The operands use `mulDiv` over wide domains, so Halmos times out on these; the `testFuzz_*` twin is
///      the primary verification (verdict TESTED). `check_*` twins are kept for completeness/regression.
contract PricingProperties is Test {
    uint16 internal constant DISCOUNT_DENOMINATOR = JB721Constants.DISCOUNT_DENOMINATOR; // 200
    uint256 internal constant SPLITS_TOTAL_PERCENT = 1_000_000_000;

    // ---------------------------------------------------------------------
    // Mirror of the discount formula used identically in recordMint and _calculateSplitAmounts.
    // effectivePrice = price - mulDiv(price, discountPercent, 200)  (only when discountPercent > 0).
    // ---------------------------------------------------------------------
    function _discountedPrice(uint256 price, uint256 discountPercent) internal pure returns (uint256) {
        if (discountPercent == 0) return price;
        return price - mulDiv({x: price, y: discountPercent, denominator: DISCOUNT_DENOMINATOR});
    }

    // =====================================================================
    // P1: A 0% discount leaves the price unchanged.
    // =====================================================================
    function testFuzz_discount_zeroIsIdentity(uint104 price) public {
        assertEq(_discountedPrice(price, 0), price);
    }

    function check_discount_zeroIsIdentity(uint104 price) public pure {
        assert(_discountedPrice(price, 0) == price);
    }

    // =====================================================================
    // P2: A 100% discount (discountPercent == DISCOUNT_DENOMINATOR == 200) yields a free mint.
    // =====================================================================
    function testFuzz_discount_fullIsFree(uint104 price) public {
        assertEq(_discountedPrice(price, DISCOUNT_DENOMINATOR), 0);
    }

    function check_discount_fullIsFree(uint104 price) public pure {
        assert(_discountedPrice(price, DISCOUNT_DENOMINATOR) == 0);
    }

    // =====================================================================
    // P3: The discounted price never exceeds the original price and is never negative
    //     (no underflow). discountPercent is bounded to [0, 200] by the store's validation.
    // =====================================================================
    function testFuzz_discount_neverExceedsPrice(uint104 price, uint8 discountPercent) public {
        vm.assume(discountPercent <= DISCOUNT_DENOMINATOR);
        uint256 discounted = _discountedPrice(price, discountPercent);
        assertLe(discounted, price);
    }

    function check_discount_neverExceedsPrice(uint104 price, uint8 discountPercent) public pure {
        vm.assume(discountPercent <= DISCOUNT_DENOMINATOR);
        uint256 discounted = _discountedPrice(price, discountPercent);
        assert(discounted <= price);
    }

    // =====================================================================
    // P4: The discount is monotonic — a larger discount percent never yields a larger price.
    // =====================================================================
    function testFuzz_discount_monotonic(uint104 price, uint8 dLow, uint8 dHigh) public {
        vm.assume(dHigh <= DISCOUNT_DENOMINATOR);
        vm.assume(dLow <= dHigh);
        assertLe(_discountedPrice(price, dHigh), _discountedPrice(price, dLow));
    }

    function check_discount_monotonic(uint104 price, uint8 dLow, uint8 dHigh) public pure {
        vm.assume(dHigh <= DISCOUNT_DENOMINATOR);
        vm.assume(dLow <= dHigh);
        assert(_discountedPrice(price, dHigh) <= _discountedPrice(price, dLow));
    }

    // =====================================================================
    // P5: Per-tier split amount = mulDiv(effectivePrice, splitPercent, 1e9) <= effectivePrice
    //     when splitPercent <= SPLITS_TOTAL_PERCENT (the store enforces this bound on add).
    //     i.e. a split never routes more than the (discounted) price the buyer pays.
    // =====================================================================
    function _splitAmount(uint256 effectivePrice, uint256 splitPercent) internal pure returns (uint256) {
        return mulDiv({x: effectivePrice, y: splitPercent, denominator: SPLITS_TOTAL_PERCENT});
    }

    function testFuzz_split_neverExceedsPrice(uint104 price, uint32 splitPercent) public {
        vm.assume(splitPercent <= SPLITS_TOTAL_PERCENT);
        assertLe(_splitAmount(price, splitPercent), price);
    }

    // 100% split routes the entire (effective) price.
    function testFuzz_split_fullRoutesAll(uint104 price) public {
        assertEq(_splitAmount(price, SPLITS_TOTAL_PERCENT), price);
    }

    // =====================================================================
    // P6: weight scaling (mirror of _calculateWeight) postconditions.
    //   - no splits OR issueTokensForSplits => full contextWeight.
    //   - splits consume entire payment (amount <= total) => 0.
    //   - partial => mulDiv(weight, value-total, value) and result <= contextWeight.
    // =====================================================================
    function _calcWeight(
        uint256 contextWeight,
        uint256 amountValue,
        uint256 totalSplitAmount,
        bool issueTokensForSplits
    )
        internal
        pure
        returns (uint256 weight)
    {
        if (totalSplitAmount == 0 || issueTokensForSplits) {
            weight = contextWeight;
        } else if (amountValue > totalSplitAmount) {
            weight = mulDiv({x: contextWeight, y: amountValue - totalSplitAmount, denominator: amountValue});
        } else {
            weight = 0;
        }
    }

    function testFuzz_weight_fullWhenNoSplitsOrIssueForSplits(
        uint256 contextWeight,
        uint256 amountValue,
        bool issueTokensForSplits
    )
        public
    {
        // No splits => full weight regardless of the flag.
        assertEq(_calcWeight(contextWeight, amountValue, 0, issueTokensForSplits), contextWeight);
        // issueTokensForSplits => full weight even with splits present.
        assertEq(_calcWeight(contextWeight, amountValue, 12_345, true), contextWeight);
    }

    function testFuzz_weight_zeroWhenSplitsConsumeAll(
        uint256 contextWeight,
        uint256 amountValue,
        uint256 totalSplitAmount
    )
        public
    {
        vm.assume(totalSplitAmount > 0);
        vm.assume(amountValue <= totalSplitAmount);
        assertEq(_calcWeight(contextWeight, amountValue, totalSplitAmount, false), 0);
    }

    function testFuzz_weight_partialNeverExceedsContext(
        uint256 contextWeight,
        uint256 amountValue,
        uint256 totalSplitAmount
    )
        public
    {
        // Constrain to avoid mulDiv overflow on the intermediate product (contextWeight * (value-total)).
        contextWeight = bound(contextWeight, 0, type(uint128).max);
        amountValue = bound(amountValue, 1, type(uint128).max);
        vm.assume(totalSplitAmount > 0 && totalSplitAmount < amountValue);
        uint256 w = _calcWeight(contextWeight, amountValue, totalSplitAmount, false);
        // Partial weight is strictly bounded by the full context weight.
        assertLe(w, contextWeight);
    }

    function check_weight_zeroWhenSplitsConsumeAll(
        uint256 contextWeight,
        uint256 amountValue,
        uint256 totalSplitAmount
    )
        public
        pure
    {
        vm.assume(totalSplitAmount > 0);
        vm.assume(amountValue <= totalSplitAmount);
        assert(_calcWeight(contextWeight, amountValue, totalSplitAmount, false) == 0);
    }

    // =====================================================================
    // P7: normalizePaymentValue same-currency decimal scaling (mirror, lines 460-465).
    //   equal decimals => identity ; more amount decimals => divide ; fewer => multiply.
    //   Round-trip up-then-down recovers the original value exactly.
    // =====================================================================
    function _normalizeSameCurrency(
        uint256 amountValue,
        uint256 amountDecimals,
        uint256 pricingDecimals
    )
        internal
        pure
        returns (uint256)
    {
        if (amountDecimals == pricingDecimals) return amountValue;
        if (amountDecimals > pricingDecimals) {
            return amountValue / (10 ** (amountDecimals - pricingDecimals));
        }
        return amountValue * (10 ** (pricingDecimals - amountDecimals));
    }

    function testFuzz_normalize_equalDecimalsIdentity(uint256 amountValue, uint8 decimals) public {
        decimals = uint8(bound(decimals, 0, 36));
        assertEq(_normalizeSameCurrency(amountValue, decimals, decimals), amountValue);
    }

    function check_normalize_equalDecimalsIdentity(uint256 amountValue, uint8 decimals) public pure {
        vm.assume(decimals <= 36);
        assert(_normalizeSameCurrency(amountValue, decimals, uint256(decimals)) == amountValue);
    }

    // Scaling up (fewer amount decimals than pricing) then back down recovers the value.
    function testFuzz_normalize_upDownRoundTrip(uint128 amountValue, uint8 lo, uint8 hi) public {
        lo = uint8(bound(lo, 0, 18));
        hi = uint8(bound(hi, lo, 36));
        // amountDecimals = lo (< pricingDecimals = hi) => multiply by 10^(hi-lo).
        uint256 up = _normalizeSameCurrency(amountValue, lo, hi);
        // Now treat that as the value at `hi` decimals and scale back to `lo` => divide by 10^(hi-lo).
        uint256 down = _normalizeSameCurrency(up, hi, lo);
        assertEq(down, amountValue);
    }
}
