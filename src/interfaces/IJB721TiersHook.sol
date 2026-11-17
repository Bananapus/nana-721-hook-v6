// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBRulesets} from "@bananapus/core-v6/src/interfaces/IJBRulesets.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JB721HeldPayout} from "../structs/JB721HeldPayout.sol";

import {IJB721Checkpoints} from "./IJB721Checkpoints.sol";
import {IJB721Hook} from "./IJB721Hook.sol";
import {IJB721TiersHookStore} from "./IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "./IJB721TokenUriResolver.sol";
import {JB721InitTiersConfig} from "../structs/JB721InitTiersConfig.sol";
import {JB721TierConfig} from "../structs/JB721TierConfig.sol";
import {JB721TiersHookFlags} from "../structs/JB721TiersHookFlags.sol";
import {JB721TiersMintReservesConfig} from "../structs/JB721TiersMintReservesConfig.sol";
import {JB721TiersSetDiscountPercentConfig} from "../structs/JB721TiersSetDiscountPercentConfig.sol";

/// @notice A 721 tiers hook that mints tiered NFTs for payments and tracks their cash out weight.
interface IJB721TiersHook is IJB721Hook {
    /// @notice Emitted when pay credits are added for an account.
    /// @param amount The amount of credits added.
    /// @param newTotalCredits The new total credits balance for the account.
    /// @param account The account that received the credits.
    /// @param caller The address that called the function.
    event AddPayCredits(
        uint256 indexed amount, uint256 indexed newTotalCredits, address indexed account, address caller
    );

    /// @notice Emitted when a new tier is added.
    /// @param tierId The ID of the tier that was added.
    /// @param tier The configuration of the tier that was added.
    /// @param caller The address that called the function.
    event AddTier(uint256 indexed tierId, JB721TierConfig tier, address caller);

    /// @notice Emitted when an NFT is minted from a payment.
    /// @param tokenId The token ID of the minted NFT.
    /// @param tierId The ID of the tier the NFT was minted from.
    /// @param beneficiary The address that received the NFT.
    /// @param totalAmountPaid The total amount paid in the transaction.
    /// @param caller The address that called the function.
    event Mint(
        uint256 indexed tokenId,
        uint256 indexed tierId,
        address indexed beneficiary,
        uint256 totalAmountPaid,
        address caller
    );

    /// @notice Emitted when a reserved NFT is minted.
    /// @param tokenId The token ID of the minted reserved NFT.
    /// @param tierId The ID of the tier the reserved NFT was minted from.
    /// @param beneficiary The address that received the reserved NFT.
    /// @param caller The address that called the function.
    event MintReservedNft(uint256 indexed tokenId, uint256 indexed tierId, address indexed beneficiary, address caller);

    /// @notice Emitted when a tier is removed.
    /// @param tierId The ID of the tier that was removed.
    /// @param caller The address that called the function.
    event RemoveTier(uint256 indexed tierId, address caller);

    /// @notice Emitted when the collection name is set.
    /// @param name The new collection name.
    /// @param caller The address that called the function.
    event SetName(string indexed name, address caller);

    /// @notice Emitted when the collection symbol is set.
    /// @param symbol The new collection symbol.
    /// @param caller The address that called the function.
    event SetSymbol(string indexed symbol, address caller);

    /// @notice Emitted when the base URI is set.
    /// @param baseUri The new base URI.
    /// @param caller The address that called the function.
    event SetBaseUri(string indexed baseUri, address caller);

    /// @notice Emitted when the contract URI is set.
    /// @param uri The new contract URI.
    /// @param caller The address that called the function.
    event SetContractUri(string indexed uri, address caller);

    /// @notice Emitted when a tier's discount percent is set.
    /// @param tierId The ID of the tier whose discount percent was set.
    /// @param discountPercent The new discount percent.
    /// @param caller The address that called the function.
    event SetDiscountPercent(uint256 indexed tierId, uint256 discountPercent, address caller);

    /// @notice Emitted when a tier's encoded IPFS URI is set.
    /// @param tierId The ID of the tier whose encoded IPFS URI was set.
    /// @param encodedUri The new encoded IPFS URI.
    /// @param caller The address that called the function.
    event SetEncodedIpfsUri(uint256 indexed tierId, bytes32 encodedUri, address caller);

    /// @notice Emitted when the token URI resolver is set.
    /// @param resolver The new token URI resolver.
    /// @param caller The address that called the function.
    event SetTokenUriResolver(IJB721TokenUriResolver indexed resolver, address caller);

    /// @notice A tier split's recipient reverted, so the amount is held for the split until a retry succeeds.
    /// @param projectId The ID of the project the payout is from.
    /// @param token The token of the payout.
    /// @param groupId The split group the split belongs to.
    /// @param decimals The decimals of `token`, as forwarded into the split hook context.
    /// @param split The split the amount is held for.
    /// @param amount The amount held.
    /// @param reason The revert reason, or the token's return data for a rejected transfer.
    event HoldPayout(
        uint256 indexed projectId,
        address indexed token,
        uint256 groupId,
        uint256 decimals,
        JBSplit split,
        uint256 amount,
        bytes reason
    );

    /// @notice A held tier split payout was retried and delivered.
    /// @param projectId The ID of the project the payout is from.
    /// @param token The token of the payout.
    /// @param groupId The split group the split belongs to.
    /// @param split The split that was paid.
    /// @param amount The amount that was held.
    /// @param sent The amount the recipient took; the rest went to the project's balance.
    /// @param caller The address that retried the payout.
    event ProcessHeldPayout(
        uint256 indexed projectId,
        address indexed token,
        uint256 groupId,
        JBSplit split,
        uint256 amount,
        uint256 sent,
        address caller
    );

