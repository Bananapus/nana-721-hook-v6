// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../utils/UnitTestSetup.sol";

contract Test_afterPayRecorded_Unit is UnitTestSetup {
    using stdStorage for StdStorage;

    function test_afterPayRecorded_mintAndReserveCorrectAmounts(
        uint256 initialSupply,
        uint256 nftsToMint,
        uint256 reserveFrequency
    )
        public
    {
        initialSupply = 400;
        reserveFrequency = bound(reserveFrequency, 0, 200);
        nftsToMint = bound(nftsToMint, 1, 200);

        defaultTierConfig.initialSupply = uint32(initialSupply);
        defaultTierConfig.reserveFrequency = uint16(reserveFrequency);
        ForTest_JB721TiersHook hook = _initializeForTestHook(1); // Initialize with 1 default tier.

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint16[] memory tierIdsToMint = new uint16[](nftsToMint);

        for (uint256 i; i < nftsToMint; i++) {
            tierIdsToMint[i] = uint16(1);
        }

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hook));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 10 * nftsToMint,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 0,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }), // 0,
            // forwarded to the hook.
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(payContext);

        // Check: has the correct number of NFTs been minted for the beneficiary?
        assertEq(hook.balanceOf(beneficiary), nftsToMint);

        // Check: were the correct number of NFTs reserved?
        if (reserveFrequency > 0 && initialSupply - nftsToMint > 0) {
            uint256 reservedToken = nftsToMint / reserveFrequency;
            if (nftsToMint % reserveFrequency > 0) reservedToken += 1;

            assertEq(hook.STORE().numberOfPendingReservesFor(address(hook), 1), reservedToken);

            // Mint the pending reserves for the beneficiary.
            vm.prank(owner);
            hook.mintPendingReservesFor(1, reservedToken);

            // Check: did the reserve beneficiary receive the correct number of NFTs?
            assertEq(hook.balanceOf(reserveBeneficiary), reservedToken);
        } else {
            // Check: does the reserve beneficiary have no NFTs?
            assertEq(hook.balanceOf(reserveBeneficiary), 0);
        }
    }

    // If the amount paid is less than the NFT's price, the payment should revert if overspending is not allowed and no
    // metadata was passed.
    function test_afterPayRecorded_revertsOnAmountBelowPriceIfNoMetadataAndOverspendingIsPrevented() public {
        JB721TiersHook hook = _initHookDefaultTiers(10, true);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Expect a revert for overspending.
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.JB721TiersHook_Overspending.selector, tiers[0].price - 1));

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                // 1 wei below the minimum amount
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price - 1,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: new bytes(0)
            })
        );
    }

    // If the amount paid is less than the NFT's price, the payment should not revert if overspending is allowed and no
    // metadata was passed.
    function test_afterPayRecorded_doesNotRevertOnAmountBelowPriceIfNoMetadata() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                // 1 wei below the minimum amount
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price - 1,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: new bytes(0)
            })
        );

        // Check: does the payer have the correct number of pay credits?
        assertEq(hook.payCreditsOf(msg.sender), tiers[0].price - 1);
    }

    // If a tier is passed and the amount paid exceeds that NFT's price, mint as many NFTs as possible.
    function test_afterPayRecorded_mintCorrectTier() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price * 2 + tiers[1].price,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the correct number of NFTs been minted?
        assertEq(totalSupplyBeforePay + 3, hook.STORE().totalSupplyOf(address(hook)));

        // Check: has the correct number of NFTs been minted in each tier?
        assertEq(hook.ownerOf(_generateTokenId(1, 1)), msg.sender);
        assertEq(hook.ownerOf(_generateTokenId(1, 2)), msg.sender);
        assertEq(hook.ownerOf(_generateTokenId(2, 1)), msg.sender);
    }

    // If no tiers are passed, no NFTs should be minted.
    function test_afterPayRecorded_mintNoneIfNonePassed(uint8 amount) public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](0);
        bytes memory metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJB721TiersHook).interfaceId, allowOverspending, tierIdsToMint);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amount,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: metadata
            })
        );

        // Check: has the total supply stayed the same?
        assertEq(totalSupplyBeforePay, hook.STORE().totalSupplyOf(address(hook)));
    }

    function test_afterPayRecorded_mintTierAndTrackLeftover() public {
        uint256 leftover = tiers[0].price - 1;
        uint256 amount = tiers[0].price + leftover;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = uint16(1);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Calculate the new pay credits.
        uint256 newPayCredits = leftover + hook.payCreditsOf(beneficiary);

        vm.expectEmit(true, true, true, true, address(hook));
        emit AddPayCredits(newPayCredits, newPayCredits, beneficiary, mockTerminalAddress);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amount,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the pay credit balance been updated appropriately?
        assertEq(hook.payCreditsOf(beneficiary), leftover);
    }

    // Mint various tiers, leaving leftovers, and use the resulting pay credits to mint more NFTs.
    function test_afterPayRecorded_mintCorrectTiersWhenPartiallyUsingPayCredits() public {
        uint256 leftover = tiers[0].price + 1; // + 1 to avoid rounding error
        uint256 amount = tiers[0].price * 2 + tiers[1].price + leftover / 2;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        uint256 payCredits = hook.payCreditsOf(beneficiary);

        leftover = leftover / 2 + payCredits; // Amount left over.

        vm.expectEmit(true, true, true, true, address(hook));
        emit AddPayCredits(leftover - payCredits, leftover, beneficiary, mockTerminalAddress);

        // First call will mint the 3 tiers requested and accumulate half of the first price in pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amount,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 totalSupplyBefore = hook.STORE().totalSupplyOf(address(hook));
        {
            // We now attempt to mint an additional NFT from tier 1 using the pay credits we collected.
            uint16[] memory moreTierIdsToMint = new uint16[](4);
            moreTierIdsToMint[0] = 1;
            moreTierIdsToMint[1] = 1;
            moreTierIdsToMint[2] = 2;
            moreTierIdsToMint[3] = 1;

            data[0] = abi.encode(allowOverspending, moreTierIdsToMint);

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Fetch existing credits.
        payCredits = hook.payCreditsOf(beneficiary);
        vm.expectEmit(true, true, true, true, address(hook));
        emit UsePayCredits(
            payCredits,
            0, // No stashed credits.
            beneficiary,
            mockTerminalAddress
        );

        // Second call will mint another 3 tiers requested and mint from the first tier using pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amount,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the total supply increased?
        assertEq(totalSupplyBefore + 4, hook.STORE().totalSupplyOf(address(hook)));

        // Check: have the correct tiers been minted...
        // ... from the first payment?
        assertEq(hook.ownerOf(_generateTokenId(1, 1)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 2)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 1)), beneficiary);

        // ... from the second payment?
        assertEq(hook.ownerOf(_generateTokenId(1, 3)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 4)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 5)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 2)), beneficiary);

        // Check: have all pay credits been used?
        assertEq(hook.payCreditsOf(beneficiary), 0);
    }

    function test_afterPayRecorded_doNotMintWithSomeoneElsesCredits() public {
        uint256 leftover = tiers[0].price + 1; // + 1 to avoid rounding error.
        uint256 amount = tiers[0].price * 2 + tiers[1].price + leftover / 2;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // The first call will mint the 3 tiers requested and accumulate half of the first price as pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amount,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 totalSupplyBefore = hook.STORE().totalSupplyOf(address(hook));
        uint256 payCreditsBefore = hook.payCreditsOf(beneficiary);

        // The second call will mint another 3 tiers requested but NOT with the pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amount,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the total supply has increased by 3 NFTs?
        assertEq(totalSupplyBefore + 3, hook.STORE().totalSupplyOf(address(hook)));

        // Check: were the correct tiers minted...
        // ... from the first payment?
        assertEq(hook.ownerOf(_generateTokenId(1, 1)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 2)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 1)), beneficiary);

        // ... from the second payment (without extras from the pay credits)?
        assertEq(hook.ownerOf(_generateTokenId(1, 3)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(1, 4)), beneficiary);
        assertEq(hook.ownerOf(_generateTokenId(2, 2)), beneficiary);

        // Check: are pay credits from both payments left over?
        assertEq(hook.payCreditsOf(beneficiary), payCreditsBefore * 2);
    }

    // The terminal uses currency 1 with 18 decimals, and the hook uses currency 2 with 9 decimals.
    // The conversion rate is set at 1:2.
    function test_afterPayRecorded_mintCorrectTierWithAnotherCurrency() public {
        address jbPrice = address(bytes20(keccak256("MockJBPrice")));
        vm.etch(jbPrice, new bytes(1));

        // Currency 2, with 9 decimals.
        JB721TiersHook hook = _initHookDefaultTiers(10, false, 2, 9, jbPrice);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mock the price oracle call.
        uint256 amountInEth = (tiers[0].price * 2 + tiers[1].price) * 2;
        mockAndExpect(
            jbPrice,
            abi.encodeCall(IJBPrices.pricePerUnitOf, (projectId, uint32(uint160(JBConstants.NATIVE_TOKEN)), 2, 18)),
            abi.encode(2 * 10 ** 9)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amountInEth,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Make sure 3 new NFTs were minted.
        assertEq(totalSupplyBeforePay + 3, hook.STORE().totalSupplyOf(address(hook)));

        // Check: have the correct NFT tiers been minted?
        assertEq(hook.ownerOf(_generateTokenId(1, 1)), msg.sender);
        assertEq(hook.ownerOf(_generateTokenId(1, 2)), msg.sender);
        assertEq(hook.ownerOf(_generateTokenId(2, 1)), msg.sender);
    }

    // If the tier has been removed, revert.
    function test_afterPayRecorded_revertIfTierRemoved() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 1;

        vm.prank(owner);
        hook.adjustTiers(new JB721TierConfig[](0), toRemove);

        vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_TierRemoved.selector, 1));

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price * 2 + tiers[1].price,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the total supply stayed the same?
        assertEq(totalSupplyBeforePay, hook.STORE().totalSupplyOf(address(hook)));
    }

    function test_afterPayRecorded_revertIfTierDoesNotExist(uint256 invalidTier) public {
        invalidTier = bound(invalidTier, tiers.length + 1, type(uint16).max);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = uint16(invalidTier);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 1;

        vm.prank(owner);
        hook.adjustTiers(new JB721TierConfig[](0), toRemove);

        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_UnrecognizedTier.selector, invalidTier)
        );

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price * 2 + tiers[1].price,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the total supply stayed the same?
        assertEq(totalSupplyBeforePay, hook.STORE().totalSupplyOf(address(hook)));
    }

    // If the amount is not enought to pay for all of the requested tiers, revert.
    function test_afterPayRecorded_revertIfAmountTooLow() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Expect a revert for the amount being too low.
        vm.expectRevert(
            abi.encodeWithSelector(
                JB721TiersHookStore.JB721TiersHookStore_PriceExceedsAmount.selector, tiers[1].price, tiers[1].price - 1
            )
        );

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price * 2 + tiers[1].price - 1,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the total supply stayed the same?
        assertEq(totalSupplyBeforePay, hook.STORE().totalSupplyOf(address(hook)));
    }

    function test_afterPayRecorded_revertIfAllowanceRunsOutInSpecifiedTier() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        uint256 supplyLeft = tiers[0].initialSupply;

        while (true) {
            uint256 totalSupplyBeforePay = hook.STORE().totalSupplyOf(address(hook));

            bool allowOverspending = true;

            uint16[] memory tierSelected = new uint16[](1);
            tierSelected[0] = 1;

            // Build the metadata using the tiers to mint and the overspending flag.
            bytes[] memory data = new bytes[](1);
            data[0] = abi.encode(allowOverspending, tierSelected);

            // Pass the hook ID.
            bytes4[] memory ids = new bytes4[](1);
            ids[0] = metadataHelper.getId("pay", address(hookOrigin));

            // Generate the metadata.
            bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

            // If there is no remaining supply, this should revert.
            if (supplyLeft == 0) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        JB721TiersHookStore.JB721TiersHookStore_InsufficientSupplyRemaining.selector, 1
                    )
                );
            }

            // Execute the payment.
            vm.prank(mockTerminalAddress);
            hook.afterPayRecordedWith(
                JBAfterPayRecordedContext({
                    payer: msg.sender,
                    projectId: projectId,
                    rulesetId: 0,
                    amount: JBTokenAmount({
                        token: JBConstants.NATIVE_TOKEN,
                        value: tiers[0].price,
                        decimals: 18,
                        currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                    }),
                    forwardedAmount: JBTokenAmount({
                        token: JBConstants.NATIVE_TOKEN,
                        value: 0,
                        decimals: 18,
                        currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                    }), // 0, forwarded to the hook.
                    weight: 10 ** 18,
                    newlyIssuedTokenCount: 0,
                    beneficiary: msg.sender,
                    hookMetadata: new bytes(0),
                    payerMetadata: hookMetadata
                })
            );
            // If there's no supply left...
            if (supplyLeft == 0) {
                // Check: has the total supply stayed the same?
                assertEq(hook.STORE().totalSupplyOf(address(hook)), totalSupplyBeforePay);
                break;
            } else {
                // Otherwise, check that the total supply has increased by 1.
                assertEq(hook.STORE().totalSupplyOf(address(hook)), totalSupplyBeforePay + 1);
            }
            --supplyLeft;
        }
    }

    function test_afterPayRecorded_revertIfCallerIsNotATerminalOfProjectId(address terminal) public {
        vm.assume(terminal != mockTerminalAddress);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, terminal),
            abi.encode(false)
        );

        // The caller is the `_expectedCaller`. However, the terminal in the calldata is not correct.
        vm.prank(terminal);

        // Expect a revert for the caller not being a terminal of the project.
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.JB721TiersHook_InvalidPay.selector));

        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: address(0), value: 0, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: new bytes(0)
            })
        );
    }

    function test_afterPayRecorded_silentlyReturnsOnCurrencyMismatchWithoutPriceFeed(address token) public {
        vm.assume(token != JBConstants.NATIVE_TOKEN);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // The payment's currency (18, from positional arg order) doesn't match the hook's pricing currency.
        // With no price feed configured, this silently returns without minting (no revert).
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount(token, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))),
                forwardedAmount: JBTokenAmount(
                    JBConstants.NATIVE_TOKEN, 0, 18, uint32(uint160(JBConstants.NATIVE_TOKEN))
                ), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: new bytes(0)
            })
        );

        // Verify no credits were added (the function returned early).
        assertEq(hook.payCreditsOf(msg.sender), 0);
    }

    function test_afterPayRecorded_mintWithExistingCreditsWhenMoreExistingCreditsThanNewCredits() public {
        uint256 leftover = tiers[0].price + 1; // + 1 to avoid rounding error.
        uint256 amount = tiers[0].price * 2 + tiers[1].price + leftover / 2;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        uint256 credits = hook.payCreditsOf(beneficiary);
        leftover = leftover / 2 + credits; // Leftover amount.

        vm.expectEmit(true, true, true, true, address(hook));
        emit AddPayCredits(leftover - credits, leftover, beneficiary, mockTerminalAddress);

        // The first call will mint the 3 tiers requested and accumulate half of the first price as pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amount,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 totalSupplyBefore = hook.STORE().totalSupplyOf(address(hook));
        {
            // We now attempt to mint an additional NFT from tier 1 by using the pay credits we collected from the last
            // payment.
            uint16[] memory moreTierIdsToMint = new uint16[](1);
            moreTierIdsToMint[0] = 1;

            data[0] = abi.encode(allowOverspending, moreTierIdsToMint);

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Fetch the existing pay credits.
        credits = hook.payCreditsOf(beneficiary);

        // Use existing credits to mint.
        leftover = tiers[0].price - 1 - credits;
        vm.expectEmit(true, true, true, true, address(hook));
        emit UsePayCredits(credits - leftover, leftover, beneficiary, mockTerminalAddress);

        // Mint with leftover pay credits.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: beneficiary,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price - 1,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        // Check: has the total supply increased by 1?
        assertEq(totalSupplyBefore + 1, hook.STORE().totalSupplyOf(address(hook)));
    }

    function test_afterPayRecorded_revertIfUnexpectedLeftover() public {
        uint256 leftover = tiers[1].price - 1;
        uint256 amount = tiers[0].price + leftover;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );
        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](0);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);
        vm.prank(mockTerminalAddress);
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.JB721TiersHook_Overspending.selector, amount));
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amount,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );
    }

    function test_afterPayRecorded_revertIfUnexpectedLeftoverAndOverspendingPrevented(bool prevent) public {
        uint256 leftover = tiers[1].price - 1;
        uint256 amount = tiers[0].price + leftover;

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Get the current flags.
        JB721TiersHookFlags memory flags = hook.STORE().flagsOf(address(hook));

        // Set the prevent flag to the given value.
        flags.preventOverspending = prevent;

        // Mock the call to return the new flags.
        mockAndExpect(
            address(hook.STORE()),
            abi.encodeWithSelector(IJB721TiersHookStore.flagsOf.selector, address(hook)),
            abi.encode(flags)
        );

        bool allowOverspending = true;
        uint16[] memory tierIdsToMint = new uint16[](0);

        bytes memory metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJB721TiersHook).interfaceId, allowOverspending, tierIdsToMint);

        // If prevent is enabled the call should revert. Otherwise, we should receive pay credits.
        if (prevent) {
            vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.JB721TiersHook_Overspending.selector, amount));
        } else {
            uint256 payCredits = hook.payCreditsOf(beneficiary);
            uint256 stashedPayCredits = payCredits;
            // Calculating new pay credit balance (since leftover is non-zero).
            uint256 newPayCredits = tiers[0].price + leftover + stashedPayCredits;
            vm.expectEmit(true, true, true, true, address(hook));
            emit AddPayCredits(newPayCredits - payCredits, newPayCredits, beneficiary, mockTerminalAddress);
        }
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: amount,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: beneficiary,
                hookMetadata: new bytes(0),
                payerMetadata: metadata
            })
        );
    }

    // If transfers are paused, transfers which do not involve the zero address are reverted,
    // as long as the `transfersPausable` flag must be true.
    // Transfers involving the zero address (minting and burning) are not affected.
    function test_transferFrom_revertTransferIfPausedInRuleset() public {
        defaultTierConfig.transfersPausable = true;
        JB721TiersHook hook = _initHookDefaultTiers(10);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

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
                            dataHook: address(hook),
                            metadata: 1
                        })
                    )
                })
            )
        );

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price * 2 + tiers[1].price,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 tokenId = _generateTokenId(1, 1);

        // Expect a revert on account of transfers being paused.
        vm.expectRevert(JB721TiersHook.JB721TiersHook_TierTransfersPaused.selector);

        vm.prank(msg.sender);
        IERC721(hook).transferFrom(msg.sender, beneficiary, tokenId);
    }

    // If the ruleset metadata has `pauseTransfers` enabled,
    // BUT the tier being transferred has `transfersPausable` disabled,
    // transfer are not paused (this bypasses the call to `JBRulesets`).
    function test_transferFrom_pauseFlagOverridesRuleset() public {
        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        JB721TiersHook hook = _initHookDefaultTiers(10);

        bool allowOverspending;
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 1;
        tierIdsToMint[2] = 2;

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIdsToMint);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: msg.sender,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price * 2 + tiers[1].price,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: msg.sender,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256 tokenId = _generateTokenId(1, 1);
        vm.prank(msg.sender);
        IERC721(hook).transferFrom(msg.sender, beneficiary, tokenId);
        // Check: was the NFT transferred to the beneficiary?
        assertEq(IERC721(hook).ownerOf(tokenId), beneficiary);
    }

    // Cash out an NFT, even if transfers are paused in the ruleset metadata. This should bypass the call to
    // `JBRulesets`.
    function test_afterCashOutRecordedWith_cashOutEvenIfTransfersPausedInRuleset() public {
        address holder = address(bytes20(keccak256("holder")));

        JB721TiersHook hook = _initHookDefaultTiers(10);

        // Mock the directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Build the metadata which will be used to mint.
        bytes memory hookMetadata;
        bytes[] memory data = new bytes[](1);
        bytes4[] memory ids = new bytes4[](1);

        {
            // Craft the metadata: mint the specified tier.
            uint16[] memory rawMetadata = new uint16[](1);
            rawMetadata[0] = uint16(1); // 1 indexed

            // Build the metadata using the tiers to mint and the overspending flag.
            data[0] = abi.encode(true, rawMetadata);

            // Pass the hook ID.
            ids[0] = metadataHelper.getId("pay", address(hook));

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Mint the NFTs. Otherwise, the voting balance is not incremented which leads to an underflow upon cash outs.
        vm.prank(mockTerminalAddress);
        hook.afterPayRecordedWith(
            JBAfterPayRecordedContext({
                payer: holder,
                projectId: projectId,
                rulesetId: 0,
                amount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: tiers[0].price,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: JBConstants.NATIVE_TOKEN,
                    value: 0,
                    decimals: 18,
                    currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0,
                // forwarded to the hook.
                weight: 10 ** 18,
                newlyIssuedTokenCount: 0,
                beneficiary: holder,
                hookMetadata: new bytes(0),
                payerMetadata: hookMetadata
            })
        );

        uint256[] memory tokenToCashOut = new uint256[](1);
        tokenToCashOut[0] = _generateTokenId(1, 1);

        // Build the metadata with the tiers to cash out.
        data[0] = abi.encode(tokenToCashOut);

        // Pass the hook ID.
        ids[0] = metadataHelper.getId("pay", address(hookOrigin));

        // Generate the metadata.
        hookMetadata = metadataHelper.createMetadata(ids, data);

        vm.prank(mockTerminalAddress);
        hook.afterCashOutRecordedWith(
            JBAfterCashOutRecordedContext({
                holder: holder,
                projectId: projectId,
                rulesetId: 1,
                cashOutCount: 0,
                reclaimedAmount: JBTokenAmount({
                    token: address(0), value: 0, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }),
                forwardedAmount: JBTokenAmount({
                    token: address(0), value: 0, decimals: 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
                }), // 0, forwarded to the hook.
                cashOutTaxRate: 5000,
                beneficiary: payable(holder),
                hookMetadata: bytes(""),
                cashOutMetadata: hookMetadata
            })
        );

        // Check: has the holder's balance returned to 0?
        assertEq(hook.balanceOf(holder), 0);
    }
}
