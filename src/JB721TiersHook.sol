// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBRulesets} from "@bananapus/core-v6/src/interfaces/IJBRulesets.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {JBRulesetMetadataResolver} from "@bananapus/core-v6/src/libraries/JBRulesetMetadataResolver.sol";
import {JBAfterPayRecordedContext} from "@bananapus/core-v6/src/structs/JBAfterPayRecordedContext.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core-v6/src/structs/JBBeforePayRecordedContext.sol";
import {JBPayHookSpecification} from "@bananapus/core-v6/src/structs/JBPayHookSpecification.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {JBOwnable} from "@bananapus/ownable-v6/src/JBOwnable.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {JB721Hook} from "./abstract/JB721Hook.sol";
import {IJB721Checkpoints} from "./interfaces/IJB721Checkpoints.sol";
import {IJB721CheckpointsDeployer} from "./interfaces/IJB721CheckpointsDeployer.sol";
import {IJB721TiersHook} from "./interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookStore} from "./interfaces/IJB721TiersHookStore.sol";
import {IJB721TokenUriResolver} from "./interfaces/IJB721TokenUriResolver.sol";
import {JB721TiersHookLib} from "./libraries/JB721TiersHookLib.sol";
import {JB721TiersRulesetMetadataResolver} from "./libraries/JB721TiersRulesetMetadataResolver.sol";
import {JB721InitTiersConfig} from "./structs/JB721InitTiersConfig.sol";
import {JB721TierConfig} from "./structs/JB721TierConfig.sol";
import {JB721TiersHookFlags} from "./structs/JB721TiersHookFlags.sol";
import {JB721TiersMintReservesConfig} from "./structs/JB721TiersMintReservesConfig.sol";
import {JB721TiersSetDiscountPercentConfig} from "./structs/JB721TiersSetDiscountPercentConfig.sol";

