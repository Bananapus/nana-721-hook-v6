// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core-v6/src/structs/JBBeforePayRecordedContext.sol";
import {JBPayHookSpecification} from "@bananapus/core-v6/src/structs/JBPayHookSpecification.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

/// @notice Regression test: split metadata is proportionally scaled when credits fund a split-bearing tier mint.
/// @dev Previously (pre-fix), the per-tier split amounts were left at the uncapped value, trapping forwarded ETH.
/// After the F-2 fix, split amounts are scaled down to match the actual forwarded amount.
contract SplitCreditsMismatch is UnitTestSetup {
    address internal splitBeneficiary = makeAddr("splitBeneficiary");

    function setUp() public override {
        super.setUp();
        vm.etch(mockJBSplits, new bytes(0x69));
    }

    function _buildPayMetadata(
        address hookAddress,
        bool allowOverspending,
        uint16[] memory tierIdsToMint
    )
        internal
        view
        returns (bytes memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", hookAddress);
        return metadataHelper.createMetadata(ids, data);
    }

    function _beforePayContext(
        address hookAddress,
        uint256 amountValue,
        uint16[] memory tierIdsToMint
    )
        internal
        view
        returns (JBBeforePayRecordedContext memory)
    {
        return JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: amountValue,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: _buildPayMetadata(hookAddress, false, tierIdsToMint)
        });
    }

    function _afterPayContext(
        address hookAddress,
        uint256 amountValue,
        uint256 forwardedAmountValue,
        bytes memory hookMetadata,
        uint16[] memory tierIdsToMint
    )
        internal
        view
        returns (JBAfterPayRecordedContext memory)
    {
        return JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: amountValue,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: forwardedAmountValue,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: hookMetadata,
            payerMetadata: _buildPayMetadata(hookAddress, true, tierIdsToMint)
        });
    }

    function test_payCreditsScaleSplitMetadata_andForwardEth() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        vm.mockCall(
            mockJBDirectory,
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Tier costs 1 ether and routes 100% of its effective price to splits.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: bytes32(uint256(0x1234)),
            category: 1,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 1_000_000_000,
            splits: new JBSplit[](0)
        });

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Seed 1 ether of pay credits with an earlier overpayment.
        uint16[] memory noTiers = new uint16[](0);
        JBAfterPayRecordedContext memory creditSeedContext = JBAfterPayRecordedContext({
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
                value: 0,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: "",
            payerMetadata: _buildPayMetadata(address(testHook), true, noTiers)
        });
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith(creditSeedContext);
        assertEq(testHook.payCreditsOf(beneficiary), 1 ether, "setup: pay credits should be seeded");

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);

        // beforePay caps the forwarded amount to the actual payment...
        (, JBPayHookSpecification[] memory specs) =
            testHook.beforePayRecordedWith(_beforePayContext(address(testHook), 1, mintIds));
        assertEq(specs[0].amount, 1, "forwarded amount should be capped to actual payment");

        // ...and proportionally scales the encoded per-tier split amounts to match the capped total.
        (,, bytes memory splitData) = abi.decode(specs[0].metadata, (address, address, bytes));
        (, uint256[] memory encodedAmounts) = abi.decode(splitData, (uint16[], uint256[]));
        assertEq(encodedAmounts.length, 1, "expected one encoded split amount");
        assertEq(encodedAmounts[0], 1, "hook metadata should be scaled down to match forwarded amount");

        // Route the split to a beneficiary and make project-balance fallback unavailable.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: 1_000_000_000,
            projectId: 0,
            beneficiary: payable(splitBeneficiary),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        vm.mockCall(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );
        vm.mockCall(
            mockJBDirectory,
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, projectId, JBConstants.NATIVE_TOKEN),
            abi.encode(address(0))
        );

        uint256 splitBeneficiaryBalanceBefore = splitBeneficiary.balance;

        // The mint succeeds because pay credits cover the price. With the fix, the split IS honored.
        JBAfterPayRecordedContext memory creditMintContext =
            _afterPayContext(address(testHook), 1, 1, specs[0].metadata, mintIds);
        vm.deal(mockTerminalAddress, 1);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1}(creditMintContext);

        assertEq(testHook.balanceOf(beneficiary), 1, "beneficiary should still receive the NFT");
        assertEq(testHook.payCreditsOf(beneficiary), 1, "only 1 wei of credits should remain");
        // After fix: split beneficiary receives the forwarded ETH, nothing trapped.
        assertEq(splitBeneficiary.balance - splitBeneficiaryBalanceBefore, 1, "split beneficiary should receive 1 wei");
        assertEq(address(testHook).balance, 0, "no ETH should be trapped in the hook");
    }
}
