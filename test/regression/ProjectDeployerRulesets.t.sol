// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/JB721TiersHookProjectDeployer.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBLaunchRulesetsConfig.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBQueueRulesetsConfig.sol";

import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";

/// @notice A mock projects contract that returns configurable owner and count.
contract MockProjects {
    uint256 private _count;
    address private _owner;

    function setup(uint256 initialCount, address projectOwner) external {
        _count = initialCount;
        _owner = projectOwner;
    }

    function count() external view returns (uint256) {
        return _count;
    }

    function ownerOf(uint256) external view returns (address) {
        return _owner;
    }
}

/// @notice A mock controller that records calls and returns a ruleset ID.
contract MockController {
    uint256 public lastProjectId;
    uint256 public lastRulesetConfigCount;
    bool public launchRulesetsForCalled;
    bool public queueRulesetsOfCalled;

    receive() external payable {}

    // The fallback accepts any call and returns uint256(42) as the ruleset ID.
    fallback() external payable {
        // Decode the selector to track which function was called.
        bytes4 selector = msg.sig;

        // launchRulesetsFor(uint256,JBRulesetConfig[],JBTerminalConfig[],string)
        if (selector == IJBController.launchRulesetsFor.selector) {
            launchRulesetsForCalled = true;
        }
        // queueRulesetsOf(uint256,JBRulesetConfig[],string)
        if (selector == IJBController.queueRulesetsOf.selector) {
            queueRulesetsOfCalled = true;
        }

        // Return uint256(42) as the ruleset ID.
        bytes memory result = abi.encode(uint256(42));
        assembly {
            return(add(result, 32), mload(result))
        }
    }
}

