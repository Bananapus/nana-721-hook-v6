// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBRulesets} from "@bananapus/core-v6/src/interfaces/IJBRulesets.sol";

import {IJB721Hook} from "./IJB721Hook.sol";
import {IJB721TiersHookStore} from "./IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "./IJB721TokenUriResolver.sol";
import {JB721InitTiersConfig} from "../structs/JB721InitTiersConfig.sol";
import {JB721TierConfig} from "../structs/JB721TierConfig.sol";
import {JB721TiersHookFlags} from "../structs/JB721TiersHookFlags.sol";
import {JB721TiersMintReservesConfig} from "../structs/JB721TiersMintReservesConfig.sol";
import {JB721TiersSetDiscountPercentConfig} from "../structs/JB721TiersSetDiscountPercentConfig.sol";

interface IJB721TiersHook is IJB721Hook {
    event AddPayCredits(
        uint256 indexed amount, uint256 indexed newTotalCredits, address indexed account, address caller
    );
    event AddTier(uint256 indexed tierId, JB721TierConfig tier, address caller);
    event Mint(
        uint256 indexed tokenId,
        uint256 indexed tierId,
        address indexed beneficiary,
        uint256 totalAmountPaid,
        address caller
    );
    event MintReservedNft(uint256 indexed tokenId, uint256 indexed tierId, address indexed beneficiary, address caller);
    event RemoveTier(uint256 indexed tierId, address caller);
    event SetBaseUri(string indexed baseUri, address caller);
    event SetContractUri(string indexed uri, address caller);
    event SetDiscountPercent(uint256 indexed tierId, uint256 discountPercent, address caller);
    event SetEncodedIPFSUri(uint256 indexed tierId, bytes32 encodedUri, address caller);
    event SetTokenUriResolver(IJB721TokenUriResolver indexed resolver, address caller);
    event UsePayCredits(
        uint256 indexed amount, uint256 indexed newTotalCredits, address indexed account, address caller
    );

    /// @notice The contract storing and managing project rulesets.
    /// @return The rulesets contract.
    function RULESETS() external view returns (IJBRulesets);

    /// @notice The contract that stores and manages data for this contract's NFTs.
    /// @return The store contract.
    function STORE() external view returns (IJB721TiersHookStore);

    /// @notice The base URI for the NFT `tokenUris`.
    /// @return The base URI string.
    function baseURI() external view returns (string memory);

    /// @notice This contract's metadata URI.
    /// @return The contract URI string.
    function contractURI() external view returns (string memory);

    /// @notice The first owner of an NFT.
    /// @param tokenId The token ID of the NFT to get the first owner of.
    /// @return The address of the NFT's first owner.
    function firstOwnerOf(uint256 tokenId) external view returns (address);

    /// @notice The amount of NFT credits the address has.
    /// @param addr The address to get the NFT credits balance of.
    /// @return The amount of credits the address has.
    function payCreditsOf(address addr) external view returns (uint256);

    /// @notice Context for the pricing of this hook's tiers.
    /// @return currency The currency used for tier prices.
    /// @return decimals The amount of decimals being used in tier prices.
    /// @return prices The prices contract used to resolve the value of payments in other currencies.
    function pricingContext() external view returns (uint256 currency, uint256 decimals, IJBPrices prices);

    /// @notice Add or remove tiers.
    /// @param tiersToAdd The tiers to add, as an array of `JB721TierConfig` structs.
    /// @param tierIdsToRemove The tiers to remove, as an array of tier IDs.
    function adjustTiers(JB721TierConfig[] calldata tiersToAdd, uint256[] calldata tierIdsToRemove) external;

    /// @notice Initializes a cloned copy of the original `JB721TiersHook` contract.
    /// @param projectId The ID of the project this hook is associated with.
    /// @param name The name of the NFT collection.
    /// @param symbol The symbol representing the NFT collection.
    /// @param baseUri The URI to use as a base for full NFT `tokenUri`s.
    /// @param tokenUriResolver An optional contract responsible for resolving the token URI for each NFT.
    /// @param contractUri A URI where this contract's metadata can be found.
    /// @param tiersConfig The NFT tiers and pricing context to initialize the hook with.
    /// @param flags A set of additional options which dictate how the hook behaves.
    function initialize(
        uint256 projectId,
        string memory name,
        string memory symbol,
        string memory baseUri,
        IJB721TokenUriResolver tokenUriResolver,
        string memory contractUri,
        JB721InitTiersConfig memory tiersConfig,
        JB721TiersHookFlags memory flags
    )
        external;

    /// @notice Set the discount percent for a tier.
    /// @param tierId The ID of the tier to set the discount of.
    /// @param discountPercent The discount percent to set.
    function setDiscountPercentOf(uint256 tierId, uint256 discountPercent) external;

    /// @notice Set the discount percent for multiple tiers.
    /// @param configs The configs to set the discount percent for.
    function setDiscountPercentsOf(JB721TiersSetDiscountPercentConfig[] calldata configs) external;

    /// @notice Manually mint NFTs from the provided tiers.
    /// @param tierIds The IDs of the tiers to mint from.
    /// @param beneficiary The address to mint to.
    /// @return tokenIds The IDs of the newly minted tokens.
    function mintFor(uint16[] calldata tierIds, address beneficiary) external returns (uint256[] memory tokenIds);

    /// @notice Mint pending reserved NFTs based on the provided information.
    /// @param reserveMintConfigs Contains information about how many reserved tokens to mint for each tier.
    function mintPendingReservesFor(JB721TiersMintReservesConfig[] calldata reserveMintConfigs) external;

    /// @notice Mint pending reserved NFTs for a specific tier.
    /// @param tierId The ID of the tier to mint reserved NFTs from.
    /// @param count The number of reserved NFTs to mint.
    function mintPendingReservesFor(uint256 tierId, uint256 count) external;

    /// @notice Update this hook's URI metadata properties.
    /// @param baseUri The new base URI.
    /// @param contractUri The new contract URI.
    /// @param tokenUriResolver The new URI resolver.
    /// @param encodedIPFSUriTierId The ID of the tier to set the encoded IPFS URI of.
    /// @param encodedIPFSUri The encoded IPFS URI to set.
    function setMetadata(
        string calldata baseUri,
        string calldata contractUri,
        IJB721TokenUriResolver tokenUriResolver,
        uint256 encodedIPFSUriTierId,
        bytes32 encodedIPFSUri
    )
        external;
}
