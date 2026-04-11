// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UnitTestSetup} from "../utils/UnitTestSetup.sol";
import {IJB721TokenUriResolver} from "../../src/interfaces/IJB721TokenUriResolver.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBRulesets} from "@bananapus/core-v6/src/interfaces/IJBRulesets.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core-v6/src/structs/JBBeforePayRecordedContext.sol";
import {JBPayHookSpecification} from "@bananapus/core-v6/src/structs/JBPayHookSpecification.sol";
import {JBTokenAmount} from "@bananapus/core-v6/src/structs/JBTokenAmount.sol";
import {JB721TiersHook} from "../../src/JB721TiersHook.sol";
import {JB721CheckpointsFactory} from "../../src/JB721CheckpointsFactory.sol";
import {IJB721CheckpointsFactory} from "../../src/interfaces/IJB721CheckpointsFactory.sol";
import {JB721TierConfig} from "../../src/structs/JB721TierConfig.sol";
import {JB721InitTiersConfig} from "../../src/structs/JB721InitTiersConfig.sol";
import {JB721TiersHookFlags} from "../../src/structs/JB721TiersHookFlags.sol";

/// @notice Regression test for: same-currency decimal mismatch in split forwarding.
/// @dev When pricing decimals differ from payment decimals but the currency is the same,
/// `convertAndCapSplitAmounts` must rescale split amounts before comparing to `amountValue`.
/// Without the fix, split amounts stay in pricing decimals (e.g. 18), the cap comparison uses
/// payment decimals (e.g. 6), and the cap clips the split to 100% of the payment.
contract SameCurrencyDecimalMismatch is UnitTestSetup {
    // Shared constants.
    address constant MOCK_TOKEN = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    // forge-lint: disable-next-line(unsafe-typecast)
    uint32 constant CURRENCY = uint32(uint160(MOCK_TOKEN));

    /// @notice Prove that a 50% split with same currency but different decimals (pricing=18, payment=6)
    /// correctly forwards ~50% of the payment, not 100%.
    function test_sameCurrency_differentDecimals_splitAmountScaledCorrectly() public {
        // Deploy hook with PRICES=address(0), tier priced at 1e18 (18-decimal), 50% split.
        JB721TiersHook testHook;
        {
            JB721TiersHook origin = new JB721TiersHook(
                IJBDirectory(mockJBDirectory),
                IJBPermissions(mockJBPermissions),
                IJBPrices(address(0)),
                IJBRulesets(mockJBRulesets),
                store,
                IJBSplits(mockJBSplits),
                IJB721CheckpointsFactory(address(new JB721CheckpointsFactory())),
                trustedForwarder
            );
            address hookAddr = makeAddr("hook18to6");
            vm.etch(hookAddr, address(origin).code);
            testHook = JB721TiersHook(hookAddr);
        }

        {
            (JB721TierConfig[] memory tierConfigs,) = _createTiers(defaultTierConfig, 1);
            tierConfigs[0].price = 1e18;
            tierConfigs[0].splitPercent = 500_000_000; // 50%.
            testHook.initialize(
                projectId,
                name,
                symbol,
                baseUri,
                IJB721TokenUriResolver(mockTokenUriResolver),
                contractUri,
                JB721InitTiersConfig({tiers: tierConfigs, currency: CURRENCY, decimals: 18}),
                JB721TiersHookFlags({
                    preventOverspending: false,
                    issueTokensForSplits: false,
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false
                })
            );
        }

        // Build payer metadata requesting tier 1.
        bytes memory payerMetadata;
        {
            uint16[] memory tierIdsToMint = new uint16[](1);
            tierIdsToMint[0] = 1;
            bytes[] memory data = new bytes[](1);
            data[0] = abi.encode(true, tierIdsToMint);
            bytes4[] memory ids = new bytes4[](1);
            ids[0] = metadataHelper.getId("pay", testHook.METADATA_ID_TARGET());
            payerMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Pay 1.0 token reported as 6 decimals (value = 1e6). Same currency, different decimals.
        (uint256 weight, JBPayHookSpecification[] memory hookSpecs) = testHook.beforePayRecordedWith(
            JBBeforePayRecordedContext({
                terminal: mockTerminalAddress,
                payer: beneficiary,
                amount: JBTokenAmount({token: MOCK_TOKEN, value: 1e6, decimals: 6, currency: CURRENCY}),
                projectId: projectId,
                rulesetId: 0,
                beneficiary: beneficiary,
                weight: 10e18,
                reservedPercent: 0,
                metadata: payerMetadata
            })
        );

        // Without the fix: split amount (5e17 in 18-decimal pricing) is compared to amountValue (1e6),
        // causing the cap to clip it to 1e6 (100% of payment) and weight becomes 0.
        // With the fix: split is rescaled to 5e5 (50% of 1e6) and weight is 5e18.
        assertEq(hookSpecs[0].amount, 5e5, "split should be 50% of payment (5e5), not capped to 100%");
        assertEq(weight, 5e18, "weight should be 50% (half goes to splits)");
    }

    /// @notice Sanity check: same currency AND same decimals — no rescaling needed.
    function test_sameCurrency_sameDecimals_splitAmountUnchanged() public {
        JB721TiersHook testHook;
        {
            JB721TiersHook origin = new JB721TiersHook(
                IJBDirectory(mockJBDirectory),
                IJBPermissions(mockJBPermissions),
                IJBPrices(address(0)),
                IJBRulesets(mockJBRulesets),
                store,
                IJBSplits(mockJBSplits),
                IJB721CheckpointsFactory(address(new JB721CheckpointsFactory())),
                trustedForwarder
            );
            address hookAddr = makeAddr("hook18to18");
            vm.etch(hookAddr, address(origin).code);
            testHook = JB721TiersHook(hookAddr);
        }

        {
            (JB721TierConfig[] memory tierConfigs,) = _createTiers(defaultTierConfig, 1);
            tierConfigs[0].price = 1e18;
            tierConfigs[0].splitPercent = 500_000_000;
            testHook.initialize(
                projectId,
                name,
                symbol,
                baseUri,
                IJB721TokenUriResolver(mockTokenUriResolver),
                contractUri,
                JB721InitTiersConfig({tiers: tierConfigs, currency: CURRENCY, decimals: 18}),
                JB721TiersHookFlags({
                    preventOverspending: false,
                    issueTokensForSplits: false,
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false
                })
            );
        }

        bytes memory payerMetadata;
        {
            uint16[] memory tierIdsToMint = new uint16[](1);
            tierIdsToMint[0] = 1;
            bytes[] memory data = new bytes[](1);
            data[0] = abi.encode(true, tierIdsToMint);
            bytes4[] memory ids = new bytes4[](1);
            ids[0] = metadataHelper.getId("pay", testHook.METADATA_ID_TARGET());
            payerMetadata = metadataHelper.createMetadata(ids, data);
        }

        (uint256 weight, JBPayHookSpecification[] memory hookSpecs) = testHook.beforePayRecordedWith(
            JBBeforePayRecordedContext({
                terminal: mockTerminalAddress,
                payer: beneficiary,
                amount: JBTokenAmount({token: MOCK_TOKEN, value: 1e18, decimals: 18, currency: CURRENCY}),
                projectId: projectId,
                rulesetId: 0,
                beneficiary: beneficiary,
                weight: 10e18,
                reservedPercent: 0,
                metadata: payerMetadata
            })
        );

        assertEq(hookSpecs[0].amount, 5e17, "split should be 50% of payment");
        assertEq(weight, 5e18, "weight should be 50%");
    }

    /// @notice Same currency, payment has MORE decimals than pricing (pricing=6, payment=18).
    function test_sameCurrency_paymentMoreDecimals_splitScaledUp() public {
        JB721TiersHook testHook;
        {
            JB721TiersHook origin = new JB721TiersHook(
                IJBDirectory(mockJBDirectory),
                IJBPermissions(mockJBPermissions),
                IJBPrices(address(0)),
                IJBRulesets(mockJBRulesets),
                store,
                IJBSplits(mockJBSplits),
                IJB721CheckpointsFactory(address(new JB721CheckpointsFactory())),
                trustedForwarder
            );
            address hookAddr = makeAddr("hook6to18");
            vm.etch(hookAddr, address(origin).code);
            testHook = JB721TiersHook(hookAddr);
        }

        {
            (JB721TierConfig[] memory tierConfigs,) = _createTiers(defaultTierConfig, 1);
            tierConfigs[0].price = 1e6; // 1.0 token in 6-decimal pricing.
            tierConfigs[0].splitPercent = 500_000_000;
            testHook.initialize(
                projectId,
                name,
                symbol,
                baseUri,
                IJB721TokenUriResolver(mockTokenUriResolver),
                contractUri,
                JB721InitTiersConfig({tiers: tierConfigs, currency: CURRENCY, decimals: 6}),
                JB721TiersHookFlags({
                    preventOverspending: false,
                    issueTokensForSplits: false,
                    noNewTiersWithReserves: false,
                    noNewTiersWithVotes: false,
                    noNewTiersWithOwnerMinting: false
                })
            );
        }

        bytes memory payerMetadata;
        {
            uint16[] memory tierIdsToMint = new uint16[](1);
            tierIdsToMint[0] = 1;
            bytes[] memory data = new bytes[](1);
            data[0] = abi.encode(true, tierIdsToMint);
            bytes4[] memory ids = new bytes4[](1);
            ids[0] = metadataHelper.getId("pay", testHook.METADATA_ID_TARGET());
            payerMetadata = metadataHelper.createMetadata(ids, data);
        }

        (uint256 weight, JBPayHookSpecification[] memory hookSpecs) = testHook.beforePayRecordedWith(
            JBBeforePayRecordedContext({
                terminal: mockTerminalAddress,
                payer: beneficiary,
                amount: JBTokenAmount({token: MOCK_TOKEN, value: 1e18, decimals: 18, currency: CURRENCY}),
                projectId: projectId,
                rulesetId: 0,
                beneficiary: beneficiary,
                weight: 10e18,
                reservedPercent: 0,
                metadata: payerMetadata
            })
        );

        // 50% of 1.0 token in 18-decimal payment = 5e17.
        assertEq(hookSpecs[0].amount, 5e17, "split scaled up to 18-decimal payment");
        assertEq(weight, 5e18, "weight should be 50%");
    }
}
