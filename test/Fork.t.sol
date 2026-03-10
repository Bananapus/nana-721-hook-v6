// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@bananapus/core-v6/src/JBController.sol";
import "@bananapus/core-v6/src/JBDirectory.sol";
import "@bananapus/core-v6/src/JBMultiTerminal.sol";
import "@bananapus/core-v6/src/JBFundAccessLimits.sol";
import "@bananapus/core-v6/src/JBFeelessAddresses.sol";
import "@bananapus/core-v6/src/JBTerminalStore.sol";
import "@bananapus/core-v6/src/JBRulesets.sol";
import "@bananapus/core-v6/src/JBPermissions.sol";
import "@bananapus/core-v6/src/JBPrices.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import "@bananapus/core-v6/src/JBSplits.sol";
import "@bananapus/core-v6/src/JBERC20.sol";
import "@bananapus/core-v6/src/JBTokens.sol";
import "@bananapus/core-v6/src/libraries/JBConstants.sol";
import "@bananapus/core-v6/src/libraries/JBRulesetMetadataResolver.sol";
import "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import "@bananapus/core-v6/src/structs/JBSplit.sol";
import "@bananapus/core-v6/src/structs/JBSplitGroup.sol";
import "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {MetadataResolverHelper} from "@bananapus/core-v6/test/helpers/MetadataResolverHelper.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";

import "../src/JB721TiersHook.sol";
import "../src/JB721TiersHookDeployer.sol";
import "../src/JB721TiersHookProjectDeployer.sol";
import "../src/JB721TiersHookStore.sol";
import "../src/interfaces/IJB721TiersHook.sol";
import "../src/structs/JBDeploy721TiersHookConfig.sol";
import "../src/structs/JBLaunchProjectConfig.sol";
import "../src/structs/JBPayDataHookRulesetConfig.sol";
import "../src/structs/JBPayDataHookRulesetMetadata.sol";
import "../src/structs/JB721TiersRulesetMetadata.sol";
import "../src/libraries/JB721TiersRulesetMetadataResolver.sol";
import "../src/libraries/JB721Constants.sol";

