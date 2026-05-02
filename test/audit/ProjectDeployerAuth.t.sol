// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../utils/UnitTestSetup.sol";

import {JB721TiersHookProjectDeployer} from "../../src/JB721TiersHookProjectDeployer.sol";
import {JBDeploy721TiersHookConfig} from "../../src/structs/JBDeploy721TiersHookConfig.sol";
import {JBLaunchRulesetsConfig} from "../../src/structs/JBLaunchRulesetsConfig.sol";
import {JBQueueRulesetsConfig} from "../../src/structs/JBQueueRulesetsConfig.sol";
import {JBPayDataHookRulesetConfig} from "../../src/structs/JBPayDataHookRulesetConfig.sol";
import {JBPayDataHookRulesetMetadata} from "../../src/structs/JBPayDataHookRulesetMetadata.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";
import {JB721InitTiersConfig} from "../../src/structs/JB721InitTiersConfig.sol";
import {JB721TiersHookFlags} from "../../src/structs/JB721TiersHookFlags.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBPermissionIds} from "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

contract MockProjects {
    uint256 internal _count;
    address internal _owner;

    function setup(uint256 count_, address owner_) external {
        _count = count_;
        _owner = owner_;
    }

    function count() external view returns (uint256) {
        return _count;
    }

    function ownerOf(uint256) external view returns (address) {
        return _owner;
    }

    fallback() external {}
}

contract StrictController {
    address internal immutable EXPECTED_CALLER;

    error UnexpectedCaller(address caller);

    constructor(address expectedCaller) {
        EXPECTED_CALLER = expectedCaller;
    }

    fallback() external payable {
        if (msg.sender != EXPECTED_CALLER) revert UnexpectedCaller(msg.sender);
        bytes memory result = abi.encode(uint256(42));
        assembly {
            return(add(result, 32), mload(result))
        }
    }
}

