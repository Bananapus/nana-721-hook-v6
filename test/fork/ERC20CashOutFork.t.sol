// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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

/// @notice Mock ERC20 with 6 decimals (USDC-like).
contract MockUSDC6_CashOut is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title ERC20CashOutFork
/// @notice Fork tests for ERC-20 (USDC) cashout with JB721TiersHook: bonding curve math, fee deduction, NFT burning.
/// @dev Run with: forge test --match-contract ERC20CashOutFork -vvv --fork-url $RPC
contract ERC20CashOutFork is Test {
    using JBRulesetMetadataResolver for JBRuleset;

    // =========================================================================
    // Constants
    // =========================================================================

    uint256 constant FEE = 25;
    uint256 constant MAX_FEE = 1000;

    // =========================================================================
    // Actors
    // =========================================================================

    address multisig = address(0xBEEF);
    address payer = makeAddr("payer");
    address beneficiary = makeAddr("beneficiary");
    address reserveBeneficiary = makeAddr("reserveBeneficiary");

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
    // Token
    // =========================================================================

    MockUSDC6_CashOut usdc;

    // =========================================================================
    // Setup
    // =========================================================================

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork("ethereum");

        _deployJBCore();
        _deploy721Hook();

        usdc = new MockUSDC6_CashOut();
        usdc.mint(payer, 1_000_000e6);

        vm.deal(payer, 10 ether);
        vm.deal(multisig, 10 ether);
        vm.deal(beneficiary, 10 ether);
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

    /// @dev Launch a USDC-denominated project with cashout enabled.
    // forge-lint: disable-next-line(mixed-case-function)
    function _launchUSDCProject(
        JB721TierConfig[] memory tierConfigs,
        uint16 cashOutTaxRate
    )
        internal
        returns (uint256 projectId, address dataHook)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 currency = uint32(uint160(address(usdc)));

        JBDeploy721TiersHookConfig memory hookConfig = JBDeploy721TiersHookConfig({
            name: "TestNFT",
            symbol: "TNFT",
            baseUri: "ipfs://base/",
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: "ipfs://contract",
            tiersConfig: JB721InitTiersConfig({tiers: tierConfigs, currency: currency, decimals: 6}),
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
            cashOutTaxRate: cashOutTaxRate,
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
            useDataHookForCashOut: true,
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
        accountingContexts[0] = JBAccountingContext({token: address(usdc), currency: currency, decimals: 6});

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](1);
        terminalConfigs[0] =
            JBTerminalConfig({terminal: jbMultiTerminal, accountingContextsToAccept: accountingContexts});

        JBLaunchProjectConfig memory launchConfig = JBLaunchProjectConfig({
            projectUri: "test-erc20-cashout-project",
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
    // Metadata Helpers
    // =========================================================================

    function _buildPayMetadata(uint16[] memory tierIds, bool allowOverspending) internal view returns (bytes memory) {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(allowOverspending, tierIds);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = JBMetadataResolver.getId("pay", address(hookImpl));
        return metadataHelper.createMetadata(ids, data);
    }

    function _buildCashOutMetadata(uint256[] memory tokenIds) internal view returns (bytes memory) {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(tokenIds);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = JBMetadataResolver.getId("cashOut", address(hookImpl));
        return metadataHelper.createMetadata(ids, data);
    }

    function _tokenId(uint256 tierId, uint256 mintNumber) internal pure returns (uint256) {
        return tierId * 1_000_000_000 + mintNumber;
    }

    // =========================================================================
    // Test 1: ERC-20 cashout returns correct amount via bonding curve at 6 decimals
    // =========================================================================

    /// @notice Pay USDC to mint 721 NFTs, cashout, verify USDC returned via bonding curve math at 6 decimals.
    function testFork_ERC20CashOutReturnsCorrectAmount() public {
        // Create 1 tier: 100 USDC, supply 10.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: 100e6,
            initialSupply: 10,
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
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        // 50% cashout tax rate (5000 out of 10000).
        (uint256 projectId, address hook) = _launchUSDCProject(tierConfigs, 5000);

        // Pay 100 USDC to mint 1 NFT from tier 1.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory payMeta = _buildPayMetadata(tierIds, true);

        vm.startPrank(payer);
        usdc.approve(address(jbMultiTerminal), 100e6);
        jbMultiTerminal.pay({
            projectId: projectId,
            amount: 100e6,
            token: address(usdc),
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: payMeta
        });
        vm.stopPrank();

        assertEq(IERC721(hook).balanceOf(beneficiary), 1, "beneficiary should own 1 NFT");

        // Cash out the NFT.
        uint256[] memory tokensToCashOut = new uint256[](1);
        tokensToCashOut[0] = _tokenId(1, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(tokensToCashOut);

        uint256 usdcBefore = usdc.balanceOf(beneficiary);

        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: address(usdc),
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: cashOutMeta
        });

        uint256 usdcAfter = usdc.balanceOf(beneficiary);
        uint256 reclaimed = usdcAfter - usdcBefore;

        // With a single payer who is the only holder and 50% cashout tax rate:
        // Bonding curve: base * [(MAX - tax) + tax * (count / supply)] / MAX
        // With count == supply (sole holder cashing out everything):
        // base * [(10000 - 5000) + 5000 * (count/supply)] / 10000 = base * 1 = base (full surplus)
        // Then a 2.5% fee is deducted: net = surplus * (1000 - 25) / 1000
        // surplus = 100e6, net = 100e6 * 975 / 1000 = 97_500_000 = 97.5 USDC
        assertGt(reclaimed, 0, "should have reclaimed some USDC");
        // The reclaim should be close to 97.5 USDC (97_500_000), accounting for potential rounding.
        // With sole holder and count == supply, bonding curve returns full surplus minus fee.
        uint256 expectedNetOfFee = mulDiv(100e6, MAX_FEE - FEE, MAX_FEE);
        assertEq(reclaimed, expectedNetOfFee, "reclaimed USDC should match bonding curve minus 2.5% fee");
    }

    // =========================================================================
    // Test 2: 2.5% fee held on ERC-20 cashout
    // =========================================================================

    /// @notice Verify 2.5% fee is held on ERC-20 cashout by checking the difference between gross and net reclaim.
    function testFork_ERC20CashOutFeeDeduction() public {
        // 1 tier: 200 USDC, supply 10.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: 200e6,
            initialSupply: 10,
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
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        // Use nonzero cashOutTaxRate so the protocol fee (2.5%) is charged on cashouts.
        // With a sole holder (cashOutCount == totalSupply), bonding curve still returns full surplus.
        (uint256 projectId,) = _launchUSDCProject(tierConfigs, 1);

        // Pay 200 USDC to mint 1 NFT.
        uint16[] memory tierIds = new uint16[](1);
        tierIds[0] = 1;
        bytes memory payMeta = _buildPayMetadata(tierIds, true);

        vm.startPrank(payer);
        usdc.approve(address(jbMultiTerminal), 200e6);
        jbMultiTerminal.pay({
            projectId: projectId,
            amount: 200e6,
            token: address(usdc),
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: payMeta
        });
        vm.stopPrank();

        // Cash out.
        uint256[] memory tokensToCashOut = new uint256[](1);
        tokensToCashOut[0] = _tokenId(1, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(tokensToCashOut);

        uint256 usdcBefore = usdc.balanceOf(beneficiary);

        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: address(usdc),
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: cashOutMeta
        });

        uint256 reclaimed = usdc.balanceOf(beneficiary) - usdcBefore;

        // With 0% tax + sole holder: bonding curve returns full surplus = 200 USDC.
        // Fee = 200e6 * 25 / 1000 = 5_000_000 (5 USDC).
        // Net = 200e6 - 5e6 = 195_000_000 (195 USDC).
        uint256 grossReclaim = 200e6;
        uint256 expectedFee = mulDiv(grossReclaim, FEE, MAX_FEE);
        uint256 expectedNet = grossReclaim - expectedFee;

        assertEq(expectedFee, 5e6, "fee should be 5 USDC (2.5% of 200)");
        assertEq(reclaimed, expectedNet, "beneficiary should receive gross minus 2.5% fee");

        // The terminal should still hold the fee amount (held for 28 days).
        // Verify the terminal USDC balance is exactly the fee amount (project balance is 0 after full cashout).
        uint256 terminalBalance = usdc.balanceOf(address(jbMultiTerminal));
        assertEq(terminalBalance, expectedFee, "terminal should hold the fee amount in USDC");
    }

    // =========================================================================
    // Test 3: 721 NFTs burned during ERC-20 cashout
    // =========================================================================

    /// @notice Verify 721 NFTs are burned during cashout (regardless of ERC-20 token type).
    function testFork_ERC20CashOutBurnsNFTs() public {
        // 2 tiers: 50 USDC and 150 USDC.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](2);
        tierConfigs[0] = JB721TierConfig({
            price: 50e6,
            initialSupply: 10,
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
            splitPercent: 0,
            splits: new JBSplit[](0)
        });
        tierConfigs[1] = JB721TierConfig({
            price: 150e6,
            initialSupply: 10,
            votingUnits: 0,
            reserveFrequency: 0,
            reserveBeneficiary: address(0),
            // forge-lint: disable-next-line(unsafe-typecast)
            encodedIPFSUri: bytes32("tier2"),
            category: 2,
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

        // 50% cashout tax rate.
        (uint256 projectId, address hook) = _launchUSDCProject(tierConfigs, 5000);

        // Pay 200 USDC to mint 1 NFT from each tier.
        uint16[] memory tierIds = new uint16[](2);
        tierIds[0] = 1;
        tierIds[1] = 2;
        bytes memory payMeta = _buildPayMetadata(tierIds, true);

        vm.startPrank(payer);
        usdc.approve(address(jbMultiTerminal), 200e6);
        jbMultiTerminal.pay({
            projectId: projectId,
            amount: 200e6,
            token: address(usdc),
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: payMeta
        });
        vm.stopPrank();

        assertEq(IERC721(hook).balanceOf(beneficiary), 2, "beneficiary should own 2 NFTs");
        assertEq(IERC721(hook).ownerOf(_tokenId(1, 1)), beneficiary, "owns tier 1 NFT");
        assertEq(IERC721(hook).ownerOf(_tokenId(2, 1)), beneficiary, "owns tier 2 NFT");

        // Verify store burn counts are 0 before cashout.
        assertEq(store.numberOfBurnedFor(hook, 1), 0, "tier 1: no burns before cashout");
        assertEq(store.numberOfBurnedFor(hook, 2), 0, "tier 2: no burns before cashout");

        // Cash out both NFTs.
        uint256[] memory tokensToCashOut = new uint256[](2);
        tokensToCashOut[0] = _tokenId(1, 1);
        tokensToCashOut[1] = _tokenId(2, 1);
        bytes memory cashOutMeta = _buildCashOutMetadata(tokensToCashOut);

        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: address(usdc),
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: cashOutMeta
        });

        // Verify NFTs are burned.
        assertEq(IERC721(hook).balanceOf(beneficiary), 0, "all NFTs should be burned");
        assertEq(store.numberOfBurnedFor(hook, 1), 1, "tier 1: 1 NFT burned");
        assertEq(store.numberOfBurnedFor(hook, 2), 1, "tier 2: 1 NFT burned");

        // Verify ownerOf reverts for burned tokens (ERC721 standard behavior).
        vm.expectRevert();
        IERC721(hook).ownerOf(_tokenId(1, 1));

        vm.expectRevert();
        IERC721(hook).ownerOf(_tokenId(2, 1));
    }
}