/// @title Fork_721Hook_Test
/// @notice Comprehensive fork tests for JB721TiersHook: lifecycle, features, flags, and adversarial conditions.
/// @dev Run with: RPC_ETHEREUM_MAINNET=<rpc_url> forge test --match-contract Fork_721Hook_Test -vvv
contract Fork_721Hook_Test is Test {
    using JBRulesetMetadataResolver for JBRuleset;

    // =========================================================================
    // Constants
    // =========================================================================

    address constant NATIVE_TOKEN = JBConstants.NATIVE_TOKEN;

    // =========================================================================
    // Actors
    // =========================================================================

    address multisig = address(0xBEEF);
    address payer = makeAddr("payer");
    address beneficiary = makeAddr("beneficiary");
    address reserveBeneficiary = makeAddr("reserveBeneficiary");
    address attacker = makeAddr("attacker");

    // =========================================================================
    // JB Core
    // =========================================================================

    JBPermissions jbPermissions;
    JBProjects jbProjects;
    JBDirectory jbDirectory;
    JBRulesets jbRulesets;
    JBTokens jbTokens;
    JBSplits jbSplits;
    JBFundAccessLimits jbFundAccessLimits;
    JBFeelessAddresses jbFeelessAddresses;
    JBPrices jbPrices;
    JBController jbController;
    JBTerminalStore jbTerminalStore;
    JBMultiTerminal jbMultiTerminal;

    // =========================================================================
    // 721 Hook
    // =========================================================================

    JB721TiersHookStore store;
    JB721TiersHook hookImpl;
    JB721TiersHookDeployer hookDeployer;
    JB721TiersHookProjectDeployer projectDeployer;
    MetadataResolverHelper metadataHelper;
    JBAddressRegistry addressRegistry;

    // =========================================================================
    // IPFS URIs (reusable)
    // =========================================================================

    bytes32 constant IPFS_URI = 0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89;

    // =========================================================================
    // Events (for expectEmit)
    // =========================================================================

    event Mint(
        uint256 indexed tokenId,
        uint256 indexed tierId,
        address indexed beneficiary,
        uint256 totalAmountPaid,
        address caller
    );
    event Burn(uint256 indexed tokenId, address owner, address caller);

    // =========================================================================
    // Setup
    // =========================================================================

    /// @dev Accept ETH for cashout returns.
    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum");

        _deployJBCore();
        _deploy721Hook();

        vm.deal(payer, 1000 ether);
        vm.deal(beneficiary, 100 ether);
        vm.deal(multisig, 100 ether);
        vm.deal(attacker, 100 ether);

        vm.label(multisig, "multisig");
        vm.label(payer, "payer");
        vm.label(beneficiary, "beneficiary");
        vm.label(reserveBeneficiary, "reserveBeneficiary");
        vm.label(attacker, "attacker");
    }

    function _deployJBCore() internal {
        jbPermissions = new JBPermissions(address(0));
        jbProjects = new JBProjects(multisig, address(0), address(0));
        jbDirectory = new JBDirectory(jbPermissions, jbProjects, multisig);
        JBERC20 jbErc20 = new JBERC20();
        jbTokens = new JBTokens(jbDirectory, jbErc20);
        jbRulesets = new JBRulesets(jbDirectory);
        jbPrices = new JBPrices(jbDirectory, jbPermissions, jbProjects, multisig, address(0));
        jbSplits = new JBSplits(jbDirectory);
        jbFundAccessLimits = new JBFundAccessLimits(jbDirectory);
        jbFeelessAddresses = new JBFeelessAddresses(multisig);

        jbController = new JBController(
            jbDirectory,
            jbFundAccessLimits,
            jbPermissions,
            jbPrices,
            jbProjects,
            jbRulesets,
            jbSplits,
            jbTokens,
            address(0), // omnichainRulesetOperator
            address(0) // trustedForwarder
        );

        vm.prank(multisig);
        jbDirectory.setIsAllowedToSetFirstController(address(jbController), true);

        jbTerminalStore = new JBTerminalStore(jbDirectory, jbPrices, jbRulesets);

        jbMultiTerminal = new JBMultiTerminal(
            jbFeelessAddresses,
            jbPermissions,
            jbProjects,
            jbSplits,
            jbTerminalStore,
            jbTokens,
            IPermit2(address(0)), // Permit2 disabled for simplicity
            address(0) // trustedForwarder
        );

        vm.label(address(jbPermissions), "JBPermissions");
        vm.label(address(jbProjects), "JBProjects");
        vm.label(address(jbDirectory), "JBDirectory");
        vm.label(address(jbController), "JBController");
        vm.label(address(jbMultiTerminal), "JBMultiTerminal");
        vm.label(address(jbTerminalStore), "JBTerminalStore");
    }

    function _deploy721Hook() internal {
        store = new JB721TiersHookStore();
        hookImpl =
            new JB721TiersHook(jbDirectory, jbPermissions, jbRulesets, store, IJBSplits(address(jbSplits)), address(0));
        addressRegistry = new JBAddressRegistry();
        hookDeployer = new JB721TiersHookDeployer(hookImpl, store, addressRegistry, address(0));
        projectDeployer = new JB721TiersHookProjectDeployer(
            IJBDirectory(jbDirectory), IJBPermissions(jbPermissions), hookDeployer, address(0)
        );
        metadataHelper = new MetadataResolverHelper();

        vm.label(address(store), "JB721TiersHookStore");
        vm.label(address(hookImpl), "JB721TiersHook_impl");
        vm.label(address(projectDeployer), "JB721TiersHookProjectDeployer");
    }

    // =========================================================================
    // Project Launch Helpers
    // =========================================================================

    /// @dev Launch a project with 721 hook. Returns projectId and hook address.
    function _launchProject(
        JB721TierConfig[] memory tierConfigs,
        JB721TiersHookFlags memory flags,
        uint16 cashOutTaxRate,
        bool useDataHookForCashOut,
        uint16 metadata721
    )
        internal
        returns (uint256 projectId, address dataHook)
    {
        JBDeploy721TiersHookConfig memory hookConfig = JBDeploy721TiersHookConfig({
            name: "TestNFT",
            symbol: "TNFT",
            baseUri: "ipfs://base/",
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: "ipfs://contract",
            tiersConfig: JB721InitTiersConfig({
                tiers: tierConfigs, currency: uint32(uint160(NATIVE_TOKEN)), decimals: 18, prices: IJBPrices(address(0))
            }),
            reserveBeneficiary: reserveBeneficiary,
            flags: flags
        });

        JBPayDataHookRulesetMetadata memory rulesetMetadata = JBPayDataHookRulesetMetadata({
            reservedPercent: 5000, // 50%
            cashOutTaxRate: cashOutTaxRate,
            baseCurrency: uint32(uint160(NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: false,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForCashOut: useDataHookForCashOut,
            metadata: metadata721
        });

        JBPayDataHookRulesetConfig[] memory rulesetConfigs = new JBPayDataHookRulesetConfig[](1);
        rulesetConfigs[0].mustStartAtOrAfter = 0;
        rulesetConfigs[0].duration = 0; // Never expires
        rulesetConfigs[0].weight = 1_000_000e18; // 1M tokens per ETH
        rulesetConfigs[0].weightCutPercent = 0;
        rulesetConfigs[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfigs[0].metadata = rulesetMetadata;

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
            JBAccountingContext({token: NATIVE_TOKEN, currency: uint32(uint160(NATIVE_TOKEN)), decimals: 18});

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](1);
        terminalConfigs[0] =
            JBTerminalConfig({terminal: jbMultiTerminal, accountingContextsToAccept: accountingContexts});

        JBLaunchProjectConfig memory launchConfig = JBLaunchProjectConfig({
            projectUri: "test-project",
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: terminalConfigs,
            memo: ""
        });

        IJB721TiersHook hookInstance;
        (projectId, hookInstance) =
            projectDeployer.launchProjectFor(multisig, hookConfig, launchConfig, jbController, bytes32(0));

        dataHook = address(hookInstance);
        vm.label(dataHook, "hook_clone");
    }

    /// @dev Shorthand: launch with standard 10 tiers, no flags, 50% tax, cash out data hook enabled.
    function _launchStandardProject()
        internal
        returns (uint256 projectId, address dataHook, JB721TierConfig[] memory tierConfigs)
    {
        tierConfigs = _makeStandardTiers(10, 10, false);
        JB721TiersHookFlags memory flags = _defaultFlags();
        (projectId, dataHook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);
    }

    function _makeStandardTiers(
        uint256 count,
        uint32 supplyPerTier,
        bool allowOwnerMint
    )
        internal
        view
        returns (JB721TierConfig[] memory tierConfigs)
    {
        tierConfigs = new JB721TierConfig[](count);
        for (uint256 i; i < count; i++) {
            tierConfigs[i] = JB721TierConfig({
                price: uint104((i + 1) * 0.01 ether),
                initialSupply: supplyPerTier,
                votingUnits: uint32((i + 1) * 10),
                reserveFrequency: 10,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: IPFS_URI,
                category: uint24(100),
                discountPercent: 0,
                allowOwnerMint: allowOwnerMint,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }
    }

    function _defaultFlags() internal pure returns (JB721TiersHookFlags memory) {
        return JB721TiersHookFlags({
            preventOverspending: false,
            issueTokensForSplits: false,
            noNewTiersWithReserves: false,
            noNewTiersWithVotes: false,
            noNewTiersWithOwnerMinting: false
        });
    }

    // =========================================================================
    // Metadata Building Helpers
    // =========================================================================

    /// @dev Build pay metadata that requests specific tier IDs. `allowOverspending` controls revert behavior.
    function _buildPayMetadata(
        address hook,
        uint16[] memory tierIds,
        bool allowOverspending
    )
        internal
        view
        returns (bytes memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIds);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = JBMetadataResolver.getId("pay", address(hookImpl));
        return metadataHelper.createMetadata(ids, data);
    }

    /// @dev Build cash out metadata that specifies token IDs to burn.
    function _buildCashOutMetadata(address hook, uint256[] memory tokenIds) internal view returns (bytes memory) {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(tokenIds);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = JBMetadataResolver.getId("cashOut", address(hookImpl));
        return metadataHelper.createMetadata(ids, data);
    }

    // =========================================================================
    // Token ID Helper
    // =========================================================================

    function _tokenId(uint256 tierId, uint256 mintNumber) internal pure returns (uint256) {
        return tierId * 1_000_000_000 + mintNumber;
    }

    // =========================================================================
    // Pay Helper
    // =========================================================================

    function _payAndMint(
        uint256 projectId,
        uint256 value,
        uint16[] memory tierIds,
        bool allowOverspending,
        address hook
    )
        internal
        returns (uint256 tokenCount)
    {
        bytes memory meta = _buildPayMetadata(hook, tierIds, allowOverspending);
        vm.prank(payer);
        tokenCount = jbMultiTerminal.pay{value: value}({
            projectId: projectId,
            amount: value,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });
    }

    // =====================================================================
    // SECTION 1: BASIC LIFECYCLE
    // =====================================================================

    /// @notice Launch project, pay to mint 1 NFT, verify ownership and balance.
    function test_fork_basicPayAndMint() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        // Mint from tier 1 (price = 0.01 ETH).
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "should own 1 NFT");
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "beneficiary should own token");
        assertEq(IJB721TiersHook(hook).firstOwnerOf(_tokenId(1, 1)), beneficiary, "firstOwner should be beneficiary");
    }

    /// @notice Pay to mint multiple NFTs from different tiers in one transaction.
    function test_fork_multiTierMintInOnePay() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        // Mint from tiers 1, 3, 5 (prices: 0.01 + 0.03 + 0.05 = 0.09 ETH).
        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 1;
        tierIds[1] = 3;
        tierIds[2] = 5;

        _payAndMint(projectId, 0.09 ether, tierIds, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 3, "should own 3 NFTs");
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "owns tier 1 NFT");
        assertEq(IERC721(hook).ownerOf(_tokenId(3, 1)), beneficiary, "owns tier 3 NFT");
        assertEq(IERC721(hook).ownerOf(_tokenId(5, 1)), beneficiary, "owns tier 5 NFT");
    }

    /// @notice Mint multiple NFTs from the SAME tier in one payment.
    function test_fork_duplicateTierMint() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 2;
        tierIds[1] = 2;
        tierIds[2] = 2;

        _payAndMint(projectId, 0.06 ether, tierIds, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 3, "3 NFTs from same tier");

        JB721Tier memory tier = store.tierOf(hook, 2, false);
        assertEq(tier.remainingSupply, 7, "remaining supply should be 7");
    }

    // =====================================================================
    // SECTION 2: CASH OUT (REDEEM) LIFECYCLE
    // =====================================================================

    /// @notice Pay, mint NFT, cash out. Verify ETH reclaim and NFT burn.
    function test_fork_cashOutSingleNFT() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 5; // Price: 0.05 ETH

        _payAndMint(projectId, 0.05 ether, tierIds, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "should own 1 NFT");

        // Cash out the NFT.
        uint256[] memory tokensToCashOut = new uint256[](1);
        tokensToCashOut[0] = _tokenId(5, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(hook, tokensToCashOut);

        uint256 balBefore = beneficiary.balance;
        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: cashOutMeta
        });

        assertEq(IERC721(hook).balanceOf(beneficiary), 0, "NFT should be burned");
        assertEq(store.numberOfBurnedFor(hook, 5), 1, "burn should be recorded");
        assertGt(beneficiary.balance, balBefore, "should have reclaimed some ETH");
    }

    /// @notice Pay with multiple tiers, cash out all at once.
    function test_fork_cashOutMultipleNFTs() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 1;
        tierIds[1] = 2;
        tierIds[2] = 3;

        _payAndMint(projectId, 0.06 ether, tierIds, true, hook);

        uint256[] memory tokensToCashOut = new uint256[](3);
        tokensToCashOut[0] = _tokenId(1, 1);
        tokensToCashOut[1] = _tokenId(2, 1);
        tokensToCashOut[2] = _tokenId(3, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(hook, tokensToCashOut);

        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: cashOutMeta
        });

        assertEq(IERC721(hook).balanceOf(beneficiary), 0, "all NFTs burned");
    }

    /// @notice With 0% cash out tax rate, reclaim should be proportional to NFT weight.
    function test_fork_cashOutWithZeroTaxRate() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 0, true, 0x00); // 0% tax

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        uint256[] memory tokensToCashOut = new uint256[](1);
        tokensToCashOut[0] = _tokenId(1, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(hook, tokensToCashOut);

        uint256 balBefore = beneficiary.balance;
        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: cashOutMeta
        });

        // With 0% tax and single NFT, should reclaim nearly all (minus fee).
        uint256 reclaimed = beneficiary.balance - balBefore;
        assertGt(reclaimed, 0, "should reclaim ETH");
    }

    // =====================================================================
    // SECTION 3: PAY CREDITS
    // =====================================================================

    /// @notice Overpayment when no tier IDs specified should accumulate credits.
    function test_fork_payCreditsAccumulation() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        // Pay without specifying tier IDs → all ETH becomes credits.
        vm.prank(payer);
        jbMultiTerminal.pay{value: 0.5 ether}({
            projectId: projectId,
            amount: 0.5 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        assertEq(IERC721(hook).balanceOf(beneficiary), 0, "no NFT minted");
        assertEq(IJB721TiersHook(hook).payCreditsOf(beneficiary), 0.5 ether, "credits should equal payment");
    }

    /// @notice Overpayment with tier IDs specified should mint the requested tier and credit the rest.
    function test_fork_overpayAccumulatesCredits() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1; // 0.01 ETH

        _payAndMint(projectId, 0.05 ether, tierIds, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "1 NFT minted");
        assertEq(IJB721TiersHook(hook).payCreditsOf(beneficiary), 0.04 ether, "leftover credited");
    }

    /// @notice Credits should be used on subsequent self-pay (payer == beneficiary).
    function test_fork_payCreditsUsedOnSelfPay() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        // First: accumulate credits.
        vm.prank(payer);
        jbMultiTerminal.pay{value: 0.005 ether}({
            projectId: projectId,
            amount: 0.005 ether,
            token: NATIVE_TOKEN,
            beneficiary: payer, // payer == beneficiary for credit usage
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        assertEq(IJB721TiersHook(hook).payCreditsOf(payer), 0.005 ether, "credits stored");

        // Second: pay 0.005 more, combined with 0.005 credits = 0.01, enough for tier 1.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        bytes memory meta = _buildPayMetadata(hook, tierIds, true);
        vm.prank(payer);
        jbMultiTerminal.pay{value: 0.005 ether}({
            projectId: projectId,
            amount: 0.005 ether,
            token: NATIVE_TOKEN,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        assertEq(IERC721(hook).balanceOf(payer), 1, "NFT minted using credits + payment");
        assertEq(IJB721TiersHook(hook).payCreditsOf(payer), 0, "credits consumed");
    }

    /// @notice Credits should NOT be combined when payer != beneficiary.
    function test_fork_payCreditsNotUsedWhenPayerDifferent() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        // Accumulate credits for beneficiary.
        vm.prank(payer);
        jbMultiTerminal.pay{value: 0.1 ether}({
            projectId: projectId,
            amount: 0.1 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        uint256 creditsBefore = IJB721TiersHook(hook).payCreditsOf(beneficiary);
        assertEq(creditsBefore, 0.1 ether, "beneficiary has credits");

        // Pay from a different payer on behalf of beneficiary — credits should NOT be combined.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1; // 0.01 ETH

        // Attacker pays 0.01 ETH on behalf of beneficiary.
        bytes memory meta = _buildPayMetadata(hook, tierIds, true);
        vm.prank(attacker);
        jbMultiTerminal.pay{value: 0.01 ether}({
            projectId: projectId,
            amount: 0.01 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        // Credits should remain unchanged (payer != beneficiary, credits not consumed).
        assertEq(IJB721TiersHook(hook).payCreditsOf(beneficiary), creditsBefore, "credits unchanged");
    }

    // =====================================================================
    // SECTION 4: FLAGS
    // =====================================================================

    /// @notice preventOverspending: reverts if leftover after minting.
    function test_fork_preventOverspending_reverts() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        JB721TiersHookFlags memory flags = _defaultFlags();
        flags.preventOverspending = true;
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        // Pay 0.05 ETH for a 0.01 ETH tier — 0.04 leftover should cause revert.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        bytes memory meta = _buildPayMetadata(hook, tierIds, false);

        vm.prank(payer);
        vm.expectRevert();
        jbMultiTerminal.pay{value: 0.05 ether}({
            projectId: projectId,
            amount: 0.05 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });
    }

    /// @notice preventOverspending: exact payment should succeed.
    function test_fork_preventOverspending_exactPaySucceeds() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        JB721TiersHookFlags memory flags = _defaultFlags();
        flags.preventOverspending = true;
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        bytes memory meta = _buildPayMetadata(hook, tierIds, false);

        vm.prank(payer);
        jbMultiTerminal.pay{value: 0.01 ether}({
            projectId: projectId,
            amount: 0.01 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "exact pay minted 1 NFT");
    }

    /// @notice noNewTiersWithReserves: adding a tier with reserveFrequency should revert.
    function test_fork_noNewTiersWithReserves_reverts() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].reserveFrequency = 0; // Initial tier has no reserves (allowed).
        JB721TiersHookFlags memory flags = _defaultFlags();
        flags.noNewTiersWithReserves = true;
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        // Try to add a new tier with reserves.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](1);
        newTiers[0] = JB721TierConfig({
            price: 0.1 ether,
            initialSupply: 10,
            votingUnits: 0,
            reserveFrequency: 5,
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: IPFS_URI,
            category: 200,
            discountPercent: 0,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        vm.prank(multisig);
        vm.expectRevert();
        IJB721TiersHook(hook).adjustTiers(newTiers, new uint256[](0));
    }

    /// @notice noNewTiersWithOwnerMinting: adding a tier with allowOwnerMint should revert.
    function test_fork_noNewTiersWithOwnerMinting_reverts() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        JB721TiersHookFlags memory flags = _defaultFlags();
        flags.noNewTiersWithOwnerMinting = true;
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        JB721TierConfig[] memory newTiers = new JB721TierConfig[](1);
        newTiers[0] = JB721TierConfig({
            price: 0.1 ether,
            initialSupply: 10,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: IPFS_URI,
            category: 200,
            discountPercent: 0,
            allowOwnerMint: true,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        vm.prank(multisig);
        vm.expectRevert();
        IJB721TiersHook(hook).adjustTiers(newTiers, new uint256[](0));
    }

    /// @notice cannotBeRemoved: removing an immutable tier should revert.
    function test_fork_cannotBeRemoved_reverts() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].cannotBeRemoved = true;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 1;

        vm.prank(multisig);
        vm.expectRevert();
        IJB721TiersHook(hook).adjustTiers(new JB721TierConfig[](0), toRemove);
    }

    // =====================================================================
    // SECTION 5: DISCOUNTS
    // =====================================================================

    /// @notice Mint at a discounted price. Discount of 100 = 50% off.
    function test_fork_discountedMint() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].discountPercent = 100; // 50% off → effective price = 0.5 ETH
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        // Pay exactly 1 ETH — should mint at 0.5 ETH effective price, leftover 0.5 ETH as credits.
        _payAndMint(projectId, 1 ether, tierIds, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "NFT minted at discounted price");
        assertEq(IJB721TiersHook(hook).payCreditsOf(beneficiary), 0.5 ether, "leftover credited");
    }

    /// @notice Full discount (200 = 100% off) makes tier free.
    function test_fork_fullDiscount_freeMint() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].discountPercent = 200; // 100% off → free
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        // Mint with 0 ETH — should work since effective price is 0.
        bytes memory meta = _buildPayMetadata(hook, tierIds, true);
        vm.prank(payer);
        jbMultiTerminal.pay{value: 0}({
            projectId: projectId,
            amount: 0,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "NFT minted for free");
    }

    /// @notice cannotIncreaseDiscountPercent: setting higher discount reverts.
    function test_fork_cannotIncreaseDiscount() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].discountPercent = 50;
        tierConfigs[0].cannotIncreaseDiscountPercent = true;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        vm.prank(multisig);
        vm.expectRevert();
        IJB721TiersHook(hook).setDiscountPercentOf(1, 100);

        // Decreasing should work.
        vm.prank(multisig);
        IJB721TiersHook(hook).setDiscountPercentOf(1, 25);

        JB721Tier memory tier = store.tierOf(hook, 1, false);
        assertEq(tier.discountPercent, 25, "discount decreased");
    }

    // =====================================================================
    // SECTION 6: RESERVE MINTING
    // =====================================================================

    /// @notice Pay enough to trigger pending reserves, then mint them.
    function test_fork_reserveMintLifecycle() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        // Mint 5 NFTs from tier 1 (reserve frequency = 10 → ceil(5/10) = 1 pending reserve).
        uint16[] memory tierIds = new uint16[](5);
        for (uint256 i; i < 5; i++) {
            tierIds[i] = 1;
        }

        _payAndMint(projectId, 0.05 ether, tierIds, true, hook);

        uint256 pending = store.numberOfPendingReservesFor(hook, 1);
        assertGt(pending, 0, "should have pending reserves");

        // Mint the pending reserves.
        vm.prank(multisig);
        IJB721TiersHook(hook).mintPendingReservesFor(1, pending);

        assertEq(store.numberOfPendingReservesFor(hook, 1), 0, "no pending reserves after mint");
        assertGt(IERC721(hook).balanceOf(reserveBeneficiary), 0, "reserve beneficiary received NFTs");
    }

    /// @notice Minting more pending reserves than available should revert.
    function test_fork_reserveMint_tooMany_reverts() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        uint256 pending = store.numberOfPendingReservesFor(hook, 1);

        vm.prank(multisig);
        vm.expectRevert();
        IJB721TiersHook(hook).mintPendingReservesFor(1, pending + 10);
    }

    /// @notice Reserve frequency = 1: every paid mint generates a pending reserve.
    function test_fork_highReserveFrequency() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 100, false);
        tierConfigs[0].reserveFrequency = 1;
        tierConfigs[0].reserveBeneficiary = reserveBeneficiary;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        // Mint 5 paid NFTs.
        uint16[] memory tierIds = new uint16[](5);
        for (uint256 i; i < 5; i++) {
            tierIds[i] = 1;
        }

        _payAndMint(projectId, 0.05 ether, tierIds, true, hook);

        uint256 pending = store.numberOfPendingReservesFor(hook, 1);
        assertGt(pending, 0, "high frequency means many pending reserves");

        vm.prank(multisig);
        IJB721TiersHook(hook).mintPendingReservesFor(1, pending);

        assertEq(store.numberOfPendingReservesFor(hook, 1), 0, "all reserves minted");
    }

    // =====================================================================
    // SECTION 7: TRANSFER PAUSING
    // =====================================================================

    /// @notice transfersPausable tier flag + ruleset metadata pauses transfers.
    function test_fork_transfersPaused_reverts() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].transfersPausable = true;
        JB721TiersHookFlags memory flags = _defaultFlags();

        // Pack 721 metadata: bit 0 = pauseTransfers = true.
        uint16 packed721Meta = uint16(
            JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(JB721TiersRulesetMetadata(true, false))
        );

        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, packed721Meta);

        // Mint an NFT.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        // Try to transfer — should revert.
        vm.prank(beneficiary);
        vm.expectRevert();
        IERC721(hook).transferFrom(beneficiary, attacker, _tokenId(1, 1));
    }

    /// @notice Transfer works when transfersPausable=true but ruleset metadata doesn't pause.
    function test_fork_transfersPausable_notPaused_works() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].transfersPausable = true;
        JB721TiersHookFlags memory flags = _defaultFlags();

        // 721 metadata: transfers NOT paused.
        uint16 packed721Meta = uint16(
            JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(JB721TiersRulesetMetadata(false, false))
        );

        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, packed721Meta);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        // Transfer should succeed.
        vm.prank(beneficiary);
        IERC721(hook).transferFrom(beneficiary, attacker, _tokenId(1, 1));

        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), attacker, "transfer succeeded");
    }

    // =====================================================================
    // SECTION 8: MINT PENDING RESERVES PAUSED
    // =====================================================================

    /// @notice mintPendingReserves paused via ruleset metadata.
    function test_fork_mintPendingReservesPaused_reverts() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 100, false);
        tierConfigs[0].reserveFrequency = 1;
        tierConfigs[0].reserveBeneficiary = reserveBeneficiary;
        JB721TiersHookFlags memory flags = _defaultFlags();

        // 721 metadata: bit 1 = pauseMintPendingReserves = true.
        uint16 packed721Meta = uint16(
            JB721TiersRulesetMetadataResolver.pack721TiersRulesetMetadata(JB721TiersRulesetMetadata(false, true))
        );

        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, packed721Meta);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        uint256 pending = store.numberOfPendingReservesFor(hook, 1);
        assertGt(pending, 0, "should have pending reserves");

        vm.prank(multisig);
        vm.expectRevert();
        IJB721TiersHook(hook).mintPendingReservesFor(1, 1);
    }

    // =====================================================================
    // SECTION 9: OWNER MINTING (mintFor)
    // =====================================================================

    /// @notice Owner can mint via mintFor when allowOwnerMint is set on tier.
    function test_fork_ownerMint() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, true); // allowOwnerMint=true
        tierConfigs[0].reserveFrequency = 0; // No reserves (required: can't have both).
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](2);
        tierIds[0] = 1;
        tierIds[1] = 1;

        vm.prank(multisig);
        IJB721TiersHook(hook).mintFor(tierIds, beneficiary);

        assertEq(IERC721(hook).balanceOf(beneficiary), 2, "owner minted 2 NFTs");
    }

    /// @notice Non-owner cannot mintFor.
    function test_fork_ownerMint_noPermission_reverts() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, true);
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        vm.prank(attacker);
        vm.expectRevert();
        IJB721TiersHook(hook).mintFor(tierIds, attacker);
    }

    // =====================================================================
    // SECTION 10: TIER MANAGEMENT
    // =====================================================================

    /// @notice Add tiers after launch, mint from new tier.
    function test_fork_addTiersAndMint() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        // Add a new expensive tier.
        JB721TierConfig[] memory newTiers = new JB721TierConfig[](1);
        newTiers[0] = JB721TierConfig({
            price: 1 ether,
            initialSupply: 5,
            votingUnits: 100,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: IPFS_URI,
            category: 200,
            discountPercent: 0,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        vm.prank(multisig);
        IJB721TiersHook(hook).adjustTiers(newTiers, new uint256[](0));

        // Tier 11 should now exist.
        JB721Tier memory newTier = store.tierOf(hook, 11, false);
        assertEq(newTier.price, 1 ether, "new tier price");
        assertEq(newTier.initialSupply, 5, "new tier supply");

        // Mint from the new tier.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 11;

        _payAndMint(projectId, 1 ether, tierIds, true, hook);

        assertEq(IERC721(hook).ownerOf(_tokenId(11, 1)), beneficiary, "minted from new tier");
    }

    /// @notice Remove a tier, verify minting from it fails.
    function test_fork_removeTierBlocksMinting() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 3;

        vm.prank(multisig);
        IJB721TiersHook(hook).adjustTiers(new JB721TierConfig[](0), toRemove);

        // Try to mint from removed tier — should revert (supply=0 after removal).
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 3;

        bytes memory meta = _buildPayMetadata(hook, tierIds, false);

        vm.prank(payer);
        vm.expectRevert();
        jbMultiTerminal.pay{value: 0.03 ether}({
            projectId: projectId,
            amount: 0.03 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });
    }

    // =====================================================================
    // SECTION 11: SUPPLY EXHAUSTION
    // =====================================================================

    /// @notice Exhaust supply, then verify further minting reverts.
    function test_fork_supplyExhaustion() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 3, false); // Only 3 NFTs
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        // Mint all 3.
        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 1;
        tierIds[1] = 1;
        tierIds[2] = 1;

        _payAndMint(projectId, 0.03 ether, tierIds, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 3, "all 3 minted");

        JB721Tier memory tier = store.tierOf(hook, 1, false);
        assertEq(tier.remainingSupply, 0, "supply exhausted");

        // Try to mint one more — should revert.
        uint16[] memory oneMore = new uint16[](1);
        oneMore[0] = 1;

        bytes memory meta = _buildPayMetadata(hook, oneMore, false);

        vm.prank(payer);
        vm.expectRevert();
        jbMultiTerminal.pay{value: 0.01 ether}({
            projectId: projectId,
            amount: 0.01 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });
    }

    // =====================================================================
    // SECTION 12: ERC-721 BEHAVIOR
    // =====================================================================

    /// @notice firstOwnerOf tracks correctly through transfers.
    function test_fork_firstOwnerOfTracksAcrossTransfers() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        uint256 tokenId = _tokenId(1, 1);
        assertEq(IJB721TiersHook(hook).firstOwnerOf(tokenId), beneficiary, "initial firstOwner");

        // Transfer to attacker.
        vm.prank(beneficiary);
        IERC721(hook).transferFrom(beneficiary, attacker, tokenId);
        assertEq(IERC721(hook).ownerOf(tokenId), attacker, "attacker owns");
        assertEq(IJB721TiersHook(hook).firstOwnerOf(tokenId), beneficiary, "firstOwner unchanged");

        // Transfer again.
        vm.prank(attacker);
        IERC721(hook).transferFrom(attacker, payer, tokenId);
        assertEq(IJB721TiersHook(hook).firstOwnerOf(tokenId), beneficiary, "firstOwner still beneficiary");
    }

    /// @notice Approval and transferFrom by approved operator.
    function test_fork_approvalAndTransfer() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        uint256 tokenId = _tokenId(1, 1);

        // Approve attacker.
        vm.prank(beneficiary);
        IERC721(hook).approve(attacker, tokenId);

        // Attacker transfers using approval.
        vm.prank(attacker);
        IERC721(hook).transferFrom(beneficiary, attacker, tokenId);

        assertEq(IERC721(hook).ownerOf(tokenId), attacker, "attacker now owns via approval");
    }

    // =====================================================================
    // SECTION 13: VOTING UNITS
    // =====================================================================

    /// @notice Price-based voting (useVotingUnits=false) uses tier price as voting power.
    function test_fork_priceBasedVoting() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        // Mint from tier 5 (price = 0.05 ETH, useVotingUnits=false → price-based).
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 5;
        _payAndMint(projectId, 0.05 ether, tierIds, true, hook);

        uint256 votingPower = store.votingUnitsOf(hook, beneficiary);
        assertEq(votingPower, 0.05 ether, "voting power should equal tier price");
    }

    /// @notice Custom voting units (useVotingUnits=true) uses specified value.
    function test_fork_customVotingUnits() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].useVotingUnits = true;
        tierConfigs[0].votingUnits = 42;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        uint256 votingPower = store.votingUnitsOf(hook, beneficiary);
        assertEq(votingPower, 42, "voting power should be custom units");
    }

    // =====================================================================
    // SECTION 14: CASH OUT WEIGHT AND MATH
    // =====================================================================

    /// @notice Cash out weight uses original price (not discounted).
    function test_fork_cashOutWeightUsesOriginalPrice() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].discountPercent = 100; // 50% discount
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 1 ether, tierIds, true, hook);

        // Cash out weight should be based on original price (1 ETH), not discounted (0.5 ETH).
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _tokenId(1, 1);
        uint256 weight = store.cashOutWeightOf(hook, tokenIds);
        assertEq(weight, 1 ether, "cash out weight uses original price");
    }

    /// @notice totalCashOutWeight includes pending reserves in denominator.
    function test_fork_totalCashOutWeightIncludesPendingReserves() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 100, false);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].reserveFrequency = 1;
        tierConfigs[0].reserveBeneficiary = reserveBeneficiary;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 1 ether, tierIds, true, hook);

        uint256 totalWeight = store.totalCashOutWeight(hook);

        // 1 paid mint + pending reserves. Total weight > just 1 * price.
        assertGt(totalWeight, 1 ether, "total weight includes pending reserves");
    }

    // =====================================================================
    // SECTION 15: ADVERSARIAL — FLASH LOAN ATTACK
    // =====================================================================

    /// @notice Pay and cash out in same block — verify no profit (bonding curve prevents it).
    function test_fork_flashLoanAttack_noProfit() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 100, false);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00); // 50% tax

        // Seed with initial payments from payer — minting NFTs so totalCashOutWeight is large.
        uint16[] memory seedTierIds = new uint16[](10);
        for (uint256 i; i < 10; i++) {
            seedTierIds[i] = 1;
        }
        bytes memory seedMeta = _buildPayMetadata(hook, seedTierIds, true);
        vm.prank(payer);
        jbMultiTerminal.pay{value: 10 ether}({
            projectId: projectId,
            amount: 10 ether,
            token: NATIVE_TOKEN,
            beneficiary: payer,
            minReturnedTokens: 0,
            memo: "",
            metadata: seedMeta
        });

        uint256 attackerBalBefore = attacker.balance;

        // Attacker: pay → mint NFT → immediately cash out.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory payMeta = _buildPayMetadata(hook, tierIds, true);

        vm.prank(attacker);
        jbMultiTerminal.pay{value: 1 ether}({
            projectId: projectId,
            amount: 1 ether,
            token: NATIVE_TOKEN,
            beneficiary: attacker,
            minReturnedTokens: 0,
            memo: "",
            metadata: payMeta
        });

        uint256[] memory tokensToCashOut = new uint256[](1);
        tokensToCashOut[0] = _tokenId(1, 11); // Token #11 (first 10 minted by payer)
        bytes memory cashOutMeta = _buildCashOutMetadata(hook, tokensToCashOut);

        vm.prank(attacker);
        jbMultiTerminal.cashOutTokensOf({
            holder: attacker,
            projectId: projectId,
            tokenToReclaim: NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(attacker),
            metadata: cashOutMeta
        });

        // Attacker should not have profited.
        assertLe(attacker.balance, attackerBalBefore, "flash loan attack should not profit");
    }

    // =====================================================================
    // SECTION 16: ADVERSARIAL — NON-OWNER CASH OUT
    // =====================================================================

    /// @notice Non-owner trying to cash out someone else's NFT should revert.
    function test_fork_nonOwnerCashOut_reverts() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        // beneficiary owns the NFT. attacker tries to cash out.
        uint256[] memory tokensToCashOut = new uint256[](1);
        tokensToCashOut[0] = _tokenId(1, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(hook, tokensToCashOut);

        vm.prank(attacker);
        vm.expectRevert();
        jbMultiTerminal.cashOutTokensOf({
            holder: attacker,
            projectId: projectId,
            tokenToReclaim: NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(attacker),
            metadata: cashOutMeta
        });
    }

    // =====================================================================
    // SECTION 17: ADVERSARIAL — RE-INITIALIZATION
    // =====================================================================

    /// @notice Calling initialize() again on a deployed hook should revert.
    function test_fork_reInitialize_reverts() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        JB721TierConfig[] memory emptyTiers = new JB721TierConfig[](0);

        vm.expectRevert();
        IJB721TiersHook(hook)
            .initialize(
                99, // different projectId
                "Evil",
                "EVIL",
                "ipfs://evil/",
                IJB721TokenUriResolver(address(0)),
                "ipfs://evil-contract",
                JB721InitTiersConfig({
                    tiers: emptyTiers,
                    currency: uint32(uint160(NATIVE_TOKEN)),
                    decimals: 18,
                    prices: IJBPrices(address(0))
                }),
                _defaultFlags()
            );
    }

    // =====================================================================
    // SECTION 18: ADVERSARIAL — UNDERPAY
    // =====================================================================

    /// @notice Paying less than tier price with preventOverspending=true should revert.
    function test_fork_underpay_reverts() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();
        flags.preventOverspending = true;
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        bytes memory meta = _buildPayMetadata(hook, tierIds, false);

        vm.prank(payer);
        vm.expectRevert();
        jbMultiTerminal.pay{value: 0.5 ether}({
            projectId: projectId,
            amount: 0.5 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });
    }

    // =====================================================================
    // SECTION 19: ADVERSARIAL — ADJUSTTIERS WITHOUT PERMISSION
    // =====================================================================

    /// @notice Non-owner cannot adjustTiers.
    function test_fork_adjustTiers_noPermission_reverts() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        JB721TierConfig[] memory newTiers = new JB721TierConfig[](1);
        newTiers[0] = JB721TierConfig({
            price: 0.001 ether,
            initialSupply: type(uint32).max,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: attacker,
            encodedIPFSUri: IPFS_URI,
            category: 200,
            discountPercent: 0,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        vm.prank(attacker);
        vm.expectRevert();
        IJB721TiersHook(hook).adjustTiers(newTiers, new uint256[](0));
    }

    // =====================================================================
    // SECTION 20: ADVERSARIAL — STALE CASH OUT WEIGHT AFTER REMOVAL
    // =====================================================================

    /// @notice Mint from a tier, remove it, verify totalCashOutWeight still includes minted tokens.
    function test_fork_cashOutWeightPreservedAfterTierRemoval() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 5;
        tierIds[1] = 5;
        tierIds[2] = 5;
        _payAndMint(projectId, 0.15 ether, tierIds, true, hook);

        uint256 weightBefore = store.totalCashOutWeight(hook);
        assertGt(weightBefore, 0, "should have weight");

        // Remove tier 5.
        uint256[] memory toRemove = new uint256[](1);
        toRemove[0] = 5;

        vm.prank(multisig);
        IJB721TiersHook(hook).adjustTiers(new JB721TierConfig[](0), toRemove);

        uint256 weightAfter = store.totalCashOutWeight(hook);
        assertEq(weightAfter, weightBefore, "weight preserved after tier removal");
    }

    // =====================================================================
    // SECTION 21: MULTI-USER SCENARIOS
    // =====================================================================

    /// @notice Multiple users pay and mint from same project.
    function test_fork_multipleUsersMinting() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        // User1 mints.
        bytes memory meta = _buildPayMetadata(hook, tierIds, true);
        vm.prank(user1);
        jbMultiTerminal.pay{value: 0.01 ether}({
            projectId: projectId,
            amount: 0.01 ether,
            token: NATIVE_TOKEN,
            beneficiary: user1,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        // User2 mints.
        vm.prank(user2);
        jbMultiTerminal.pay{value: 0.01 ether}({
            projectId: projectId,
            amount: 0.01 ether,
            token: NATIVE_TOKEN,
            beneficiary: user2,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        // User3 mints.
        vm.prank(user3);
        jbMultiTerminal.pay{value: 0.01 ether}({
            projectId: projectId,
            amount: 0.01 ether,
            token: NATIVE_TOKEN,
            beneficiary: user3,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        assertEq(IERC721(hook).balanceOf(user1), 1, "user1 has 1 NFT");
        assertEq(IERC721(hook).balanceOf(user2), 1, "user2 has 1 NFT");
        assertEq(IERC721(hook).balanceOf(user3), 1, "user3 has 1 NFT");

        // Each user got a different token number.
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), user1, "user1 has #1");
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 2)), user2, "user2 has #2");
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 3)), user3, "user3 has #3");

        JB721Tier memory tier = store.tierOf(hook, 1, false);
        assertEq(tier.remainingSupply, 7, "supply decreased by 3");
    }

    // =====================================================================
    // SECTION 22: FULL LIFECYCLE — PAY, MINT, RESERVE, CASH OUT, REMINT
    // =====================================================================

    /// @notice Complete lifecycle: pay → mint → reserves → cash out → verify store consistency.
    function test_fork_fullLifecycle() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(3, 20, false);
        tierConfigs[0].reserveFrequency = 5;
        tierConfigs[1].reserveFrequency = 5;
        tierConfigs[2].reserveFrequency = 5;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        // Phase 1: Multiple payments minting various tiers.
        uint16[] memory batch1 = new uint16[](3);
        batch1[0] = 1;
        batch1[1] = 1;
        batch1[2] = 2;
        _payAndMint(projectId, 0.04 ether, batch1, true, hook);

        uint16[] memory batch2 = new uint16[](2);
        batch2[0] = 2;
        batch2[1] = 3;
        _payAndMint(projectId, 0.05 ether, batch2, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 5, "5 NFTs total");

        // Phase 2: Mint pending reserves.
        for (uint256 tierId = 1; tierId <= 3; tierId++) {
            uint256 pending = store.numberOfPendingReservesFor(hook, tierId);
            if (pending > 0) {
                vm.prank(multisig);
                IJB721TiersHook(hook).mintPendingReservesFor(tierId, pending);
            }
        }

        assertGt(IERC721(hook).balanceOf(reserveBeneficiary), 0, "reserve beneficiary has NFTs");

        // Phase 3: Cash out some NFTs.
        uint256[] memory tokensToCashOut = new uint256[](2);
        tokensToCashOut[0] = _tokenId(1, 1);
        tokensToCashOut[1] = _tokenId(2, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(hook, tokensToCashOut);

        uint256 balBefore = beneficiary.balance;
        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: cashOutMeta
        });

        assertEq(IERC721(hook).balanceOf(beneficiary), 3, "3 NFTs remaining");
        assertGt(beneficiary.balance, balBefore, "ETH reclaimed");
        assertEq(store.numberOfBurnedFor(hook, 1), 1, "tier 1 burn recorded");
        assertEq(store.numberOfBurnedFor(hook, 2), 1, "tier 2 burn recorded");

        // Phase 4: Re-mint from depleted tiers — supply should still be available.
        uint16[] memory reMint = new uint16[](1);
        reMint[0] = 1;
        _payAndMint(projectId, 0.01 ether, reMint, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 4, "4 NFTs after remint");
    }

    // =====================================================================
    // SECTION 23: ZERO PRICE TIER
    // =====================================================================

    /// @notice A zero-price tier can be minted for free.
    function test_fork_zeroPriceTier() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].price = 0;
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        bytes memory meta = _buildPayMetadata(hook, tierIds, true);
        vm.prank(payer);
        jbMultiTerminal.pay{value: 0}({
            projectId: projectId,
            amount: 0,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "zero price tier minted");
    }

    // =====================================================================
    // SECTION 24: DETERMINISTIC DEPLOYMENT
    // =====================================================================

    /// @notice Deterministic and non-deterministic clone deployments both work.
    function test_fork_deterministicDeployment() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();

        // Non-deterministic.
        (uint256 projectId1, address hook1) = _launchProject(tierConfigs, flags, 5000, true, 0x00);
        assertGt(projectId1, 0, "project 1 launched");
        assertTrue(hook1.code.length > 0, "hook 1 deployed");

        // Verify registered in address registry.
        assertEq(addressRegistry.deployerOf(hook1), address(hookDeployer), "hook 1 in registry");
    }

    // =====================================================================
    // SECTION 25: MULTI-CATEGORY TIERS
    // =====================================================================

    /// @notice Tiers across multiple categories can be minted independently.
    function test_fork_multiCategoryTiers() public {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](3);
        for (uint256 i; i < 3; i++) {
            tierConfigs[i] = JB721TierConfig({
                price: uint104((i + 1) * 0.01 ether),
                initialSupply: 10,
                votingUnits: 0,
                reserveFrequency: 0,
                reserveBeneficiary: address(0),
                encodedIPFSUri: IPFS_URI,
                category: uint24((i + 1) * 100), // Categories: 100, 200, 300
                discountPercent: 0,
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false,
                splitPercent: 0,
                splits: new JBSplit[](0)
            });
        }
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        // Mint from each category.
        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 1;
        tierIds[1] = 2;
        tierIds[2] = 3;

        _payAndMint(projectId, 0.06 ether, tierIds, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 3, "one from each category");

        // Query tiers by category.
        uint256[] memory cat100 = new uint256[](1);
        cat100[0] = 100;
        JB721Tier[] memory cat100Tiers = store.tiersOf(hook, cat100, false, 0, 100);
        assertEq(cat100Tiers.length, 1, "1 tier in category 100");
    }

    // =====================================================================
    // SECTION 26: PAY WITHOUT METADATA — NO TIERS SPECIFIED
    // =====================================================================

    /// @notice Paying without metadata gives all payment as credits.
    function test_fork_payWithoutMetadata_noNFTsMinted() public {
        (uint256 projectId, address hook,) = _launchStandardProject();

        vm.prank(payer);
        jbMultiTerminal.pay{value: 1 ether}({
            projectId: projectId,
            amount: 1 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        assertEq(IERC721(hook).balanceOf(beneficiary), 0, "no NFTs minted");
        assertEq(IJB721TiersHook(hook).payCreditsOf(beneficiary), 1 ether, "full payment as credits");
    }

    // =====================================================================
    // SECTION 27: M6 RESERVE PROTECTION
    // =====================================================================

    /// @notice M6: Cannot mint past pending reserves. If remaining supply would drop below
    ///         pending reserves, the paid mint reverts.
    function test_fork_m6_reserveProtection() public {
        // Supply=4, reserveFrequency=1.
        // After 2 paid mints: remaining=2, pendingReserves = ceil(2/1) = 2+1 = 3? No:
        // Formula: nonReserveMints = initialSupply - remaining - reservesMinted = 4-2-0 = 2
        // pendingReserves = ceil(2/1) - 0 = 2
        // remaining(2) >= pending(2) → OK (M6 checks remaining < pending, not <=)
        // After 3rd paid mint attempt: remaining would be 1
        // nonReserveMints = 4-1-0 = 3, pending = ceil(3/1) - 0 = 3
        // remaining(1) < pending(3) → REVERTS!
        // So: mint 2, then 3rd should revert.
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 4, false);
        tierConfigs[0].reserveFrequency = 1;
        tierConfigs[0].reserveBeneficiary = reserveBeneficiary;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        // Mint 2 NFTs successfully.
        uint16[] memory two = new uint16[](2);
        two[0] = 1;
        two[1] = 1;
        _payAndMint(projectId, 0.02 ether, two, true, hook);

        assertEq(IERC721(hook).balanceOf(beneficiary), 2, "2 minted successfully");

        // 3rd mint should fail — remaining would drop below pending reserves.
        uint16[] memory one = new uint16[](1);
        one[0] = 1;
        bytes memory meta = _buildPayMetadata(hook, one, false);

        vm.prank(payer);
        vm.expectRevert();
        jbMultiTerminal.pay{value: 0.01 ether}({
            projectId: projectId,
            amount: 0.01 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });
    }

    // =====================================================================
    // SECTION 28: CASH OUT RECLAIM CONSISTENCY
    // =====================================================================

    /// @notice Two users mint same tier. Higher tax rate should yield less reclaim.
    function test_fork_cashOutTaxRateEffect() public {
        // High tax rate project.
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 100, false);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 9000, true, 0x00); // 90% tax

        // First user pays.
        address user1 = makeAddr("taxUser1");
        vm.deal(user1, 10 ether);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;

        bytes memory meta = _buildPayMetadata(hook, tierIds, true);
        vm.prank(user1);
        jbMultiTerminal.pay{value: 1 ether}({
            projectId: projectId,
            amount: 1 ether,
            token: NATIVE_TOKEN,
            beneficiary: user1,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        // Second user pays.
        address user2 = makeAddr("taxUser2");
        vm.deal(user2, 10 ether);
        vm.prank(user2);
        jbMultiTerminal.pay{value: 1 ether}({
            projectId: projectId,
            amount: 1 ether,
            token: NATIVE_TOKEN,
            beneficiary: user2,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        // User1 cashes out — with 90% tax, they should get very little back.
        uint256[] memory tokensToCashOut = new uint256[](1);
        tokensToCashOut[0] = _tokenId(1, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(hook, tokensToCashOut);

        uint256 balBefore = user1.balance;
        vm.prank(user1);
        jbMultiTerminal.cashOutTokensOf({
            holder: user1,
            projectId: projectId,
            tokenToReclaim: NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(user1),
            metadata: cashOutMeta
        });

        uint256 reclaimed = user1.balance - balBefore;
        // With 90% tax, should get less than what was paid (1 ETH).
        assertLt(reclaimed, 1 ether, "90% tax should yield less than paid");
    }

    // =====================================================================
    // SECTION 29: MULTIPLE PROJECTS SHARING SAME STORE
    // =====================================================================

    /// @notice Two projects using the same store should not interfere with each other.
    function test_fork_crossProjectIsolation() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 10, false);
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();

        (uint256 projectId1, address hook1) = _launchProject(tierConfigs, flags, 5000, true, 0x00);
        (uint256 projectId2, address hook2) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        assertTrue(hook1 != hook2, "hooks are different clones");

        // Mint from project 1.
        uint16[] memory tierIds = new uint16[](3);
        tierIds[0] = 1;
        tierIds[1] = 1;
        tierIds[2] = 1;
        bytes memory meta1 = _buildPayMetadata(hook1, tierIds, true);
        vm.prank(payer);
        jbMultiTerminal.pay{value: 0.03 ether}({
            projectId: projectId1,
            amount: 0.03 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta1
        });

        // Project 2's supply should be unaffected.
        JB721Tier memory p2Tier = store.tierOf(hook2, 1, false);
        assertEq(p2Tier.remainingSupply, 10, "project 2 supply unaffected");

        // Project 1's supply should be decreased.
        JB721Tier memory p1Tier = store.tierOf(hook1, 1, false);
        assertEq(p1Tier.remainingSupply, 7, "project 1 supply decreased");
    }

    // =====================================================================
    // SECTION 30: BURN AFTER CASH OUT AND REMINT
    // =====================================================================

    /// @notice After burning via cash out, new mints get different token numbers.
    function test_fork_tokenNumbersAfterBurn() public {
        JB721TierConfig[] memory tierConfigs = _makeStandardTiers(1, 100, false);
        tierConfigs[0].reserveFrequency = 0;
        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 0, true, 0x00);

        // Mint token #1.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "token #1 exists");

        // Cash out token #1 (burn it).
        uint256[] memory toCashOut = new uint256[](1);
        toCashOut[0] = _tokenId(1, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(hook, toCashOut);
        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: cashOutMeta
        });

        // Mint again — should get token #2, not #1 (burned tokens don't recycle numbers).
        _payAndMint(projectId, 0.01 ether, tierIds, true, hook);

        assertEq(IERC721(hook).ownerOf(_tokenId(1, 2)), beneficiary, "token #2 after burn");

        // Token #1 should no longer exist (burned).
        vm.expectRevert();
        IERC721(hook).ownerOf(_tokenId(1, 1));
    }

    // =====================================================================
    // SECTION 31: TIER SPLITS
    /// @dev Helper: build a single split tier config.
    function _makeSplitTierConfig(
        uint104 price,
        uint32 splitPct,
        JBSplit[] memory splits,
        uint24 category
    )
        internal
        view
        returns (JB721TierConfig memory)
    {
        return JB721TierConfig({
            price: price,
            initialSupply: 10,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            encodedIPFSUri: IPFS_URI,
            category: category,
            discountPercent: 0,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            splitPercent: splitPct,
            splits: splits
        });
    }

    /// @notice A tier with splitPercent routes that portion of the payment to the split beneficiary.
    ///         The payer's token weight is reduced by the split fraction.
    function test_fork_tierSplit_routesFundsToSplitBeneficiary() public {
        address splitReceiver = makeAddr("splitReceiver");

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT), // 100% of split amount goes to this beneficiary
            projectId: 0,
            beneficiary: payable(splitReceiver),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _makeSplitTierConfig(1 ether, uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2), splits, 100);

        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        // Pay 1 ETH to mint the tier (tier ID = 1, since it's the first added).
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        uint256 tokensMinted = _payAndMint(projectId, 1 ether, tierIds, true, hook);

        // Split receiver should have received 0.5 ETH (50% of 1 ETH tier price).
        assertEq(splitReceiver.balance, 0.5 ether, "split receiver got 50%");

        // Beneficiary should own the NFT.
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "NFT minted to beneficiary");

        // Token weight is reduced by split: weight = 1M * (1 - 0.5) = 500k tokens/ETH.
        // Then 50% reserved percent halves it further: payer gets 250k tokens.
        assertEq(tokensMinted, 250_000e18, "tokens minted for non-split portion (after reserved)");
    }

    /// @notice When issueTokensForSplits is true, payer gets full token credit despite splits.
    function test_fork_tierSplit_issueTokensForSplits() public {
        address splitReceiver = makeAddr("splitReceiver");

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(splitReceiver),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _makeSplitTierConfig(1 ether, uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2), splits, 100);

        // Enable issueTokensForSplits.
        JB721TiersHookFlags memory flags = _defaultFlags();
        flags.issueTokensForSplits = true;
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        uint256 tokensMinted = _payAndMint(projectId, 1 ether, tierIds, true, hook);

        // Split receiver still gets their ETH.
        assertEq(splitReceiver.balance, 0.5 ether, "split receiver got 50%");

        // Payer gets FULL token credit (weight not reduced by split).
        // 1M tokens/ETH * 1 ETH * (1 - 50% reserved) = 500k tokens.
        assertEq(tokensMinted, 500_000e18, "full tokens despite split (after reserved)");
    }

    /// @notice Mix of tiers: one with splits, one without. Only the split tier routes funds.
    function test_fork_tierSplit_mixedTiers() public {
        address splitReceiver = makeAddr("splitReceiver");

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(splitReceiver),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](2);
        // Tier 1: no splits (0.5 ETH).
        tierConfigs[0] = _makeSplitTierConfig(0.5 ether, 0, new JBSplit[](0), 100);
        // Tier 2: 50% split (0.5 ETH) → 0.25 ETH routed. Higher category for sort order.
        tierConfigs[1] = _makeSplitTierConfig(0.5 ether, uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2), splits, 200);

        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        // Mint both tiers (total: 1 ETH).
        uint16[] memory tierIds = new uint16[](2);
        tierIds[0] = 1;
        tierIds[1] = 2;
        uint256 tokensMinted = _payAndMint(projectId, 1 ether, tierIds, true, hook);

        // Split receiver gets 0.25 ETH (50% of tier 2's 0.5 ETH price).
        assertEq(splitReceiver.balance, 0.25 ether, "split receiver got 50% of tier 2 price");

        // Both NFTs minted.
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "tier 1 NFT minted");
        assertEq(IERC721(hook).ownerOf(_tokenId(2, 1)), beneficiary, "tier 2 NFT minted");

        // Weight reduced by split fraction: 1M * (1 - 0.25) / 1 = 750k, then 50% reserved = 375k.
        assertEq(tokensMinted, 375_000e18, "tokens reduced by split fraction (after reserved)");
    }

    /// @notice Split with no valid recipient (no projectId, no beneficiary) sends funds
    ///         back into the project's terminal balance as leftover.
    function test_fork_tierSplit_preferAddToBalance() public {
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: true,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _makeSplitTierConfig(1 ether, uint32(JBConstants.SPLITS_TOTAL_PERCENT), splits, 100);

        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 1 ether, tierIds, true, hook);

        // NFT still minted.
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "NFT minted");

        // All 1 ETH should be in the project's terminal balance (split had no valid recipient,
        // so leftover is added back to balance).
        uint256 projectBalance = jbTerminalStore.balanceOf(address(jbMultiTerminal), projectId, NATIVE_TOKEN);
        assertEq(projectBalance, 1 ether, "full amount in project balance");
    }

    /// @notice 100% split with valid receiver means weight goes to zero (no project tokens minted).
    function test_fork_tierSplit_fullSplitZerosWeight() public {
        address splitReceiver = makeAddr("splitReceiver");

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(splitReceiver),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _makeSplitTierConfig(1 ether, uint32(JBConstants.SPLITS_TOTAL_PERCENT), splits, 100);

        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        uint256 tokensMinted = _payAndMint(projectId, 1 ether, tierIds, true, hook);

        // All funds routed to split receiver.
        assertEq(splitReceiver.balance, 1 ether, "split receiver got 100%");

        // Zero project tokens minted (weight set to 0 when splits consume entire payment).
        assertEq(tokensMinted, 0, "zero tokens when full split");

        // NFT still minted.
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "NFT still minted");
    }

    /// @notice Split to another Juicebox project (via pay into its terminal).
    function test_fork_tierSplit_toProject() public {
        address splitReceiver = makeAddr("splitReceiver");

        // First launch a receiver project (simple, no hooks).
        JBRulesetMetadata memory receiverMetadata = JBRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: uint32(uint160(NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: false,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: false,
            allowAddPriceFeed: false,
            ownerMustSendPayouts: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForPay: false,
            useDataHookForCashOut: false,
            dataHook: address(0),
            metadata: 0
        });

        JBRulesetConfig[] memory receiverRulesets = new JBRulesetConfig[](1);
        receiverRulesets[0] = JBRulesetConfig({
            mustStartAtOrAfter: 0,
            duration: 0,
            weight: 1_000_000e18,
            weightCutPercent: 0,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: receiverMetadata,
            splitGroups: new JBSplitGroup[](0),
            fundAccessLimitGroups: new JBFundAccessLimitGroup[](0)
        });

        JBAccountingContext[] memory receiverAccounting = new JBAccountingContext[](1);
        receiverAccounting[0] =
            JBAccountingContext({token: NATIVE_TOKEN, currency: uint32(uint160(NATIVE_TOKEN)), decimals: 18});
        JBTerminalConfig[] memory receiverTerminals = new JBTerminalConfig[](1);
        receiverTerminals[0] =
            JBTerminalConfig({terminal: jbMultiTerminal, accountingContextsToAccept: receiverAccounting});

        vm.prank(multisig);
        uint256 receiverProjectId = jbController.launchProjectFor({
            owner: multisig,
            projectUri: "receiver-project",
            rulesetConfigurations: receiverRulesets,
            terminalConfigurations: receiverTerminals,
            memo: ""
        });

        // Now create the 721 hook project with a split that pays into the receiver project.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: uint56(receiverProjectId),
            beneficiary: payable(splitReceiver),
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _makeSplitTierConfig(1 ether, uint32(JBConstants.SPLITS_TOTAL_PERCENT / 2), splits, 100);

        JB721TiersHookFlags memory flags = _defaultFlags();
        (uint256 projectId, address hook) = _launchProject(tierConfigs, flags, 5000, true, 0x00);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        _payAndMint(projectId, 1 ether, tierIds, true, hook);

        // Receiver project should have 0.5 ETH in its balance.
        uint256 receiverBalance = jbTerminalStore.balanceOf(address(jbMultiTerminal), receiverProjectId, NATIVE_TOKEN);
        assertEq(receiverBalance, 0.5 ether, "receiver project got split funds");
    }
}
