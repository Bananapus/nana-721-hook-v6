// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "forge-std/Test.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

/// @notice Mock ERC20 with 6 decimals (USDC-like).
contract MockUSDC6 is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title ERC20TierSplitFork
/// @notice Fork tests for ERC20 tier split distribution in JB721TiersHook.
/// @dev Run with: forge test --match-contract ERC20TierSplitFork -vvv --fork-url $RPC
contract ERC20TierSplitFork is Test {
    using JBRulesetMetadataResolver for JBRuleset;

    // Actors
    address multisig = address(0xBEEF);
    address payer = makeAddr("payer");
    address beneficiary = makeAddr("beneficiary");
    address splitBeneficiary = makeAddr("splitBeneficiary");
    address reserveBeneficiary = makeAddr("reserveBeneficiary");

    // JB Core
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

    // 721 Hook
    JB721TiersHookStore store;
    JB721TiersHook hookImpl;
    JB721TiersHookDeployer hookDeployer;
    JB721TiersHookProjectDeployer projectDeployer;
    MetadataResolverHelper metadataHelper;
    JBAddressRegistry addressRegistry;

    // Token
    MockUSDC6 usdc;

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum");

        _deployJBCore();
        _deploy721Hook();

        usdc = new MockUSDC6();
        usdc.mint(payer, 100_000e6);

        vm.deal(payer, 10 ether);
        vm.deal(multisig, 10 ether);
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
    }

    // =========================================================================
    // Launch Helper
    // =========================================================================

    // forge-lint: disable-next-line(mixed-case-function)
    function _launchERC20Project(
        JB721TierConfig[] memory tierConfigs,
        address token,
        uint8 tokenDecimals
    )
        internal
        returns (uint256 projectId, address dataHook)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 currency = uint32(uint160(token));

        JBDeploy721TiersHookConfig memory hookConfig = JBDeploy721TiersHookConfig({
            name: "TestNFT",
            symbol: "TNFT",
            baseUri: "ipfs://base/",
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: "ipfs://contract",
            tiersConfig: JB721InitTiersConfig({tiers: tierConfigs, currency: currency, decimals: tokenDecimals}),
            reserveBeneficiary: reserveBeneficiary,
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: false
            })
        });

        JBPayDataHookRulesetMetadata memory rulesetMetadata = JBPayDataHookRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: currency,
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
            useDataHookForCashOut: false,
            metadata: 0x00
        });

        JBPayDataHookRulesetConfig[] memory rulesetConfigs = new JBPayDataHookRulesetConfig[](1);
        rulesetConfigs[0].mustStartAtOrAfter = 0;
        rulesetConfigs[0].duration = 0;
        rulesetConfigs[0].weight = 1_000_000e18;
        rulesetConfigs[0].weightCutPercent = 0;
        rulesetConfigs[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfigs[0].metadata = rulesetMetadata;

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] = JBAccountingContext({token: token, currency: currency, decimals: tokenDecimals});

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](1);
        terminalConfigs[0] =
            JBTerminalConfig({terminal: jbMultiTerminal, accountingContextsToAccept: accountingContexts});

        JBLaunchProjectConfig memory launchConfig = JBLaunchProjectConfig({
            projectUri: "test-erc20-project",
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: terminalConfigs,
            memo: ""
        });

        IJB721TiersHook hookInstance;
        (projectId, hookInstance) =
            projectDeployer.launchProjectFor(multisig, hookConfig, launchConfig, jbController, bytes32(0));

        dataHook = address(hookInstance);
    }

    /// @dev Launch with ETH accounting (for regression test).
    // forge-lint: disable-next-line(mixed-case-function)
    function _launchETHProject(JB721TierConfig[] memory tierConfigs)
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
                tiers: tierConfigs, currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
            }),
            reserveBeneficiary: reserveBeneficiary,
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: false
            })
        });

        JBPayDataHookRulesetMetadata memory rulesetMetadata = JBPayDataHookRulesetMetadata({
            reservedPercent: 0,
            cashOutTaxRate: 0,
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
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
            useDataHookForCashOut: false,
            metadata: 0x00
        });

        JBPayDataHookRulesetConfig[] memory rulesetConfigs = new JBPayDataHookRulesetConfig[](1);
        rulesetConfigs[0].mustStartAtOrAfter = 0;
        rulesetConfigs[0].duration = 0;
        rulesetConfigs[0].weight = 1_000_000e18;
        rulesetConfigs[0].weightCutPercent = 0;
        rulesetConfigs[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfigs[0].metadata = rulesetMetadata;

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN, currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
        });

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](1);
        terminalConfigs[0] =
            JBTerminalConfig({terminal: jbMultiTerminal, accountingContextsToAccept: accountingContexts});

        JBLaunchProjectConfig memory launchConfig = JBLaunchProjectConfig({
            projectUri: "test-eth-project",
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: terminalConfigs,
            memo: ""
        });

        IJB721TiersHook hookInstance;
        (projectId, hookInstance) =
            projectDeployer.launchProjectFor(multisig, hookConfig, launchConfig, jbController, bytes32(0));

        dataHook = address(hookInstance);
    }

    // =========================================================================
    // Metadata Helper
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
    // Test 1: USDC payment with tier split to beneficiary
    // =========================================================================

    function test_fork_usdcPayment_tierSplitToBeneficiary() public {
        // Create a tier: 100 USDC, 30% split to splitBeneficiary.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(splitBeneficiary),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: 100e6,
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
            splitPercent: 300_000_000, // 30%
            splits: splits
        });

        (uint256 projectId, address hook) = _launchERC20Project(tierConfigs, address(usdc), 6);

        // Pay 100 USDC to mint tier 1 NFT.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory meta = _buildPayMetadata(tierIds, true);

        vm.startPrank(payer);
        usdc.approve(address(jbMultiTerminal), 100e6);
        jbMultiTerminal.pay({
            projectId: projectId,
            amount: 100e6,
            token: address(usdc),
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });
        vm.stopPrank();

        // Split beneficiary should have received 30% of 100 USDC = 30 USDC.
        assertEq(usdc.balanceOf(splitBeneficiary), 30e6, "split beneficiary should have 30 USDC");
        // NFT minted to beneficiary.
        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "beneficiary should own 1 NFT");
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "beneficiary owns tier 1 NFT");
    }

    // =========================================================================
    // Test 2: USDC payment with tier split to project
    // =========================================================================

    function test_fork_usdcPayment_tierSplitToProject() public {
        // First launch a target project that accepts USDC.
        JB721TierConfig[] memory emptyTiers = new JB721TierConfig[](0);
        (uint256 targetProjectId,) = _launchERC20Project(emptyTiers, address(usdc), 6);

        // Now create the main project with tier split pointing to target project.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            // forge-lint: disable-next-line(unsafe-typecast)
            projectId: uint56(targetProjectId),
            beneficiary: payable(address(0)),
            preferAddToBalance: true,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: 100e6,
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
            splitPercent: 300_000_000, // 30%
            splits: splits
        });

        (uint256 projectId, address hook) = _launchERC20Project(tierConfigs, address(usdc), 6);

        // Record target project's terminal USDC balance before.
        uint256 targetBalanceBefore =
            jbTerminalStore.balanceOf(address(jbMultiTerminal), targetProjectId, address(usdc));

        // Pay 100 USDC.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory meta = _buildPayMetadata(tierIds, true);

        vm.startPrank(payer);
        usdc.approve(address(jbMultiTerminal), 100e6);
        jbMultiTerminal.pay({
            projectId: projectId,
            amount: 100e6,
            token: address(usdc),
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });
        vm.stopPrank();

        // Target project should have received 30 USDC via addToBalance.
        uint256 targetBalanceAfter = jbTerminalStore.balanceOf(address(jbMultiTerminal), targetProjectId, address(usdc));
        assertEq(targetBalanceAfter - targetBalanceBefore, 30e6, "target project should have 30 USDC more");
        // NFT minted.
        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "beneficiary should own 1 NFT");
    }

    // =========================================================================
    // Test 3: ETH payment with tier split still works (regression)
    // =========================================================================

    function test_fork_ethPayment_tierSplitStillWorks() public {
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(splitBeneficiary),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: 1 ether,
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
            splitPercent: 500_000_000, // 50%
            splits: splits
        });

        (uint256 projectId, address hook) = _launchETHProject(tierConfigs);

        uint256 splitBalanceBefore = splitBeneficiary.balance;

        // Pay 1 ETH.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory meta = _buildPayMetadata(tierIds, true);

        vm.prank(payer);
        jbMultiTerminal.pay{value: 1 ether}({
            projectId: projectId,
            amount: 1 ether,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: meta
        });

        // Split beneficiary should have received 50% of 1 ETH = 0.5 ETH.
        assertEq(splitBeneficiary.balance - splitBalanceBefore, 0.5 ether, "split beneficiary should have 0.5 ETH");
        // NFT minted.
        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "beneficiary should own 1 NFT");
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "beneficiary owns tier 1 NFT");
    }
}
