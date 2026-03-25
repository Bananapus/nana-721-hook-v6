// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "forge-std/Test.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBController.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBDirectory.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBMultiTerminal.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBFundAccessLimits.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBFeelessAddresses.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBTerminalStore.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBRulesets.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBPermissions.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBPrices.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBSplits.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBERC20.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/JBTokens.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/libraries/JBConstants.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/libraries/JBRulesetMetadataResolver.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBSplit.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {MetadataResolverHelper} from "@bananapus/core-v6/test/helpers/MetadataResolverHelper.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
// forge-lint: disable-next-line(unused-import)
import {mulDiv} from "@prb/math/src/Common.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/JB721TiersHook.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/JB721TiersHookDeployer.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/JB721TiersHookProjectDeployer.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/JB721TiersHookStore.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/interfaces/IJB721TiersHook.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBDeploy721TiersHookConfig.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBLaunchProjectConfig.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBPayDataHookRulesetConfig.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBPayDataHookRulesetMetadata.sol";

/// @title IssueTokensForSplitsFork
/// @notice Fork tests for the issueTokensForSplits flag in JB721TiersHookFlags.
/// @dev When `issueTokensForSplits = true`, the payer gets tokens at full weight regardless of split routing.
///      When `false`, weight is scaled by `(amountValue - totalSplitAmount) / amountValue`.
/// @dev Run with: forge test --match-contract IssueTokensForSplitsFork -vvv --fork-url $RPC
contract IssueTokensForSplitsFork is Test {
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
    address splitBeneficiary = makeAddr("splitBeneficiary");

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
    // Setup
    // =========================================================================

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum");

        _deployJBCore();
        _deploy721Hook();

        vm.deal(payer, 1000 ether);
        vm.deal(beneficiary, 100 ether);
        vm.deal(multisig, 100 ether);

        vm.label(multisig, "multisig");
        vm.label(payer, "payer");
        vm.label(beneficiary, "beneficiary");
        vm.label(reserveBeneficiary, "reserveBeneficiary");
        vm.label(splitBeneficiary, "splitBeneficiary");
    }

    // forge-lint: disable-next-line(mixed-case-function)
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
            address(0),
            address(0)
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
            IPermit2(address(0)),
            address(0)
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
        hookImpl = new JB721TiersHook(
            jbDirectory, jbPermissions, jbPrices, jbRulesets, store, IJBSplits(address(jbSplits)), address(0)
        );
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
    // Launch Helper
    // =========================================================================

    /// @dev Launch an ETH-denominated project with configurable issueTokensForSplits flag.
    // forge-lint: disable-next-line(mixed-case-function)
    function _launchProjectWithFlag(
        JB721TierConfig[] memory tierConfigs,
        bool issueTokensForSplits
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
                tiers: tierConfigs,
                // forge-lint: disable-next-line(unsafe-typecast)
                currency: uint32(uint160(NATIVE_TOKEN)),
                decimals: 18
            }),
            reserveBeneficiary: reserveBeneficiary,
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: issueTokensForSplits,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: false
            })
        });

        JBPayDataHookRulesetMetadata memory rulesetMetadata = JBPayDataHookRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            // forge-lint: disable-next-line(unsafe-typecast)
            baseCurrency: uint32(uint160(NATIVE_TOKEN)),
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
            useDataHookForCashOut: true,
            metadata: 0x00
        });

        JBPayDataHookRulesetConfig[] memory rulesetConfigs = new JBPayDataHookRulesetConfig[](1);
        rulesetConfigs[0].mustStartAtOrAfter = 0;
        rulesetConfigs[0].duration = 0;
        rulesetConfigs[0].weight = 1_000_000e18; // 1M tokens per ETH
        rulesetConfigs[0].weightCutPercent = 0;
        rulesetConfigs[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfigs[0].metadata = rulesetMetadata;

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] =
        // forge-lint: disable-next-line(unsafe-typecast)
        JBAccountingContext({token: NATIVE_TOKEN, currency: uint32(uint160(NATIVE_TOKEN)), decimals: 18});

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](1);
        terminalConfigs[0] =
            JBTerminalConfig({terminal: jbMultiTerminal, accountingContextsToAccept: accountingContexts});

        JBLaunchProjectConfig memory launchConfig = JBLaunchProjectConfig({
            projectUri: "test-issue-tokens-splits",
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

    // =========================================================================
    // Metadata & Token ID Helpers
    // =========================================================================

    function _buildPayMetadata(uint16[] memory tierIds, bool allowOverspending) internal view returns (bytes memory) {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIds);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = JBMetadataResolver.getId("pay", address(hookImpl));
        return metadataHelper.createMetadata(ids, data);
    }

    function _tokenId(uint256 tierId, uint256 mintNumber) internal pure returns (uint256) {
        return tierId * 1_000_000_000 + mintNumber;
    }

    // =========================================================================
    // Helper: create a tier with 50% split to splitBeneficiary
    // =========================================================================

    function _makeTierWithSplit(uint104 price, uint32 splitPercent) internal view returns (JB721TierConfig memory) {
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(splitBeneficiary),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        return JB721TierConfig({
            price: price,
            initialSupply: 100,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32("tier1"),
            category: 1,
            discountPercent: 0,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            splitPercent: splitPercent,
            splits: splits
        });
    }

    // =========================================================================
    // Test 1: issueTokensForSplits = true -> payer gets tokens at full weight
    // =========================================================================

    /// @notice When issueTokensForSplits = true and tier has splits, payer gets tokens on full amount.
    function testFork_IssueTokensForSplitsTrueFullWeight() public {
        // Tier: 1 ETH, 50% split to splitBeneficiary.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _makeTierWithSplit(1 ether, 500_000_000); // 50% split

        (uint256 projectId,) = _launchProjectWithFlag(tierConfigs, true);

        // Pay 1 ETH to mint tier 1 NFT.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory meta = _buildPayMetadata(tierIds, true);

        vm.prank(payer);
        uint256 tokenCount = jbMultiTerminal.pay{value: 1 ether}({
            projectId: projectId,
            amount: 1 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        // With issueTokensForSplits = true, weight = contextWeight (full).
        // weight = 1_000_000e18, payment = 1 ETH => tokens = 1_000_000e18 * 1e18 / 1e18 = 1_000_000e18
        // tokenCount is the number of tokens minted to the beneficiary.
        uint256 balance = jbTokens.totalBalanceOf(beneficiary, projectId);

        // Full weight: beneficiary should receive tokens based on the full 1 ETH amount.
        // With weight = 1_000_000e18 and payment = 1 ETH: expected = 1_000_000e18.
        assertEq(balance, 1_000_000e18, "issueTokensForSplits=true: full weight tokens minted");
        assertEq(tokenCount, 1_000_000e18, "pay() return value should match full token count");

        // Split beneficiary should have received 0.5 ETH.
        assertGt(splitBeneficiary.balance, 0, "split beneficiary should have received ETH");
    }

    // =========================================================================
    // Test 2: issueTokensForSplits = false -> payer gets scaled tokens
    // =========================================================================

    /// @notice When issueTokensForSplits = false and tier has splits, payer gets scaled tokens.
    function testFork_IssueTokensForSplitsFalseScaledWeight() public {
        // Tier: 1 ETH, 50% split to splitBeneficiary.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _makeTierWithSplit(1 ether, 500_000_000); // 50% split

        (uint256 projectId,) = _launchProjectWithFlag(tierConfigs, false);

        // Pay 1 ETH to mint tier 1 NFT.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory meta = _buildPayMetadata(tierIds, true);

        vm.prank(payer);
        uint256 tokenCount = jbMultiTerminal.pay{value: 1 ether}({
            projectId: projectId,
            amount: 1 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        // With issueTokensForSplits = false, weight = contextWeight * (amount - splitAmount) / amount.
        // splitAmount = 50% of 1 ETH = 0.5 ETH.
        // weight = 1_000_000e18 * (1e18 - 0.5e18) / 1e18 = 500_000e18.
        // tokens = 500_000e18 * 1e18 / 1e18 = 500_000e18.
        uint256 balance = jbTokens.totalBalanceOf(beneficiary, projectId);

        // Scaled weight: beneficiary should receive tokens based on 50% of the payment.
        assertEq(balance, 500_000e18, "issueTokensForSplits=false: scaled weight tokens minted");
        assertEq(tokenCount, 500_000e18, "pay() return value should match scaled token count");

        // Split beneficiary should have received 0.5 ETH.
        assertGt(splitBeneficiary.balance, 0, "split beneficiary should have received ETH");
    }

    // =========================================================================
    // Test 3: 100% to splits edge case
    // =========================================================================

    /// @notice 100% to splits: flag true -> tokens still minted at full weight; flag false -> weight = 0, no tokens.
    function testFork_IssueTokensForSplitsEdgeCaseAllSplits() public {
        // Tier: 1 ETH, 100% split to splitBeneficiary (SPLITS_TOTAL_PERCENT = 1e9).
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _makeTierWithSplit(1 ether, 1_000_000_000); // 100% split

        // --- Part A: issueTokensForSplits = true ---
        (uint256 projectIdTrue,) = _launchProjectWithFlag(tierConfigs, true);

        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory meta = _buildPayMetadata(tierIds, true);

        vm.prank(payer);
        uint256 tokenCountTrue = jbMultiTerminal.pay{value: 1 ether}({
            projectId: projectIdTrue,
            amount: 1 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        uint256 balanceTrue = jbTokens.totalBalanceOf(beneficiary, projectIdTrue);

        // issueTokensForSplits=true: full weight even though 100% goes to splits.
        assertEq(balanceTrue, 1_000_000e18, "100% splits + flag=true: full weight tokens minted");
        assertEq(tokenCountTrue, 1_000_000e18, "pay() return value: full tokens with flag=true");

        // --- Part B: issueTokensForSplits = false ---
        (uint256 projectIdFalse,) = _launchProjectWithFlag(tierConfigs, false);

        meta = _buildPayMetadata(tierIds, true);

        vm.prank(payer);
        uint256 tokenCountFalse = jbMultiTerminal.pay{value: 1 ether}({
            projectId: projectIdFalse,
            amount: 1 ether,
            token: NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        uint256 balanceFalse = jbTokens.totalBalanceOf(beneficiary, projectIdFalse);

        // issueTokensForSplits=false + 100% splits: weight = 0, no tokens minted.
        assertEq(balanceFalse, 0, "100% splits + flag=false: zero tokens minted");
        assertEq(tokenCountFalse, 0, "pay() return value: zero tokens with flag=false");
    }
}
