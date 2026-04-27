// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {JBAfterPayRecordedContext} from "@bananapus/core-v6/src/structs/JBAfterPayRecordedContext.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

contract RetroactiveReserveBeneficiaryDilution is UnitTestSetup {
    function _buildPayMetadata(address hookAddress, uint16[] memory tierIdsToMint)
        internal
        view
        returns (bytes memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", hookAddress);
        return metadataHelper.createMetadata(ids, data);
    }

    function _afterPayContext(
        address hookAddress,
        uint256 amountValue,
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
                value: 0,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: "",
            payerMetadata: _buildPayMetadata(hookAddress, tierIdsToMint)
        });
    }

    function test_adjustTier_can_retroactively_create_reserves_for_existing_supply() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);

        JB721TierConfig[] memory tier1 = new JB721TierConfig[](1);
        tier1[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 2,
            reserveBeneficiary: address(0),
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
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        vm.prank(owner);
        testHook.adjustTiers(tier1, new uint256[](0));

        assertEq(
            testHook.STORE().numberOfPendingReservesFor(address(testHook), 1),
            0,
            "no beneficiary means no reserves are pending"
        );

        vm.mockCall(
            mockJBDirectory,
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint16[] memory mintIds = new uint16[](3);
        mintIds[0] = 1;
        mintIds[1] = 1;
        mintIds[2] = 1;

        JBAfterPayRecordedContext memory payContext = _afterPayContext(address(testHook), 3 ether, mintIds);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith(payContext);

        assertEq(testHook.balanceOf(beneficiary), 3, "beneficiary should own the three paid NFTs");
        assertEq(testHook.totalCashOutWeight(), 3 ether, "denominator initially reflects only sold NFTs");

        JB721TierConfig[] memory tier2 = new JB721TierConfig[](1);
        tier2[0] = JB721TierConfig({
            price: 2 ether,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 1,
            reserveBeneficiary: owner,
            encodedIPFSUri: bytes32(uint256(0x5678)),
            category: 2,
            discountPercent: 0,
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: true,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        vm.prank(owner);
        testHook.adjustTiers(tier2, new uint256[](0));

        assertEq(
            testHook.STORE().reserveBeneficiaryOf(address(testHook), 1),
            owner,
            "new default beneficiary retroactively applies to the old tier"
        );
        assertEq(
            testHook.STORE().numberOfPendingReservesFor(address(testHook), 1),
            2,
            "historical sales now generate retroactive pending reserves"
        );
        assertEq(
            testHook.totalCashOutWeight(),
            5 ether,
            "existing holders are diluted before any new payment enters the system"
        );

        vm.prank(address(0xBEEF));
        testHook.mintPendingReservesFor(1, 2);

        assertEq(testHook.balanceOf(owner), 2, "retroactive reserves mint directly to the new default beneficiary");
        assertEq(
            testHook.STORE().numberOfPendingReservesFor(address(testHook), 1),
            0,
            "all retroactive reserve entitlement can be extracted"
        );
    }
}
