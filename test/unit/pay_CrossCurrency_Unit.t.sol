// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";

/// @notice Cross-currency unit tests for the 721 hook's normalizePaymentValue path.
/// Verifies correct behavior when payment token currency differs from tier pricing currency.
contract Test_crossCurrencyPay_Unit is UnitTestSetup {
    using stdStorage for StdStorage;

    // -- Currency constants
    uint32 nativeCurrency = uint32(uint160(JBConstants.NATIVE_TOKEN));

    // -- Mock USDC address
    address constant MOCK_USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    // forge-lint: disable-next-line(unsafe-typecast)
    uint32 usdcCurrency = uint32(uint160(MOCK_USDC));

    /// @notice Test 1: USDC payment -> USD-priced tier. normalizePaymentValue works with 1:1 USDC/USD.
    function test_normalizePaymentValue_usdcPayment_usdTier() public {
        // Initialize hook with USD-priced tiers + prices oracle.
        JB721TiersHook crossHook = _initHookDefaultTiers(1, false, uint32(USD()), 18);

        // Mock directory call.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mock pricePerUnitOf: USDC -> USD, 6 decimals. Returns 1e6 (1:1 USDC/USD).
        vm.mockCall(
            mockJBPrices,
            abi.encodeWithSelector(IJBPrices.pricePerUnitOf.selector, projectId, usdcCurrency, USD(), uint256(6)),
            abi.encode(uint256(1e6))
        );

        // Tier price is 10 (the default: tierId * 10 = 1 * 10 = 10).
        // Pay 10 USDC (6 decimals) -> normalized to 10e18 USD -> matches tier price of 10 (18 decimals).
        // But default tier price is 10 with 18-decimal pricing -> need exactly 10 as normalized value.
        // normalizePaymentValue: mulDiv(10e6, 1e18, pricePerUnitOf(_, usdcCurrency, USD, 6))
        // = mulDiv(10e6, 1e18, 1e6) = 10e18. But tier price with USD/18 decimals is 10 (raw).
        // Actually the tier prices from default config are: tiers[0].price = 10. With 18-decimal pricing,
        // the normalized value needs to be >= 10. normalizePaymentValue returns mulDiv(10e6, 1e18, 1e6) = 10e18.
        // 10e18 >= 10 → NFT minted.

        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", crossHook.METADATA_ID_TARGET());
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({token: MOCK_USDC, value: 10e6, decimals: 6, currency: usdcCurrency}),
            forwardedAmount: JBTokenAmount({token: MOCK_USDC, value: 0, decimals: 6, currency: usdcCurrency}),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });

        vm.prank(mockTerminalAddress);
        crossHook.afterPayRecordedWith(payContext);

        assertEq(crossHook.balanceOf(beneficiary), 1, "1 NFT minted from USDC -> USD tier");
    }

    /// @notice Test 2: ETH payment -> USD-priced tier (2000:1 ratio).
    function test_normalizePaymentValue_ethPayment_usdTier() public {
        JB721TiersHook crossHook = _initHookDefaultTiers(1, false, uint32(USD()), 18);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mock: pricePerUnitOf(_, nativeCurrency, USD, 18) = 5e14 (inverse of $2000).
        // "1 nativeCurrency unit costs 5e14 USD units" which represents 1/2000 of a USD unit in 18 decimals.
        vm.mockCall(
            mockJBPrices,
            abi.encodeWithSelector(IJBPrices.pricePerUnitOf.selector, projectId, nativeCurrency, USD(), uint256(18)),
            abi.encode(uint256(5e14))
        );

        // Pay 1 ETH -> normalizePaymentValue: mulDiv(1e18, 1e18, 5e14) = 2000e18.
        // Default tier price = 10 with 18 decimals. 2000e18 >= 10 → NFT minted.
        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", crossHook.METADATA_ID_TARGET());
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 1e18, decimals: 18, currency: nativeCurrency
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 0, decimals: 18, currency: nativeCurrency
            }),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });

        vm.prank(mockTerminalAddress);
        crossHook.afterPayRecordedWith(payContext);

        assertEq(crossHook.balanceOf(beneficiary), 1, "1 NFT minted from ETH -> USD tier");
    }

    /// @notice Test 3: Payment normalizes to exactly the tier price -> NFT minted.
    function test_normalizePaymentValue_exactTierBoundary() public {
        JB721TiersHook crossHook = _initHookDefaultTiers(1, false, uint32(USD()), 18);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Price feed returns exactly the amount needed for tier price of 10.
        // If we pay 10 units with a 1:1 ratio, normalized = 10. Tier price = 10 → exact match.
        vm.mockCall(
            mockJBPrices,
            abi.encodeWithSelector(IJBPrices.pricePerUnitOf.selector, projectId, nativeCurrency, USD(), uint256(18)),
            abi.encode(uint256(1e18)) // 1:1 ratio
        );

        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", crossHook.METADATA_ID_TARGET());
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Pay exactly 10 units → normalizePaymentValue = mulDiv(10, 1e18, 1e18) = 10.
        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({token: JBConstants.NATIVE_TOKEN, value: 10, decimals: 18, currency: nativeCurrency}),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 0, decimals: 18, currency: nativeCurrency
            }),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });

        vm.prank(mockTerminalAddress);
        crossHook.afterPayRecordedWith(payContext);

        assertEq(crossHook.balanceOf(beneficiary), 1, "NFT minted at exact tier price boundary");
    }

    /// @notice Test 4: Payment normalizes to 1 wei below tier price -> no NFT minted (stored as credit).
    function test_normalizePaymentValue_justBelowTierPrice() public {
        // preventOverspending = false so it doesn't revert, just skips the tier.
        JB721TiersHook crossHook = _initHookDefaultTiers(1, false, uint32(USD()), 18);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        vm.mockCall(
            mockJBPrices,
            abi.encodeWithSelector(IJBPrices.pricePerUnitOf.selector, projectId, nativeCurrency, USD(), uint256(18)),
            abi.encode(uint256(1e18)) // 1:1
        );

        // Pay 9 units → normalized = 9. Tier price = 10 → below threshold.
        // No metadata = no explicit tier selection, overspending allowed → 0 NFTs (just credit).
        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({token: JBConstants.NATIVE_TOKEN, value: 9, decimals: 18, currency: nativeCurrency}),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 0, decimals: 18, currency: nativeCurrency
            }),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: new bytes(0) // no metadata → auto-mint path
        });

        vm.prank(mockTerminalAddress);
        crossHook.afterPayRecordedWith(payContext);

        assertEq(crossHook.balanceOf(beneficiary), 0, "no NFT minted below tier price");
    }

    /// @notice Test 5: prices=address(0) + currencies differ -> normalizePaymentValue returns (0, false).
    function test_normalizePaymentValue_noPricesContract() public {
        // Deploy a separate hook origin with address(0) as PRICES to test the no-prices path.
        JB721TiersHook noPricesOrigin = new JB721TiersHook(
            IJBDirectory(mockJBDirectory),
            IJBPermissions(mockJBPermissions),
            IJBPrices(address(0)),
            IJBRulesets(mockJBRulesets),
            IJB721TiersHookStore(store),
            IJBSplits(mockJBSplits),
            trustedForwarder
        );

        // Create a fresh proxy address and etch the no-prices bytecode.
        address noPricesProxy = makeAddr("noPricesProxy");
        vm.etch(noPricesProxy, address(noPricesOrigin).code);
        JB721TiersHook crossHook = JB721TiersHook(noPricesProxy);

        // Initialize tiers with USD currency.
        (JB721TierConfig[] memory tierConfigs,) = _createTiers(defaultTierConfig, 1);
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

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Pay with native token (currency != USD). prices=address(0) → normalizePaymentValue returns (0, false).
        // No NFTs minted.
        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 1e18, decimals: 18, currency: nativeCurrency
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 0, decimals: 18, currency: nativeCurrency
            }),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: new bytes(0)
        });

        vm.prank(mockTerminalAddress);
        crossHook.afterPayRecordedWith(payContext);

        assertEq(crossHook.balanceOf(beneficiary), 0, "no NFT minted (prices=0, currencies differ)");
    }

    /// @notice Test 6: Extreme high price ratio (1e27) -> no overflow, correct normalization.
    function test_normalizePaymentValue_extremeHighPrice() public {
        JB721TiersHook crossHook = _initHookDefaultTiers(1, false, uint32(USD()), 18);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Price feed returns 1e27 (extreme ratio: 1 unit of pricingCurrency costs 1e27 units of unitCurrency).
        // pricePerUnitOf returns 1e27 with 18 decimals.
        // normalizePaymentValue: mulDiv(1e18, 1e18, 1e27) = 1e9.
        // 1e9 >= tier price 10 → NFT minted.
        vm.mockCall(
            mockJBPrices,
            abi.encodeWithSelector(IJBPrices.pricePerUnitOf.selector, projectId, nativeCurrency, USD(), uint256(18)),
            abi.encode(uint256(1e27))
        );

        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", crossHook.METADATA_ID_TARGET());
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 1e18, decimals: 18, currency: nativeCurrency
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 0, decimals: 18, currency: nativeCurrency
            }),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });

        vm.prank(mockTerminalAddress);
        crossHook.afterPayRecordedWith(payContext);

        assertEq(crossHook.balanceOf(beneficiary), 1, "NFT minted with extreme high price ratio");
    }

    /// @notice Test 7: Extreme low price ratio (1 wei) -> large normalized value, no revert.
    function test_normalizePaymentValue_extremeLowPrice() public {
        JB721TiersHook crossHook = _initHookDefaultTiers(1, false, uint32(USD()), 18);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Price feed returns 1 (near-zero: 1 unit costs 1 wei of the pricing currency).
        // normalizePaymentValue: mulDiv(1e18, 1e18, 1) = 1e36. This is a very large number.
        // 1e36 >= tier price 10 → NFT minted.
        vm.mockCall(
            mockJBPrices,
            abi.encodeWithSelector(IJBPrices.pricePerUnitOf.selector, projectId, nativeCurrency, USD(), uint256(18)),
            abi.encode(uint256(1))
        );

        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", crossHook.METADATA_ID_TARGET());
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 1e18, decimals: 18, currency: nativeCurrency
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 0, decimals: 18, currency: nativeCurrency
            }),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });

        vm.prank(mockTerminalAddress);
        crossHook.afterPayRecordedWith(payContext);

        assertEq(crossHook.balanceOf(beneficiary), 1, "NFT minted with extreme low price ratio");
    }

    /// @notice Test 8: Reverting price feed blocks afterPayRecordedWith (DoS, not fund loss).
    function test_revertingPriceFeed_blocksPayment() public {
        JB721TiersHook crossHook = _initHookDefaultTiers(1, false, uint32(USD()), 18);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Price feed reverts (stale data, sequencer down, etc.).
        vm.mockCallRevert(
            mockJBPrices,
            abi.encodeWithSelector(IJBPrices.pricePerUnitOf.selector),
            abi.encodeWithSignature("Error(string)", "stale price")
        );

        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", crossHook.METADATA_ID_TARGET());
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 1e18, decimals: 18, currency: nativeCurrency
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 0, decimals: 18, currency: nativeCurrency
            }),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });

        vm.prank(mockTerminalAddress);
        vm.expectRevert();
        crossHook.afterPayRecordedWith(payContext);
    }

    /// @notice Test 9: Reverting price feed blocks beforePayRecordedWith when tier has splits.
    function test_revertingPriceFeed_blocksSplitConversion() public {
        // Set splitPercent on the default tier config so the tier has a non-zero split.
        defaultTierConfig.splitPercent = 500_000_000; // 50%
        JB721TiersHook crossHook = _initHookDefaultTiers(1, false, uint32(USD()), 18);

        // Build payer metadata requesting tier 1.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = 1;
        bytes[] memory payMetadata = new bytes[](1);
        payMetadata[0] = abi.encode(false, mintIds);
        bytes4[] memory metaIds = new bytes4[](1);
        metaIds[0] = metadataHelper.getId("pay", crossHook.METADATA_ID_TARGET());
        bytes memory pMeta = metadataHelper.createMetadata(metaIds, payMetadata);

        // Price feed reverts (stale data, sequencer down, etc.).
        vm.mockCallRevert(
            mockJBPrices,
            abi.encodeWithSelector(IJBPrices.pricePerUnitOf.selector),
            abi.encodeWithSignature("Error(string)", "stale price")
        );

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: beneficiary,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 200, decimals: 18, currency: nativeCurrency
            }),
            projectId: projectId,
            rulesetId: 0,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 0,
            metadata: pMeta
        });

        // convertSplitAmounts calls pricePerUnitOf → reverts.
        vm.expectRevert();
        crossHook.beforePayRecordedWith(context);

        // Reset for other tests.
        defaultTierConfig.splitPercent = 0;
    }

    /// @notice Test 10: Mint multiple tiers at different USD prices, pay with ETH equivalent.
    function test_crossCurrency_mintMultipleTiers() public {
        // Create 3 tiers with different USD prices.
        tiers[0].price = 100; // Tier 1: 100 USD units
        tiers[1].price = 200; // Tier 2: 200 USD units
        tiers[2].price = 500; // Tier 3: 500 USD units

        JB721TiersHook crossHook = _initHookDefaultTiers(3, false, uint32(USD()), 18);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mock 1:1 USD/native ratio for simplicity.
        vm.mockCall(
            mockJBPrices,
            abi.encodeWithSelector(IJBPrices.pricePerUnitOf.selector, projectId, nativeCurrency, USD(), uint256(18)),
            abi.encode(uint256(1e18))
        );

        // Pay 800 units (= 100 + 200 + 500) -> should mint all 3 tiers.
        uint16[] memory tierIdsToMint = new uint16[](3);
        tierIdsToMint[0] = 1;
        tierIdsToMint[1] = 2;
        tierIdsToMint[2] = 3;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", crossHook.METADATA_ID_TARGET());
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 800, decimals: 18, currency: nativeCurrency
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN, value: 0, decimals: 18, currency: nativeCurrency
            }),
            weight: 10 ** 18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: bytes(""),
            payerMetadata: hookMetadata
        });

        vm.prank(mockTerminalAddress);
        crossHook.afterPayRecordedWith(payContext);

        assertEq(crossHook.balanceOf(beneficiary), 3, "3 NFTs minted across different USD-priced tiers");
    }
}