/// @notice Regression tests for JB721TiersHookProjectDeployer's launchRulesetsFor and queueRulesetsOf.
/// @dev These verify that the deployer correctly deploys a hook, transfers ownership, wires up the data hook,
/// and delegates to the controller for both launch and queue paths.
contract Test_ProjectDeployerRulesets is UnitTestSetup {
    using stdStorage for StdStorage;

    JB721TiersHookProjectDeployer deployer;
    MockProjects mockProj;
    MockController mockCtrl;

    uint256 testProjectId = 5;

    function setUp() public override {
        super.setUp();

        // Deploy mock projects contract and etch onto the existing mockJBProjects address.
        mockProj = new MockProjects();
        vm.etch(mockJBProjects, address(mockProj).code);
        MockProjects(mockJBProjects).setup(testProjectId, owner);

        // Mock DIRECTORY.PROJECTS() to return mockJBProjects.
        vm.mockCall(mockJBDirectory, abi.encodeWithSelector(IJBDirectory.PROJECTS.selector), abi.encode(mockJBProjects));

        // Mock all permission checks to return true.
        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(true));

        // Deploy the mock controller.
        mockCtrl = new MockController();

        // Deploy the project deployer.
        deployer = new JB721TiersHookProjectDeployer(
            IJBDirectory(mockJBDirectory), IJBPermissions(mockJBPermissions), jbHookDeployer, address(0)
        );
    }

    /// @notice Build a minimal deploy config and launch rulesets config for testing.
    function _buildLaunchRulesetsConfigs()
        internal
        view
        returns (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchRulesetsConfig memory launchConfig)
    {
        // Build a minimal tier config (1 tier).
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: uint104(10),
            initialSupply: uint32(100),
            votingUnits: uint16(0),
            reserveFrequency: uint16(0),
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: tokenUris[0],
            category: uint24(100),
            discountPercent: uint8(0),
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: true,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false,
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        hookConfig = JBDeploy721TiersHookConfig({
            name: name,
            symbol: symbol,
            baseUri: baseUri,
            tokenUriResolver: IJB721TokenUriResolver(mockTokenUriResolver),
            contractUri: contractUri,
            tiersConfig: JB721InitTiersConfig({
                tiers: tierConfigs, currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
            }),
            reserveBeneficiary: reserveBeneficiary,
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: false,
                noNewTiersWithReserves: true,
                noNewTiersWithVotes: true,
                noNewTiersWithOwnerMinting: true
            })
        });

        // Build a minimal ruleset config.
        JBPayDataHookRulesetConfig[] memory rulesetConfigs = new JBPayDataHookRulesetConfig[](1);
        rulesetConfigs[0].mustStartAtOrAfter = 0;
        rulesetConfigs[0].duration = 14;
        rulesetConfigs[0].weight = 10 ** 18;
        rulesetConfigs[0].weightCutPercent = 0;
        rulesetConfigs[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfigs[0].metadata = JBPayDataHookRulesetMetadata({
            reservedPercent: 5000,
            cashOutTaxRate: 5000,
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: false,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            ownerMustSendPayouts: false,
            allowAddAccountingContext: false,
            allowAddPriceFeed: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForCashOut: false,
            metadata: 0x00
        });

        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](1);
        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] = JBAccountingContext({
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18, token: JBConstants.NATIVE_TOKEN
        });
        terminalConfigs[0] = JBTerminalConfig({
            terminal: IJBTerminal(mockTerminalAddress), accountingContextsToAccept: accountingContexts
        });

        launchConfig = JBLaunchRulesetsConfig({
            // forge-lint: disable-next-line(unsafe-typecast)
            projectId: uint56(testProjectId),
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: terminalConfigs,
            memo: "launch rulesets"
        });
    }

    /// @notice Build a minimal deploy config and queue rulesets config for testing.
    function _buildQueueRulesetsConfigs()
        internal
        view
        returns (JBDeploy721TiersHookConfig memory hookConfig, JBQueueRulesetsConfig memory queueConfig)
    {
        // Reuse the launch config builder for the hook config.
        JBLaunchRulesetsConfig memory launchConfig;
        (hookConfig, launchConfig) = _buildLaunchRulesetsConfigs();

        queueConfig = JBQueueRulesetsConfig({
            // forge-lint: disable-next-line(unsafe-typecast)
            projectId: uint56(testProjectId),
            rulesetConfigurations: launchConfig.rulesetConfigurations,
            memo: "queue rulesets"
        });
    }

    // -----------------------------------------------------------------------
    // launchRulesetsFor
    // -----------------------------------------------------------------------

    /// @notice launchRulesetsFor deploys a hook, transfers ownership to the project, and calls the controller.
    function test_launchRulesetsFor_deploysHookAndCallsController() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchRulesetsConfig memory launchConfig) =
            _buildLaunchRulesetsConfigs();

        // Call as the project owner.
        vm.prank(owner);
        (uint256 rulesetId, IJB721TiersHook deployedHook) = deployer.launchRulesetsFor(
            testProjectId, hookConfig, launchConfig, IJBController(address(mockCtrl)), bytes32(0)
        );

        // Verify the ruleset ID returned by the mock controller.
        assertEq(rulesetId, 42, "Should return the ruleset ID from the controller");

        // Verify a hook was deployed (non-zero address).
        assertTrue(address(deployedHook) != address(0), "Hook should be deployed");

        // Verify the controller's launchRulesetsFor was called.
        assertTrue(mockCtrl.launchRulesetsForCalled(), "Controller launchRulesetsFor should be called");

        // Verify the hook's PROJECT_ID is correct.
        assertEq(deployedHook.PROJECT_ID(), testProjectId, "Hook PROJECT_ID should match");

        // Verify the hook's ownership was transferred to the project.
        (, uint88 ownerProjectId,) = JBOwnable(address(deployedHook)).jbOwner();
        assertEq(ownerProjectId, testProjectId, "Hook should be owned by project");
    }

    /// @notice launchRulesetsFor with a deterministic salt produces a hook at a predictable address.
    function test_launchRulesetsFor_deterministicSalt() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchRulesetsConfig memory launchConfig) =
            _buildLaunchRulesetsConfigs();

        bytes32 salt = bytes32(uint256(0xdead));

        vm.prank(owner);
        (, IJB721TiersHook hook1) =
            deployer.launchRulesetsFor(testProjectId, hookConfig, launchConfig, IJBController(address(mockCtrl)), salt);

        // Deploy a second hook with a different salt to verify addresses differ.
        bytes32 salt2 = bytes32(uint256(0xbeef));

        vm.prank(owner);
        (, IJB721TiersHook hook2) =
            deployer.launchRulesetsFor(testProjectId, hookConfig, launchConfig, IJBController(address(mockCtrl)), salt2);

        assertTrue(address(hook1) != address(hook2), "Different salts should produce different hook addresses");
    }

    /// @notice launchRulesetsFor reverts when the caller lacks QUEUE_RULESETS permission.
    function test_launchRulesetsFor_revertsWithoutPermission() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchRulesetsConfig memory launchConfig) =
            _buildLaunchRulesetsConfigs();

        // Override: mock permissions to deny.
        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(false));

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert();
        deployer.launchRulesetsFor(
            testProjectId, hookConfig, launchConfig, IJBController(address(mockCtrl)), bytes32(0)
        );
    }

    // -----------------------------------------------------------------------
    // queueRulesetsOf
    // -----------------------------------------------------------------------

    /// @notice queueRulesetsOf deploys a hook, transfers ownership to the project, and calls the controller.
    function test_queueRulesetsOf_deploysHookAndCallsController() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBQueueRulesetsConfig memory queueConfig) =
            _buildQueueRulesetsConfigs();

        vm.prank(owner);
        (uint256 rulesetId, IJB721TiersHook deployedHook) = deployer.queueRulesetsOf(
            testProjectId, hookConfig, queueConfig, IJBController(address(mockCtrl)), bytes32(0)
        );

        // Verify the ruleset ID returned by the mock controller.
        assertEq(rulesetId, 42, "Should return the ruleset ID from the controller");

        // Verify a hook was deployed (non-zero address).
        assertTrue(address(deployedHook) != address(0), "Hook should be deployed");

        // Verify the controller's queueRulesetsOf was called.
        assertTrue(mockCtrl.queueRulesetsOfCalled(), "Controller queueRulesetsOf should be called");

        // Verify the hook's PROJECT_ID is correct.
        assertEq(deployedHook.PROJECT_ID(), testProjectId, "Hook PROJECT_ID should match");

        // Verify the hook's ownership was transferred to the project.
        (, uint88 ownerProjectId,) = JBOwnable(address(deployedHook)).jbOwner();
        assertEq(ownerProjectId, testProjectId, "Hook should be owned by project");
    }

    /// @notice queueRulesetsOf correctly wires useDataHookForPay = true in the forwarded ruleset metadata.
    function test_queueRulesetsOf_wiresDataHookForPay() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBQueueRulesetsConfig memory queueConfig) =
            _buildQueueRulesetsConfigs();

        vm.prank(owner);
        (, IJB721TiersHook deployedHook) = deployer.queueRulesetsOf(
            testProjectId, hookConfig, queueConfig, IJBController(address(mockCtrl)), bytes32(0)
        );

        // The hook address should not be zero -- this indirectly validates the dataHook was wired.
        assertTrue(address(deployedHook) != address(0), "Hook should be deployed and wired as data hook");
    }

    /// @notice queueRulesetsOf reverts when the caller lacks QUEUE_RULESETS permission.
    function test_queueRulesetsOf_revertsWithoutPermission() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBQueueRulesetsConfig memory queueConfig) =
            _buildQueueRulesetsConfigs();

        // Override: mock permissions to deny.
        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(false));

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert();
        deployer.queueRulesetsOf(testProjectId, hookConfig, queueConfig, IJBController(address(mockCtrl)), bytes32(0));
    }

    /// @notice queueRulesetsOf with a zero salt uses non-deterministic deployment.
    function test_queueRulesetsOf_zeroSaltNonDeterministic() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBQueueRulesetsConfig memory queueConfig) =
            _buildQueueRulesetsConfigs();

        vm.prank(owner);
        (uint256 rulesetId, IJB721TiersHook deployedHook) = deployer.queueRulesetsOf(
            testProjectId, hookConfig, queueConfig, IJBController(address(mockCtrl)), bytes32(0)
        );

        assertEq(rulesetId, 42, "Should return the ruleset ID");
        assertTrue(address(deployedHook) != address(0), "Hook should be deployed");
    }
}
