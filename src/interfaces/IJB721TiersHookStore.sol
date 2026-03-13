// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJB721TokenUriResolver} from "./IJB721TokenUriResolver.sol";
import {JB721Tier} from "../structs/JB721Tier.sol";
import {JB721TierConfig} from "../structs/JB721TierConfig.sol";
import {JB721TiersHookFlags} from "../structs/JB721TiersHookFlags.sol";

/// @notice Stores and manages data for 721 tiers hooks.
interface IJB721TiersHookStore {
    /// @notice Emitted when removed tiers are cleaned from the sorting sequence.
    /// @param hook The 721 contract whose tiers were cleaned.
    /// @param caller The address that called the function.
    event CleanTiers(address indexed hook, address caller);

    /// @notice Emitted when the default reserve beneficiary is changed.
    /// @dev This affects ALL tiers that do not have a tier-specific reserve beneficiary set.
    /// @param hook The 721 contract whose default reserve beneficiary was changed.
    /// @param newBeneficiary The new default reserve beneficiary address.
    /// @param caller The address that triggered the change.
    event SetDefaultReserveBeneficiary(address indexed hook, address indexed newBeneficiary, address caller);

    /// @notice Get the number of NFTs that the specified address owns from the specified 721 contract.
    /// @param hook The 721 contract to get the balance within.
    /// @param owner The address to check the balance of.
    /// @return The number of NFTs the owner has from the 721 contract.
    function balanceOf(address hook, address owner) external view returns (uint256);

    /// @notice The combined cash out weight of the NFTs with the provided token IDs.
    /// @param hook The 721 contract that the NFTs belong to.
    /// @param tokenIds The token IDs of the NFTs to get the cash out weight of.
    /// @return weight The cash out weight.
    function cashOutWeightOf(address hook, uint256[] calldata tokenIds) external view returns (uint256 weight);

    /// @notice The default reserve beneficiary for the provided 721 contract.
    /// @param hook The 721 contract to get the default reserve beneficiary of.
    /// @return The default reserve beneficiary address.
    function defaultReserveBeneficiaryOf(address hook) external view returns (address);

    /// @notice The encoded IPFS URI for the provided tier ID of the provided 721 contract.
    /// @param hook The 721 contract that the tier belongs to.
    /// @param tierId The ID of the tier to get the encoded IPFS URI of.
    /// @return The encoded IPFS URI.
    // forge-lint: disable-next-line(mixed-case-function)
    function encodedIPFSUriOf(address hook, uint256 tierId) external view returns (bytes32);

    /// @notice The encoded IPFS URI for the tier of the 721 with the provided token ID.
    /// @param hook The 721 contract that the encoded IPFS URI belongs to.
    /// @param tokenId The token ID of the 721 to get the encoded tier IPFS URI of.
    /// @return The encoded IPFS URI.
    // forge-lint: disable-next-line(mixed-case-function)
    function encodedTierIPFSUriOf(address hook, uint256 tokenId) external view returns (bytes32);

    /// @notice Get the flags that dictate the behavior of the provided 721 contract.
    /// @param hook The 721 contract to get the flags of.
    /// @return The flags.
    function flagsOf(address hook) external view returns (JB721TiersHookFlags memory);

    /// @notice Check if the provided tier has been removed from the provided 721 contract.
    /// @param hook The 721 contract the tier belongs to.
    /// @param tierId The ID of the tier to check the removal status of.
    /// @return Whether the tier has been removed.
    function isTierRemoved(address hook, uint256 tierId) external view returns (bool);

    /// @notice The largest tier ID currently used on the provided 721 contract.
    /// @param hook The 721 contract to get the largest tier ID from.
    /// @return The largest tier ID.
    function maxTierIdOf(address hook) external view returns (uint256);

    /// @notice The number of NFTs which have been burned from the provided tier ID.
    /// @param hook The 721 contract that the tier belongs to.
    /// @param tierId The ID of the tier to get the burn count of.
    /// @return The number of burned NFTs.
    function numberOfBurnedFor(address hook, uint256 tierId) external view returns (uint256);

    /// @notice The number of pending reserve NFTs for the provided tier ID.
    /// @param hook The 721 contract to check for pending reserved NFTs.
    /// @param tierId The ID of the tier to get the number of pending reserves for.
    /// @return The number of pending reserved NFTs.
    function numberOfPendingReservesFor(address hook, uint256 tierId) external view returns (uint256);

    /// @notice The number of reserve NFTs which have been minted from the provided tier ID.
    /// @param hook The 721 contract that the tier belongs to.
    /// @param tierId The ID of the tier to get the reserve mint count of.
    /// @return The number of reserve NFTs minted.
    function numberOfReservesMintedFor(address hook, uint256 tierId) external view returns (uint256);

    /// @notice The reserve beneficiary for the provided tier ID on the provided 721 contract.
    /// @param hook The 721 contract that the tier belongs to.
    /// @param tierId The ID of the tier to get the reserve beneficiary of.
    /// @return The reserve beneficiary address.
    function reserveBeneficiaryOf(address hook, uint256 tierId) external view returns (address);

    /// @notice The number of NFTs the provided owner address owns from the provided tier.
    /// @param hook The 721 contract to get the balance from.
    /// @param owner The address to get the tier balance of.
    /// @param tierId The ID of the tier to get the balance for.
    /// @return The tier balance.
    function tierBalanceOf(address hook, address owner, uint256 tierId) external view returns (uint256);

    /// @notice The tier ID for the 721 with the provided token ID.
    /// @param tokenId The token ID of the 721 to get the tier ID of.
    /// @return The tier ID.
    function tierIdOfToken(uint256 tokenId) external pure returns (uint256);

