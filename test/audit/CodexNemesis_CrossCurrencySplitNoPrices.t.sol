// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../utils/UnitTestSetup.sol";
import {IJB721TokenUriResolver} from "../../src/interfaces/IJB721TokenUriResolver.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBRulesets} from "@bananapus/core-v6/src/interfaces/IJBRulesets.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core-v6/src/structs/JBBeforePayRecordedContext.sol";

contract CodexNemesis_CrossCurrencySplitNoPrices is UnitTestSetup {
    function test_crossCurrencySplit_withoutPrices_locksForwardedNativeFunds() public {
        JB721TiersHook noPricesOrigin = new JB721TiersHook(
            IJBDirectory(mockJBDirectory),
            IJBPermissions(mockJBPermissions),
            IJBPrices(address(0)),
            IJBRulesets(mockJBRulesets),
            store,
            IJBSplits(mockJBSplits),
            trustedForwarder
        );

        address noPricesProxy = makeAddr("noPricesProxy");
        vm.etch(noPricesProxy, address(noPricesOrigin).code);
        JB721TiersHook crossHook = JB721TiersHook(noPricesProxy);

        (JB721TierConfig[] memory tierConfigs,) = _createTiers(defaultTierConfig, 1);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].splitPercent = 500_000_000; // 50%

        crossHook.initialize(
            projectId,
            name,
            symbol,
            baseUri,
            IJB721TokenUriResolver(mockTokenUriResolver),
            contractUri,
            JB721InitTiersConfig({tiers: tierConfigs, currency: uint32(USD()), decimals: 18}),
            JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: false
            })
        );

        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", crossHook.METADATA_ID_TARGET());
        bytes memory payerMetadata = metadataHelper.createMetadata(ids, data);

        (uint256 weight, JBPayHookSpecification[] memory hookSpecifications) = crossHook.beforePayRecordedWith(
            JBBeforePayRecordedContext({
                terminal: mockTerminalAddress,
                payer: beneficiary,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 1 ether,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                projectId: projectId,
                rulesetId: 0,
                beneficiary: beneficiary,
                weight: 10e18,
                reservedPercent: 0,
                metadata: payerMetadata
            })
        );

        // When PRICES is address(0) and currencies differ, convertSplitAmounts returns 0
        // to avoid forwarding an unconverted amount in the wrong currency denomination.
        // This means weight is NOT reduced (full weight) and no funds are forwarded.
        assertEq(weight, 10e18, "weight unchanged when split conversion fails due to missing prices");
        assertEq(hookSpecifications.length, 1, "one pay hook spec");
        assertEq(hookSpecifications[0].amount, 0, "split amount is zero when prices unavailable for conversion");

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: hookSpecifications[0].amount,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: weight,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: hookSpecifications[0].metadata,
            payerMetadata: payerMetadata
        });

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        crossHook.afterPayRecordedWith{value: hookSpecifications[0].amount}(payContext);

        assertEq(crossHook.balanceOf(beneficiary), 0, "no NFTs minted (currency mismatch, no prices)");
        assertEq(crossHook.payCreditsOf(beneficiary), 0, "no credits accrued (currency mismatch, no prices)");
        assertEq(address(crossHook).balance, 0, "no funds forwarded to hook when split conversion returns zero");
    }
}