/// @title JB721TiersHook
/// @notice A Juicebox project can use this hook to sell tiered ERC-721 NFTs with different prices and metadata. When
/// the project is paid, the hook may mint NFTs to the payer, depending on the hook's setup, the amount paid, and
/// information specified by the payer. The project's owner can enable NFT cash outs through this hook, allowing
/// holders to burn their NFTs to reclaim funds from the project (in proportion to the NFT's price).
contract JB721TiersHook is JBOwnable, ERC2771Context, JB721Hook, IJB721TiersHook {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JB721TiersHook_AlreadyInitialized(uint256 projectId);
    error JB721TiersHook_CantBuyWithCredits();
    error JB721TiersHook_InvalidPricingDecimals(uint256 decimals);
    error JB721TiersHook_MintReserveNftsPaused();
    error JB721TiersHook_NoProjectId();
    error JB721TiersHook_Overspending(uint256 leftoverAmount);
    error JB721TiersHook_TierTransfersPaused();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The contract that exposes price feeds for currency conversions.
    IJBPrices public immutable override PRICES;

    /// @notice The contract storing and managing project rulesets.
    IJBRulesets public immutable override RULESETS;

    /// @notice The contract that stores and manages data for this contract's NFTs.
    IJB721TiersHookStore public immutable override STORE;

    /// @notice The contract that stores and manages splits.
    IJBSplits public immutable override SPLITS;

    /// @notice The deployer used to deploy checkpoint module clones during initialization.
    IJB721CheckpointsDeployer internal immutable CHECKPOINTS_DEPLOYER;

    //*********************************************************************//
    // --------------------- private stored properties ------------------ //
    //*********************************************************************//

    /// @notice Whether this contract has been initialized. Used to prevent re-initialization of both the
    /// implementation contract itself and its clones.
    /// @dev Internal (not private) so test harnesses that extend this contract can reset it in their constructors.
    bool internal _initialized;

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice The base URI for the NFT `tokenUris`.
    string public override baseURI;

    /// @notice This contract's metadata URI.
    string public override contractURI;

    /// @notice If an address pays more than the price of the NFT they received, the extra amount is stored as credits
    /// which can be cashed out to mint NFTs.
    /// @custom:param addr The address to get the NFT credits balance of.
    /// @return The amount of credits the address has.
    mapping(address addr => uint256) public override payCreditsOf;

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /// @notice The first owner of each token ID, stored on first transfer out.
    /// @custom:param The token ID of the NFT to get the stored first owner of.
    mapping(uint256 tokenId => address) internal _firstOwnerOf;

    /// @notice Packed context for the pricing of this contract's tiers.
    /// @dev Packed into a uint256:
    /// - currency in bits 0-31 (32 bits), and
    /// - pricing decimals in bits 32-39 (8 bits).
    uint256 internal _packedPricingContext;

    /// @notice The checkpoint module that manages IVotes-compatible checkpointed voting power for this hook's NFTs.
    /// @dev Lazily deployed on the first transfer. Pass this to JBTokenDistributor as the IVotes token.
    IJB721Checkpoints public override CHECKPOINTS;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param directory A directory of terminals and controllers for projects.
    /// @param permissions A contract storing permissions.
    /// @param prices A contract that exposes price feeds for currency conversions.
    /// @param rulesets A contract storing and managing project rulesets.
    /// @param store The contract which stores the NFT's data.
    /// @param splits The contract that stores and manages splits.
    /// @param checkpointsDeployer The deployer used to deploy checkpoint module clones during initialization.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBPrices prices,
        IJBRulesets rulesets,
        IJB721TiersHookStore store,
        IJBSplits splits,
        IJB721CheckpointsDeployer checkpointsDeployer,
        address trustedForwarder
    )
        JBOwnable(permissions, directory.PROJECTS(), msg.sender, uint88(0))
        JB721Hook(directory)
        ERC2771Context(trustedForwarder)
    {
        PRICES = prices;
        RULESETS = rulesets;
        STORE = store;
        SPLITS = splits;
        CHECKPOINTS_DEPLOYER = checkpointsDeployer;

        // Prevent the implementation contract from being initialized.
        _initialized = true;
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice The address that originally received an NFT (typically the payer). Tracked separately from the current
    /// owner so it persists through transfers, useful for provenance and historical voting checkpoints.
    /// @param tokenId The token ID of the NFT.
    /// @return The address of the NFT's first owner.
    function firstOwnerOf(uint256 tokenId) external view override returns (address) {
        address first = _firstOwnerOf[tokenId];
        return first != address(0) ? first : _ownerOf(tokenId);
    }

    /// @notice The currency and decimal precision used for this hook's tier prices. For example, if tiers are priced
    /// in ETH with 18 decimals, `currency` would be the ETH currency ID and `decimals` would be 18.
    /// @return currency The currency used for tier prices.
    /// @return decimals The number of decimals used in tier prices.
    function pricingContext() external view override returns (uint256 currency, uint256 decimals) {
        // Get a reference to the packed pricing context.
        uint256 packed = _packedPricingContext;
        // currency in bits 0-31 (32 bits).
        // forge-lint: disable-next-line(unsafe-typecast)
        currency = uint256(uint32(packed));
        // pricing decimals in bits 32-39 (8 bits).
        // forge-lint: disable-next-line(unsafe-typecast)
        decimals = uint256(uint8(packed >> 32));
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice The total number of this hook's NFTs that an address holds (from all tiers).
    /// @param owner The address to check the balance of.
    /// @return balance The number of NFTs the address owns across this hook's tiers.
    function balanceOf(address owner) public view override returns (uint256 balance) {
        return STORE.balanceOf({hook: address(this), owner: owner});
    }

    /// @notice Called by the terminal before recording a payment. Calculates how much of the payment should be routed
    /// to tier-based splits vs. kept by the project, and adjusts the minting weight accordingly.
    /// @dev Overrides the base to compute tier split amounts from each tier's `splitPercent`.
    /// @param context The payment context from the terminal.
    /// @return weight The adjusted weight for project token minting (reduced when splits route funds away).
    /// @return hookSpecifications Specifies this hook as the pay hook, with the split amount to forward.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        public
        view
        virtual
        override(JB721Hook, IJBRulesetDataHook)
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        hookSpecifications = new JBPayHookSpecification[](1);

        // Compute split amounts, adjusted weight, and resolved beneficiary in a single library call.
        uint256 totalSplitAmount;
        bytes memory splitMetadata;
        address beneficiary;
        uint256 splitCreditWeight;
        (weight, totalSplitAmount, splitMetadata, beneficiary, splitCreditWeight) =
            JB721TiersHookLib.computeSplitsAndWeight({
                store: STORE,
                metadataIdTarget: METADATA_ID_TARGET,
                packedPricingContext: _packedPricingContext,
                prices: PRICES,
                context: context
            });

        hookSpecifications[0] = JBPayHookSpecification({
            hook: this,
            noop: false,
            amount: totalSplitAmount,
            metadata: abi.encode(beneficiary, context.payer, splitMetadata, splitCreditWeight)
        });
    }

    /// @notice The combined cash-out weight of specific NFTs. Divide by `totalCashOutWeight()` to get the fraction of
    /// surplus these NFTs can reclaim. Weight is based on the original tier price, not any discount paid.
    /// @param tokenIds The token IDs of the NFTs to get the combined cash-out weight of.
    /// @return weight The combined cash-out weight.
    function cashOutWeightOf(uint256[] memory tokenIds) public view virtual override returns (uint256) {
        return STORE.cashOutWeightOf({hook: address(this), tokenIds: tokenIds});
    }

    /// @notice Initializes a cloned copy of the original hook contract.
    /// @param projectId The ID of the project this this hook is associated with.
    /// @param name The name of the NFT collection.
    /// @param symbol The symbol representing the NFT collection.
    /// @param baseUri The URI to use as a base for full NFT `tokenUri`s.
    /// @param tokenUriResolver An optional contract responsible for resolving the token URI for each NFT's token ID.
    /// @param contractUri A URI where this contract's metadata can be found.
    /// @param tiersConfig The NFT tiers and pricing context to initialize the hook with. The tiers must be sorted by
    /// category (from least to greatest).
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
        public
        override
    {
        // Stop re-initialization. This protects both the implementation contract (initialized in constructor)
        // and clones (initialized via this function).
        if (_initialized) revert JB721TiersHook_AlreadyInitialized(PROJECT_ID);
        _initialized = true;

        // Make sure a projectId is provided.
        if (projectId == 0) revert JB721TiersHook_NoProjectId();

        // Initialize the superclass.
        JB721Hook._initialize({projectId: projectId, name: name, symbol: symbol});

        // Validate pricing decimals are within a reasonable range.
        if (tiersConfig.decimals > 18) revert JB721TiersHook_InvalidPricingDecimals(tiersConfig.decimals);

        // Pack pricing context from the `tiersConfig`.
        uint256 packed;
        // pack the currency in bits 0-31 (32 bits).
        packed |= uint256(tiersConfig.currency);
        // pack the pricing decimals in bits 32-39 (8 bits).
        packed |= uint256(tiersConfig.decimals) << 32;
        // Store the packed value.
        // slither-disable-next-line events-maths
        _packedPricingContext = packed;

        // Store the base URI if provided.
        if (bytes(baseUri).length != 0) baseURI = baseUri;

        // Set the contract URI if provided.
        if (bytes(contractUri).length != 0) contractURI = contractUri;

        // Set the token URI resolver if provided.
        if (tokenUriResolver != IJB721TokenUriResolver(address(0))) {
            _recordSetTokenUriResolver(tokenUriResolver);
        }

        // Record the tiers in this hook's store and set any tier split groups.
        if (tiersConfig.tiers.length != 0) {
            JB721TiersHookLib.recordAddTiersFor({
                store: STORE,
                splits: SPLITS,
                projectId: projectId,
                hookAddress: address(this),
                caller: _msgSender(),
                tiersToAdd: tiersConfig.tiers
            });
        }

        // Set the flags if needed.
        if (
            flags.noNewTiersWithReserves || flags.noNewTiersWithVotes || flags.noNewTiersWithOwnerMinting
                || flags.preventOverspending || flags.issueTokensForSplits
        ) STORE.recordFlags(flags);

        // Transfer ownership to the initializer.
        _transferOwnership(_msgSender());
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param interfaceId The ID of the interface to check for adherence to.
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, JB721Hook) returns (bool) {
        return interfaceId == type(IJB721TiersHook).interfaceId || JB721Hook.supportsInterface(interfaceId);
    }

    /// @notice The metadata URI of the NFT with the specified token ID.
    /// @dev Defers to the `tokenUriResolver` if it is set. Otherwise, use the `tokenUri` corresponding with the NFT's
    /// tier.
    /// @param tokenId The token ID of the NFT to get the metadata URI of.
    /// @return The token URI from the `tokenUriResolver` if it is set. If it isn't set, the token URI for the NFT's
    /// tier.
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return JB721TiersHookLib.resolveTokenURI(STORE, address(this), baseURI, tokenId);
    }

    /// @notice The total cash-out weight across all outstanding NFTs and pending reserves. This is the denominator
    /// for cash-out calculations — an NFT's share of the surplus is its weight divided by this total.
    /// @return weight The total cash-out weight.
    function totalCashOutWeight() public view virtual override returns (uint256) {
        return STORE.totalCashOutWeight(address(this));
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Add new NFT tiers or remove existing ones. Added tiers get sequential IDs and must be sorted by
    /// category. Removed tiers stop accepting new mints but existing NFTs remain valid.
    /// @dev Only the collection owner or an operator with `ADJUST_721_TIERS` permission can call this.
    /// @dev Added tiers must respect this hook's flags (e.g. `noNewTiersWithVotes`, `noNewTiersWithReserves`).
    /// @param tiersToAdd The tiers to add, as an array of `JB721TierConfig` structs.
    /// @param tierIdsToRemove The IDs of the tiers to remove.
    function adjustTiers(JB721TierConfig[] calldata tiersToAdd, uint256[] calldata tierIdsToRemove) external override {
        // Enforce permissions.
        _requirePermissionFrom({
            account: owner(), projectId: PROJECT_ID, permissionId: JBPermissionIds.ADJUST_721_TIERS
        });

        // Delegate to the library (via DELEGATECALL) for tier removal, addition, event emission, and split setting.
        JB721TiersHookLib.adjustTiersFor({
            store: STORE,
            splits: SPLITS,
            projectId: PROJECT_ID,
            hookAddress: address(this),
            caller: _msgSender(),
            tiersToAdd: tiersToAdd,
            tierIdsToRemove: tierIdsToRemove
        });
    }

    /// @notice Manually mint NFTs from specific tiers to a beneficiary, without requiring payment. Only tiers with
    /// `allowOwnerMint` enabled can be minted this way.
    /// @dev Only the collection owner or an operator with `MINT_721` permission can call this.
    /// @param tierIds The IDs of the tiers to mint from.
    /// @param beneficiary The address to mint the NFTs to.
    /// @return tokenIds The IDs of the newly minted tokens.
    function mintFor(
        uint16[] calldata tierIds,
        address beneficiary
    )
        external
        override
        returns (uint256[] memory tokenIds)
    {
        // Enforce permissions.
        _requirePermissionFrom({account: owner(), projectId: PROJECT_ID, permissionId: JBPermissionIds.MINT_721});

        // Record the mint. The token IDs returned correspond to the tiers passed in.
        // slither-disable-next-line reentrancy-events,unused-return
        (tokenIds,,) = STORE.recordMint({
            amount: type(uint256).max, // force the mint.
            tierIds: tierIds,
            isOwnerMint: true // manual mint.
        });

        _mintTokens({tokenIds: tokenIds, tierIds: tierIds, beneficiary: beneficiary, totalAmountPaid: 0});
    }

    /// @notice Mint pending reserved NFTs across multiple tiers in a single call. Reserves accumulate automatically
    /// as NFTs are sold (based on each tier's `reserveFrequency`) and anyone can trigger their minting.
    /// @param reserveMintConfigs The tier IDs and counts specifying how many reserves to mint from each tier.
    function mintPendingReservesFor(JB721TiersMintReservesConfig[] calldata reserveMintConfigs) external override {
        for (uint256 i; i < reserveMintConfigs.length;) {
            // Get a reference to the params being iterated upon.
            JB721TiersMintReservesConfig memory params = reserveMintConfigs[i];

            // Mint pending reserved NFTs from the tier.
            mintPendingReservesFor({tierId: params.tierId, count: params.count});

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Set a discount on a tier's price. Discounts reduce the price payers must pay, but don't affect the
    /// NFT's cash-out weight (which always uses the original price). The tier must have `cannotIncreaseDiscountPercent`
    /// set appropriately.
    /// @dev Only the collection owner or an operator with `SET_721_DISCOUNT_PERCENT` permission can call this.
    /// @param tierId The ID of the tier to set the discount of.
    /// @param discountPercent The discount percent to set (0–100).
    function setDiscountPercentOf(uint256 tierId, uint256 discountPercent) external override {
        // Enforce permissions.
        _requirePermissionFrom({
            account: owner(), projectId: PROJECT_ID, permissionId: JBPermissionIds.SET_721_DISCOUNT_PERCENT
        });
        _setDiscountPercentOf({tierId: tierId, discountPercent: discountPercent});
    }

    /// @notice Set discount percentages for multiple tiers in a single call.
    /// @dev Only the collection owner or an operator with `SET_721_DISCOUNT_PERCENT` permission can call this.
    /// @param configs An array of tier ID + discount percent pairs to apply.
    function setDiscountPercentsOf(JB721TiersSetDiscountPercentConfig[] calldata configs) external override {
        // Enforce permissions.
        _requirePermissionFrom({
            account: owner(), projectId: PROJECT_ID, permissionId: JBPermissionIds.SET_721_DISCOUNT_PERCENT
        });

        for (uint256 i; i < configs.length;) {
            // Set the config being iterated on.
            JB721TiersSetDiscountPercentConfig memory config = configs[i];

            _setDiscountPercentOf({tierId: config.tierId, discountPercent: config.discountPercent});

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Update this hook's metadata properties.
    /// @dev Only this contract's owner or an operator with the `SET_721_METADATA` permission can set the metadata.
    /// @param name The new collection name. Send empty to leave unchanged.
    /// @param symbol The new collection symbol. Send empty to leave unchanged.
    /// @param baseUri The new base URI. Send empty to leave unchanged.
    /// @param contractUri The new contract URI. Send empty to leave unchanged.
    /// @param tokenUriResolver The new URI resolver. Pass `IJB721TokenUriResolver(address(this))` as a sentinel value
    /// to leave unchanged. `address(this)` is used instead of `address(0)` because `address(0)` is a valid value that
    /// clears the resolver.
    /// @param encodedIPFSUriTierId The ID of the tier to set the encoded IPFS URI of.
    /// @param encodedIPFSUri The encoded IPFS URI to set.
    function setMetadata(
        string calldata name,
        string calldata symbol,
        string calldata baseUri,
        string calldata contractUri,
        IJB721TokenUriResolver tokenUriResolver,
        uint256 encodedIPFSUriTierId,
        bytes32 encodedIPFSUri
    )
        external
        override
    {
        // Enforce permissions.
        _requirePermissionFrom({
            account: owner(), projectId: PROJECT_ID, permissionId: JBPermissionIds.SET_721_METADATA
        });

        // Cache _msgSender() at function entry to avoid repeated calls.
        address caller = _msgSender();

        if (bytes(name).length != 0) {
            // Store the new collection name.
            _setName(name);
            emit SetName({name: name, caller: caller});
        }
        if (bytes(symbol).length != 0) {
            // Store the new collection symbol.
            _setSymbol(symbol);
            emit SetSymbol({symbol: symbol, caller: caller});
        }
        if (bytes(baseUri).length != 0) {
            // Store the new base URI.
            baseURI = baseUri;
            emit SetBaseUri({baseUri: baseUri, caller: caller});
        }
        if (bytes(contractUri).length != 0) {
            // Store the new contract URI.
            contractURI = contractUri;
            emit SetContractUri({uri: contractUri, caller: caller});
        }

        // `address(this)` is the sentinel value meaning "leave unchanged" (since `address(0)` clears the resolver).
        if (tokenUriResolver != IJB721TokenUriResolver(address(this))) {
            // Store the new URI resolver.
            // slither-disable-next-line reentrancy-events
            _recordSetTokenUriResolver(tokenUriResolver);
        }
        if (encodedIPFSUriTierId != 0 && encodedIPFSUri != bytes32(0)) {
            emit SetEncodedIPFSUri({tierId: encodedIPFSUriTierId, encodedUri: encodedIPFSUri, caller: caller});

            // Store the new encoded IPFS URI.
            STORE.recordSetEncodedIPFSUriOf({tierId: encodedIPFSUriTierId, encodedIPFSUri: encodedIPFSUri});
        }
    }

    //*********************************************************************//
    // ----------------------- public transactions ----------------------- //
    //*********************************************************************//

    /// @notice Mint pending reserved NFTs from a specific tier. Anyone can call this — reserves are minted to the
    /// tier's reserve beneficiary (or the hook's default). Reverts if the ruleset has reserve minting paused.
    /// @param tierId The ID of the tier to mint reserved NFTs from.
    /// @param count The number of reserved NFTs to mint.
    function mintPendingReservesFor(uint256 tierId, uint256 count) public override {
        // Get a reference to the project's current ruleset.
        JBRuleset memory ruleset = _currentRulesetOf(PROJECT_ID);

        // Pending reserve mints must not be paused.
        if (JB721TiersRulesetMetadataResolver.mintPendingReservesPaused((JBRulesetMetadataResolver.metadata(ruleset))))
        {
            revert JB721TiersHook_MintReserveNftsPaused();
        }

        // Record the reserved mint for the tier.
        // slither-disable-next-line reentrancy-events,calls-loop
        uint256[] memory tokenIds = STORE.recordMintReservesFor({tierId: tierId, count: count});

        // Keep a reference to the beneficiary.
        // slither-disable-next-line calls-loop
        address reserveBeneficiary = STORE.reserveBeneficiaryOf({hook: address(this), tierId: tierId});

        // Cache _msgSender() before the loop to avoid repeated calls.
        address caller = _msgSender();

        for (uint256 i; i < count;) {
            // Set the token ID.
            uint256 tokenId = tokenIds[i];

            emit MintReservedNft({tokenId: tokenId, tierId: tierId, beneficiary: reserveBeneficiary, caller: caller});

            // Mint the NFT.
            // slither-disable-next-line reentrency-events
            _mint({to: reserveBeneficiary, tokenId: tokenId});

            unchecked {
                ++i;
            }
        }
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @dev ERC-2771 specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view virtual override(ERC2771Context, Context) returns (uint256) {
        return super._contextSuffixLength();
    }

    /// @notice The project's current ruleset.
    /// @param projectId The ID of the project to check.
    /// @return The project's current ruleset.
    function _currentRulesetOf(uint256 projectId) internal view returns (JBRuleset memory) {
        // slither-disable-next-line calls-loop
        return RULESETS.currentOf(projectId);
    }

    /// @notice Returns the calldata, preferred to use over `msg.data`
    /// @return calldata the `msg.data` of this call
    function _msgData() internal view virtual override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice Returns the sender, preferred to use over `msg.sender`
    /// @return sender the sender address of this call.
    function _msgSender() internal view virtual override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice A function which gets called after NFTs have been cashed out and recorded by the terminal.
    /// @param tokenIds The token IDs of the NFTs that were burned.
    function _didBurn(uint256[] memory tokenIds) internal virtual override {
        // Add to burned counter.
        STORE.recordBurn(tokenIds);
    }

    /// @notice Mints NFTs and emits events for each.
    /// @param tokenIds The token IDs to mint.
    /// @param tierIds The tier IDs corresponding to each token.
    /// @param beneficiary The address receiving the NFTs.
    /// @param totalAmountPaid The amount to report in the Mint event.
    function _mintTokens(
        uint256[] memory tokenIds,
        uint16[] memory tierIds,
        address beneficiary,
        uint256 totalAmountPaid
    )
        internal
    {
        // Cache _msgSender() before the loop to avoid repeated calls.
        address caller = _msgSender();

        for (uint256 i; i < tokenIds.length;) {
            emit Mint({
                tokenId: tokenIds[i],
                tierId: tierIds[i],
                beneficiary: beneficiary,
                totalAmountPaid: totalAmountPaid,
                caller: caller
            });

            // slither-disable-next-line reentrancy-events
            _mint({to: beneficiary, tokenId: tokenIds[i]});

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Mint NFTs from the specified tiers and update the beneficiary's pay credits.
    /// @param value The normalized payment value.
    /// @param payer The address that initiated the payment.
    /// @param payerMetadata The metadata provided by the payer.
    /// @param beneficiary The address to mint NFTs to and track credits for.
    function _mintAndUpdateCredits(
        uint256 value,
        address payer,
        bytes calldata payerMetadata,
        address beneficiary
    )
        internal
    {
        // Keep a reference to the number of NFT credits the beneficiary already has.
        uint256 payCredits = payCreditsOf[beneficiary];

        // Compute the mint: combine credits, decode metadata, record mint, and check overspending.
        (uint256[] memory tokenIds, uint16[] memory tierIdsToMint, uint256 newPayCredits) = JB721TiersHookLib.prepareMint({
            store: STORE,
            metadataIdTarget: METADATA_ID_TARGET,
            value: value,
            payer: payer,
            beneficiary: beneficiary,
            payCredits: payCredits,
            payerMetadata: payerMetadata
        });

        // Mint each token to the effective beneficiary.
        if (tokenIds.length != 0) {
            // totalAmountPaid is the full amount available before recordMint deducted tier prices.
            uint256 totalAmountPaid = (payer == beneficiary) ? value + payCredits : value;
            // slither-disable-next-line reentrancy-events
            _mintTokens({
                tokenIds: tokenIds, tierIds: tierIdsToMint, beneficiary: beneficiary, totalAmountPaid: totalAmountPaid
            });
        }

        // Update NFT credits if they changed.
        if (newPayCredits != payCredits) {
            if (newPayCredits > payCredits) {
                emit AddPayCredits({
                    amount: newPayCredits - payCredits,
                    newTotalCredits: newPayCredits,
                    account: beneficiary,
                    caller: _msgSender()
                });
            } else {
                emit UsePayCredits({
                    amount: payCredits - newPayCredits,
                    newTotalCredits: newPayCredits,
                    account: beneficiary,
                    caller: _msgSender()
                });
            }

            // slither-disable-next-line reentrancy-no-eth
            payCreditsOf[beneficiary] = newPayCredits;
        }
    }

    /// @notice Process a payment, minting NFTs and updating credits as necessary.
    /// @dev Pay credits are tracked per beneficiary, not per payer. When the payer differs from the beneficiary,
    /// the payer's existing credits are NOT applied to the mint. Only the beneficiary's credits are combined with
    /// the incoming payment value. Leftover funds after minting are stored as credits for the beneficiary.
    /// @param context Payment context provided by the terminal after it has recorded the payment in the terminal store.
    function _processPayment(JBAfterPayRecordedContext calldata context) internal virtual override {
        // Normalize the payment value based on the pricing context.
        bool valid;
        uint256 value;
        (value, valid) = JB721TiersHookLib.normalizePaymentValue({
            packedPricingContext: _packedPricingContext,
            prices: PRICES,
            projectId: PROJECT_ID,
            amountValue: context.amount.value,
            amountCurrency: context.amount.currency,
            amountDecimals: context.amount.decimals
        });
        if (!valid) return;

        // Decode the beneficiary and payer forwarded from beforePayRecordedWith.
        address beneficiary;
        address payer;
        bytes memory splitData;
        if (context.hookMetadata.length != 0) {
            (beneficiary, payer, splitData) = abi.decode(context.hookMetadata, (address, address, bytes));
        }
        // Fall back to context values if none were forwarded.
        if (beneficiary == address(0)) beneficiary = context.beneficiary;
        if (payer == address(0)) payer = context.payer;

        // Mint NFTs from the specified tiers and update the beneficiary's pay credits.
        _mintAndUpdateCredits({
            value: value, payer: payer, payerMetadata: context.payerMetadata, beneficiary: beneficiary
        });

        // Distribute any forwarded funds to tier split groups.
        if (splitData.length != 0 && context.forwardedAmount.value != 0) {
            JB721TiersHookLib.distributeAll({
                directory: DIRECTORY,
                splits: SPLITS,
                projectId: PROJECT_ID,
                hookAddress: address(this),
                token: context.forwardedAmount.token,
                amount: context.forwardedAmount.value,
                decimals: context.forwardedAmount.decimals,
                encodedSplitData: splitData
            });
        }
    }

    /// @notice Record the setting of a new token URI resolver.
    /// @param tokenUriResolver The new token URI resolver.
    function _recordSetTokenUriResolver(IJB721TokenUriResolver tokenUriResolver) internal {
        emit SetTokenUriResolver({resolver: tokenUriResolver, caller: _msgSender()});

        STORE.recordSetTokenUriResolver(tokenUriResolver);
    }

    /// @notice Internal function to set the discount percent for a tier.
    /// @param tierId The ID of the tier to set the discount percent for.
    /// @param discountPercent The discount percent to set for the tier.
    function _setDiscountPercentOf(uint256 tierId, uint256 discountPercent) internal {
        // slither-disable-next-line calls-loop
        JB721TiersHookLib.setDiscountPercentOf({
            store: STORE, tierId: tierId, discountPercent: discountPercent, caller: _msgSender()
        });
    }

    /// @notice Before transferring an NFT, register its first owner (if necessary).
    /// @param to The address the NFT is being transferred to.
    /// @param tokenId The token ID of the NFT being transferred.
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address from) {
        // Get only the tier ID and transfersPausable flag (lightweight — avoids full struct construction).
        // slither-disable-next-line calls-loop
        (uint256 tierId, bool transfersPausable) =
            STORE.tierTransferInfoOfTokenId({hook: address(this), tokenId: tokenId});

        // Record the transfers and keep a reference to where the token is coming from.
        from = super._update({to: to, tokenId: tokenId, auth: auth});

        // Transfers must not be paused (when not minting or burning).
        if (from != address(0)) {
            // If transfers are pausable, check if they're paused.
            if (transfersPausable) {
                // Get a reference to the project's current ruleset.
                JBRuleset memory ruleset = _currentRulesetOf(PROJECT_ID);

                // If transfers are paused and the NFT isn't being transferred to the zero address, revert.
                if (
                    to != address(0)
                        && JB721TiersRulesetMetadataResolver.transfersPaused(
                            (JBRulesetMetadataResolver.metadata(ruleset))
                        )
                ) revert JB721TiersHook_TierTransfersPaused();
            }

            // If the token isn't already associated with a first owner, store the sender as the first owner.
            // slither-disable-next-line calls-loop
            if (_firstOwnerOf[tokenId] == address(0)) _firstOwnerOf[tokenId] = from;
        }

        // Record the transfer.
        // slither-disable-next-line reentrency-events,calls-loop
        STORE.recordTransferForTier({tierId: tierId, from: from, to: to});

        // Deploy the checkpoint module lazily on the first transfer.
        if (address(CHECKPOINTS) == address(0)) {
            // slither-disable-next-line calls-loop,reentrancy-events
            CHECKPOINTS = CHECKPOINTS_DEPLOYER.deploy(address(this));
        }

        // Notify the checkpoint module to update checkpointed voting power.
        // slither-disable-next-line calls-loop,reentrancy-events
        CHECKPOINTS.onTransfer({from: from, to: to, tokenId: tokenId});
    }
}