    /// @notice Emitted when pay credits are used by an account.
    /// @param amount The amount of credits used.
    /// @param newTotalCredits The new total credits balance for the account.
    /// @param account The account that used the credits.
    /// @param caller The address that called the function.
    event UsePayCredits(
        uint256 indexed amount, uint256 indexed newTotalCredits, address indexed account, address caller
    );

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

    /// @notice A tier split payout held because its recipient could not take it.
    /// @param heldPayoutId `keccak256(abi.encode(token, groupId, decimals, split))`, as emitted in `HoldPayout`.
    /// @return The amount held.
    function heldPayoutOf(bytes32 heldPayoutId) external view returns (uint256);

    /// @notice Context for the pricing of this hook's tiers.
    /// @return currency The currency used for tier prices.
    /// @return decimals The number of decimals used in tier prices.
    function pricingContext() external view returns (uint256 currency, uint256 decimals);

    /// @notice The checkpoint module that manages IVotes-compatible checkpointed voting power for this hook's NFTs.
    /// @dev Deployed lazily on first mint. Pass this to JBTokenDistributor as the IVotes token.
    /// @return The checkpoint module.
    function checkpoints() external view returns (IJB721Checkpoints);

    /// @notice The contract that exposes price feeds for currency conversions.
    /// @return The prices contract.
    function PRICES() external view returns (IJBPrices);

    /// @notice The contract storing and managing project rulesets.
    /// @return The rulesets contract.
    function RULESETS() external view returns (IJBRulesets);

    /// @notice The contract that stores and manages data for this contract's NFTs.
    /// @return The store contract.
    function STORE() external view returns (IJB721TiersHookStore);

    /// @notice The contract that stores and manages splits.
    /// @return The splits contract.
    function SPLITS() external view returns (IJBSplits);

    /// @notice Add or remove tiers.
    /// @param tiersToAdd The tiers to add, as an array of `JB721TierConfig` structs.
    /// @param tierIdsToRemove The tiers to remove, as an array of tier IDs.
    function adjustTiers(JB721TierConfig[] calldata tiersToAdd, uint256[] calldata tierIdsToRemove) external;

    /// @notice Initializes a cloned copy of the original `JB721TiersHook` contract.
    /// @param initialProjectId The ID of the project this hook is associated with.
    /// @param name The name of the NFT collection.
    /// @param symbol The symbol representing the NFT collection.
    /// @param baseUri The URI to use as a base for full NFT `tokenUri`s.
    /// @param tokenUriResolver An optional contract responsible for resolving the token URI for each NFT.
    /// @param contractUri A URI where this contract's metadata can be found.
    /// @param tiersConfig The NFT tiers and pricing context to initialize the hook with.
    /// @param flags A set of additional options which dictate how the hook behaves.
    function initialize(
        uint256 initialProjectId,
        string memory name,
        string memory symbol,
        string memory baseUri,
        IJB721TokenUriResolver tokenUriResolver,
        string memory contractUri,
        JB721InitTiersConfig memory tiersConfig,
        JB721TiersHookFlags memory flags
    )
        external;

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

    /// @notice Retries a held tier split payout. Reverts if the recipient still cannot take it.
    /// @param token The token of the payout.
    /// @param tierId The tier whose split group the split belongs to.
    /// @param decimals The decimals of `token`, as emitted in `HoldPayout`.
    /// @param split The held split, as emitted in `HoldPayout`.
    function processHeldPayoutOf(address token, uint16 tierId, uint256 decimals, JBSplit calldata split) external;

    /// @notice Retries several held tier split payouts. Reverts if any recipient still cannot take it.
    /// @param payouts The held payouts, as emitted in `HoldPayout`.
    function processHeldPayoutsOf(JB721HeldPayout[] calldata payouts) external;

    /// @notice Set the discount percent for a tier.
    /// @param tierId The ID of the tier to set the discount of.
    /// @param discountPercent The discount percent to set.
    function setDiscountPercentOf(uint256 tierId, uint256 discountPercent) external;

    /// @notice Set the discount percent for multiple tiers.
    /// @param configs The configs to set the discount percent for.
    function setDiscountPercentsOf(JB721TiersSetDiscountPercentConfig[] calldata configs) external;

    /// @notice Update this hook's metadata properties.
    /// @param name The new collection name. Send empty to leave unchanged.
    /// @param symbol The new collection symbol. Send empty to leave unchanged.
    /// @param baseUri The new base URI. Send empty to leave unchanged.
    /// @param contractUri The new contract URI. Send empty to leave unchanged.
    /// @param tokenUriResolver The new URI resolver. Pass `IJB721TokenUriResolver(address(this))` to leave it
    /// unchanged; `address(0)` clears the resolver.
    /// @param encodedIpfsUriTierId The ID of the tier to set the encoded IPFS URI of.
    /// @param encodedIpfsUri The encoded IPFS URI to set.
    function setMetadata(
        string calldata name,
        string calldata symbol,
        string calldata baseUri,
        string calldata contractUri,
        IJB721TokenUriResolver tokenUriResolver,
        uint256 encodedIpfsUriTierId,
        bytes32 encodedIpfsUri
    )
        external;
}
