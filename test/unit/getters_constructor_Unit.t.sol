// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../utils/UnitTestSetup.sol";

contract Test_Getters_Constructor_Unit is UnitTestSetup {
    using stdStorage for StdStorage;

    function test_tiersOf_returnsAllTiers(uint256 numberOfTiers) public {
        numberOfTiers = bound(numberOfTiers, 0, 30);

        (, JB721Tier[] memory tiers) = _createTiers(defaultTierConfig, numberOfTiers);

        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Check: is everything from `tiersOf` in `tiers`, and vice versa (do they match)?
        assertTrue(_isIn(hook.test_store().tiersOf(address(hook), new uint256[](0), false, 0, numberOfTiers), tiers));
        assertTrue(_isIn(tiers, hook.test_store().tiersOf(address(hook), new uint256[](0), false, 0, numberOfTiers)));
    }

    function test_pricingContext_packingFunctionsAsExpected(
        uint32 currency,
        uint8 decimals,
        address prices,
        bytes32 salt
    )
        public
    {
        // Decimals must be <= 18 per validation in initialize.
        vm.assume(decimals <= 18);
        JBDeploy721TiersHookConfig memory hookConfig = JBDeploy721TiersHookConfig(
            name,
            symbol,
            baseUri,
            IJB721TokenUriResolver(mockTokenUriResolver),
            contractUri,
            JB721InitTiersConfig({tiers: tiers, currency: currency, decimals: decimals, prices: IJBPrices(prices)}),
            address(0),
            JB721TiersHookFlags({
                preventOverspending: false,
                noNewTiersWithReserves: true,
                noNewTiersWithVotes: true,
                noNewTiersWithOwnerMinting: true
            })
        );

        JB721TiersHook hook = JB721TiersHook(address(jbHookDeployer.deployHookFor(projectId, hookConfig, salt)));

        (uint256 currency2, uint256 decimals2, IJBPrices prices2) = hook.pricingContext();
        // Check: do the unpacked values from `pricingContext` match the values we used in the config?
        assertEq(currency2, uint256(currency));
        assertEq(decimals2, uint256(decimals));
        assertEq(address(prices2), prices);
    }

    function test_bools_doesPackingAndUnpackingWork(bool a, bool b, bool c, bool d, bool e) public {
        ForTest_JB721TiersHookStore store = new ForTest_JB721TiersHookStore();
        uint8 packed = store.ForTest_packBools(a, b, c, d, e);
        (bool a2, bool b2, bool c2, bool d2, bool e2) = store.ForTest_unpackBools(packed);
        // Check: do the packed values match the unpacked values?
        assertEq(a, a2);
        assertEq(b, b2);
        assertEq(c, c2);
        assertEq(d, d2);
        assertEq(e, e2);
    }

    function test_tiersOf_returnsAllTiersWithResolver(uint256 numberOfTiers) public {
        numberOfTiers = bound(numberOfTiers, 0, 30);

        // Use a non-null resolved URI.
        defaultTierConfig.encodedIPFSUri = bytes32(hex"69");

        (, JB721Tier[] memory tiers) = _createTiers(defaultTierConfig, numberOfTiers);

        mockTokenUriResolver = makeAddr("mockTokenUriResolver");
        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        for (uint256 i; i < numberOfTiers; i++) {
            // Mock the URI resolver call
            mockAndExpect(
                mockTokenUriResolver,
                abi.encodeWithSelector(
                    IJB721TokenUriResolver.tokenUriOf.selector, address(hook), _generateTokenId(i + 1, 0)
                ),
                abi.encode(string(abi.encodePacked("resolverURI", _generateTokenId(i + 1, 0))))
            );
        }

        // Check: is everything from `tiersOf` in `tiers`, and vice versa (do they match)? Do the resolved URIs match?
        assertTrue(_isIn(hook.test_store().tiersOf(address(hook), new uint256[](0), true, 0, 100), tiers));
        assertTrue(_isIn(tiers, hook.test_store().tiersOf(address(hook), new uint256[](0), true, 0, 100)));
    }

    function test_tiersOf_returnsAllTiersExcludingRemovedOnes(
        uint256 numberOfTiers,
        uint256 firstRemovedTier,
        uint256 secondRemovedTier
    )
        public
    {
        numberOfTiers = bound(numberOfTiers, 1, 30);
        firstRemovedTier = bound(firstRemovedTier, 1, numberOfTiers);
        secondRemovedTier = bound(secondRemovedTier, 1, numberOfTiers);
        vm.assume(firstRemovedTier != secondRemovedTier);

        (, JB721Tier[] memory tiers) = _createTiers(defaultTierConfig, numberOfTiers);

        // Only copy the tiers we keep.
        JB721Tier[] memory nonRemovedTiers = new JB721Tier[](numberOfTiers - 2);
        uint256 j;
        for (uint256 i; i < numberOfTiers; i++) {
            if (i != firstRemovedTier - 1 && i != secondRemovedTier - 1) {
                nonRemovedTiers[j] = tiers[i];
                j++;
            }
        }

        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Set the removed tiers.
        hook.test_store().ForTest_setIsTierRemoved(address(hook), firstRemovedTier);
        hook.test_store().ForTest_setIsTierRemoved(address(hook), secondRemovedTier);

        JB721Tier[] memory storedTiers =
            hook.test_store().tiersOf(address(hook), new uint256[](0), false, 0, numberOfTiers);

        // Check: was the returned tier array resized correctly?
        assertEq(storedTiers.length, numberOfTiers - 2);

        // Check: is everything from `storedTiers` a `nonRemovedTier`, and vice versa (do they match)?
        assertTrue(_isIn(storedTiers, nonRemovedTiers));
        assertTrue(_isIn(nonRemovedTiers, storedTiers));
    }

    function test_tierOf_returnsAGivenTier(uint256 numberOfTiers, uint16 givenTier) public {
        numberOfTiers = bound(numberOfTiers, 0, 30);

        (, JB721Tier[] memory tiers) = _createTiers(defaultTierConfig, numberOfTiers);
        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Check: if the tier exists, it is returned correctly?
        if (givenTier <= numberOfTiers && givenTier != 0) {
            assertEq(hook.test_store().tierOf(address(hook), givenTier, false), tiers[givenTier - 1]);
        } else {
            assertEq( // Check: if the tier doesn't exist, is an empty tier returned?
                hook.test_store().tierOf(address(hook), givenTier, false),
                JB721Tier({
                    id: givenTier,
                    price: 0,
                    remainingSupply: 0,
                    initialSupply: 0,
                    votingUnits: 0,
                    reserveFrequency: 0,
                    reserveBeneficiary: address(0),
                    encodedIPFSUri: bytes32(0),
                    category: uint24(100),
                    discountPercent: uint8(0),
                    allowOwnerMint: false,
                    transfersPausable: false,
                    cannotBeRemoved: false,
                    cannotIncreaseDiscountPercent: false,
                    resolvedUri: ""
                })
            );
        }
    }

    function test_totalSupplyOf_returnsTotalSupply(uint256 numberOfTiers) public {
        numberOfTiers = bound(numberOfTiers, 0, 30);

        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Initialize `numberOfTiers` tiers with an initial supply of 100, and (i + 1) mints.
        // This should yield a total supply of (`numberOfTiers` * (`numberOfTiers` + 1)) / 2,
        // which is the sum of natural numbers from 1 to `numberOfTiers`.
        for (uint256 i; i < numberOfTiers; i++) {
            hook.test_store().ForTest_setTier(
                address(hook),
                i + 1,
                JBStored721Tier({
                    price: uint104((i + 1) * 10),
                    remainingSupply: uint32(100 - (i + 1)),
                    initialSupply: uint32(100),
                    votingUnits: uint16(0),
                    reserveFrequency: uint16(0),
                    category: uint24(100),
                    discountPercent: uint8(0),
                    packedBools: hook.test_store().ForTest_packBools(false, false, false, false, false)
                })
            );
        }

        // Check: does the total supply match the expected value?
        assertEq(hook.test_store().totalSupplyOf(address(hook)), ((numberOfTiers * (numberOfTiers + 1)) / 2));
    }

    function test_balanceOf_returnsCompleteBalance(uint256 numberOfTiers, address holder) public {
        numberOfTiers = bound(numberOfTiers, 0, 30);

        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Give the holder (i + 1) * 10 NFTs from each tier up to `numberOfTiers`.
        for (uint256 i; i < numberOfTiers; i++) {
            hook.test_store().ForTest_setBalanceOf(address(hook), holder, i + 1, (i + 1) * 10);
        }

        // Check: does the holder have the correct NFT balance?
        // Calculated using 10 * sum of natural numbers from 1 to `numberOfTiers`.
        assertEq(hook.balanceOf(holder), 10 * ((numberOfTiers * (numberOfTiers + 1)) / 2));
    }

    function test_numberOfPendingReservesFor_returnsPendingReserves() public {
        uint256 initialSupply = 200; // the starting supply
        uint256 totalMinted = 120; // the number to mint from the supply
        uint256 reservedMinted = 10; // the number of reserve mints (out of `totalMinted`)
        uint256 reserveFrequency = 9; // the reserve frequency

        // For each tier, 120 NFTs are minted, and 10 of these are reserve mints.
        // This means 110 non-reserved NFTs are minted.
        // Since the `reserveFrequency` is 9, for every 9 non-reserved tokens minted, 1 reserved token is minted.
        // The total number of reserve mints should be `ceil(non-reserve mints / reserveFrequency)`.
        // In our case, `ceil(110/9)` comes out to 13, and 10 reserve mints have already been minted.
        // Therefore, there should be 3 reserve mints remaining for each tier.

        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        // Set up 10 tiers, each with the parameters above.
        for (uint256 i; i < 10; i++) {
            hook.test_store().ForTest_setTier(
                address(hook),
                i + 1,
                JBStored721Tier({
                    price: uint104((i + 1) * 10),
                    remainingSupply: uint32(initialSupply - totalMinted),
                    initialSupply: uint32(initialSupply),
                    votingUnits: uint16(0),
                    reserveFrequency: uint16(reserveFrequency),
                    category: uint24(100),
                    discountPercent: uint8(0),
                    packedBools: hook.test_store().ForTest_packBools(false, false, false, false, false)
                })
            );
            // Manually set the number of reserve mints for each tier.
            hook.test_store().ForTest_setReservesMintedFor(address(hook), i + 1, reservedMinted);
        }

        // Check: does each tier have the correct number of pending reserves?
        for (uint256 i; i < 10; i++) {
            assertEq(hook.test_store().numberOfPendingReservesFor(address(hook), i + 1), 3);
        }
    }

    function test_votingUnitsOf_returnsVotingUnitsCorrectly(
        uint256 numberOfTiers,
        uint256 votingUnits,
        uint256 balances
    )
        public
    {
        numberOfTiers = bound(numberOfTiers, 1, 30);
        votingUnits = bound(votingUnits, 1, type(uint32).max);
        balances = bound(balances, 1, type(uint32).max);

        defaultTierConfig.useVotingUnits = true;
        defaultTierConfig.votingUnits = uint32(votingUnits);
        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Set up tier 1 with 0 voting units.
        hook.test_store().ForTest_setTier(
            address(hook),
            1,
            JBStored721Tier({
                price: uint104(10),
                remainingSupply: uint32(10),
                initialSupply: uint32(20),
                votingUnits: uint16(0),
                reserveFrequency: uint16(100),
                category: uint24(100),
                discountPercent: uint8(0),
                packedBools: hook.test_store().ForTest_packBools(false, false, true, false, false)
            })
        );

        // Give the beneficiary `balances` NFTs from each tier up to `numberOfTiers`.
        for (uint256 i; i < numberOfTiers; i++) {
            hook.test_store().ForTest_setBalanceOf(address(hook), beneficiary, i + 1, balances);
        }

        // Check: does the beneficiary have the correct number voting units?
        assertEq(
            hook.test_store().votingUnitsOf(address(hook), beneficiary),
            numberOfTiers * votingUnits * balances - (votingUnits * balances) // One tier has no voting units.
        );
    }

    function test_tierOfTokenId_returnsCorrectTierNumber(uint16 tierId, uint16 tokenNumber) public {
        vm.assume(tierId > 0 && tokenNumber > 0);
        uint256 tokenId = _generateTokenId(tierId, tokenNumber);
        // Check: does the generated token ID match the provided `tierId`.
        assertEq(hook.STORE().tierOfTokenId(address(hook), tokenId, false).id, tierId);
    }

    function test_tokenURI_returnsCorrectUriWithResolver(uint256 tokenId) public {
        mockTokenUriResolver = makeAddr("mockTokenUriResolver");

        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        // Mock the URI resolver call.
        mockAndExpect(
            mockTokenUriResolver,
            abi.encodeWithSelector(IJB721TokenUriResolver.tokenUriOf.selector, address(hook), tokenId),
            abi.encode("resolverURI")
        );

        hook.ForTest_setOwnerOf(tokenId, beneficiary);

        // Check: does the token URI resolver return the correct URI from the resolver?
        assertEq(hook.tokenURI(tokenId), "resolverURI");
    }

    function test_tokenURI_returnsCorrectUriWithoutResolver() public {
        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        // Check: for each tier, does the tier's token URI match the theoretic hash?
        for (uint256 i = 1; i <= 10; i++) {
            uint256 tokenId = _generateTokenId(i, 1);
            assertEq(hook.tokenURI(tokenId), string(abi.encodePacked(baseUri, theoreticHashes[i - 1])));
        }
    }

    function test_setEncodedIPFSUriOf_returnsCorrectEncodedURI() public {
        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        uint256 tokenId = _generateTokenId(1, 1);
        hook.ForTest_setOwnerOf(tokenId, address(123));

        vm.prank(owner);
        hook.setMetadata("", "", IJB721TokenUriResolver(address(0)), 1, tokenUris[1]);

        // Check: does the token URI match the theoretic hash?
        assertEq(hook.tokenURI(tokenId), string(abi.encodePacked(baseUri, theoreticHashes[1])));
    }

    function test_cashOutWeightOf_returnsCorrectWeightAsCumSumOfPrices(
        uint256 numberOfTiers,
        uint256 firstTier,
        uint256 lastTier
    )
        public
    {
        numberOfTiers = bound(numberOfTiers, 0, 30);
        lastTier = bound(lastTier, 0, numberOfTiers);
        firstTier = bound(firstTier, 0, lastTier);

        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        // Each tier has `tierId` mintable NFTs, so the maximum number of mints
        // is the sum of natural numbers from 1 to `numberOfTiers`.
        uint256 maxNumberOfTiers = (numberOfTiers * (numberOfTiers + 1)) / 2;

        // Initialize an array `tierToGetWeightOf` to store the token IDs for each tier,
        // which will later be used to calculate the cash out weight.
        uint256[] memory tierToGetWeightOf = new uint256[](maxNumberOfTiers);
        uint256 iterator;
        uint256 theoreticalWeight;

        // Mint `tierId` NFTs for each tier. In the inner loop, `i + 1` is the tier ID, and `j + 1` is the token ID.
        for (uint256 i; i < numberOfTiers; i++) {
            if (i >= firstTier && i < lastTier) {
                for (uint256 j; j <= i; j++) {
                    tierToGetWeightOf[iterator] = _generateTokenId(i + 1, j + 1);
                    iterator++;
                }
                theoreticalWeight += (i + 1) * (i + 1) * 10; // Add the price of the NFTs to the weight.
                    // (10 is the price multiplier).
            }
        }

        // Check: does the cash out weight match the expected value?
        assertEq(hook.test_store().cashOutWeightOf(address(hook), tierToGetWeightOf), theoreticalWeight);
    }

    function test_totalCashOutWeight_returnsCorrectTotalWeightAsCumSumOfPrices(uint256 numberOfTiers) public {
        numberOfTiers = bound(numberOfTiers, 0, 30);

        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);

        uint256 theoreticalWeight;

        // Set up `numberOfTiers` tiers and calculate the theoretical weight for each.
        for (uint256 i = 1; i <= numberOfTiers; i++) {
            hook.test_store().ForTest_setTier(
                address(hook),
                i,
                JBStored721Tier({
                    price: uint104(i * 10),
                    remainingSupply: uint32(10 * i - 5 * i),
                    initialSupply: uint32(10 * i),
                    votingUnits: uint16(0),
                    reserveFrequency: uint16(0),
                    category: uint24(100),
                    discountPercent: uint8(0),
                    packedBools: hook.test_store().ForTest_packBools(false, false, false, false, false)
                })
            );
            // Calculate the theoretical weight for the current tier. 10 the price multiplier.
            theoreticalWeight += (10 * i - 5 * i) * i * 10;
        }
        // Check: does the total cash out weight match the theoretical weight calculated?
        assertEq(hook.test_store().totalCashOutWeight(address(hook)), theoreticalWeight);
    }

    function test_firstOwnerOf_shouldReturnCurrentOwnerIfFirstOwner(uint256 tokenId, address owner) public {
        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        hook.ForTest_setOwnerOf(tokenId, owner);

        // Check: is the first owner of the NFT is the current owner?
        assertEq(hook.firstOwnerOf(tokenId), owner);
    }

    function test_firstOwnerOf_shouldReturnFirstOwnerIfOwnerChanged(address newOwner, address previousOwner) public {
        // Assume that the new owner and previous owner are different and not the zero address.
        vm.assume(newOwner != previousOwner);
        vm.assume(newOwner != address(0));
        vm.assume(previousOwner != address(0));

        // Trusted forwarder is a special case, it can only be the sender if the transaction is a meta transaction.
        // which we aren't doing here.
        vm.assume(newOwner != trustedForwarder);
        vm.assume(previousOwner != trustedForwarder);

        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        ForTest_JB721TiersHook hook = _initializeForTestHook(10);

        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;

        uint256 tokenId = _generateTokenId(tiersToMint[0], 1);

        vm.prank(owner);
        hook.mintFor(tiersToMint, previousOwner);

        // Check: is the first owner of the NFT the previous owner?
        assertEq(hook.firstOwnerOf(tokenId), previousOwner);

        // Prank the previous owner and transfer the NFT to the new owner.
        vm.startPrank(previousOwner);
        IERC721(hook).transferFrom(previousOwner, newOwner, tokenId);
        vm.stopPrank();

        // Check: is the first owner of the NFT still the previous owner?
        assertEq(hook.firstOwnerOf(tokenId), previousOwner);
    }

    function test_firstOwnerOf_shouldReturnZeroAddressIfNotMinted(uint256 tokenId) public {
        ForTest_JB721TiersHook hook = _initializeForTestHook(10);
        // Check: is the "first owner" of the NFT the zero address?
        assertEq(hook.firstOwnerOf(tokenId), address(0));
    }

    function test_constructor_deployIfInitialSuppliesNotEmpty(uint256 numberOfTiers) public {
        numberOfTiers = bound(numberOfTiers, 0, 10);
        // Create new tiers array.
        ForTest_JB721TiersHook hook = _initializeForTestHook(numberOfTiers);
        (, JB721Tier[] memory tiers) = _createTiers(defaultTierConfig, numberOfTiers);

        // Check: do the hook's parameters match the expected values?
        assertEq(hook.PROJECT_ID(), projectId);
        assertEq(address(hook.DIRECTORY()), mockJBDirectory);
        assertEq(hook.name(), name);
        assertEq(hook.symbol(), symbol);
        assertEq(address(hook.STORE().tokenUriResolverOf(address(hook))), mockTokenUriResolver);
        assertEq(hook.contractURI(), contractUri);
        assertEq(hook.owner(), owner);
        // Check: are all of the `tiers` in `hook.STORE().tiersOf`, and vice versa (do they match)?
        // Order is not guaranteed, so we use `_isIn` and check both ways.
        assertTrue(_isIn(hook.STORE().tiersOf(address(hook), new uint256[](0), false, 0, numberOfTiers), tiers));
        assertTrue(_isIn(tiers, hook.STORE().tiersOf(address(hook), new uint256[](0), false, 0, numberOfTiers)));
    }

    function test_constructor_revertDeploymentIfOneEmptyInitialSupply(
        uint256 numberOfTiers,
        uint256 errorIndex
    )
        public
    {
        numberOfTiers = bound(numberOfTiers, 1, 20);
        errorIndex = bound(errorIndex, 0, numberOfTiers - 1);
        JB721TierConfig[] memory tiers = new JB721TierConfig[](numberOfTiers);

        // Populate the tiers array with the default tier config.
        for (uint256 i; i < numberOfTiers; i++) {
            tiers[i] = JB721TierConfig({
                price: uint104(i * 10),
                initialSupply: uint32(100),
                votingUnits: uint16(0),
                reserveFrequency: uint16(0),
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[0],
                category: uint24(100),
                discountPercent: uint8(0),
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: true,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false
            });
        }

        // Set the initial supply of the tier at `errorIndex` to 0. This should cause an error.
        tiers[errorIndex].initialSupply = 0;

        // Expect the error.
        vm.expectRevert(JB721TiersHookStore.JB721TiersHookStore_ZeroInitialSupply.selector);
        vm.etch(hook_i, address(hook).code);
        JB721TiersHook hook = JB721TiersHook(hook_i);
        hook.initialize(
            projectId,
            name,
            symbol,
            baseUri,
            IJB721TokenUriResolver(mockTokenUriResolver),
            contractUri,
            JB721InitTiersConfig({
                tiers: tiers,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                decimals: 18,
                prices: IJBPrices(address(0))
            }),
            JB721TiersHookFlags({
                preventOverspending: false,
                noNewTiersWithReserves: true,
                noNewTiersWithVotes: true,
                noNewTiersWithOwnerMinting: true
            })
        );
    }
}
