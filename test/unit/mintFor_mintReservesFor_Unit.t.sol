// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";

contract Test_mintFor_mintReservesFor_Unit is UnitTestSetup {
    using stdStorage for StdStorage;

    function test_mintPendingReservesFor_mintsCorrectly() public {
        uint256 initialSupply = 200; // The number of NFTs available for each tier.
        uint256 totalMinted = 120; // The number of NFTs already minted for each tier (out of `initialSupply`).
        uint256 reservedMinted = 1; // The number of reserve NFTs already minted (out of `totalMinted`).
        uint256 reserveFrequency = 4000; // The frequency at which NFTs are reserved (4000/10000 = 40%).
        uint256 numberOfTiers = 3; // The number of tiers to set up.

        // With 120 total NFTs minted and 1 being a reserve mint, 119 are non-reserved.
        // With a 40% reserve frequency, 47 should be reserved.
        // Accounting for the 1 already minted, there should be 46 pending reserve mints.

        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Initialize `numberOfTiers` tiers.
        for (uint256 i; i < numberOfTiers; i++) {
            hook.test_store()
                .ForTest_setTier(
                    address(hook),
                    i + 1,
                    JBStored721Tier({
                        price: uint104((i + 1) * 10),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        remainingSupply: uint32(initialSupply - totalMinted),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        initialSupply: uint32(initialSupply),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        reserveFrequency: uint16(reserveFrequency),
                        category: uint24(100),
                        discountPercent: uint8(0),
                        packedBools: hook.test_store().ForTest_packBools(false, false, true, false, false),
                        splitPercent: 0
                    })
                );
            hook.test_store().ForTest_setReservesMintedFor(address(hook), i + 1, reservedMinted);
        }

        // Iterate through the tiers, minting the pending reserves,
        // and ensuring that the correct number of NFTs have been minted.
        for (uint256 tier = 1; tier <= numberOfTiers; tier++) {
            uint256 mintable = hook.test_store().numberOfPendingReservesFor(address(hook), tier);

            // Mint the reserve NFTs for the tier.
            for (uint256 token = 1; token <= mintable; token++) {
                vm.expectEmit(true, true, true, true, address(hook));
                emit MintReservedNft(_generateTokenId(tier, totalMinted + token), tier, reserveBeneficiary, owner);
            }

            vm.prank(owner);
            hook.mintPendingReservesFor(tier, mintable);

            // Check: does the reserve beneficiary have the correct number of NFTs?
            assertEq(hook.balanceOf(reserveBeneficiary), mintable * tier);
        }
    }

    // Todo case: initial 10, rr 3, minted 6, what happens? mint the reserves till there's no remaining. then if all
    // users burn, what happens?
    function test_mintPendingReservesFor_mintOddReservedTokens() public {
        uint256 initialSupply = 10; // The number of NFTs available for each tier.
        uint256 totalMinted = 6; // The number of NFTs already minted for each tier (out of `initialSupply`).
        uint256 reserveFrequency = 3; // The frequency at which NFTs are reserved (3/10 = 30%).

        ForTest_JB721TiersHook hook = _initializeForTestHook(1);

        // Initialize `numberOfTiers` tiers.
        hook.test_store()
            .ForTest_setTier(
                address(hook),
                1,
                JBStored721Tier({
                    price: uint104(10),
                    // forge-lint: disable-next-line(unsafe-typecast)
                    remainingSupply: uint32(initialSupply),
                    // forge-lint: disable-next-line(unsafe-typecast)
                    initialSupply: uint32(initialSupply),
                    // forge-lint: disable-next-line(unsafe-typecast)
                    reserveFrequency: uint16(reserveFrequency),
                    category: uint24(100),
                    discountPercent: uint8(0),
                    packedBools: hook.test_store().ForTest_packBools(true, false, true, false, false),
                    splitPercent: 0
                })
            );

        // Mint the initial tiers.
        uint16[] memory tiersToMint = new uint16[](totalMinted);
        for (uint256 i; i < totalMinted; i++) {
            tiersToMint[i] = 1;
        }
        vm.prank(owner);
        hook.mintFor(tiersToMint, beneficiary);

        // Iterate through the tiers, calculating how many reserve NFTs should be mintable.
        uint256 mintable = hook.test_store().numberOfPendingReservesFor(address(hook), 1);
        assertEq(mintable, 2, "Tier 1 should have 2 reserve NFTs mintable.");

        // Mint the next tier
        tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        hook.mintFor(tiersToMint, beneficiary);

        // Should have one more reserved.
        mintable = hook.test_store().numberOfPendingReservesFor(address(hook), 1);
        assertEq(mintable, 3, "Tier 1 should have 3 reserve NFTs mintable.");

        // Revert when minting the next.
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector, 1)
        );
        vm.prank(owner);
        hook.mintFor(tiersToMint, beneficiary);

        // Package reserves to mint.
        JB721TiersMintReservesConfig[] memory reservesToMint = new JB721TiersMintReservesConfig[](1);
        // forge-lint: disable-next-line(unsafe-typecast)
        reservesToMint[0] = JB721TiersMintReservesConfig({tierId: uint32(1), count: uint16(mintable)});

        // Mint the pending reserve NFTs.
        vm.prank(owner);
        hook.mintPendingReservesFor(reservesToMint);

        // Check: does the reserve beneficiary and beneficiary have the correct number of NFTs?
        assertEq(hook.balanceOf(reserveBeneficiary), 3);
        assertEq(hook.balanceOf(beneficiary), 7);

        mintable = hook.test_store().numberOfPendingReservesFor(address(hook), 1);
        assertEq(mintable, 0, "Tier 1 should have 0 reserve NFTs mintable.");

        // Burn them all.
        uint256[] memory tokenIdsToBurn = new uint256[](initialSupply);
        for (uint256 i; i < initialSupply; i++) {
            tokenIdsToBurn[i] = 1_000_000_000 + 1 + i;
        }
        vm.prank(address(hook));
        hook.burn(tokenIdsToBurn);

        // Check: does the reserve beneficiary and beneficiary have the correct number of NFTs?
        assertEq(hook.balanceOf(reserveBeneficiary), 0);
        assertEq(hook.balanceOf(beneficiary), 0);

        // No pending reserves still.
        mintable = hook.test_store().numberOfPendingReservesFor(address(hook), 1);
        assertEq(mintable, 0, "Tier 1 should have 0 reserve NFTs mintable.");

        // No remaining supply still.
        JB721Tier memory tier = hook.STORE().tierOf(address(hook), 1, false);
        assertEq(tier.remainingSupply, 0, "Tier 1 should have 0 remaining supply.");

        // Revert when minting the next.
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector, 1)
        );
        vm.prank(owner);
        hook.mintFor(tiersToMint, beneficiary);
    }

    function test_mintPendingReservesFor_mintMultipleReservedTokens() public {
        uint256 initialSupply = 200; // The number of NFTs available for each tier.
        uint256 totalMinted = 120; // The number of NFTs already minted for each tier (out of `initialSupply`).
        uint256 reservedMinted = 1; // The number of reserve NFTs already minted (out of `totalMinted`).
        uint256 reserveFrequency = 4000; // The frequency at which NFTs are reserved (4000/10000 = 40%).
        uint256 numberOfTiers = 3; // The number of tiers to set up.

        // With 120 total NFTs minted and 1 being a reserve mint, 119 are non-reserved.
        // With a 40% reserve frequency, 47 should be reserved.
        // Accounting for the 1 already minted, there should be 46 pending reserve mints.

        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Initialize `numberOfTiers` tiers.
        for (uint256 i; i < numberOfTiers; i++) {
            hook.test_store()
                .ForTest_setTier(
                    address(hook),
                    i + 1,
                    JBStored721Tier({
                        price: uint104((i + 1) * 10),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        remainingSupply: uint32(initialSupply - totalMinted),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        initialSupply: uint32(initialSupply),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        reserveFrequency: uint16(reserveFrequency),
                        category: uint24(100),
                        discountPercent: uint8(0),
                        packedBools: hook.test_store().ForTest_packBools(false, false, true, false, false),
                        splitPercent: 0
                    })
                );

            // Set the number of reserve NFTs already minted for the tier.
            hook.test_store().ForTest_setReservesMintedFor(address(hook), i + 1, reservedMinted);
        }

        uint256 totalMintable; // Keep a running counter of how many reserve NFTs should be mintable.

        JB721TiersMintReservesConfig[] memory reservesToMint = new JB721TiersMintReservesConfig[](numberOfTiers);

        // Iterate through the tiers, calculating how many reserve NFTs should be mintable.
        for (uint256 tier = 1; tier <= numberOfTiers; tier++) {
            uint256 mintable = hook.test_store().numberOfPendingReservesFor(address(hook), tier);
            // forge-lint: disable-next-line(unsafe-typecast)
            reservesToMint[tier - 1] = JB721TiersMintReservesConfig({tierId: uint32(tier), count: uint16(mintable)});
            totalMintable += mintable;
            for (uint256 token = 1; token <= mintable; token++) {
                uint256 tokenNonce = totalMinted + token; // Avoid stack too deep
                vm.expectEmit(true, true, true, true, address(hook));
                emit MintReservedNft(_generateTokenId(tier, tokenNonce), tier, reserveBeneficiary, owner);
            }
        }

        // Mint the pending reserve NFTs.
        vm.prank(owner);
        hook.mintPendingReservesFor(reservesToMint);

        // Check: does the reserve beneficiary has the correct number of NFTs?
        assertEq(hook.balanceOf(reserveBeneficiary), totalMintable);
    }

    function test_mintPendingReservesFor_revertIfReservedMintingIsPausedInRuleset() public {
        uint256 initialSupply = 200; // The number of NFTs available for each tier.
        uint256 totalMinted = 120; // The number of NFTs already minted for each tier (out of `initialSupply`).
        uint256 reservedMinted = 1; // The number of reserve NFTs already minted (out of `totalMinted`).
        uint256 reserveFrequency = 4000; // The frequency at which NFTs are reserved (4000/10000 = 40%).
        uint256 numberOfTiers = 3; // The number of tiers to set up.

        // Set up the ruleset to pause reserved minting.
        // This is done with the `JBRulesetMetadata.metadata` field.
        // The second bit in `JBRulesetMetadata.metadata` is the `mintPendingReservesPaused` bit.
        // See `JB721TiersRulesetMetadataResolver`.
        mockAndExpect(
            mockJBRulesets,
            abi.encodeCall(IJBRulesets.currentOf, projectId),
            abi.encode(
                JBRuleset({
                    cycleNumber: 1,
                    id: uint48(block.timestamp),
                    basedOnId: 0,
                    start: uint48(block.timestamp),
                    duration: 600,
                    weight: 10e18,
                    weightCutPercent: 0,
                    approvalHook: IJBRulesetApprovalHook(address(0)),
                    metadata: JBRulesetMetadataResolver.packRulesetMetadata(
                        JBRulesetMetadata({
                            reservedPercent: 5000, //50%
                            cashOutTaxRate: 5000, //50%
                            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                            pausePay: false,
                            pauseCreditTransfers: false,
                            allowOwnerMinting: true,
                            allowSetCustomToken: false,
                            allowTerminalMigration: false,
                            allowSetTerminals: false,
                            allowSetController: false,
                            allowAddAccountingContext: false,
                            allowAddPriceFeed: false,
                            ownerMustSendPayouts: false,
                            holdFees: false,
                            useTotalSurplusForCashOuts: false,
                            useDataHookForPay: true,
                            useDataHookForCashOut: true,
                            dataHook: address(0),
                            metadata: 2
                        })
                    )
                })
            )
        );

        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        for (uint256 i; i < numberOfTiers; i++) {
            hook.test_store()
                .ForTest_setTier(
                    address(hook),
                    i + 1,
                    JBStored721Tier({
                        price: uint104((i + 1) * 10),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        remainingSupply: uint32(initialSupply - totalMinted),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        initialSupply: uint32(initialSupply),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        reserveFrequency: uint16(reserveFrequency),
                        category: uint24(100),
                        discountPercent: uint8(0),
                        packedBools: hook.test_store().ForTest_packBools(false, false, true, false, false),
                        splitPercent: 0
                    })
                );
            hook.test_store().ForTest_setReservesMintedFor(address(hook), i + 1, reservedMinted);
        }

        // Iterate through the tiers, attempting to mint the pending reserves.
        // Check: is the correct error thrown?
        for (uint256 tier = 1; tier <= numberOfTiers; tier++) {
            uint256 mintable = hook.test_store().numberOfPendingReservesFor(address(hook), tier);
            vm.prank(owner);
            vm.expectRevert(JB721TiersHook.JB721TiersHook_MintReserveNftsPaused.selector);
            hook.mintPendingReservesFor(tier, mintable);
        }
    }

    function test_mintPendingReservesFor_revertIfNotEnoughPendingReserves() public {
        uint256 initialSupply = 200; // The number of NFTs available for each tier.
        uint256 totalMinted = 120; // The number of NFTs already minted for each tier (out of `initialSupply`).
        uint256 reservedMinted = 1; // The number of reserve NFTs already minted (out of `totalMinted`).
        uint256 reserveFrequency = 4000; // The frequency at which NFTs are reserved (4000/10000 = 40%).

        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        // Initialize `numberOfTiers` tiers.
        for (uint256 i; i < 10; i++) {
            hook.test_store()
                .ForTest_setTier(
                    address(hook),
                    i + 1,
                    JBStored721Tier({
                        price: uint104((i + 1) * 10),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        remainingSupply: uint32(initialSupply - totalMinted),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        initialSupply: uint32(initialSupply),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        reserveFrequency: uint16(reserveFrequency),
                        category: uint24(100),
                        discountPercent: uint8(0),
                        packedBools: hook.test_store().ForTest_packBools(false, false, true, false, false),
                        splitPercent: 0
                    })
                );
            hook.test_store().ForTest_setReservesMintedFor(address(hook), i + 1, reservedMinted);
        }

        // Iterate through the tiers, attempting to mint more pending reserves than what is available.
        for (uint256 i = 1; i <= 10; i++) {
            // Get the number that we could mint successfully.
            uint256 amount = hook.test_store().numberOfPendingReservesFor(address(hook), i);
            // Increase it by 1 to cause an error, then attempt to mint.
            amount++;
            // Check: is the correct error thrown?
            vm.expectRevert(
                abi.encodeWithSelector(
                    JB721TiersHookStore.JB721TiersHookStore_InsufficientPendingReserves.selector, amount, amount - 1
                )
            );
            vm.prank(owner);
            hook.mintPendingReservesFor(i, amount);
        }
    }

    function test_numberOfPendingReservesFor_noReservesIfNoBeneficiarySet() public {
        uint256 initialSupply = 200; // The number of NFTs available for each tier.
        uint256 totalMinted = 120; // The number of NFTs already minted for each tier (out of `initialSupply`).
        uint256 reservedMinted = 10; // The number of reserve NFTs already minted (out of `totalMinted`).
        uint256 reserveFrequency = 9; // The frequency at which NFTs are reserved.
        // (For every 9 NFTs minted, 1 is reserved).

        reserveBeneficiary = address(0);
        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        // Initialize `numberOfTiers` tiers, and set the number of reserve NFTs already minted for each tier.
        // Although the `reserveFrequency` is set, it should be ignored since there is no reserve beneficiary.
        for (uint256 i; i < 10; i++) {
            hook.test_store()
                .ForTest_setTier(
                    address(hook),
                    i + 1,
                    JBStored721Tier({
                        price: uint104((i + 1) * 10),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        remainingSupply: uint32(initialSupply - totalMinted),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        initialSupply: uint32(initialSupply),
                        // forge-lint: disable-next-line(unsafe-typecast)
                        reserveFrequency: uint16(reserveFrequency),
                        category: uint24(100),
                        discountPercent: uint8(0),
                        packedBools: hook.test_store().ForTest_packBools(false, false, true, false, false),
                        splitPercent: 0
                    })
                );
            hook.test_store().ForTest_setReservesMintedFor(address(hook), i + 1, reservedMinted);
        }

        // Fetch the stored tiers.
        JB721Tier[] memory storedTiers = hook.test_store().tiersOf(address(hook), new uint256[](0), false, 0, 10);

        // Check: did the reserve frequency default to 0 for all tiers?
        for (uint256 i; i < 10; i++) {
            assertEq(storedTiers[i].reserveFrequency, 0, "Reserve frequency should be zero (no beneficiary set).");
        }
        // Check: are we sure there are no pending reserves for all tiers?
        for (uint256 i; i < 10; i++) {
            assertEq(
                hook.test_store().numberOfPendingReservesFor(address(hook), i + 1),
                0,
                "There should not be any pending reserves (no beneficiary set)."
            );
        }
    }

    function test_mintFor_mintArrayOfTiers() public {
        uint256 numberOfTiers = 3;

        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Mint 6 NFTs, 2 from each tier.
        uint16[] memory tiersToMint = new uint16[](numberOfTiers * 2);
        for (uint256 i; i < numberOfTiers; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            tiersToMint[i] = uint16(i) + 1;
            // forge-lint: disable-next-line(unsafe-typecast)
            tiersToMint[tiersToMint.length - 1 - i] = uint16(i) + 1;
        }

        vm.prank(owner);
        hook.mintFor(tiersToMint, beneficiary);

        // Check: does the beneficiary have the correct number of NFTs?
        assertEq(hook.balanceOf(beneficiary), 6);

        // Check: does the beneficiary own the correct NFTs?
        assertEq(hook.ownerOf(_generateTokenId(1, 1)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 2)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 1)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 2)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(3, 1)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(3, 2)), beneficiary);
    }

    function test_mintFor_revertIfManualMintNotAllowed() public {
        uint256 numberOfTiers = 10;

        uint16[] memory tiersToMint = new uint16[](numberOfTiers * 2);
        for (uint256 i; i < numberOfTiers; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            tiersToMint[i] = uint16(i) + 1;
            // forge-lint: disable-next-line(unsafe-typecast)
            tiersToMint[tiersToMint.length - 1 - i] = uint16(i) + 1;
        }

        // Set the `allowOwnerMint` flag to false and initialize the hook.
        defaultTierConfig.allowOwnerMint = false;
        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        vm.prank(owner);

        // Expect the function call to revert with the specified error message.
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_CantMintManually.selector, 1));

        // Call the `mintFor` function to trigger the revert.
        hook.mintFor(tiersToMint, beneficiary);
    }
}