contract Test_ProjectDeployerAuth is UnitTestSetup {
    JB721TiersHookProjectDeployer internal projectDeployer;
    address internal operator = address(0xBEEF);
    uint256 internal testProjectId = 5;

    function setUp() public override {
        super.setUp();

        MockProjects projects = new MockProjects();
        vm.etch(mockJBProjects, address(projects).code);
        MockProjects(mockJBProjects).setup(testProjectId, owner);

        vm.mockCall(mockJBDirectory, abi.encodeWithSelector(IJBDirectory.PROJECTS.selector), abi.encode(mockJBProjects));

        projectDeployer = new JB721TiersHookProjectDeployer(
            IJBDirectory(mockJBDirectory), IJBPermissions(mockJBPermissions), jbHookDeployer, address(0)
        );
    }

    function test_launchRulesetsFor_revertsBeforeDeployingHookIfProjectDeployerMissingControllerPermission() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchRulesetsConfig memory launchConfig) =
            _launchConfig(testProjectId);

        StrictController controller = new StrictController(owner);

        _mockProjectDeployerPermission(JBPermissionIds.LAUNCH_RULESETS, false);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                JB721TiersHookProjectDeployer.JB721TiersHookProjectDeployer_ControllerPermissionMissing.selector,
                owner,
                testProjectId,
                JBPermissionIds.LAUNCH_RULESETS
            )
        );
        projectDeployer.launchRulesetsFor(
            testProjectId, hookConfig, launchConfig, "", IJBController(address(controller)), bytes32(0)
        );
    }

    function test_queueRulesetsOf_revertsBeforeDeployingHookIfProjectDeployerMissingControllerPermission() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBQueueRulesetsConfig memory queueConfig) =
            _queueConfig(testProjectId);

        StrictController controller = new StrictController(owner);

        _mockProjectDeployerPermission(JBPermissionIds.QUEUE_RULESETS, false);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                JB721TiersHookProjectDeployer.JB721TiersHookProjectDeployer_ControllerPermissionMissing.selector,
                owner,
                testProjectId,
                JBPermissionIds.QUEUE_RULESETS
            )
        );
        projectDeployer.queueRulesetsOf(
            testProjectId, hookConfig, queueConfig, IJBController(address(controller)), bytes32(0)
        );
    }

    function test_launchRulesetsFor_checksLaunchPermission() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchRulesetsConfig memory launchConfig) =
            _launchConfig(testProjectId);

        address account = owner;
        StrictController controller = new StrictController(owner);

        // Grant LAUNCH_RULESETS and SET_TERMINALS, deny QUEUE_RULESETS.
        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(
                IJBPermissions.hasPermission.selector,
                operator,
                account,
                testProjectId,
                JBPermissionIds.QUEUE_RULESETS,
                true,
                true
            ),
            abi.encode(false)
        );
        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(
                IJBPermissions.hasPermission.selector,
                operator,
                account,
                testProjectId,
                JBPermissionIds.LAUNCH_RULESETS,
                true,
                true
            ),
            abi.encode(true)
        );
        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(
                IJBPermissions.hasPermission.selector,
                operator,
                account,
                testProjectId,
                JBPermissionIds.SET_TERMINALS,
                true,
                true
            ),
            abi.encode(true)
        );

        _mockProjectDeployerPermission(JBPermissionIds.LAUNCH_RULESETS, false);

        // The operator permission check passes with LAUNCH_RULESETS, then the helper fails explicitly because it has
        // not been permissioned for the controller call it is about to make.
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                JB721TiersHookProjectDeployer.JB721TiersHookProjectDeployer_ControllerPermissionMissing.selector,
                account,
                testProjectId,
                JBPermissionIds.LAUNCH_RULESETS
            )
        );
        projectDeployer.launchRulesetsFor(
            testProjectId, hookConfig, launchConfig, "", IJBController(address(controller)), bytes32(0)
        );
    }

    function test_launchRulesetsFor_revertsBeforeDeployingHookIfProjectDeployerMissingUriPermission() external {
        (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchRulesetsConfig memory launchConfig) =
            _launchConfig(testProjectId);

        StrictController controller = new StrictController(owner);

        _mockProjectDeployerPermission(JBPermissionIds.LAUNCH_RULESETS, true);
        _mockProjectDeployerPermission(JBPermissionIds.SET_TERMINALS, true);
        _mockProjectDeployerPermission(JBPermissionIds.SET_PROJECT_URI, false);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                JB721TiersHookProjectDeployer.JB721TiersHookProjectDeployer_ControllerPermissionMissing.selector,
                owner,
                testProjectId,
                JBPermissionIds.SET_PROJECT_URI
            )
        );
        projectDeployer.launchRulesetsFor(
            testProjectId, hookConfig, launchConfig, "ipfs://project", IJBController(address(controller)), bytes32(0)
        );
    }

    function _mockProjectDeployerPermission(uint256 permissionId, bool allowed) internal {
        vm.mockCall(
            mockJBPermissions,
            abi.encodeWithSelector(
                IJBPermissions.hasPermission.selector,
                address(projectDeployer),
                owner,
                testProjectId,
                permissionId,
                true,
                true
            ),
            abi.encode(allowed)
        );
    }

    function _launchConfig(uint256 projectId_)
        internal
        view
        returns (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchRulesetsConfig memory launchConfig)
    {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: uint104(10),
            initialSupply: uint32(100),
            votingUnits: uint16(0),
            reserveFrequency: uint16(0),
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: tokenUris[0],
            category: uint24(1),
            discountPercent: uint8(0),
            flags: JB721TierConfigFlags({
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cantBeRemoved: false,
                cantIncreaseDiscountPercent: false,
                cantBuyWithCredits: false
            }),
            splitPercent: 0,
            splits: new JBSplit[](0)
        });

        hookConfig = JBDeploy721TiersHookConfig({
            name: name,
            symbol: symbol,
            baseUri: baseUri,
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: contractUri,
            tiersConfig: JB721InitTiersConfig({
                tiers: tierConfigs, currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
            }),
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: false,
                noNewTiersWithReserves: true,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: true
            })
        });

        JBPayDataHookRulesetConfig[] memory rulesetConfigs = new JBPayDataHookRulesetConfig[](1);
        rulesetConfigs[0].mustStartAtOrAfter = 0;
        rulesetConfigs[0].duration = 14;
        rulesetConfigs[0].weight = 1e18;
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

        JBAccountingContext[] memory accountingContexts = new JBAccountingContext[](1);
        accountingContexts[0] = JBAccountingContext({
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18, token: JBConstants.NATIVE_TOKEN
        });
        JBTerminalConfig[] memory terminalConfigs = new JBTerminalConfig[](1);
        terminalConfigs[0] = JBTerminalConfig({
            terminal: IJBTerminal(mockTerminalAddress), accountingContextsToAccept: accountingContexts
        });

        launchConfig = JBLaunchRulesetsConfig({
            // forge-lint: disable-next-line(unsafe-typecast)
            projectId: uint56(projectId_),
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: terminalConfigs,
            memo: "launch"
        });
    }

    function _queueConfig(uint256 projectId_)
        internal
        view
        returns (JBDeploy721TiersHookConfig memory hookConfig, JBQueueRulesetsConfig memory queueConfig)
    {
        JBLaunchRulesetsConfig memory launchConfig;
        (hookConfig, launchConfig) = _launchConfig(projectId_);
        queueConfig = JBQueueRulesetsConfig({
            // forge-lint: disable-next-line(unsafe-typecast)
            projectId: uint56(projectId_),
            rulesetConfigurations: launchConfig.rulesetConfigurations,
            memo: "queue"
        });
    }
}
