// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/interfaces/IJB721TiersHook.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/JB721TiersHook.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/JB721TiersHookStore.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBBitmapWord.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/interfaces/IJBPermissioned.sol";
import {MetadataResolverHelper} from "@bananapus/core-v6/test/helpers/MetadataResolverHelper.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/libraries/JBConstants.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "./UnitTestSetup.sol"; // Only used to get the `PAY_HOOK_ID` and `CASH_OUT_HOOK_ID` constants.

interface IJB721TiersHookStore_ForTest is IJB721TiersHookStore {
    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_dumpTiersList(address nft) external view returns (JB721Tier[] memory tiers);
    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setTier(address hook, uint256 index, JBStored721Tier calldata newTier) external;
    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setTierVotingUnits(address hook, uint256 tierId, uint32 votingUnits) external;
    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setBalanceOf(address hook, address holder, uint256 tier, uint256 balance) external;
    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setReservesMintedFor(address hook, uint256 tier, uint256 amount) external;
    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setIsTierRemoved(address hook, uint256 tokenId) external;
    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_packBools(
        bool allowOwnerMint,
        bool transfersPausable,
        bool useVotingUnits,
        bool cannotBeRemoved,
        bool cannotIncreaseDiscountPercent
    )
        external
        returns (uint8);
}

// A customized 721 tiers hook for testing purposes.
contract ForTest_JB721TiersHook is JB721TiersHook {
    // forge-lint: disable-next-line(mixed-case-variable)
    IJB721TiersHookStore_ForTest public test_store;
    MetadataResolverHelper metadataHelper;

    uint256 constant SURPLUS = 10e18;
    uint256 constant CASH_OUT_TAX_RATE = JBConstants.MAX_CASH_OUT_TAX_RATE; // 40%
    address _trustedForwarder = address(123_456);

    /// @dev Bundles ForTest_JB721TiersHook constructor args to avoid stack-too-deep.
    struct ForTestInitConfig {
        uint256 projectId;
        string name;
        string symbol;
        string baseUri;
        IJB721TokenUriResolver tokenUriResolver;
        string contractUri;
        JB721TierConfig[] tiers;
        JB721TiersHookFlags flags;
    }

    constructor(
        ForTestInitConfig memory config,
        IJBDirectory directory,
        IJBPrices prices,
        IJBRulesets rulesets,
        IJB721TiersHookStore store,
        IJBSplits splits
    )
        // The directory is also `IJBPermissioned`.
        JB721TiersHook(
            directory,
            IJBPermissioned(address(directory)).PERMISSIONS(),
            prices,
            rulesets,
            store,
            splits,
            _trustedForwarder
        )
    {
        // Disable the safety check to not allow initializing the original contract
        JB721TiersHook.initialize(
            config.projectId,
            config.name,
            config.symbol,
            config.baseUri,
            config.tokenUriResolver,
            config.contractUri,
            JB721InitTiersConfig({
                tiers: config.tiers, currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
            }),
            config.flags
        );
        test_store = IJB721TiersHookStore_ForTest(address(store));

        metadataHelper = new MetadataResolverHelper();
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setOwnerOf(uint256 tokenId, address owner) public {
        _owners[tokenId] = owner;
    }

    function burn(uint256[] memory tokenIds) public {
        for (uint256 i; i < tokenIds.length; i++) {
            _burn(tokenIds[i]);
        }
        STORE.recordBurn(tokenIds);
    }
}

// A customized 721 tiers hook store for testing purposes.
contract ForTest_JB721TiersHookStore is JB721TiersHookStore, IJB721TiersHookStore_ForTest {
    using JBBitmap for mapping(uint256 => uint256);
    using JBBitmap for JBBitmapWord;

    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_dumpTiersList(address nft) public view override returns (JB721Tier[] memory tiers) {
        // Keep a reference to the max tier ID.
        uint256 maxTierId = maxTierIdOf[nft];
        // Initialize an array with the appropriate length.
        tiers = new JB721Tier[](maxTierId);
        // Count the number of included tiers.
        uint256 numberOfIncludedTiers;
        // Get a reference to the sorted index being iterated on, starting with the first one.
        uint256 currentSortIndex = _firstSortedTierIdOf(nft, 0);
        // Keep a reference to the tier being iterated on.
        JBStored721Tier memory storedTier;
        // Make the sorted array.
        while (currentSortIndex != 0 && numberOfIncludedTiers < maxTierId) {
            storedTier = _storedTierOf[nft][currentSortIndex];

            // Unpack stored tier.
            (bool allowOwnerMint, bool transfersPausable,,,) = _unpackBools(storedTier.packedBools);

            // Add the tier to the array being returned.
            tiers[numberOfIncludedTiers++] = JB721Tier({
                // forge-lint: disable-next-line(unsafe-typecast)
                id: uint32(currentSortIndex),
                price: storedTier.price,
                remainingSupply: storedTier.remainingSupply,
                initialSupply: storedTier.initialSupply,
                votingUnits: storedTier.price,
                reserveFrequency: storedTier.reserveFrequency,
                reserveBeneficiary: reserveBeneficiaryOf(nft, currentSortIndex),
                encodedIPFSUri: encodedIPFSUriOf[nft][currentSortIndex],
                category: storedTier.category,
                discountPercent: storedTier.discountPercent,
                allowOwnerMint: allowOwnerMint,
                transfersPausable: transfersPausable,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                splitPercent: storedTier.splitPercent,
                resolvedUri: ""
            });
            // Set the next sort index.
            currentSortIndex = _nextSortedTierIdOf(nft, currentSortIndex, maxTierId);
        }
        // Drop the empty tiers at the end of the array.
        // The array's size is based on `maxTierIdOf`, which *might* exceed the actual number of tiers.
        for (uint256 i = tiers.length - 1; i >= 0; i--) {
            if (tiers[i].id == 0) {
                assembly ("memory-safe") {
                    mstore(tiers, sub(mload(tiers), 1))
                }
            } else {
                break;
            }
        }
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setTier(address hook, uint256 index, JBStored721Tier calldata newTier) public override {
        _storedTierOf[address(hook)][index] = newTier;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setTierVotingUnits(address hook, uint256 tierId, uint32 votingUnits) public override {
        _tierVotingUnitsOf[address(hook)][tierId] = votingUnits;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setBalanceOf(address hook, address holder, uint256 tier, uint256 balance) public override {
        tierBalanceOf[address(hook)][holder][tier] = balance;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setReservesMintedFor(address hook, uint256 tier, uint256 amount) public override {
        numberOfReservesMintedFor[address(hook)][tier] = amount;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_setIsTierRemoved(address hook, uint256 tokenId) public override {
        _removedTiersBitmapWordOf[hook].removeTier(tokenId);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_packBools(
        bool allowOwnerMint,
        bool transfersPausable,
        bool useVotingUnits,
        bool cannotBeRemoved,
        bool cannotIncreaseDiscountPercent
    )
        public
        pure
        returns (uint8)
    {
        return
            _packBools(
                allowOwnerMint, transfersPausable, useVotingUnits, cannotBeRemoved, cannotIncreaseDiscountPercent
            );
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function ForTest_unpackBools(uint8 packed) public pure returns (bool, bool, bool, bool, bool) {
        return _unpackBools(packed);
    }
}
