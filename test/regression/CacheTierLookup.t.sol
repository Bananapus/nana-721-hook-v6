// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
// forge-lint: disable-next-line(unused-import)
import {JB721TiersHookLib} from "../../src/libraries/JB721TiersHookLib.sol";

/// @notice calculateSplitAmounts caches the tierOf result to avoid a duplicate external call.
/// Verifies that the cached tier lookup returns the same split amounts as reading price and splitPercent individually.
contract Test_L35_CacheTierLookup is UnitTestSetup {
    using stdStorage for StdStorage;

    /// @notice Verify that calculateSplitAmounts returns correct per-tier amounts when multiple tiers have different
    /// prices and split percentages. This exercises the cached `tier` variable.
    function test_calculateSplitAmounts_multiTier_correctAmounts() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add 3 tiers with different prices and split percents.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](3);

        // Tier A: 1 ETH, 25% split -> 0.25 ETH
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1111));
        tierConfigs[0].splitPercent = 250_000_000; // 25%

        // Tier B: 2 ETH, 50% split -> 1 ETH
        tierConfigs[1].price = 2 ether;
        tierConfigs[1].initialSupply = uint32(100);
        tierConfigs[1].category = uint24(2);
        tierConfigs[1].encodedIPFSUri = bytes32(uint256(0x2222));
        tierConfigs[1].splitPercent = 500_000_000; // 50%

        // Tier C: 0.5 ETH, 100% split -> 0.5 ETH
        tierConfigs[2].price = 0.5 ether;
        tierConfigs[2].initialSupply = uint32(100);
        tierConfigs[2].category = uint24(3);
        tierConfigs[2].encodedIPFSUri = bytes32(uint256(0x3333));
        tierConfigs[2].splitPercent = 1_000_000_000; // 100%

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Build payer metadata requesting all 3 tiers.
        uint16[] memory mintIds = new uint16[](3);
        mintIds[0] = uint16(tierIds[0]);
        mintIds[1] = uint16(tierIds[1]);
        mintIds[2] = uint16(tierIds[2]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 3.5 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: payerMetadata
        });

        (, JBPayHookSpecification[] memory specs) = testHook.beforePayRecordedWith(context);

        // Total split = 0.25 + 1.0 + 0.5 = 1.75 ETH
        assertEq(specs[0].amount, 1.75 ether, "Total split amount should be 1.75 ETH");
    }

    /// @notice Verify that a tier with splitPercent == 0 contributes nothing to the total, even when cached.
    function test_calculateSplitAmounts_zeroSplitSkipped() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Tier A: 1 ETH, 50% split
        // Tier B: 3 ETH, 0% split (should be skipped)
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](2);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0xAAAA));
        tierConfigs[0].splitPercent = 500_000_000; // 50%

        tierConfigs[1].price = 3 ether;
        tierConfigs[1].initialSupply = uint32(100);
        tierConfigs[1].category = uint24(2);
        tierConfigs[1].encodedIPFSUri = bytes32(uint256(0xBBBB));
        tierConfigs[1].splitPercent = 0; // 0%

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        uint16[] memory mintIds = new uint16[](2);
        mintIds[0] = uint16(tierIds[0]);
        mintIds[1] = uint16(tierIds[1]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 4 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: payerMetadata
        });

        (, JBPayHookSpecification[] memory specs) = testHook.beforePayRecordedWith(context);

        // Only tier A contributes: 1 ETH * 50% = 0.5 ETH
        assertEq(specs[0].amount, 0.5 ether, "Only non-zero split tiers should contribute");
    }

    /// @notice Verify that duplicate tier IDs in metadata produce correct cumulative split amounts.
    /// The cached tier lookup must handle the same tier appearing multiple times.
    function test_calculateSplitAmounts_duplicateTierIds() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Single tier: 1 ETH, 30% split
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0xCCCC));
        tierConfigs[0].splitPercent = 300_000_000; // 30%

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Request the same tier twice in metadata.
        uint16[] memory mintIds = new uint16[](2);
        mintIds[0] = uint16(tierIds[0]);
        mintIds[1] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 2 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: payerMetadata
        });

        (, JBPayHookSpecification[] memory specs) = testHook.beforePayRecordedWith(context);

        // 2 x (1 ETH * 30%) = 0.6 ETH
        assertEq(specs[0].amount, 0.6 ether, "Duplicate tier IDs should each contribute their split amount");
    }

    // Helper: build payer metadata for tier IDs.
    function _buildPayerMetadata(
        address hookAddress,
        uint16[] memory tierIdsToMint
    )
        internal
        view
        returns (bytes memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", hookAddress);
        return metadataHelper.createMetadata(ids, data);
    }
}
