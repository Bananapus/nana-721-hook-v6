// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../src/interfaces/IJB721TiersHookStore.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// =====================================================================
// Malicious split hook that attempts reentrancy during fund distribution
// =====================================================================

/// @notice A split hook that re-enters the hook's afterPayRecordedWith during split distribution.
contract ReentrantSplitHook is IJBSplitHook {
    address public target;
    bytes public reentrantCalldata;
    uint256 public callCount;
    bool public reentryAttempted;
    bool public reentrySucceeded;

    constructor(address _target, bytes memory _calldata) {
        target = _target;
        reentrantCalldata = _calldata;
    }

    function processSplitWith(JBSplitHookContext calldata) external payable override {
        callCount++;
        // Attempt reentrancy on the first call only.
        if (callCount == 1) {
            reentryAttempted = true;
            // Try to re-enter the hook contract by calling afterPayRecordedWith again.
            // This should revert because msg.sender is not a terminal.
            (bool success,) = target.call{value: 0}(reentrantCalldata);
            reentrySucceeded = success;
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IJBSplitHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    receive() external payable {}
}

/// @notice A split hook that attempts to re-enter adjustTiers during split distribution.
contract ReentrantAdjustTiersSplitHook is IJBSplitHook {
    address public hookTarget;
    uint256 public callCount;
    bool public reentryAttempted;
    bool public reentryReverted;

    constructor(address _hookTarget) {
        hookTarget = _hookTarget;
    }

    function processSplitWith(JBSplitHookContext calldata) external payable override {
        callCount++;
        if (callCount == 1) {
            reentryAttempted = true;
            // Try to re-enter via adjustTiers (remove tier 1).
            uint256[] memory tierIdsToRemove = new uint256[](1);
            tierIdsToRemove[0] = 1;
            // This should revert because caller is not the owner/permissioned.
            try IJB721TiersHook(hookTarget).adjustTiers(new JB721TierConfig[](0), tierIdsToRemove) {
                reentryReverted = false;
            } catch {
                reentryReverted = true;
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IJBSplitHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    receive() external payable {}
}

// =====================================================================
// Test Contract: Reentrancy on Split Distribution
// =====================================================================

/// @title TestAuditGaps_Reentrancy
/// @notice Tests that malicious split hooks cannot exploit reentrancy during NFT split fund distribution.
contract TestAuditGaps_Reentrancy is UnitTestSetup {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.etch(mockJBSplits, new bytes(0x69));
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    function _tierConfigWithSplit(
        uint104 price,
        uint32 splitPercent
    )
        internal
        pure
        returns (JB721TierConfig memory config)
    {
        config.price = price;
        config.initialSupply = uint32(100);
        config.category = uint24(1);
        config.encodedIPFSUri = bytes32(uint256(0x1234));
        config.splitPercent = splitPercent;
    }

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

    /// @dev Build a full JBAfterPayRecordedContext with split forwarding.
    function _buildPayContextWithSplits(
        address hookAddress,
        uint16[] memory mintIds,
        uint16[] memory splitTierIds,
        uint256[] memory splitAmounts,
        uint256 payValue,
        uint256 forwardValue
    )
        internal
        view
        returns (JBAfterPayRecordedContext memory)
    {
        bytes memory payerMetadata = _buildPayerMetadata(hookAddress, mintIds);

        return JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: payValue,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: forwardValue,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });
    }

    // ---------------------------------------------------------------
    // Test 1: Reentrant split hook cannot re-call afterPayRecordedWith
    // ---------------------------------------------------------------
    /// @notice A malicious split hook tries to re-enter afterPayRecordedWith during
    /// fund distribution. The reentrancy is blocked because the split hook's address
    /// is not registered as a terminal in the directory.
    function test_reentrancy_splitHook_cannotReenterAfterPay() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add tier with 100% split, priced at 1 ETH.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 1_000_000_000);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Mock the terminal check for the legitimate terminal.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Build reentrant calldata (a second afterPayRecordedWith call).
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 1 ether;

        JBAfterPayRecordedContext memory reentrantContext =
            _buildPayContextWithSplits(address(testHook), mintIds, splitTierIds, splitAmounts, 1 ether, 1 ether);

        // Create the reentrant split hook.
        ReentrantSplitHook reentrantHook = new ReentrantSplitHook(
            address(testHook), abi.encodeCall(testHook.afterPayRecordedWith, (reentrantContext))
        );

        // Set up splits: 100% to the malicious hook.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(reentrantHook))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        // The reentrant split hook is NOT a terminal, so mock it as such.
        vm.mockCall(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, address(reentrantHook)),
            abi.encode(false)
        );

        // Execute the payment.
        JBAfterPayRecordedContext memory payContext =
            _buildPayContextWithSplits(address(testHook), mintIds, splitTierIds, splitAmounts, 1 ether, 1 ether);

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        // Verify the split hook was called.
        assertEq(reentrantHook.callCount(), 1, "Split hook should be called once");

        // Verify reentrancy was attempted but failed (the hook contract checks msg.sender is a terminal).
        assertTrue(reentrantHook.reentryAttempted(), "Reentrancy should have been attempted");
        assertFalse(reentrantHook.reentrySucceeded(), "Reentrancy should have failed");
    }

    // ---------------------------------------------------------------
    // Test 2: Reentrant split hook cannot re-call adjustTiers
    // ---------------------------------------------------------------
    /// @notice A malicious split hook tries to call adjustTiers during fund distribution.
    /// The call is blocked by permission checks (caller is the hook library, not the owner).
    function test_reentrancy_splitHook_cannotReenterAdjustTiers() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add tier with 100% split, priced at 1 ETH.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 1_000_000_000);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Create the malicious hook that tries adjustTiers.
        ReentrantAdjustTiersSplitHook maliciousHook = new ReentrantAdjustTiersSplitHook(address(testHook));

        // Mock permissions: the malicious hook does NOT have permission.
        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(IJBPermissions.hasPermission.selector, address(maliciousHook)),
            abi.encode(false)
        );

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(maliciousHook))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 1 ether;

        JBAfterPayRecordedContext memory payContext =
            _buildPayContextWithSplits(address(testHook), mintIds, splitTierIds, splitAmounts, 1 ether, 1 ether);

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        // Verify the split hook was called and the reentrancy was attempted.
        assertEq(maliciousHook.callCount(), 1, "Split hook should be called once");
        assertTrue(maliciousHook.reentryAttempted(), "Reentrancy should have been attempted");
        assertTrue(maliciousHook.reentryReverted(), "adjustTiers reentrancy should have reverted");
    }

    // ---------------------------------------------------------------
    // Test 3: Split hook with multiple tiers cannot manipulate state
    // ---------------------------------------------------------------
    /// @notice With multiple tiers having splits, a malicious hook on the first tier cannot
    /// affect the distribution of the second tier. State should be consistent after distribution.
    function test_reentrancy_multiTierSplit_stateConsistent() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add two tiers, each with 50% split, priced at 0.5 ETH each.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](2);
        tierConfigs[0] = _tierConfigWithSplit(0.5 ether, 500_000_000); // 50% split
        tierConfigs[0].category = 1;
        tierConfigs[1] = _tierConfigWithSplit(0.5 ether, 500_000_000); // 50% split
        tierConfigs[1].category = 2;
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Create the reentrant split hook for tier 1, and a clean beneficiary for tier 2.
        ReentrantAdjustTiersSplitHook maliciousHook = new ReentrantAdjustTiersSplitHook(address(testHook));
        address cleanBeneficiary = makeAddr("cleanBeneficiary");

        // Tier 1 splits: 100% to malicious hook.
        JBSplit[] memory splits1 = new JBSplit[](1);
        splits1[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(maliciousHook))
        });

        // Tier 2 splits: 100% to clean beneficiary.
        JBSplit[] memory splits2 = new JBSplit[](1);
        splits2[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(cleanBeneficiary),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId1 = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        uint256 groupId2 = uint256(uint160(address(testHook))) | (uint256(tierIds[1]) << 160);

        mockAndExpect(
            mockJBSplits,
            abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId1),
            abi.encode(splits1)
        );
        mockAndExpect(
            mockJBSplits,
            abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId2),
            abi.encode(splits2)
        );

        // Mock permissions to deny the malicious hook.
        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(IJBPermissions.hasPermission.selector, address(maliciousHook)),
            abi.encode(false)
        );

        uint16[] memory mintIds = new uint16[](2);
        mintIds[0] = uint16(tierIds[0]);
        mintIds[1] = uint16(tierIds[1]);

        uint16[] memory splitTierIds = new uint16[](2);
        splitTierIds[0] = uint16(tierIds[0]);
        splitTierIds[1] = uint16(tierIds[1]);
        uint256[] memory splitAmounts = new uint256[](2);
        splitAmounts[0] = 0.25 ether; // 50% of 0.5 ETH
        splitAmounts[1] = 0.25 ether;

        JBAfterPayRecordedContext memory payContext =
            _buildPayContextWithSplits(address(testHook), mintIds, splitTierIds, splitAmounts, 1 ether, 0.5 ether);

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 0.5 ether}(payContext);

        // Verify both splits were distributed.
        assertEq(maliciousHook.callCount(), 1, "Malicious hook should be called for tier 1");
        assertEq(address(maliciousHook).balance, 0.25 ether, "Malicious hook should get tier 1 split");
        assertEq(cleanBeneficiary.balance, 0.25 ether, "Clean beneficiary should get tier 2 split");

        // Verify NFTs were minted (state is consistent).
        assertEq(testHook.balanceOf(beneficiary), 2, "Beneficiary should have 2 NFTs");
    }
}