    /// @notice Get the tier with the provided ID from the provided 721 contract.
    /// @param hook The 721 contract to get the tier from.
    /// @param id The ID of the tier to get.
    /// @param includeResolvedUri If `true`, the resolved token URI will be included.
    /// @return tier The tier.
    function tierOf(address hook, uint256 id, bool includeResolvedUri) external view returns (JB721Tier memory tier);

    /// @notice Get the tier of the 721 with the provided token ID.
    /// @param hook The 721 contract that the tier belongs to.
    /// @param tokenId The token ID of the 721 to get the tier of.
    /// @param includeResolvedUri If `true`, the resolved token URI will be included.
    /// @return tier The tier.
    function tierOfTokenId(
        address hook,
        uint256 tokenId,
        bool includeResolvedUri
    )
        external
        view
        returns (JB721Tier memory tier);

    /// @notice Get an array of currently active 721 tiers for the provided 721 contract.
    /// @param hook The 721 contract to get the tiers of.
    /// @param categories An array of tier categories to get tiers from. Empty for all categories.
    /// @param includeResolvedUri If `true`, the resolved token URIs will be included.
    /// @param startingId The ID of the first tier to get. Send 0 to get all active tiers.
    /// @param size The number of tiers to include.
    /// @return tiers An array of active 721 tiers.
    function tiersOf(
        address hook,
        uint256[] calldata categories,
        bool includeResolvedUri,
        uint256 startingId,
        uint256 size
    )
        external
        view
        returns (JB721Tier[] memory tiers);

    /// @notice The number of voting units an address has within the specified tier.
    /// @param hook The 721 contract that the tier belongs to.
    /// @param account The address to get the voting units of within the tier.
    /// @param tierId The ID of the tier to get voting units within.
    /// @return units The voting units.
    function tierVotingUnitsOf(address hook, address account, uint256 tierId) external view returns (uint256 units);

    /// @notice The custom token URI resolver for the provided 721 contract.
    /// @param hook The 721 contract to get the custom token URI resolver of.
    /// @return The token URI resolver.
    function tokenUriResolverOf(address hook) external view returns (IJB721TokenUriResolver);

    /// @notice The combined cash out weight for all NFTs from the provided 721 contract.
    /// @param hook The 721 contract to get the total cash out weight of.
    /// @return weight The total cash out weight.
    function totalCashOutWeight(address hook) external view returns (uint256 weight);

    /// @notice The total number of NFTs minted from the provided 721 contract.
    /// @param hook The 721 contract to get a total supply of.
    /// @return The total supply.
    function totalSupplyOf(address hook) external view returns (uint256);

    /// @notice The total number of voting units an address has for the provided 721 contract.
    /// @param hook The 721 contract to get the voting units within.
    /// @param account The address to get the voting unit total of.
    /// @return units The total voting units.
    function votingUnitsOf(address hook, address account) external view returns (uint256 units);

    /// @notice Clean removed tiers from the tier sorting sequence.
    /// @param hook The 721 contract to clean tiers for.
    function cleanTiers(address hook) external;

    /// @notice Record newly added tiers.
    /// @param tiersToAdd The tiers to add.
    /// @return tierIds The IDs of the tiers being added.
    function recordAddTiers(JB721TierConfig[] calldata tiersToAdd) external returns (uint256[] memory tierIds);

    /// @notice Record 721 burns.
    /// @param tokenIds The token IDs of the NFTs to burn.
    function recordBurn(uint256[] calldata tokenIds) external;

    /// @notice Record newly set flags.
    /// @param flags The flags to set.
    function recordFlags(JB721TiersHookFlags calldata flags) external;

    /// @notice Record 721 mints from the provided tiers.
    /// @param amount The amount being spent on NFTs.
    /// @param tierIds The IDs of the tiers to mint from.
    /// @param isOwnerMint Whether this is a direct owner mint.
    /// @return tokenIds The token IDs of the NFTs which were minted.
    /// @return leftoverAmount The amount remaining after minting.
    function recordMint(
        uint256 amount,
        uint16[] calldata tierIds,
        bool isOwnerMint
    )
        external
        returns (uint256[] memory tokenIds, uint256 leftoverAmount);

    /// @notice Record reserve 721 minting for the provided tier ID.
    /// @param tierId The ID of the tier to mint reserves from.
    /// @param count The number of reserve NFTs to mint.
    /// @return tokenIds The token IDs of the reserve NFTs which were minted.
    function recordMintReservesFor(uint256 tierId, uint256 count) external returns (uint256[] memory tokenIds);

    /// @notice Record tiers being removed.
    /// @param tierIds The IDs of the tiers being removed.
    function recordRemoveTierIds(uint256[] calldata tierIds) external;

    /// @notice Record the setting of a discount for a tier.
    /// @param tierId The ID of the tier to set the discount of.
    /// @param discountPercent The new discount percent being applied.
    function recordSetDiscountPercentOf(uint256 tierId, uint256 discountPercent) external;

    /// @notice Record a new encoded IPFS URI for a tier.
    /// @param tierId The ID of the tier to set the encoded IPFS URI of.
    /// @param encodedIPFSUri The encoded IPFS URI to set for the tier.
    // forge-lint: disable-next-line(mixed-case-function, mixed-case-variable)
    function recordSetEncodedIPFSUriOf(uint256 tierId, bytes32 encodedIPFSUri) external;

    /// @notice Record a newly set token URI resolver.
    /// @param resolver The resolver to set.
    function recordSetTokenUriResolver(IJB721TokenUriResolver resolver) external;

    /// @notice Record an 721 transfer.
    /// @param tierId The ID of the tier that the 721 being transferred belongs to.
    /// @param from The address that the 721 is being transferred from.
    /// @param to The address that the 721 is being transferred to.
    function recordTransferForTier(uint256 tierId, address from, address to) external;
}
