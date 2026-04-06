// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {JB721TiersHookFlags} from "../../src/structs/JB721TiersHookFlags.sol";
import {JB721TiersHookLib} from "../../src/libraries/JB721TiersHookLib.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

/// @notice Tests for 4 audit fixes: F-2, F-11, F-12, F-13.
contract Test_AuditFixes_Unit is UnitTestSetup {
    using stdStorage for StdStorage;

    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();
        vm.etch(mockJBSplits, new bytes(0x69));
    }

    // ─────────────────────────────────────────────────────────
    // Helpers (same patterns as tierSplitRouting_Unit.t.sol)
    // ─────────────────────────────────────────────────────────

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

    // ═════════════════════════════════════════════════════════
    // F-2: Proportional split metadata scaling
    // ═════════════════════════════════════════════════════════
    //
    // When totalSplitAmount > context.amount.value (e.g., because pay credits cover the NFT cost
    // but there is not enough real ETH to forward), the per-tier amounts in splitMetadata must
    // be proportionally scaled down so the terminal never attempts to forward more than the
    // actual payment value.

    /// @notice F-2: When amount.value < totalSplitAmount, per-tier split amounts are scaled down proportionally.
    function test_F2_splitMetadataScaledDown_whenAmountBelowSplitTotal() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Create two tiers with split percentages:
        // Tier A: 2 ETH, 50% split -> split amount = 1 ETH
        // Tier B: 4 ETH, 50% split -> split amount = 2 ETH
        // Total split = 3 ETH
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](2);
        tierConfigs[0] = _tierConfigWithSplit(2 ether, 500_000_000); // 50%
        tierConfigs[0].category = 1;
        tierConfigs[1] = _tierConfigWithSplit(4 ether, 500_000_000); // 50%
        tierConfigs[1].category = 2;
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Build payer metadata requesting both tiers.
        uint16[] memory mintIds = new uint16[](2);
        mintIds[0] = uint16(tierIds[0]);
        mintIds[1] = uint16(tierIds[1]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        // Payment of 2 ETH - less than totalSplitAmount of 3 ETH.
        // The user may have pay credits that cover the NFT cost (2 + 4 = 6 ETH worth),
        // but only 2 ETH of real value is being sent to the terminal.
        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 2 ether, // Less than 3 ETH total split
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

        // The total forwarded amount must be capped at the payment value (may be up to 1 wei less due to rounding).
        assertApproxEqAbs(specs[0].amount, 2 ether, 1, "Total split should be capped at payment value");

        // Decode the per-tier breakdown from hookMetadata.
        (uint16[] memory resultTierIds, uint256[] memory resultAmounts) =
            abi.decode(specs[0].metadata, (uint16[], uint256[]));

        // Both tiers should be present in the metadata.
        assertEq(resultTierIds.length, 2, "Should have 2 tier entries");

        // Per-tier amounts should be proportionally scaled:
        // Original: tierA = 1 ETH, tierB = 2 ETH, total = 3 ETH
        // Scaled by (2 ETH / 3 ETH):
        //   tierA = 1 * 2/3 = 0.666... ETH
        //   tierB = 2 * 2/3 = 1.333... ETH
        uint256 tierAOriginal = 1 ether;
        uint256 tierBOriginal = 2 ether;
        uint256 originalTotal = 3 ether;
        uint256 cappedTotal = 2 ether;
        uint256 expectedA = (tierAOriginal * cappedTotal) / originalTotal;
        uint256 expectedB = (tierBOriginal * cappedTotal) / originalTotal;

        assertEq(resultAmounts[0], expectedA, "Tier A amount should be proportionally scaled");
        assertEq(resultAmounts[1], expectedB, "Tier B amount should be proportionally scaled");

        // The sum of scaled amounts should be <= the payment value.
        assertLe(resultAmounts[0] + resultAmounts[1], 2 ether, "Sum of scaled amounts must not exceed payment value");
    }

    /// @notice F-2: When amount.value >= totalSplitAmount, no scaling occurs.
    function test_F2_noScaling_whenAmountExceedsSplitTotal() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Tier: 1 ETH, 50% split -> split amount = 0.5 ETH
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 500_000_000);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        // Payment of 1 ETH - greater than 0.5 ETH total split.
        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
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
            reservedPercent: 5000,
            metadata: payerMetadata
        });

        (, JBPayHookSpecification[] memory specs) = testHook.beforePayRecordedWith(context);

        // No scaling needed - the original split amount should be returned.
        assertEq(specs[0].amount, 0.5 ether, "No scaling when payment >= split total");
    }

    // ═════════════════════════════════════════════════════════
    // F-11: Revert when no terminal for leftover funds
    // ═════════════════════════════════════════════════════════
    //
    // When there are leftover funds after split distribution (splits don't consume 100%),
    // the library looks up directory.primaryTerminalOf() to route the leftovers.
    // If primaryTerminalOf returns address(0), the library now reverts with
    // JB721TiersHookLib_NoTerminalForLeftover instead of silently losing funds.

    /// @notice F-11: Revert when leftover funds exist but no primary terminal is available.
    function test_F11_revertsWhenNoTerminalForLeftover() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 50% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 500_000_000); // 50%
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Mock directory: isTerminalOf returns true for the mock terminal.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Splits: 50% to alice (leaves 50% as leftover).
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(500_000_000), // 50%
            projectId: 0,
            beneficiary: payable(alice),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        // Mock directory: primaryTerminalOf returns address(0) -- no terminal available.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, projectId, JBConstants.NATIVE_TOKEN),
            abi.encode(address(0))
        );

        // Build payer metadata.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        // Build hook metadata (per-tier split breakdown).
        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 0.5 ether;

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
                value: 0.5 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        // Expect the revert from the library (called via DELEGATECALL, so it reverts in the hook's context).
        // The leftover is 50% of 0.5 ETH = 0.25 ETH (alice gets 50% of the 0.5 ETH forwarded).
        vm.expectRevert(
            abi.encodeWithSelector(
                JB721TiersHookLib.JB721TiersHookLib_NoTerminalForLeftover.selector,
                projectId,
                JBConstants.NATIVE_TOKEN,
                0.25 ether
            )
        );

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 0.5 ether}(payContext);
    }

    /// @notice F-11: No revert when splits consume 100% (no leftover).
    function test_F11_noRevertWhenSplitsConsume100Percent() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 100% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 1_000_000_000); // 100%
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Splits: 100% to alice (no leftover).
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(alice),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 1 ether;

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
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        // Should NOT revert: splits consume 100%, no leftover to route.
        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        // Verify alice received the funds.
        assertEq(alice.balance, 1 ether, "Alice should receive full split amount");
    }

    // ═════════════════════════════════════════════════════════
    // F-12: _initialized flag prevents re-initialization
    // ═════════════════════════════════════════════════════════
    //
    // The implementation contract sets _initialized = true in the constructor, so it cannot
    // be initialized. Clones start with _initialized = false, so they can be initialized once.
    // A second call to initialize() on a clone must revert.

    /// @notice F-12: The implementation contract cannot be initialized (constructor sets _initialized = true).
    function test_F12_implementationCannotBeInitialized() public {
        // hookOrigin is the implementation contract deployed in setUp().
        // Its constructor already set _initialized = true.
        // PROJECT_ID is 0 on the implementation (never initialized with a project ID).
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.JB721TiersHook_AlreadyInitialized.selector, 0));

        hookOrigin.initialize({
            projectId: 42,
            name: "Test",
            symbol: "TST",
            baseUri: "http://test.com/",
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: "ipfs://test",
            tiersConfig: JB721InitTiersConfig({
                tiers: new JB721TierConfig[](0), currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
            }),
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: false
            })
        });
    }

    /// @notice F-12: A clone can be initialized once, but not twice.
    function test_F12_cloneInitializedOnce_secondCallReverts() public {
        // Deploy a fresh clone of the implementation.
        address cloneAddr = LibClone.clone(address(hookOrigin));
        JB721TiersHook cloneHook = JB721TiersHook(cloneAddr);

        // First initialization should succeed.
        cloneHook.initialize({
            projectId: 42,
            name: "Clone",
            symbol: "CLN",
            baseUri: "http://clone.com/",
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: "ipfs://clone",
            tiersConfig: JB721InitTiersConfig({
                tiers: new JB721TierConfig[](0), currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
            }),
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: false
            })
        });

        // Verify clone was initialized with the correct project ID.
        assertEq(cloneHook.PROJECT_ID(), 42, "Clone should have projectId 42");

        // Second initialization should revert with the project ID from the first init.
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.JB721TiersHook_AlreadyInitialized.selector, 42));

        cloneHook.initialize({
            projectId: 99,
            name: "Bad",
            symbol: "BAD",
            baseUri: "http://bad.com/",
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: "ipfs://bad",
            tiersConfig: JB721InitTiersConfig({
                tiers: new JB721TierConfig[](0), currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
            }),
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: false
            })
        });
    }

    // ═════════════════════════════════════════════════════════
    // F-13: _startingTierIdOfCategory updated in cleanTiers
    // ═════════════════════════════════════════════════════════
    //
    // When the first tier in a category is removed, `cleanTiers` must update
    // `_startingTierIdOfCategory` to point to the next non-removed tier in that category.
    // Without this fix, tier lookups starting from the category pointer would begin at a
    // removed (invisible) tier, causing incorrect iteration behavior.

    /// @notice F-13: After removing the first tier of a category and calling cleanTiers,
    ///         the category's starting tier ID is updated to the next valid tier.
    function test_F13_cleanTiersUpdatesStartingTierIdOfCategory() public {
        // Initialize a hook with no default tiers.
        JB721TiersHook testHook = _initHookDefaultTiers(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add 3 tiers in category 5. They will get sequential IDs (1, 2, 3).
        // All in the same category, so _startingTierIdOfCategory[5] = 1 after addition.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](3);

        tierConfigs[0] = JB721TierConfig({
            price: uint104(10),
            initialSupply: uint32(100),
            votingUnits: uint16(0),
            reserveFrequency: uint16(0),
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: tokenUris[0],
            category: uint24(5),
            discountPercent: uint8(0),
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
        tierConfigs[1] = JB721TierConfig({
            price: uint104(20),
            initialSupply: uint32(100),
            votingUnits: uint16(0),
            reserveFrequency: uint16(0),
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: tokenUris[1],
            category: uint24(5),
            discountPercent: uint8(0),
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
        tierConfigs[2] = JB721TierConfig({
            price: uint104(30),
            initialSupply: uint32(100),
            votingUnits: uint16(0),
            reserveFrequency: uint16(0),
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: tokenUris[2],
            category: uint24(5),
            discountPercent: uint8(0),
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

        // Add tiers to the store. Tier IDs will be 1, 2, 3.
        vm.prank(address(testHook));
        hookStore.recordAddTiers(tierConfigs);

        // Verify all 3 tiers exist.
        JB721Tier[] memory allTiers = hookStore.tiersOf(address(testHook), new uint256[](0), false, 0, 10);
        assertEq(allTiers.length, 3, "Should have 3 tiers initially");

        // Remove tier ID 1 (the first tier in category 5, which is the _startingTierIdOfCategory).
        uint256[] memory tiersToRemove = new uint256[](1);
        tiersToRemove[0] = 1;
        vm.prank(address(testHook));
        hookStore.recordRemoveTierIds(tiersToRemove);

        // Before cleanTiers: category 5's starting tier still points to the removed tier 1.
        // Verify that tiersOf still correctly returns only non-removed tiers.
        JB721Tier[] memory tiersBeforeClean = hookStore.tiersOf(address(testHook), new uint256[](0), false, 0, 10);
        assertEq(tiersBeforeClean.length, 2, "Should have 2 tiers after removal (before clean)");

        // Call cleanTiers to update the linked list and _startingTierIdOfCategory.
        hookStore.cleanTiers(address(testHook));

        // After cleanTiers: verify tiers are correctly iterable.
        JB721Tier[] memory tiersAfterClean = hookStore.tiersOf(address(testHook), new uint256[](0), false, 0, 10);
        assertEq(tiersAfterClean.length, 2, "Should have 2 tiers after clean");

        // The remaining tiers should be IDs 2 and 3 (sorted by ID ascending within the same category).
        assertEq(tiersAfterClean[0].id, 2, "First tier should be ID 2");
        assertEq(tiersAfterClean[1].id, 3, "Second tier should be ID 3");

        // Verify individual tier lookups still work for the remaining tiers.
        JB721Tier memory tier2 = hookStore.tierOf(address(testHook), 2, false);
        assertEq(tier2.id, 2, "Tier 2 should be accessible");
        assertEq(tier2.price, 20, "Tier 2 price should be 20");

        JB721Tier memory tier3 = hookStore.tierOf(address(testHook), 3, false);
        assertEq(tier3.id, 3, "Tier 3 should be accessible");
        assertEq(tier3.price, 30, "Tier 3 price should be 30");
    }

    /// @notice F-13: Removing a non-starting tier does not affect _startingTierIdOfCategory.
    function test_F13_removingNonStartingTierPreservesStartingId() public {
        JB721TiersHook testHook = _initHookDefaultTiers(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add 3 tiers in category 5.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](3);

        for (uint256 i; i < 3; i++) {
            tierConfigs[i] = JB721TierConfig({
                price: uint104((i + 1) * 10),
                initialSupply: uint32(100),
                votingUnits: uint16(0),
                reserveFrequency: uint16(0),
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i],
                category: uint24(5),
                discountPercent: uint8(0),
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
        }

        vm.prank(address(testHook));
        hookStore.recordAddTiers(tierConfigs);

        // Remove tier ID 2 (the middle tier, NOT the starting tier).
        uint256[] memory tiersToRemove = new uint256[](1);
        tiersToRemove[0] = 2;
        vm.prank(address(testHook));
        hookStore.recordRemoveTierIds(tiersToRemove);

        hookStore.cleanTiers(address(testHook));

        // After clean: 2 tiers remain (IDs 1 and 3).
        JB721Tier[] memory tiersAfterClean = hookStore.tiersOf(address(testHook), new uint256[](0), false, 0, 10);
        assertEq(tiersAfterClean.length, 2, "Should have 2 tiers after removing middle tier");

        // Both remaining tiers should be accessible.
        JB721Tier memory tier1 = hookStore.tierOf(address(testHook), 1, false);
        assertEq(tier1.id, 1, "Tier 1 should still be accessible");
        assertEq(tier1.price, 10, "Tier 1 price should be 10");

        JB721Tier memory tier3 = hookStore.tierOf(address(testHook), 3, false);
        assertEq(tier3.id, 3, "Tier 3 should still be accessible");
        assertEq(tier3.price, 30, "Tier 3 price should be 30");
    }
}
