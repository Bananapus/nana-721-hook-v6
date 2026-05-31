// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {mulDiv} from "@prb/math/src/Common.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";

import {IJB721TiersHookStore} from "./interfaces/IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "./interfaces/IJB721TokenUriResolver.sol";
import {JB721Constants} from "./libraries/JB721Constants.sol";
import {JBBitmap} from "./libraries/JBBitmap.sol";
import {JB721Tier} from "./structs/JB721Tier.sol";
import {JB721TierConfig} from "./structs/JB721TierConfig.sol";
import {JB721TierFlags} from "./structs/JB721TierFlags.sol";
import {JB721TiersHookFlags} from "./structs/JB721TiersHookFlags.sol";
import {JBBitmapWord} from "./structs/JBBitmapWord.sol";
import {JBStored721Tier} from "./structs/JBStored721Tier.sol";

/// @title JB721TiersHookStore
/// @notice The shared data store for all `JB721TiersHook` instances. Stores tier definitions, mint counts, reserve
/// tracking, voting units, and removal bitmaps. Each hook registers its own tiers here; the store handles
/// tier validation, minting logic (including reserve accounting), and cash-out weight calculations.
/// @dev One store is shared across all hooks. Functions are keyed by hook address so each hook reads/writes
/// only its own data. Tier IDs are sequential per hook and 1-indexed.
contract JB721TiersHookStore is IJB721TiersHookStore {
    using JBBitmap for mapping(uint256 => uint256);
    using JBBitmap for JBBitmapWord;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JB721TiersHookStore_CantMintManually(uint256 tierId);
    error JB721TiersHookStore_CantRemoveTier(uint256 tierId);
    error JB721TiersHookStore_DeadlockedReserve(uint256 tierId, uint256 initialSupply, uint256 reserveFrequency);
    error JB721TiersHookStore_DiscountPercentExceedsBounds(uint256 percent, uint256 limit);
    error JB721TiersHookStore_DiscountPercentIncreaseNotAllowed(uint256 percent, uint256 storedPercent);
    error JB721TiersHookStore_InsufficientPendingReserves(uint256 count, uint256 numberOfPendingReserves);
    error JB721TiersHookStore_InsufficientSupplyRemaining(uint256 tierId);
    error JB721TiersHookStore_InvalidCategorySortOrder(uint256 tierCategory, uint256 previousTierCategory);
    error JB721TiersHookStore_InvalidQuantity(uint256 quantity, uint256 limit);
    error JB721TiersHookStore_ManualMintingNotAllowed(uint256 tierId);
    error JB721TiersHookStore_MaxTiersExceeded(uint256 numberOfTiers, uint256 limit);
    error JB721TiersHookStore_MissingReserveBeneficiary(uint256 tierId);
    error JB721TiersHookStore_PriceExceedsAmount(uint256 price, uint256 leftoverAmount);
    error JB721TiersHookStore_ReserveFrequencyNotAllowed(uint256 tierId);
    error JB721TiersHookStore_SplitPercentExceedsBounds(uint256 percent, uint256 limit);
    error JB721TiersHookStore_TierRemoved(uint256 tierId);
    error JB721TiersHookStore_UnrecognizedTier(uint256 tierId);
    error JB721TiersHookStore_VotingUnitsNotAllowed(uint256 tierId);
    error JB721TiersHookStore_ZeroInitialSupply(uint256 tierId);

    //*********************************************************************//
    // ------------------------- private constants ------------------------ //
    //*********************************************************************//

    /// @notice Just a kind reminder to our readers.
    /// @dev Used in 721 token ID generation.
    uint256 private constant _ONE_BILLION = 1_000_000_000;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice Returns the default reserve beneficiary for the provided 721 contract.
    /// @dev If a tier has a reserve beneficiary set, it will override this value.
    /// @custom:param hook The 721 contract to get the default reserve beneficiary of.
    mapping(address hook => address) public override defaultReserveBeneficiaryOf;

    /// @notice Returns the encoded IPFS URI for the provided tier ID of the provided 721 contract.
    /// @dev Token URIs managed by this contract are stored in 32 bytes, based on stripped down IPFS hashes.
    /// @custom:param hook The 721 contract that the tier belongs to.
    /// @custom:param tierId The ID of the tier to get the encoded IPFS URI of.
    /// @custom:returns The encoded IPFS URI.
    mapping(address hook => mapping(uint256 tierId => bytes32)) public override encodedIpfsUriOf;

    /// @notice Returns the largest tier ID currently used on the provided 721 contract.
    /// @dev This may not include the last tier ID if it has been removed.
    /// @custom:param hook The 721 contract to get the largest tier ID from.
    mapping(address hook => uint256) public override maxTierIdOf;

    /// @notice Returns the number of NFTs which have been burned from the provided tier ID of the provided 721
    /// contract.
    /// @custom:param hook The 721 contract that the tier belongs to.
    /// @custom:param tierId The ID of the tier to get the burn count of.
    mapping(address hook => mapping(uint256 tierId => uint256)) public override numberOfBurnedFor;

    /// @notice Returns the number of reserve NFTs which have been minted from the provided tier ID of the provided 721
    /// contract.
    /// @custom:param hook The 721 contract that the tier belongs to.
    /// @custom:param tierId The ID of the tier to get the reserve mint count of.
    mapping(address hook => mapping(uint256 tierId => uint256)) public override numberOfReservesMintedFor;

    /// @notice Returns the number of NFTs which the provided owner address owns from the provided 721 contract and tier
    /// ID.
    /// @custom:param hook The 721 contract to get the balance from.
    /// @custom:param owner The address to get the tier balance of.
    /// @custom:param tierId The ID of the tier to get the balance for.
    mapping(address hook => mapping(address owner => mapping(uint256 tierId => uint256))) public override tierBalanceOf;

    /// @notice Running aggregate of `totalCashOutWeight` per hook so cash-out pricing is O(1) instead of
    /// O(maxTierId). Maintained incrementally: a paid mint adds the tier's full price for the new outstanding NFT
    /// plus any newly-accrued pending reserve; a burn subtracts the tier's full price. Reserve mints are
    /// weight-neutral (one pending reserve becomes one outstanding NFT), removed tiers keep their weight, and newly
    /// added (unminted) tiers contribute zero — so spamming empty tiers can never grow this read or its cost.
    /// @custom:param hook The 721 contract the running weight belongs to.
    mapping(address hook => uint256) internal _totalCashOutWeightOf;

    /// @notice Running per-owner NFT count per hook so `balanceOf` is O(1) instead of O(maxTierId). Maintained in
    /// `recordTransferForTier` (mint increments the receiver, burn decrements the sender, transfer does both).
    /// @custom:param hook The 721 contract the balance belongs to.
    /// @custom:param owner The address whose running balance this is.
    mapping(address hook => mapping(address owner => uint256)) internal _addressBalanceOf;

    /// @notice Returns the custom token URI resolver which overrides the default token URI resolver for the provided
    /// 721 contract.
    /// @custom:param hook The 721 contract to get the custom token URI resolver of.
    mapping(address hook => IJB721TokenUriResolver) public override tokenUriResolverOf;

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /// @notice Returns the flags which dictate the behavior of the provided `IJB721TiersHook` contract.
    /// @custom:param hook The address of the 721 contract to get the flags for.
    /// @custom:returns The flags.
    mapping(address hook => JB721TiersHookFlags) internal _flagsOf;

    /// @notice Return the ID of the last sorted tier from the provided 721 contract.
    /// @dev If not set, it is assumed the `maxTierIdOf` is the last sorted tier ID.
    /// @custom:param hook The 721 contract to get the last sorted tier ID from.
    mapping(address hook => uint256) internal _lastTrackedSortedTierIdOf;

    /// @notice Get the bitmap word at the provided depth from the provided 721 contract's tier removal bitmap.
    /// @dev See `JBBitmap` for more information.
    /// @custom:param hook The 721 contract to get the bitmap word from.
    /// @custom:param depth The depth of the bitmap row to get. Each row stores 256 tiers.
    /// @custom:returns word The bitmap row's content.
    mapping(address hook => mapping(uint256 depth => uint256 word)) internal _removedTiersBitmapWordOf;

    /// @notice Returns the reserve beneficiary (if there is one) for the provided tier ID on the provided
    /// `IJB721TiersHook` contract.
    /// @custom:param hook The address of the 721 contract to get the reserve beneficiary from.
    /// @custom:param tierId The ID of the tier to get the reserve beneficiary of.
    /// @custom:returns The address of the reserved token beneficiary.
    mapping(address hook => mapping(uint256 tierId => address)) internal _reserveBeneficiaryOf;

    /// @notice Returns the ID of the first tier in the provided category on the provided 721 contract.
    /// @custom:param hook The 721 contract to get the category's first tier ID from.
    /// @custom:param category The category to get the first tier ID of.
    mapping(address hook => mapping(uint256 category => uint256)) internal _startingTierIdOfCategory;

    /// @notice Returns the stored tier of the provided tier ID on the provided `IJB721TiersHook` contract.
    /// @custom:param hook The address of the 721 contract to get the tier from.
    /// @custom:param tierId The ID of the tier to get.
    /// @custom:returns The stored tier, as a `JBStored721Tier` struct.
    mapping(address hook => mapping(uint256 tierId => JBStored721Tier)) internal _storedTierOf;

    /// @notice Returns the ID of the tier which comes after the provided tier ID (sorted by category).
    /// @dev If empty, assume the next tier ID should come after.
    /// @custom:param hook The address of the 721 contract to get the next tier ID from.
    /// @custom:param tierId The ID of the tier to get the next tier ID in relation to.
    /// @custom:returns The following tier's ID.
    mapping(address hook => mapping(uint256 tierId => uint256)) internal _tierIdAfter;

    /// @notice Returns the custom voting units for the provided tier ID on the provided hook.
    /// @dev Only populated when `useVotingUnits` is true. When not set, voting power defaults to the tier's price.
    /// @custom:param hook The address of the 721 contract.
    /// @custom:param tierId The ID of the tier.
    /// @custom:returns The voting units for the tier.
    mapping(address hook => mapping(uint256 tierId => uint32)) internal _tierVotingUnitsOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Get the encoded IPFS URI for the tier that a specific NFT belongs to. Used to resolve the NFT's
    /// metadata when no custom `tokenUriResolver` is set.
    /// @param hook The 721 hook contract the NFT belongs to.
    /// @param tokenId The token ID of the NFT.
    /// @return The encoded IPFS URI for the NFT's tier.
    // forge-lint: disable-next-line(mixed-case-function)
    function encodedTierIPFSUriOf(address hook, uint256 tokenId) external view override returns (bytes32) {
        return encodedIpfsUriOf[hook][tierIdOfToken(tokenId)];
    }

    /// @notice Get the behavioral flags for a hook — such as whether transfers are pausable, whether NFT holders can
    /// cash out, and whether token issuance occurs for split-routed payments.
    /// @param hook The 721 hook contract to get the flags of.
    /// @return The hook's flags.
    function flagsOf(address hook) external view override returns (JB721TiersHookFlags memory) {
        return _flagsOf[hook];
    }

    /// @notice Check whether a tier has been removed. Removed tiers can no longer be minted from, but existing NFTs
    /// from that tier remain valid and can still be cashed out.
    /// @param hook The 721 hook contract the tier belongs to.
    /// @param tierId The ID of the tier to check.
    /// @return `true` if the tier has been removed, `false` otherwise.
    function isTierRemoved(address hook, uint256 tierId) external view override returns (bool) {
        JBBitmapWord memory bitmapWord = _removedTiersBitmapWordOf[hook].readId(tierId);

        return bitmapWord.isTierIdRemoved(tierId);
    }

    /// @notice How many reserved NFTs are waiting to be minted for a tier. Reserves accumulate automatically as
    /// non-reserve NFTs are minted (based on the tier's `reserveFrequency`). Anyone can mint them via
    /// `mintPendingReservesFor`.
    /// @param hook The 721 hook contract to check.
    /// @param tierId The ID of the tier to check.
    /// @return The number of pending reserved NFTs that can be minted.
    function numberOfPendingReservesFor(address hook, uint256 tierId) external view override returns (uint256) {
        return _numberOfPendingReservesFor({hook: hook, tierId: tierId, storedTier: _storedTierOf[hook][tierId]});
    }

    /// @notice Look up which tier an NFT belongs to and return the full tier details (price, supply, metadata, etc.).
    /// @param hook The 721 hook contract the NFT belongs to.
    /// @param tokenId The token ID of the NFT.
    /// @param includeResolvedUri If `true` and the hook has a `tokenUriResolver`, resolves the URI and includes it.
    /// @return The tier that the NFT belongs to.
    function tierOfTokenId(
        address hook,
        uint256 tokenId,
        bool includeResolvedUri
    )
        external
        view
        override
        returns (JB721Tier memory)
    {
        // Get a reference to the tier's ID.
        uint256 tierId = tierIdOfToken(tokenId);
        return _getTierFrom({
            hook: hook, tierId: tierId, storedTier: _storedTierOf[hook][tierId], includeResolvedUri: includeResolvedUri
        });
    }

    /// @notice Get only the pricing fields for a tier, avoiding full struct construction.
    /// @param hook The 721 contract that the tier belongs to.
    /// @param id The tier ID.
    /// @return price The tier price.
    /// @return splitPercent The split percent.
    /// @return discountPercent The discount percent.
    function tierPricingOf(
        address hook,
        uint256 id
    )
        external
        view
        override
        returns (uint104 price, uint32 splitPercent, uint8 discountPercent)
    {
        JBStored721Tier memory storedTier = _storedTierOf[hook][id];
        price = storedTier.price;
        splitPercent = storedTier.splitPercent;
        discountPercent = storedTier.discountPercent;
    }

    /// @notice Get only the tier ID and transfersPausable flag for a token, avoiding full struct construction.
    /// @param hook The 721 hook address.
    /// @param tokenId The token ID.
    /// @return tierId The tier ID.
    /// @return transfersPausable Whether transfers are paused for this tier.
    function tierTransferInfoOfTokenId(
        address hook,
        uint256 tokenId
    )
        external
        view
        override
        returns (uint256 tierId, bool transfersPausable)
    {
        tierId = tierIdOfToken(tokenId);
        JBStored721Tier memory storedTier = _storedTierOf[hook][tierId];
        // Bit 1 (0-indexed) of packedBools is transfersPausable.
        transfersPausable = (storedTier.packedBools & 0x2) != 0;
    }

    /// @notice Get only the per-unit voting value for a token's tier, avoiding full struct construction.
    /// @dev Mirrors the `votingUnits` field computed in `_getTierFrom`: a tier with custom voting units configured
    /// (the `useVotingUnits` flag, bit 2 of `packedBools`) contributes its stored voting units per NFT, otherwise it
    /// contributes its price per NFT. Multiply by an account's balance in the tier to get its voting power there.
    /// @param hook The 721 hook contract that the token belongs to.
    /// @param tokenId The token ID.
    /// @return The per-unit voting value for the token's tier.
    function tierVotingUnitsOfTokenId(address hook, uint256 tokenId) external view override returns (uint256) {
        // Get a reference to the tier's ID.
        uint256 tierId = tierIdOfToken(tokenId);

        // Keep a reference to the stored tier.
        JBStored721Tier memory storedTier = _storedTierOf[hook][tierId];

        // Bit 2 (0-indexed) of packedBools is useVotingUnits. Use custom voting units if set, otherwise the price.
        return (storedTier.packedBools & 0x4 != 0) ? _tierVotingUnitsOf[hook][tierId] : storedTier.price;
    }

    /// @notice Get all active (non-removed) tiers for a hook, with optional filtering by category and pagination.
    /// Tiers are returned sorted by category.
    /// @param hook The 721 hook contract to get tiers from.
    /// @param categories Filter to specific categories. Pass an empty array to include all categories.
    /// @param includeResolvedUri If `true` and the hook has a `tokenUriResolver`, resolves URIs and includes them.
    /// @param startingId Start from this tier ID (for pagination). Pass 0 to start from the beginning.
    /// @param size The maximum number of tiers to return.
    /// @return tiers An array of active tiers.
    function tiersOf(
        address hook,
        uint256[] calldata categories,
        bool includeResolvedUri,
        uint256 startingId,
        uint256 size
    )
        external
        view
        override
        returns (JB721Tier[] memory tiers)
    {
        // Keep a reference to the last tier ID.
        uint256 lastTierId = _lastSortedTierIdOf(hook);

        // Return an empty array if there are no tiers.
        if (lastTierId == 0) return tiers;

        // Initialize an array with the provided length.
        tiers = new JB721Tier[](size);

        // Count the number of tiers to include in the result.
        uint256 numberOfIncludedTiers;

        // Keep a reference to the tier being iterated upon.
        JBStored721Tier memory storedTier;

        // Initialize a `JBBitmapWord` to track whether tiers have been removed.
        JBBitmapWord memory bitmapWord;

        // Keep a reference to an iterator variable to represent the category being iterated upon.
        uint256 i;

        // Iterate at least once.
        do {
            // Stop iterating if the size limit has been reached.
            if (numberOfIncludedTiers == size) break;

            // Get a reference to the ID of the tier being iterated upon, starting with the first tier ID if no starting
            // ID was specified.
            uint256 currentSortedTierId = startingId != 0
                ? startingId
                : _firstSortedTierIdOf({hook: hook, category: categories.length == 0 ? 0 : categories[i]});

            // Add the tiers from the category being iterated upon.
            while (currentSortedTierId != 0 && numberOfIncludedTiers < size) {
                if (!_isTierRemovedWithRefresh({hook: hook, tierId: currentSortedTierId, bitmapWord: bitmapWord})) {
                    storedTier = _storedTierOf[hook][currentSortedTierId];

                    // If categories were provided and the current tier's category is greater than category being added,
                    // break.
                    if (categories.length != 0 && storedTier.category > categories[i]) {
                        break;
                    }
                    // If a category is specified and matches, add the returned values.
                    else if (categories.length == 0 || storedTier.category == categories[i]) {
                        // Add the tier to the array being returned.
                        tiers[numberOfIncludedTiers++] = _getTierFrom({
                            hook: hook,
                            tierId: currentSortedTierId,
                            storedTier: storedTier,
                            includeResolvedUri: includeResolvedUri
                        });
                    }
                }
                // Set the next sorted tier ID.
                currentSortedTierId = _nextSortedTierIdOf({hook: hook, id: currentSortedTierId, max: lastTierId});
            }

            unchecked {
                i++;
            }
        } while (i < categories.length);

        // Resize the array if there are removed tiers.
        if (numberOfIncludedTiers != size) {
            assembly ("memory-safe") {
                mstore(tiers, numberOfIncludedTiers)
            }
        }
    }

    /// @notice Get an address's voting power from a specific tier. Each NFT in the tier contributes either the tier's
    /// custom `votingUnits` (if configured) or the tier's price. Multiply by the holder's balance in the tier.
    /// @param hook The 721 hook contract that the tier belongs to.
    /// @param account The address to get voting units for.
    /// @param tierId The ID of the tier.
    /// @return The address's total voting units within the tier.
    function tierVotingUnitsOf(
        address hook,
        address account,
        uint256 tierId
    )
        external
        view
        virtual
        override
        returns (uint256)
    {
        // Get a reference to the account's balance in this tier.
        uint256 balance = tierBalanceOf[hook][account][tierId];

        if (balance == 0) return 0;

        // Keep a reference to the stored tier.
        JBStored721Tier memory storedTier = _storedTierOf[hook][tierId];

        // Check if voting units should be used. Price will be used otherwise.
        (,, bool useVotingUnits,,,) = _unpackBools(storedTier.packedBools);

        // Return the address' voting units within the tier.
        return balance * (useVotingUnits ? _tierVotingUnitsOf[hook][tierId] : storedTier.price);
    }

    /// @notice The total number of NFTs currently in circulation for a hook (minted minus burned, across all tiers).
    /// @param hook The 721 hook contract to get the total supply of.
    /// @return supply The total number of outstanding NFTs.
    function totalSupplyOf(address hook) external view override returns (uint256 supply) {
        // Keep a reference to the greatest tier ID.
        uint256 maxTierId = maxTierIdOf[hook];

        for (uint256 i = maxTierId; i != 0;) {
            // Set the tier being iterated on.
            JBStored721Tier memory storedTier = _storedTierOf[hook][i];

            // Skip unminted tiers — they contribute zero supply.
            if (storedTier.initialSupply != storedTier.remainingSupply) {
                // Increment the total supply by the number of tokens already minted.
                supply += storedTier.initialSupply - (storedTier.remainingSupply + numberOfBurnedFor[hook][i]);
            }

            unchecked {
                --i;
            }
        }
    }

    /// @notice Get an address's total voting power across all tiers of a hook. Sums up the voting units from every
    /// tier where the address holds NFTs.
    /// @dev Each tier contributes: `balance * (customVotingUnits || tierPrice)`.
    /// @param hook The 721 hook contract to get voting units within.
    /// @param account The address to get the voting unit total of.
    /// @return units The total voting units the address holds across all tiers.
    function votingUnitsOf(address hook, address account) external view virtual override returns (uint256 units) {
        // Keep a reference to the greatest tier ID.
        uint256 maxTierId = maxTierIdOf[hook];

        // Loop through all tiers.
        for (uint256 i = maxTierId; i != 0;) {
            // Get a reference to the account's balance in this tier.
            uint256 balance = tierBalanceOf[hook][account][i];

            // If the account has no balance, return.
            if (balance == 0) {
                unchecked {
                    --i;
                }
                continue;
            }

            // Get the tier.
            JBStored721Tier memory storedTier = _storedTierOf[hook][i];

            // Parse the flags.
            (,, bool useVotingUnits,,,) = _unpackBools(storedTier.packedBools);

            // Add the voting units for the address' balance in this tier.
            // Use custom voting units if set. Otherwise, use the tier's price.
            units += balance * (useVotingUnits ? _tierVotingUnitsOf[hook][i] : storedTier.price);

            unchecked {
                --i;
            }
        }
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice How many NFTs an address owns from a hook, totaled across all tiers.
    /// @param hook The 721 hook contract to check.
    /// @param owner The address to check the balance of.
    /// @return balance The total number of NFTs the owner holds.
    function balanceOf(address hook, address owner) public view override returns (uint256 balance) {
        // Read the running per-owner aggregate (maintained in `recordTransferForTier`). O(1) — independent of the
        // tier count, so an attacker spamming empty tiers cannot make this read run out of gas.
        return _addressBalanceOf[hook][owner];
    }

    /// @notice The combined cash-out weight of specific NFTs. Divide by `totalCashOutWeight` to get the fraction of
    /// the project's surplus that cashing out these NFTs would reclaim.
    /// @dev Weight is based on each NFT's original tier price (not the discounted price paid). Discounts are
    /// transient purchase incentives and don't affect an NFT's share of the cash-out pool.
    /// @param hook The 721 hook contract the NFTs belong to.
    /// @param tokenIds The token IDs to get the combined cash-out weight of.
    /// @return weight The combined cash-out weight.
    function cashOutWeightOf(address hook, uint256[] calldata tokenIds) public view override returns (uint256 weight) {
        // Add each 721's original price (from its tier) to the weight.
        // Uses the full tier price, not the discounted price — by design. Discounts are transient incentives
        // that affect the purchase price, but the NFT's weight in the cash out curve is always based on its
        // tier's original price. This prevents discount changes from altering the cash out value of already-minted
        // NFTs.
        for (uint256 i; i < tokenIds.length;) {
            weight += _storedTierOf[hook][tierIdOfToken(tokenIds[i])].price;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice The address that receives reserved NFTs for a tier. Falls back to the hook's default reserve
    /// beneficiary if no tier-specific beneficiary is set.
    /// @param hook The 721 hook contract.
    /// @param tierId The ID of the tier.
    /// @return The reserve beneficiary address for the tier.
    function reserveBeneficiaryOf(address hook, uint256 tierId) public view override returns (address) {
        // Get the stored reserve beneficiary.
        address storedReserveBeneficiaryOfTier = _reserveBeneficiaryOf[hook][tierId];

        // If the tier has a beneficiary specified, return it.
        if (storedReserveBeneficiaryOfTier != address(0)) {
            return storedReserveBeneficiaryOfTier;
        }

        // Otherwise, return the contract's default reserve beneficiary.
        return defaultReserveBeneficiaryOf[hook];
    }

    /// @notice Derive which tier an NFT belongs to from its token ID. Token IDs encode the tier: `tokenId / 1e9`
    /// gives the tier ID.
    /// @param tokenId The token ID of the NFT.
    /// @return The tier ID.
    function tierIdOfToken(uint256 tokenId) public pure override returns (uint256) {
        return tokenId / _ONE_BILLION;
    }

    /// @notice Get the full details of a specific tier by its ID — price, supply, reserve info, metadata, etc.
    /// @param hook The 721 hook contract to get the tier from.
    /// @param id The ID of the tier to get.
    /// @param includeResolvedUri If `true` and the hook has a `tokenUriResolver`, resolves the URI and includes it.
    /// @return The tier.
    function tierOf(address hook, uint256 id, bool includeResolvedUri) public view override returns (JB721Tier memory) {
        return _getTierFrom({
            hook: hook, tierId: id, storedTier: _storedTierOf[hook][id], includeResolvedUri: includeResolvedUri
        });
    }

    /// @notice The total cash-out weight across all outstanding NFTs (including pending reserves). This is the
    /// denominator used to determine what fraction of a project's surplus each NFT can reclaim on cash out.
    /// @param hook The 721 hook contract to get the total cash-out weight of.
    /// @return weight The total cash-out weight.
    /// @dev Returns the running aggregate maintained in `recordMint`/`recordBurn`, so this is O(1) — independent of
    /// the tier count. This matters because cash out invokes this on the hot path (via the hook's
    /// `beforeCashOutRecordedWith`), and an attacker who can permissionlessly add tiers (e.g. via Croptop) could
    /// otherwise grow `maxTierId` until the old O(maxTierId) loop exceeded the block gas limit and bricked every
    /// holder's cash out. The aggregate equals
    /// `sum over tiers of price * (outstanding + pendingReserves)` using the FULL tier price (not the discounted
    /// price), by the same design as the per-token `cashOutWeightOf`. It is invariant under: adding empty tiers
    /// (zero contribution), removing tiers (removed tiers keep their already-minted weight), reserve mints (a
    /// pending reserve simply becomes an outstanding NFT), and changing `defaultReserveBeneficiaryOf` (a reserve
    /// tier must already have a beneficiary when added, and the default is write-once-nonzero, so no tier's pending
    /// is ever toggled on/off afterwards).
    function totalCashOutWeight(address hook) public view override returns (uint256 weight) {
        return _totalCashOutWeightOf[hook];
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @notice Get the first tier ID from an 721 contract (when sorted by category) within a provided category.
    /// @param hook The 721 contract to get the first sorted tier ID of.
    /// @param category The category to get the first sorted tier ID within. Send 0 for the first ID across all tiers,
    /// which may belong to any category.
    /// @return id The first sorted tier ID within the provided category.
    function _firstSortedTierIdOf(address hook, uint256 category) internal view returns (uint256 id) {
        id = category == 0 ? _tierIdAfter[hook][0] : _startingTierIdOfCategory[hook][category];
        // Start at the first tier ID if nothing is specified.
        if (id == 0) id = 1;
    }

    /// @notice Generate a token ID for an 721 given a tier ID and a token number within that tier.
    /// @param tierId The ID of the tier to generate a token ID for.
    /// @param tokenNumber The token number of the 721 within the tier.
    /// @return The token ID of the 721.
    function _generateTokenId(uint256 tierId, uint256 tokenNumber) internal pure returns (uint256) {
        return (tierId * _ONE_BILLION) + tokenNumber;
    }

    /// @notice Returns the tier corresponding to the stored tier provided.
    /// @dev Translate `JBStored721Tier` to `JB721Tier`.
    /// @param hook The 721 contract to get the tier from.
    /// @param tierId The ID of the tier to get.
    /// @param storedTier The stored tier to get the corresponding tier for.
    /// @param includeResolvedUri If set to `true`, if the contract has a token URI resolver, its content will be
    /// resolved and included.
    /// @return tier The tier as a `JB721Tier` struct.
    function _getTierFrom(
        address hook,
        uint256 tierId,
        JBStored721Tier memory storedTier,
        bool includeResolvedUri
    )
        internal
        view
        returns (JB721Tier memory)
    {
        // Get a reference to the reserve beneficiary.
        address reserveBeneficiary = reserveBeneficiaryOf({hook: hook, tierId: tierId});

        // Cache packed bools to avoid stack-too-deep from destructuring all 6 bools.
        uint8 packed = storedTier.packedBools;

        return JB721Tier({
            // forge-lint: disable-next-line(unsafe-typecast)
            id: uint32(tierId),
            price: storedTier.price,
            remainingSupply: storedTier.remainingSupply,
            initialSupply: storedTier.initialSupply,
            votingUnits: (packed & 0x4 != 0) ? _tierVotingUnitsOf[hook][tierId] : storedTier.price,
            // No reserve frequency if there is no reserve beneficiary.
            reserveFrequency: reserveBeneficiary == address(0) ? 0 : storedTier.reserveFrequency,
            reserveBeneficiary: reserveBeneficiary,
            encodedIpfsUri: encodedIpfsUriOf[hook][tierId],
            category: storedTier.category,
            discountPercent: storedTier.discountPercent,
            flags: JB721TierFlags({
                allowOwnerMint: (packed & 0x1 != 0),
                transfersPausable: (packed & 0x2 != 0),
                cantBeRemoved: (packed & 0x8 != 0),
                cantIncreaseDiscountPercent: (packed & 0x10 != 0),
                cantBuyWithCredits: (packed & 0x20 != 0)
            }),
            splitPercent: storedTier.splitPercent,
            resolvedUri: !includeResolvedUri || tokenUriResolverOf[hook] == IJB721TokenUriResolver(address(0))
                ? ""
                : tokenUriResolverOf[hook].tokenUriOf({
                    nft: hook, tokenId: _generateTokenId({tierId: tierId, tokenNumber: 0})
                })
        });
    }

    /// @notice Check whether a tier has been removed while refreshing the relevant bitmap word if needed.
    /// @param hook The 721 contract to check for removals on.
    /// @param tierId The ID of the tier to check the removal status of.
    /// @param bitmapWord The bitmap word to use.
    /// @return A boolean which is `true` if the tier has been removed.
    function _isTierRemovedWithRefresh(
        address hook,
        uint256 tierId,
        JBBitmapWord memory bitmapWord
    )
        internal
        view
        returns (bool)
    {
        // If the current tier ID is outside current bitmap word (depth), refresh the bitmap word.
        if (bitmapWord.refreshBitmapNeeded(tierId) || (bitmapWord.currentWord == 0 && bitmapWord.currentDepth == 0)) {
            bitmapWord = _removedTiersBitmapWordOf[hook].readId(tierId);
        }

        return bitmapWord.isTierIdRemoved(tierId);
    }

    /// @notice The last sorted tier ID from an 721 contract (when sorted by category).
    /// @param hook The 721 contract to get the last sorted tier ID of.
    /// @return id The last sorted tier ID.
    function _lastSortedTierIdOf(address hook) internal view returns (uint256 id) {
        id = _lastTrackedSortedTierIdOf[hook];
        // Use the maximum tier ID if nothing is specified.
        if (id == 0) id = maxTierIdOf[hook];
    }

    /// @notice Get the tier ID which comes after the provided one when sorted by category.
    /// @param hook The 721 contract to get the next sorted tier ID from.
    /// @param id The tier ID to get the next sorted tier ID relative to.
    /// @param max The maximum tier ID.
    /// @return The next sorted tier ID.
    function _nextSortedTierIdOf(address hook, uint256 id, uint256 max) internal view returns (uint256) {
        // If this is the last tier (maximum), return zero.
        if (id == max) return 0;

        // If a tier ID is saved to come after the provided ID, return it.
        uint256 storedNext = _tierIdAfter[hook][id];

        if (storedNext != 0) return storedNext;

        // Otherwise, increment the provided tier ID.
        return id + 1;
    }

    /// @notice Get the number of pending reserve NFTs for the specified tier ID.
    /// @dev The reserve frequency is immutable once a tier is created (set in `recordAddTiers`) and cannot be modified
    /// afterward. The pending reserve count is derived from the ratio of non-reserve mints to the reserve frequency,
    /// rounded up. This means each batch of `reserveFrequency` non-reserve mints entitles exactly one reserve mint,
    /// plus one additional reserve mint if there is any remainder. Because the reserve frequency is fixed per tier,
    /// the accounting remains consistent: the total available reserve mints always equals
    /// `ceil(numberOfNonReserveMints / reserveFrequency)`. If a project wishes to use a different reserve frequency,
    /// it must create a new tier — the existing tier's pending reserves will continue to be calculated using its
    /// original frequency. Removing a tier does not affect already-pending reserves; they can still be minted.
    /// @param hook The 721 contract that the tier belongs to.
    /// @param tierId The ID of the tier to get the number of pending reserve NFTs for.
    /// @param storedTier The stored tier to get the number of pending reserve NFTs for.
    /// @return numberReservedTokensOutstanding The number of pending reserve NFTs for the tier.
    function _numberOfPendingReservesFor(
        address hook,
        uint256 tierId,
        JBStored721Tier memory storedTier
    )
        internal
        view
        returns (uint256)
    {
        // Get a reference to the initial supply with burned NFTs included.
        uint256 initialSupply = storedTier.initialSupply;

        // No pending reserves if no mints, no reserve frequency, or no reserve beneficiary.
        if (
            storedTier.reserveFrequency == 0 || initialSupply == storedTier.remainingSupply
                || reserveBeneficiaryOf({hook: hook, tierId: tierId}) == address(0)
        ) return 0;

        // The number of reserve NFTs which have already been minted from the tier.
        uint256 numberOfReserveMints = numberOfReservesMintedFor[hook][tierId];

        // If only the reserved 721 (from rounding up) has been minted so far, return 0.
        if (initialSupply == storedTier.remainingSupply + numberOfReserveMints) {
            return 0;
        }

        // Get a reference to the number of NFTs minted from the tier (not counting reserve mints or burned tokens).
        uint256 numberOfNonReserveMints;
        unchecked {
            numberOfNonReserveMints = initialSupply - storedTier.remainingSupply - numberOfReserveMints;
        }

        // Get the number of total available reserve 721 mints given the number of non-reserve NFTs minted divided by
        // the reserve frequency. This will round down.
        uint256 totalNumberOfAvailableReserveMints = numberOfNonReserveMints / storedTier.reserveFrequency;

        // Round up.
        if (numberOfNonReserveMints % storedTier.reserveFrequency > 0) ++totalNumberOfAvailableReserveMints;

        // Return the difference between the number of available reserve mints and the amount already minted.
        unchecked {
            return totalNumberOfAvailableReserveMints - numberOfReserveMints;
        }
    }

    /// @notice Pack six tier-level boolean flags into a single uint8 for compact storage in `JBStored721Tier`.
    /// @dev Bit layout: 0=allowOwnerMint, 1=transfersPausable, 2=useVotingUnits, 3=cantBeRemoved,
    /// 4=cantIncreaseDiscountPercent, 5=cantBuyWithCredits.
    /// @param allowOwnerMint Whether the project owner can mint from this tier directly (without paying).
    /// @param transfersPausable Whether transfers of NFTs from this tier can be paused by the ruleset.
    /// @param useVotingUnits Whether this tier uses a custom voting power value instead of defaulting to its price.
    /// @param cantBeRemoved Whether this tier is permanently locked and cannot be removed once added.
    /// @param cantIncreaseDiscountPercent Whether the discount percent can only stay the same or decrease.
    /// @param cantBuyWithCredits Whether this tier cannot be purchased using accumulated pay credits.
    /// @return packed The packed bools.
    function _packBools(
        bool allowOwnerMint,
        bool transfersPausable,
        bool useVotingUnits,
        bool cantBeRemoved,
        bool cantIncreaseDiscountPercent,
        bool cantBuyWithCredits
    )
        internal
        pure
        returns (uint8 packed)
    {
        assembly {
            packed := or(allowOwnerMint, packed)
            packed := or(shl(0x1, transfersPausable), packed)
            packed := or(shl(0x2, useVotingUnits), packed)
            packed := or(shl(0x3, cantBeRemoved), packed)
            packed := or(shl(0x4, cantIncreaseDiscountPercent), packed)
            packed := or(shl(0x5, cantBuyWithCredits), packed)
        }
    }

    /// @notice Unpack six tier-level boolean flags from a single uint8 stored in `JBStored721Tier.packedBools`.
    /// @dev Inverse of `_packBools`. Same bit layout: 0=allowOwnerMint, 1=transfersPausable, 2=useVotingUnits,
    /// 3=cantBeRemoved, 4=cantIncreaseDiscountPercent, 5=cantBuyWithCredits.
    /// @param packed The packed bools.
    /// @param allowOwnerMint Whether the project owner can mint from this tier directly (without paying).
    /// @param transfersPausable Whether transfers of NFTs from this tier can be paused by the ruleset.
    /// @param useVotingUnits Whether this tier uses a custom voting power value instead of defaulting to its price.
    /// @param cantBeRemoved Whether this tier is permanently locked and cannot be removed once added.
    /// @param cantIncreaseDiscountPercent Whether the discount percent can only stay the same or decrease.
    /// @param cantBuyWithCredits Whether this tier cannot be purchased using accumulated pay credits.
    function _unpackBools(uint8 packed)
        internal
        pure
        returns (
            bool allowOwnerMint,
            bool transfersPausable,
            bool useVotingUnits,
            bool cantBeRemoved,
            bool cantIncreaseDiscountPercent,
            bool cantBuyWithCredits
        )
    {
        assembly {
            allowOwnerMint := iszero(iszero(and(0x1, packed)))
            transfersPausable := iszero(iszero(and(0x2, packed)))
            useVotingUnits := iszero(iszero(and(0x4, packed)))
            cantBeRemoved := iszero(iszero(and(0x8, packed)))
            cantIncreaseDiscountPercent := iszero(iszero(and(0x10, packed)))
            cantBuyWithCredits := iszero(iszero(and(0x20, packed)))
        }
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Walk through the tier sorting sequence and skip over any tiers that have been removed. This compacts
    /// the linked list so that `tiersOf` iteration no longer visits removed tiers. Anyone can call this — it's a
    /// maintenance operation with no access control.
    /// @dev Call this after `recordRemoveTierIds` to keep tier iteration efficient. Without cleaning, removed tiers
    /// remain in the linked list (they just can't be minted from). The function also updates
    /// `_startingTierIdOfCategory` if the previous starting tier for a category was removed.
    /// @param hook The 721 contract to clean tiers for.
    function cleanTiers(address hook) external override {
        // Keep a reference to the last tier ID.
        uint256 lastSortedTierId = _lastSortedTierIdOf(hook);

        // Get a reference to the tier ID being iterated on, starting with the starting tier ID.
        uint256 currentSortedTierId = _firstSortedTierIdOf({hook: hook, category: 0});

        // Keep track of the previous non-removed tier ID.
        uint256 previousSortedTierId;

        // Initialize a `JBBitmapWord` for tracking removed tiers.
        JBBitmapWord memory bitmapWord;

        // Make the sorted array.
        while (currentSortedTierId != 0) {
            // Check if the current tier has been removed.
            if (!_isTierRemovedWithRefresh({hook: hook, tierId: currentSortedTierId, bitmapWord: bitmapWord})) {
                // Update its `_tierIdAfter` if needed.
                if (currentSortedTierId != previousSortedTierId + 1) {
                    if (_tierIdAfter[hook][previousSortedTierId] != currentSortedTierId) {
                        _tierIdAfter[hook][previousSortedTierId] = currentSortedTierId;
                    }
                    // Otherwise, if the current tier ID IS an increment of the previous one,
                    // AND the tier ID after it isn't 0,
                } else if (_tierIdAfter[hook][previousSortedTierId] != 0) {
                    // Set its `_tierIdAfter` to 0.
                    _tierIdAfter[hook][previousSortedTierId] = 0;
                }

                // If this tier's category has a stale `_startingTierIdOfCategory` (reset to 0 because the
                // previous starting tier was removed), set this tier as the new starting tier for its category.
                uint256 tierCategory = _storedTierOf[hook][currentSortedTierId].category;
                if (tierCategory != 0 && _startingTierIdOfCategory[hook][tierCategory] == 0) {
                    _startingTierIdOfCategory[hook][tierCategory] = currentSortedTierId;
                }

                // Iterate by setting the previous tier ID for the next loop to the current tier ID.
                previousSortedTierId = currentSortedTierId;
            } else {
                // The tier was removed. If it was the `_startingTierIdOfCategory` for its category, reset the
                // pointer so the next non-removed tier in the same category can claim it.
                uint256 removedCategory = _storedTierOf[hook][currentSortedTierId].category;
                if (removedCategory != 0 && _startingTierIdOfCategory[hook][removedCategory] == currentSortedTierId) {
                    _startingTierIdOfCategory[hook][removedCategory] = 0;
                }
            }
            // Iterate by updating the current sorted tier ID to the next sorted tier ID.
            currentSortedTierId = _nextSortedTierIdOf({hook: hook, id: currentSortedTierId, max: lastSortedTierId});
        }

        if (previousSortedTierId != 0 && previousSortedTierId != lastSortedTierId) {
            // All sorted IDs after `previousSortedTierId` were removed. Make the last active tier the traversal end so
            // view functions do not keep walking a removed trailing suffix after cleanup.
            if (_tierIdAfter[hook][previousSortedTierId] != 0) _tierIdAfter[hook][previousSortedTierId] = 0;

            // Track the compacted end only when it is not the natural max tier ID. A zero value means
            // `_lastSortedTierIdOf` can keep using `maxTierIdOf` as the implicit end.
            uint256 maxTierId = maxTierIdOf[hook];
            uint256 newLastTrackedSortedTierId = previousSortedTierId == maxTierId ? 0 : previousSortedTierId;
            if (_lastTrackedSortedTierIdOf[hook] != newLastTrackedSortedTierId) {
                _lastTrackedSortedTierIdOf[hook] = newLastTrackedSortedTierId;
            }
        }

        emit CleanTiers({hook: hook, caller: msg.sender});
    }

    /// @notice Validate and store new tiers for the calling hook. Each tier is assigned a sequential ID, inserted
    /// into the category-sorted linked list, and has its reserve beneficiary, voting units, IPFS URI, and flags
    /// persisted. Tiers must be provided sorted by category (ascending).
    /// @dev Only callable by hook contracts (msg.sender is treated as the hook address).
    /// WARNING: If any tier in `tiersToAdd` has `useReserveBeneficiaryAsDefault` set to `true`, its
    /// `reserveBeneficiary` will overwrite the hook's global `defaultReserveBeneficiaryOf`. This affects ALL existing
    /// tiers that do not have a tier-specific reserve beneficiary set via `_reserveBeneficiaryOf`. Callers should be
    /// aware of this side effect when using `adjustTiers` to add new tiers.
    /// @param tiersToAdd The tiers to add.
    /// @return tierIds The IDs of the tiers added.
    function recordAddTiers(JB721TierConfig[] calldata tiersToAdd)
        external
        override
        returns (uint256[] memory tierIds)
    {
        // Keep a reference to the current greatest tier ID.
        uint256 currentMaxTierIdOf = maxTierIdOf[msg.sender];

        // Make sure the max number of tiers won't be exceeded.
        if (currentMaxTierIdOf + tiersToAdd.length > type(uint16).max) {
            revert JB721TiersHookStore_MaxTiersExceeded({
                numberOfTiers: currentMaxTierIdOf + tiersToAdd.length, limit: type(uint16).max
            });
        }

        // Keep a reference to the current last sorted tier ID (sorted by category).
        uint256 currentLastSortedTierId = _lastSortedTierIdOf(msg.sender);

        // Initialize an array for the new tier IDs to be returned.
        tierIds = new uint256[](tiersToAdd.length);

        // Keep a reference to the first sorted tier ID, to use when sorting new tiers if needed.
        // There's no need for sorting if there are no current tiers.
        uint256 startSortedTierId = currentMaxTierIdOf == 0 ? 0 : _firstSortedTierIdOf({hook: msg.sender, category: 0});

        // Keep track of the previous tier's ID while iterating.
        uint256 previousTierId;

        // Keep a reference to the 721 contract's flags.
        JB721TiersHookFlags memory flags = _flagsOf[msg.sender];

        for (uint256 i; i < tiersToAdd.length;) {
            // Set the tier being iterated upon.
            JB721TierConfig memory tierToAdd = tiersToAdd[i];

            // Make sure the supply maximum is enforced. If it's greater than one billion, it would overflow into the
            // next tier.
            if (tierToAdd.initialSupply > _ONE_BILLION - 1) {
                revert JB721TiersHookStore_InvalidQuantity({quantity: tierToAdd.initialSupply, limit: _ONE_BILLION - 1});
            }

            // Make sure the tier's category is greater than or equal to the previously added tier's category.
            // Access calldata directly for the previous tier's category — it's only used once per iteration.
            if (i != 0) {
                uint256 previousCategory = tiersToAdd[i - 1].category;

                // Revert if the category is less than the previously added tier's category.
                if (tierToAdd.category < previousCategory) {
                    revert JB721TiersHookStore_InvalidCategorySortOrder({
                        tierCategory: tierToAdd.category, previousTierCategory: previousCategory
                    });
                }
            }

            // Get a reference to the ID for the new tier.
            uint256 tierId = currentMaxTierIdOf + i + 1;

            // Make sure the new tier doesn't have voting units if the 721 contract's flags don't allow it to.
            if (
                flags.noNewTiersWithVotes
                    && ((tierToAdd.flags.useVotingUnits && tierToAdd.votingUnits != 0)
                        || (!tierToAdd.flags.useVotingUnits && tierToAdd.price != 0))
            ) {
                revert JB721TiersHookStore_VotingUnitsNotAllowed({tierId: tierId});
            }

            // Make sure the new tier doesn't have a reserve frequency if the 721 contract's flags don't allow it to.
            if (flags.noNewTiersWithReserves && tierToAdd.reserveFrequency != 0) {
                revert JB721TiersHookStore_ReserveFrequencyNotAllowed({tierId: tierId});
            }

            // Make sure the new tier doesn't have owner minting enabled if the 721 contract's flags don't allow it to.
            if (flags.noNewTiersWithOwnerMinting && tierToAdd.flags.allowOwnerMint) {
                revert JB721TiersHookStore_ManualMintingNotAllowed({tierId: tierId});
            }

            // Make sure the discount percent is within the bound.
            if (tierToAdd.discountPercent > JB721Constants.DISCOUNT_DENOMINATOR) {
                revert JB721TiersHookStore_DiscountPercentExceedsBounds({
                    percent: tierToAdd.discountPercent, limit: JB721Constants.DISCOUNT_DENOMINATOR
                });
            }

            // Make sure the split percent is within the bound.
            if (tierToAdd.splitPercent > JBConstants.SPLITS_TOTAL_PERCENT) {
                revert JB721TiersHookStore_SplitPercentExceedsBounds({
                    percent: tierToAdd.splitPercent, limit: JBConstants.SPLITS_TOTAL_PERCENT
                });
            }

            // Make sure the tier has a non-zero supply.
            if (tierToAdd.initialSupply == 0) revert JB721TiersHookStore_ZeroInitialSupply(tierId);

            // A tier with initialSupply == 1 and reserveFrequency > 0 deadlocks: the single mint is reserved,
            // leaving zero available for paid mints, but reserves only mint after a paid mint triggers them.
            if (tierToAdd.initialSupply == 1 && tierToAdd.reserveFrequency > 0) {
                revert JB721TiersHookStore_DeadlockedReserve({
                    tierId: tierId, initialSupply: tierToAdd.initialSupply, reserveFrequency: tierToAdd.reserveFrequency
                });
            }

            // A tier with reserves must have a beneficiary — either tier-specific or a previously set default.
            // Without one, minted reserves would be sent to address(0).
            if (
                tierToAdd.reserveFrequency > 0 && tierToAdd.reserveBeneficiary == address(0)
                    && defaultReserveBeneficiaryOf[msg.sender] == address(0)
            ) {
                revert JB721TiersHookStore_MissingReserveBeneficiary({tierId: tierId});
            }

            // Store the tier with that ID.
            _storedTierOf[msg.sender][tierId] = JBStored721Tier({
                price: uint104(tierToAdd.price),
                remainingSupply: uint32(tierToAdd.initialSupply),
                initialSupply: uint32(tierToAdd.initialSupply),
                splitPercent: uint32(tierToAdd.splitPercent),
                reserveFrequency: uint16(tierToAdd.reserveFrequency),
                category: uint24(tierToAdd.category),
                discountPercent: uint8(tierToAdd.discountPercent),
                packedBools: _packBools({
                    allowOwnerMint: tierToAdd.flags.allowOwnerMint,
                    transfersPausable: tierToAdd.flags.transfersPausable,
                    useVotingUnits: tierToAdd.flags.useVotingUnits,
                    cantBeRemoved: tierToAdd.flags.cantBeRemoved,
                    cantIncreaseDiscountPercent: tierToAdd.flags.cantIncreaseDiscountPercent,
                    cantBuyWithCredits: tierToAdd.flags.cantBuyWithCredits
                })
            });

            // Store voting units in a separate mapping if custom voting units are used.
            if (tierToAdd.flags.useVotingUnits && tierToAdd.votingUnits != 0) {
                _tierVotingUnitsOf[msg.sender][tierId] = uint32(tierToAdd.votingUnits);
            }

            // If this is the first tier in a category within this batch, store it as that category's traversal start.
            // Same-category additions are inserted before older tiers in the category-sorted linked list, so a later
            // batch must overwrite the previous start pointer to keep category-filtered `tiersOf` queries complete.
            // Category 0 starts at the same tier as the default traversal.
            // Access the previous tier's category directly from calldata (0 when i == 0, matching the old
            // uninitialized-memory behavior).
            if ((i == 0 ? 0 : tiersToAdd[i - 1].category) != tierToAdd.category && tierToAdd.category != 0) {
                _startingTierIdOfCategory[msg.sender][tierToAdd.category] = tierId;
            }

            // Set the reserve beneficiary if needed.
            if (tierToAdd.reserveBeneficiary != address(0) && tierToAdd.reserveFrequency != 0) {
                if (tierToAdd.flags.useReserveBeneficiaryAsDefault) {
                    // WARNING: This overwrites the global default for ALL tiers without a tier-specific beneficiary.
                    if (defaultReserveBeneficiaryOf[msg.sender] != tierToAdd.reserveBeneficiary) {
                        defaultReserveBeneficiaryOf[msg.sender] = tierToAdd.reserveBeneficiary;
                        emit SetDefaultReserveBeneficiary({
                            hook: msg.sender, newBeneficiary: tierToAdd.reserveBeneficiary, caller: msg.sender
                        });
                    }
                } else {
                    _reserveBeneficiaryOf[msg.sender][tierId] = tierToAdd.reserveBeneficiary;
                }
            }

            // Set the `encodedIpfsUri` if needed.
            if (tierToAdd.encodedIpfsUri != bytes32(0)) {
                encodedIpfsUriOf[msg.sender][tierId] = tierToAdd.encodedIpfsUri;
            }

            if (startSortedTierId != 0) {
                // Keep track of the sorted tier ID being iterated on.
                uint256 currentSortedTierId = startSortedTierId;

                // Keep a reference to the tier ID to iterate to next.
                uint256 nextTierId;

                // Make sure the tier is sorted correctly.
                while (currentSortedTierId != 0) {
                    // Set the next tier ID.
                    nextTierId =
                        _nextSortedTierIdOf({hook: msg.sender, id: currentSortedTierId, max: currentLastSortedTierId});

                    // If the category is less than or equal to the sorted tier being iterated on,
                    // AND the tier being iterated on isn't among those being added, store the order.
                    if (
                        tierToAdd.category <= _storedTierOf[msg.sender][currentSortedTierId].category
                            && currentSortedTierId <= currentMaxTierIdOf
                    ) {
                        // If the tier ID being iterated on isn't the next tier ID, set the `_tierIdAfter` (next tier
                        // ID).
                        if (currentSortedTierId != tierId + 1) {
                            _tierIdAfter[msg.sender][tierId] = currentSortedTierId;
                        }

                        // If this is the first tier being added, track it as the current last sorted tier ID (if it's
                        // not already tracked).
                        if (_lastTrackedSortedTierIdOf[msg.sender] != currentLastSortedTierId) {
                            _lastTrackedSortedTierIdOf[msg.sender] = currentLastSortedTierId;
                        }

                        // If the previous tier's `_tierIdAfter` was set to something else, update it.
                        if (previousTierId != tierId - 1 || _tierIdAfter[msg.sender][previousTierId] != 0) {
                            // Point the previous tier at the tier being added, or store 0 when the next ID is implicit.
                            _tierIdAfter[msg.sender][previousTierId] = previousTierId == tierId - 1 ? 0 : tierId;
                        }

                        // When the next tier is being added, start at the sorted tier just set.
                        startSortedTierId = currentSortedTierId;

                        // Use the current tier ID as the "previous tier ID" when the next tier is being added.
                        previousTierId = tierId;

                        // Set the current sorted tier ID to zero to break out of the loop (the tier has been sorted).
                        currentSortedTierId = 0;
                    }
                    // If the tier being iterated on is the last tier, add the new tier after it.
                    else if (nextTierId == 0 || nextTierId > currentMaxTierIdOf) {
                        if (tierId != currentSortedTierId + 1) {
                            _tierIdAfter[msg.sender][currentSortedTierId] = tierId;
                        }

                        // For the next tier being added, start at this current tier ID.
                        startSortedTierId = tierId;

                        // Break out.
                        currentSortedTierId = 0;

                        // If there's currently a last sorted tier ID tracked, override it.
                        if (_lastTrackedSortedTierIdOf[msg.sender] != 0) _lastTrackedSortedTierIdOf[msg.sender] = 0;
                    }
                    // Move on to the next tier ID.
                    else {
                        // Set the previous tier ID to be the current tier ID.
                        previousTierId = currentSortedTierId;

                        // Go to the next tier ID.
                        currentSortedTierId = nextTierId;
                    }
                }
            }

            // Add the tier ID to the array being returned.
            tierIds[i] = tierId;

            unchecked {
                ++i;
            }
        }

        // Update the maximum tier ID to include the new tiers.
        maxTierIdOf[msg.sender] = currentMaxTierIdOf + tiersToAdd.length;
    }

    /// @notice Increment the burn counter for each token's tier. Does NOT affect `remainingSupply` — burned NFTs
    /// cannot be re-minted. The burn count is used by `totalSupplyOf` to compute the circulating supply.
    /// @dev This function trusts `msg.sender` (the hook contract) to only call it after actually burning the
    /// tokens. It does not verify ownership or existence of the token IDs — the hook is responsible for
    /// performing those checks before calling this function.
    /// @param tokenIds The token IDs of the NFTs to burn.
    function recordBurn(uint256[] calldata tokenIds) external override {
        // Iterate through all token IDs to increment the burn count.
        for (uint256 i; i < tokenIds.length;) {
            // Set the 721's token ID.
            uint256 tokenId = tokenIds[i];

            uint256 tierId = tierIdOfToken(tokenId);

            // Increment the number of NFTs burned from the tier.
            numberOfBurnedFor[msg.sender][tierId]++;

            // Maintain the running cash-out weight: a burn removes one outstanding NFT (weighted by the tier's full
            // price). Pending reserves are unaffected — they track non-reserve MINTS, which a burn does not change.
            unchecked {
                _totalCashOutWeightOf[msg.sender] -= _storedTierOf[msg.sender][tierId].price;
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Store the behavioral flags for the calling hook. These flags govern whether new tiers can have voting
    /// units, reserves, or owner minting enabled.
    /// @dev Only callable by hook contracts. Overwrites any previously stored flags for the caller.
    /// @param flags The flags to set.
    function recordFlags(JB721TiersHookFlags calldata flags) external override {
        _flagsOf[msg.sender] = flags;
    }

    /// @notice Record paid mints: deduct each tier's (discounted) price from `amount`, decrement supply, generate
    /// token IDs, and enforce that enough supply remains to satisfy pending reserves. Returns the leftover amount
    /// and the total cost of credit-restricted tiers so the hook can enforce pay-credit rules.
    /// @dev Reverts if the tier is removed, unrecognized, sold out, or its price exceeds the remaining amount.
    /// For owner mints, the tier must have `allowOwnerMint` set.
    /// @param amount The amount to spend on NFTs. The total price must not exceed this amount.
    /// @param tierIds The IDs of the tiers to mint from.
    /// @param isOwnerMint A flag indicating whether the 721 contract's owner is directly calling this function.
    /// @return tokenIds The token IDs of the NFTs which were minted.
    /// @return leftoverAmount The `amount` remaining after minting.
    /// @return restrictedCost Total cost of tiers with `cantBuyWithCredits` set. The caller can use this to enforce
    /// credit restrictions.
    function recordMint(
        uint256 amount,
        uint16[] calldata tierIds,
        bool isOwnerMint
    )
        external
        override
        returns (uint256[] memory tokenIds, uint256 leftoverAmount, uint256 restrictedCost)
    {
        // Set the leftover amount as the initial amount.
        leftoverAmount = amount;

        // Keep a reference to the tier being iterated on.
        JBStored721Tier storage storedTier;

        // Get a reference to the number of tiers.
        uint256 numberOfTiers = tierIds.length;

        // Initialize the array for the token IDs to be returned.
        tokenIds = new uint256[](numberOfTiers);

        // Initialize a `JBBitmapWord` for checking whether tiers have been removed.
        JBBitmapWord memory bitmapWord;

        for (uint256 i; i < numberOfTiers;) {
            // Set the tier ID being iterated on.
            uint256 tierId = tierIds[i];

            // Make sure the tier hasn't been removed.
            if (_isTierRemovedWithRefresh({hook: msg.sender, tierId: tierId, bitmapWord: bitmapWord})) {
                revert JB721TiersHookStore_TierRemoved({tierId: tierId});
            }

            // Keep a reference to the stored tier being iterated on.
            storedTier = _storedTierOf[msg.sender][tierId];

            // Parse the flags.
            (bool allowOwnerMint,,,,, bool cantBuyWithCredits) = _unpackBools(storedTier.packedBools);

            // If this is an owner mint, make sure owner minting is allowed.
            if (isOwnerMint && !allowOwnerMint) revert JB721TiersHookStore_CantMintManually(tierId);

            // Make sure the provided tier exists (tiers cannot have a supply of 0).
            if (storedTier.initialSupply == 0) revert JB721TiersHookStore_UnrecognizedTier(tierId);

            // Get a reference to the price.
            uint256 price = storedTier.price;

            // Apply a discount if needed.
            // 100% discount (discountPercent == DISCOUNT_DENOMINATOR) is a valid configuration
            // for promotional/free mint tiers. Project owners control discount percentages via tier config.
            // A tier with 100% discount and no other access controls is intentionally free.
            if (storedTier.discountPercent > 0) {
                price -= mulDiv({
                    x: price, y: storedTier.discountPercent, denominator: JB721Constants.DISCOUNT_DENOMINATOR
                });
            }

            // Accumulate cost of credit-restricted tiers.
            if (cantBuyWithCredits) restrictedCost += price;

            // Make sure the `amount` is greater than or equal to the tier's price.
            if (price > leftoverAmount) revert JB721TiersHookStore_PriceExceedsAmount(price, leftoverAmount);

            // Make sure there's at least one NFT remaining to mint.
            if (storedTier.remainingSupply == 0) revert JB721TiersHookStore_InsufficientSupplyRemaining(tierId);

            // Pending reserves before this mint, captured to maintain the O(1) cash-out weight aggregate.
            uint256 pendingReservesBefore =
                _numberOfPendingReservesFor({hook: msg.sender, tierId: tierId, storedTier: storedTier});

            // Mint the 721 — decrement remaining supply first so the reserve check below
            // sees the correct post-mint non-reserve-mint count.
            unchecked {
                // Keep a reference to its token ID.
                tokenIds[i] = _generateTokenId({
                    tierId: tierId, tokenNumber: storedTier.initialSupply - --storedTier.remainingSupply
                });
                leftoverAmount = leftoverAmount - price;
            }

            // Pending reserves after this mint (also used for the supply check below). A non-reserve mint can only
            // increase pending reserves, by at most one, so the difference is 0 or 1.
            uint256 pendingReservesAfter =
                _numberOfPendingReservesFor({hook: msg.sender, tierId: tierId, storedTier: storedTier});

            // Make sure there are still enough NFTs remaining to satisfy pending reserves.
            if (storedTier.remainingSupply < pendingReservesAfter) {
                revert JB721TiersHookStore_InsufficientSupplyRemaining({tierId: tierId});
            }

            // Maintain the running cash-out weight: this mint adds one outstanding NFT plus any newly-accrued pending
            // reserve, each weighted by the tier's FULL price (the cash-out weight uses the full price, not the
            // discounted one). Keeps `totalCashOutWeight` O(1) regardless of the tier count.
            unchecked {
                _totalCashOutWeightOf[msg.sender] +=
                    storedTier.price * (1 + (pendingReservesAfter - pendingReservesBefore));
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Generate token IDs for reserve NFT mints and decrement the tier's remaining supply. Reserves
    /// accumulate as non-reserve NFTs are minted (one reserve per `reserveFrequency` mints). Reverts if `count`
    /// exceeds the number of pending reserves.
    /// @param tierId The ID of the tier to mint reserves from.
    /// @param count The number of reserve NFTs to mint.
    /// @return tokenIds The token IDs of the reserve NFTs which were minted.
    function recordMintReservesFor(uint256 tierId, uint256 count)
        external
        override
        returns (uint256[] memory tokenIds)
    {
        // Get a reference to the stored tier.
        JBStored721Tier storage storedTier = _storedTierOf[msg.sender][tierId];

        // Get a reference to the number of pending reserve NFTs for the tier.
        // "Pending" means that the NFTs have been reserved, but have not been minted yet.
        uint256 numberOfPendingReserves =
            _numberOfPendingReservesFor({hook: msg.sender, tierId: tierId, storedTier: storedTier});

        // Can't mint more than the number of pending reserves.
        if (count > numberOfPendingReserves) {
            revert JB721TiersHookStore_InsufficientPendingReserves({
                count: count, numberOfPendingReserves: numberOfPendingReserves
            });
        }

        // Increment the number of reserve NFTs minted.
        numberOfReservesMintedFor[msg.sender][tierId] += count;

        // Initialize an array for the token IDs to be returned.
        tokenIds = new uint256[](count);

        for (uint256 i; i < count;) {
            // Generate the NFTs.
            tokenIds[i] = _generateTokenId({
                tierId: tierId, tokenNumber: storedTier.initialSupply - --storedTier.remainingSupply
            });

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Mark one or more tiers as removed. Removed tiers cannot be minted from, but existing NFTs from those
    /// tiers remain valid (can still be cashed out and transferred). Pending reserves can still be minted.
    /// @dev Removing a tier only marks it in a bitmap — it does not update the sorted tier linked list.
    /// Call `cleanTiers()` after removing tiers to update the sorting sequence and prevent stale tier iteration.
    /// Reverts if the tier has `cantBeRemoved` set, or if the tier ID is 0 or exceeds `maxTierIdOf`.
    /// @param tierIds The IDs of the tiers to remove.
    function recordRemoveTierIds(uint256[] calldata tierIds) external override {
        for (uint256 i; i < tierIds.length;) {
            // Set the tier being iterated upon (0-indexed).
            uint256 tierId = tierIds[i];

            // Reject tier IDs that don't exist yet — removing a future tier would cause it
            // to be born already removed when later added.
            if (tierId == 0 || tierId > maxTierIdOf[msg.sender]) {
                revert JB721TiersHookStore_UnrecognizedTier({tierId: tierId});
            }

            // Get a reference to the stored tier.
            JBStored721Tier storage storedTier = _storedTierOf[msg.sender][tierId];

            // Parse the flags.
            (,,, bool cantBeRemoved,,) = _unpackBools(storedTier.packedBools);

            // Make sure the tier can be removed.
            if (cantBeRemoved) revert JB721TiersHookStore_CantRemoveTier(tierId);

            // Remove the tier by marking it as removed in the bitmap.
            _removedTiersBitmapWordOf[msg.sender].removeTier(tierId);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Update the discount percentage for a tier. Discounts reduce the price payers pay without affecting the
    /// NFT's cash-out weight (which always uses the original price). Reverts if the tier is removed, if the percent
    /// exceeds the denominator, or if the tier has `cantIncreaseDiscountPercent` set and the new value is higher.
    /// @param tierId The ID of the tier to record a discount for.
    /// @param discountPercent The new discount percent to apply.
    function recordSetDiscountPercentOf(uint256 tierId, uint256 discountPercent) external override {
        // Make sure the tier hasn't been removed.
        JBBitmapWord memory bitmapWord = _removedTiersBitmapWordOf[msg.sender].readId(tierId);
        if (bitmapWord.isTierIdRemoved(tierId)) revert JB721TiersHookStore_TierRemoved(tierId);

        // Make sure the discount percent is within the bound.
        if (discountPercent > JB721Constants.DISCOUNT_DENOMINATOR) {
            revert JB721TiersHookStore_DiscountPercentExceedsBounds({
                percent: discountPercent, limit: JB721Constants.DISCOUNT_DENOMINATOR
            });
        }

        // Get a reference to the stored tier.
        JBStored721Tier storage storedTier = _storedTierOf[msg.sender][tierId];

        // Parse the flags.
        (,,,, bool cantIncreaseDiscountPercent,) = _unpackBools(storedTier.packedBools);

        // Make sure that increasing the discount is allowed for the tier.
        if (discountPercent > storedTier.discountPercent && cantIncreaseDiscountPercent) {
            revert JB721TiersHookStore_DiscountPercentIncreaseNotAllowed({
                percent: discountPercent, storedPercent: storedTier.discountPercent
            });
        }

        // Set the discount.
        // forge-lint: disable-next-line(unsafe-typecast)
        storedTier.discountPercent = uint8(discountPercent);
    }

    /// @notice Record a new encoded IPFS URI for a tier.
    /// @param tierId The ID of the tier to set the encoded IPFS URI of.
    /// @param encodedIpfsUri The encoded IPFS URI to set for the tier.
    // forge-lint: disable-next-line(mixed-case-function)
    function recordSetEncodedIpfsUriOf(uint256 tierId, bytes32 encodedIpfsUri) external override {
        encodedIpfsUriOf[msg.sender][tierId] = encodedIpfsUri;
    }

    /// @notice Record a newly set token URI resolver.
    /// @param resolver The resolver to set.
    function recordSetTokenUriResolver(IJB721TokenUriResolver resolver) external override {
        tokenUriResolverOf[msg.sender] = resolver;
    }

    /// @notice Update tier balance accounting when an NFT is transferred. Decrements the sender's balance and
    /// increments the receiver's balance for the given tier. Handles mints (from == address(0)) and burns
    /// (to == address(0)) as one-sided updates.
    /// @param tierId The ID of the tier that the 721 to transfer belongs to.
    /// @param from The address to transfer the 721 from.
    /// @param to The address to transfer the 721 to.
    function recordTransferForTier(uint256 tierId, address from, address to) external override {
        // If this is not a mint,
        if (from != address(0)) {
            // then subtract the tier balance from the sender, and the running per-owner balance read by `balanceOf`.
            --tierBalanceOf[msg.sender][from][tierId];
            --_addressBalanceOf[msg.sender][from];
        }

        // If this is not a burn,
        if (to != address(0)) {
            unchecked {
                // then increase the tier balance for the receiver, and the running per-owner balance.
                ++tierBalanceOf[msg.sender][to][tierId];
                ++_addressBalanceOf[msg.sender][to];
            }
        }
    }
}