// =====================================================================
// Test Contract: Gas Limits with Hundreds of Tiers
// =====================================================================

/// @title TestAuditGaps_GasLimits
/// @notice Tests that operations with 100+ tiers do not hit gas limits or behave unexpectedly.
contract TestAuditGaps_GasLimits is UnitTestSetup {
    using stdStorage for StdStorage;

    /// @dev The block gas limit on mainnet is 30M. We use a generous limit for safety.
    uint256 constant BLOCK_GAS_LIMIT = 30_000_000;
    uint256 constant OPERATING_ENVELOPE_SOFT_LIMIT = 200;

    // ---------------------------------------------------------------
    // Test 1: Add 100 tiers in a single adjustTiers call
    // ---------------------------------------------------------------
    /// @notice Adding 100 tiers in a single transaction should succeed within the block gas limit.
    function test_gasLimit_add100Tiers() public {
        defaultTierConfig.initialSupply = 10;
        defaultTierConfig.reserveFrequency = 0;

        JB721TiersHook targetHook = _initHookDefaultTiers(0);

        // Build 100 tier configs, sorted by category.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](100);
        for (uint256 i; i < 100; i++) {
            newTiers[i] = JB721TierConfig({
                price: uint104((i + 1) * 1e15), // Different prices
                initialSupply: uint32(10),
                votingUnits: 0,
                reserveFrequency: 0,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i % 10],
                // forge-lint: disable-next-line(unsafe-typecast)
                // forge-lint: disable-next-line(unsafe-typecast)
                category: uint24(i + 1), // Ascending categories
                discountPercent: 0,
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                useVotingUnits: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }

        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(true));

        uint256 gasBefore = gasleft();
        vm.prank(owner);
        targetHook.adjustTiers(newTiers, new uint256[](0));
        uint256 gasUsed = gasBefore - gasleft();

        // Verify all 100 tiers were added.
        IJB721TiersHookStore hookStore = targetHook.STORE();
        assertEq(hookStore.maxTierIdOf(address(targetHook)), 100, "Should have 100 tiers");

        // Verify gas usage is within block gas limit.
        assertTrue(gasUsed < BLOCK_GAS_LIMIT, "Adding 100 tiers should fit within block gas limit");

        // Log gas for visibility.
        emit log_named_uint("Gas used to add 100 tiers", gasUsed);
    }

    // ---------------------------------------------------------------
    // Test 2: Read tiersOf with 100+ tiers
    // ---------------------------------------------------------------
    /// @notice Reading all tiers via tiersOf should succeed with 100+ tiers.
    function test_gasLimit_readTiersOf_100() public {
        defaultTierConfig.initialSupply = 10;
        defaultTierConfig.reserveFrequency = 0;

        JB721TiersHook targetHook = _initHookDefaultTiers(0);

        // Add 100 tiers.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](100);
        for (uint256 i; i < 100; i++) {
            newTiers[i] = JB721TierConfig({
                price: uint104((i + 1) * 1e15),
                initialSupply: uint32(10),
                votingUnits: 0,
                reserveFrequency: 0,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i % 10],
                // forge-lint: disable-next-line(unsafe-typecast)
                // forge-lint: disable-next-line(unsafe-typecast)
                category: uint24(i + 1),
                discountPercent: 0,
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                useVotingUnits: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }

        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(true));

        vm.prank(owner);
        targetHook.adjustTiers(newTiers, new uint256[](0));

        IJB721TiersHookStore hookStore = targetHook.STORE();

        // Read all 100 tiers.
        uint256 gasBefore = gasleft();
        JB721Tier[] memory allTiers = hookStore.tiersOf(address(targetHook), new uint256[](0), false, 0, 100);
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(allTiers.length, 100, "Should return 100 tiers");
        assertTrue(gasUsed < BLOCK_GAS_LIMIT, "Reading 100 tiers should fit within block gas limit");

        emit log_named_uint("Gas used to read 100 tiers", gasUsed);
    }

    // ---------------------------------------------------------------
    // Test 3: totalCashOutWeight with 100 tiers (some minted)
    // ---------------------------------------------------------------
    /// @notice totalCashOutWeight iterates all tiers. With 100 tiers and some minted, it should not
    /// exceed gas limits.
    function test_gasLimit_totalCashOutWeight_100tiers() public {
        defaultTierConfig.initialSupply = 10;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        // Add 100 tiers.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](100);
        for (uint256 i; i < 100; i++) {
            newTiers[i] = JB721TierConfig({
                price: uint104((i + 1) * 1e15),
                initialSupply: uint32(10),
                votingUnits: 0,
                reserveFrequency: 0,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i % 10],
                // forge-lint: disable-next-line(unsafe-typecast)
                // forge-lint: disable-next-line(unsafe-typecast)
                category: uint24(i + 1),
                discountPercent: 0,
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                useVotingUnits: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }

        vm.prank(address(targetHook));
        hookStore.recordAddTiers(newTiers);

        // Mock the directory for terminal auth.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mint 1 NFT from each of the first 10 tiers.
        uint16[] memory tierIdsToMint = new uint16[](10);
        uint256 totalCost;
        for (uint256 i; i < 10; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            // forge-lint: disable-next-line(unsafe-typecast)
            tierIdsToMint[i] = uint16(i + 1);
            totalCost += (i + 1) * 1e15;
        }

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(targetHook));
        bytes memory payerMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: totalCost,
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
            hookMetadata: bytes(""),
            payerMetadata: payerMetadata
        });

        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(payContext);

        assertEq(targetHook.balanceOf(beneficiary), 10, "10 NFTs minted");

        // Now measure gas for totalCashOutWeight.
        uint256 gasBefore = gasleft();
        uint256 weight = hookStore.totalCashOutWeight(address(targetHook));
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(weight > 0, "Cash out weight should be non-zero");
        assertTrue(gasUsed < BLOCK_GAS_LIMIT, "totalCashOutWeight should fit within block gas limit");

        emit log_named_uint("Gas used for totalCashOutWeight (100 tiers, 10 minted)", gasUsed);
    }

    // ---------------------------------------------------------------
    // Test 4: balanceOf with 100 tiers
    // ---------------------------------------------------------------
    /// @notice balanceOf iterates all tiers. With 100 tiers it should not be too expensive.
    function test_gasLimit_balanceOf_100tiers() public {
        defaultTierConfig.initialSupply = 10;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        // Add 100 tiers.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](100);
        for (uint256 i; i < 100; i++) {
            newTiers[i] = JB721TierConfig({
                price: uint104((i + 1) * 1e15),
                initialSupply: uint32(10),
                votingUnits: 0,
                reserveFrequency: 0,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i % 10],
                // forge-lint: disable-next-line(unsafe-typecast)
                // forge-lint: disable-next-line(unsafe-typecast)
                category: uint24(i + 1),
                discountPercent: 0,
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                useVotingUnits: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }

        vm.prank(address(targetHook));
        hookStore.recordAddTiers(newTiers);

        // Measure gas for balanceOf with 100 tiers (user has 0 NFTs).
        uint256 gasBefore = gasleft();
        uint256 balance = hookStore.balanceOf(address(targetHook), beneficiary);
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(balance, 0, "Balance should be 0");
        assertTrue(gasUsed < BLOCK_GAS_LIMIT, "balanceOf with 100 tiers should be within gas limit");

        emit log_named_uint("Gas used for balanceOf (100 tiers, 0 NFTs)", gasUsed);
    }

    // ---------------------------------------------------------------
    // Test 5: Add 200 tiers and verify store correctness
    // ---------------------------------------------------------------
    /// @notice Adding 200 tiers should still work and the store should report correct data.
    function test_gasLimit_add200Tiers_storeCorrectness() public {
        defaultTierConfig.initialSupply = 5;
        defaultTierConfig.reserveFrequency = 0;

        JB721TiersHook targetHook = _initHookDefaultTiers(0);

        // Build 200 tiers in a single batch.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](200);
        for (uint256 i; i < 200; i++) {
            newTiers[i] = JB721TierConfig({
                price: uint104((i + 1) * 1e14),
                initialSupply: uint32(5),
                votingUnits: 0,
                reserveFrequency: 0,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i % 10],
                // forge-lint: disable-next-line(unsafe-typecast)
                // forge-lint: disable-next-line(unsafe-typecast)
                category: uint24(i + 1),
                discountPercent: 0,
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                useVotingUnits: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }

        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(true));

        uint256 gasBefore = gasleft();
        vm.prank(owner);
        targetHook.adjustTiers(newTiers, new uint256[](0));
        uint256 gasUsed = gasBefore - gasleft();

        IJB721TiersHookStore hookStore = targetHook.STORE();

        // Verify all 200 tiers were added.
        assertEq(hookStore.maxTierIdOf(address(targetHook)), 200, "Should have 200 tiers");

        // Spot check first and last tier.
        JB721Tier memory firstTier = hookStore.tierOf(address(targetHook), 1, false);
        assertEq(firstTier.price, 1e14, "First tier price should be correct");
        assertEq(firstTier.initialSupply, 5, "First tier supply should be 5");

        JB721Tier memory lastTier = hookStore.tierOf(address(targetHook), 200, false);
        assertEq(lastTier.price, 200 * 1e14, "Last tier price should be correct");
        assertEq(lastTier.initialSupply, 5, "Last tier supply should be 5");

        assertTrue(gasUsed < BLOCK_GAS_LIMIT, "Adding 200 tiers should fit within block gas limit");

        emit log_named_uint("Gas used to add 200 tiers", gasUsed);
    }

    // ---------------------------------------------------------------
    // Test 6: Remove many tiers and verify gas is bounded
    // ---------------------------------------------------------------
    /// @notice Removing 50 tiers from a 100-tier collection should be gas-efficient.
    function test_gasLimit_remove50TiersFrom100() public {
        defaultTierConfig.initialSupply = 10;
        defaultTierConfig.reserveFrequency = 0;

        JB721TiersHook targetHook = _initHookDefaultTiers(0);

        // Add 100 tiers.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](100);
        for (uint256 i; i < 100; i++) {
            newTiers[i] = JB721TierConfig({
                price: uint104((i + 1) * 1e15),
                initialSupply: uint32(10),
                votingUnits: 0,
                reserveFrequency: 0,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i % 10],
                // forge-lint: disable-next-line(unsafe-typecast)
                // forge-lint: disable-next-line(unsafe-typecast)
                category: uint24(i + 1),
                discountPercent: 0,
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                useVotingUnits: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }

        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(true));

        vm.prank(owner);
        targetHook.adjustTiers(newTiers, new uint256[](0));

        // Now remove 50 tiers (odd-numbered tiers: 1, 3, 5, ..., 99).
        uint256[] memory tierIdsToRemove = new uint256[](50);
        for (uint256 i; i < 50; i++) {
            tierIdsToRemove[i] = (i * 2) + 1; // 1, 3, 5, ...
        }

        uint256 gasBefore = gasleft();
        vm.prank(owner);
        targetHook.adjustTiers(new JB721TierConfig[](0), tierIdsToRemove);
        uint256 gasUsed = gasBefore - gasleft();

        IJB721TiersHookStore hookStore = targetHook.STORE();

        // Verify the removed tiers are marked as removed.
        assertTrue(hookStore.isTierRemoved(address(targetHook), 1), "Tier 1 should be removed");
        assertTrue(hookStore.isTierRemoved(address(targetHook), 99), "Tier 99 should be removed");

        // Verify even tiers are still active.
        assertFalse(hookStore.isTierRemoved(address(targetHook), 2), "Tier 2 should still be active");
        assertFalse(hookStore.isTierRemoved(address(targetHook), 100), "Tier 100 should still be active");

        // Reading the active tiers should return 50 (the even-numbered ones).
        JB721Tier[] memory activeTiers = hookStore.tiersOf(address(targetHook), new uint256[](0), false, 0, 100);
        assertEq(activeTiers.length, 50, "Should have 50 active tiers after removing 50");

        assertTrue(gasUsed < BLOCK_GAS_LIMIT, "Removing 50 tiers should fit within block gas limit");

        emit log_named_uint("Gas used to remove 50 tiers from 100", gasUsed);
    }

    // ---------------------------------------------------------------
    // Test 7: Mint from many different tiers in a single payment
    // ---------------------------------------------------------------
    /// @notice Minting 1 NFT from each of 50 different tiers in a single payment should not
    /// exceed gas limits.
    function test_gasLimit_mintFrom50TiersInSinglePayment() public {
        defaultTierConfig.initialSupply = 10;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        // Add 50 tiers.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](50);
        for (uint256 i; i < 50; i++) {
            newTiers[i] = JB721TierConfig({
                price: uint104((i + 1) * 1e15),
                initialSupply: uint32(10),
                votingUnits: 0,
                reserveFrequency: 0,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i % 10],
                // forge-lint: disable-next-line(unsafe-typecast)
                // forge-lint: disable-next-line(unsafe-typecast)
                category: uint24(i + 1),
                discountPercent: 0,
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                useVotingUnits: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }

        vm.prank(address(targetHook));
        hookStore.recordAddTiers(newTiers);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mint 1 NFT from each of the 50 tiers.
        uint16[] memory tierIdsToMint = new uint16[](50);
        uint256 totalCost;
        for (uint256 i; i < 50; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            // forge-lint: disable-next-line(unsafe-typecast)
            tierIdsToMint[i] = uint16(i + 1);
            totalCost += (i + 1) * 1e15;
        }

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, tierIdsToMint);
        bytes4[] memory metaIds = new bytes4[](1);
        metaIds[0] = metadataHelper.getId("pay", address(targetHook));
        bytes memory payerMetadata = metadataHelper.createMetadata(metaIds, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: totalCost,
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
            hookMetadata: bytes(""),
            payerMetadata: payerMetadata
        });

        uint256 gasBefore = gasleft();
        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(payContext);
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(targetHook.balanceOf(beneficiary), 50, "Should have minted 50 NFTs");
        assertTrue(gasUsed < BLOCK_GAS_LIMIT, "Minting from 50 tiers should fit within block gas limit");

        emit log_named_uint("Gas used to mint from 50 tiers in single payment", gasUsed);
    }

    /// @notice The expensive read paths scale with tier count, not just with the beneficiary's holdings.
    /// This test exists to prove that a 100-tier catalog is materially more expensive than a 10-tier catalog even
    /// when the queried user owns zero NFTs.
    function test_operatingEnvelope_balanceOf_100tiersIsMateriallyMoreExpensiveThan10tiers() public {
        uint256 gasFor10 = _measureBalanceOfGas({tierCount: 10});
        uint256 gasFor100 = _measureBalanceOfGas({tierCount: 100});

        assertGt(gasFor100, gasFor10 * 4, "100-tier balanceOf should be materially more expensive than 10 tiers");
        emit log_named_uint("Gas used for balanceOf (10 tiers)", gasFor10);
        emit log_named_uint("Gas used for balanceOf (100 tiers)", gasFor100);
    }

    /// @notice Cash-out accounting also scales with the catalog size because totalCashOutWeight walks the tier set.
    /// We use a ratio check instead of an absolute snapshot so the test stays stable across compiler changes while
    /// still proving the production-scale cost increase.
    function test_operatingEnvelope_totalCashOutWeight_100tiersIsMateriallyMoreExpensiveThan10tiers() public {
        uint256 gasFor10 = _measureTotalCashOutWeightGas({tierCount: 10, mintedCount: 10});
        uint256 gasFor100 = _measureTotalCashOutWeightGas({tierCount: 100, mintedCount: 10});

        assertGt(
            gasFor100, gasFor10 * 4, "100-tier totalCashOutWeight should be materially more expensive than 10 tiers"
        );
        emit log_named_uint("Gas used for totalCashOutWeight (10 tiers)", gasFor10);
        emit log_named_uint("Gas used for totalCashOutWeight (100 tiers)", gasFor100);
    }

    function _measureBalanceOfGas(uint256 tierCount) internal returns (uint256 gasUsed) {
        defaultTierConfig.initialSupply = 10;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        vm.prank(address(targetHook));
        hookStore.recordAddTiers(_sequentialTierConfigs(tierCount, 1e15, 10));

        uint256 gasBefore = gasleft();
        hookStore.balanceOf(address(targetHook), beneficiary);
        gasUsed = gasBefore - gasleft();
    }

    function _measureTotalCashOutWeightGas(uint256 tierCount, uint256 mintedCount) internal returns (uint256 gasUsed) {
        defaultTierConfig.initialSupply = 10;
        defaultTierConfig.reserveFrequency = 0;

        ForTest_JB721TiersHook targetHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = targetHook.STORE();

        vm.prank(address(targetHook));
        hookStore.recordAddTiers(_sequentialTierConfigs(tierCount, 1e15, 10));

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint16[] memory tierIdsToMint = new uint16[](mintedCount);
        uint256 totalCost;
        for (uint256 i; i < mintedCount; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            tierIdsToMint[i] = uint16(i + 1);
            totalCost += (i + 1) * 1e15;
        }

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(targetHook));
        bytes memory payerMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: totalCost,
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
            hookMetadata: bytes(""),
            payerMetadata: payerMetadata
        });

        vm.prank(mockTerminalAddress);
        targetHook.afterPayRecordedWith(payContext);

        uint256 gasBefore = gasleft();
        hookStore.totalCashOutWeight(address(targetHook));
        gasUsed = gasBefore - gasleft();
    }

    function _sequentialTierConfigs(
        uint256 tierCount,
        uint104 priceStep,
        uint32 initialSupply
    )
        internal
        view
        returns (JB721TierConfig[] memory newTiers)
    {
        require(tierCount <= OPERATING_ENVELOPE_SOFT_LIMIT, "test helper only sized for envelope coverage");

        newTiers = new JB721TierConfig[](tierCount);
        for (uint256 i; i < tierCount; i++) {
            newTiers[i] = JB721TierConfig({
                price: uint104((i + 1) * priceStep),
                initialSupply: initialSupply,
                votingUnits: 0,
                reserveFrequency: 0,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i % 10],
                // forge-lint: disable-next-line(unsafe-typecast)
                category: uint24(i + 1),
                discountPercent: 0,
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                useVotingUnits: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }
    }
}
