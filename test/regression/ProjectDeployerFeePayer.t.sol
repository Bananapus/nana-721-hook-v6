// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";

import {JB721TiersHookProjectDeployer} from "../../src/JB721TiersHookProjectDeployer.sol";
import {JBDeploy721TiersHookConfig} from "../../src/structs/JBDeploy721TiersHookConfig.sol";
import {JBLaunchProjectConfig} from "../../src/structs/JBLaunchProjectConfig.sol";
import {JBPayDataHookRulesetConfig} from "../../src/structs/JBPayDataHookRulesetConfig.sol";
import {JBPayDataHookRulesetMetadata} from "../../src/structs/JBPayDataHookRulesetMetadata.sol";
import {JB721TierConfigFlags} from "../../src/structs/JB721TierConfigFlags.sol";

import {IJBController} from "@bananapus/core-v6/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPayerTracker} from "@bananapus/core-v6/src/interfaces/IJBPayerTracker.sol";
import {IJBPermissions} from "@bananapus/core-v6/src/interfaces/IJBPermissions.sol";
import {JBAccountingContext} from "@bananapus/core-v6/src/structs/JBAccountingContext.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBTerminalConfig} from "@bananapus/core-v6/src/structs/JBTerminalConfig.sol";

/// @notice A mock projects contract that records the deployer's advertised fee payer while `createFor` runs.
/// @dev `createFor` probes its caller (the project deployer) back through `IJBPayerTracker.originalPayer()` so the
/// test can assert the deployer advertises the resolved payer for the duration of the forwarded creation fee, just as
/// the real `JBProjects` does before paying the fee receiver.
contract RecordingMockProjects {
    uint256 internal _count;

    address public observedPayerDuringCreate;
    uint256 public lastCreateValue;

    function setup(uint256 count_) external {
        _count = count_;
    }

    function count() external view returns (uint256) {
        return _count;
    }

    function createFor(address) external payable returns (uint256 projectId) {
        // Probe the caller (the deployer) for the payer it is advertising for this forwarded fee.
        observedPayerDuringCreate = IJBPayerTracker(msg.sender).originalPayer();
        lastCreateValue = msg.value;
        return ++_count;
    }

    function ownerOf(uint256) external view returns (address) {
        return address(this);
    }

    function safeTransferFrom(address, address, uint256) external {}

    receive() external payable {}

    fallback() external payable {}
}

/// @notice A mock controller that accepts the deployer's `launchRulesetsFor` call.
contract RecordingMockController {
    bool public launchRulesetsForCalled;

    receive() external payable {}

    fallback() external payable {
        if (msg.sig == IJBController.launchRulesetsFor.selector) launchRulesetsForCalled = true;

        // Return uint256(42) as the ruleset ID for any call.
        bytes memory result = abi.encode(uint256(42));
        assembly {
            return(add(result, 32), mload(result))
        }
    }
}

/// @notice Regression tests proving `JB721TiersHookProjectDeployer` advertises the resolved fee payer to `JBProjects`
/// while forwarding a project creation fee, so a `pay`-routing fee receiver credits the end user instead of the
/// deployer.
contract Test_ProjectDeployerFeePayer is UnitTestSetup {
    JB721TiersHookProjectDeployer internal deployer;
    RecordingMockProjects internal mockProj;
    RecordingMockController internal mockCtrl;

    function setUp() public override {
        super.setUp();

        // Etch the recording projects mock onto the shared mock projects address.
        mockProj = new RecordingMockProjects();
        vm.etch(mockJBProjects, address(mockProj).code);
        RecordingMockProjects(payable(mockJBProjects)).setup(0);

        // Route `DIRECTORY.PROJECTS()` to the recording projects mock.
        vm.mockCall(mockJBDirectory, abi.encodeWithSelector(IJBDirectory.PROJECTS.selector), abi.encode(mockJBProjects));

        mockCtrl = new RecordingMockController();

        deployer = new JB721TiersHookProjectDeployer(
            IJBDirectory(mockJBDirectory), IJBPermissions(mockJBPermissions), jbHookDeployer, address(0)
        );
    }

    /// @notice The deployer implements `IJBPayerTracker` and leaves `originalPayer` cleared between launches.
    function test_implementsPayerTrackerAndClearsByDefault() external {
        // The deployer satisfies the `IJBPayerTracker` ABI: `originalPayer()` is callable and cleared by default.
        assertEq(IJBPayerTracker(address(deployer)).originalPayer(), address(0), "originalPayer cleared by default");
    }

    /// @notice `launchProjectFor` advertises the calling EOA as the resolved fee payer during `createFor`, then clears
    /// it once the call returns.
    function test_launchProjectFor_advertisesResolvedFeePayer() external {
        address payer = makeAddr("feePayer");

        (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchProjectConfig memory launchConfig) = _launchConfig();

        vm.prank(payer);
        deployer.launchProjectFor(payer, hookConfig, launchConfig, IJBController(address(mockCtrl)), bytes32(0));

        // The deployer advertised the EOA payer to `JBProjects` for the duration of the forwarded creation fee.
        assertEq(
            RecordingMockProjects(payable(mockJBProjects)).observedPayerDuringCreate(),
            payer,
            "deployer advertised the resolved payer during createFor"
        );

        // The transient payer is cleared once the launch returns.
        assertEq(deployer.originalPayer(), address(0), "originalPayer cleared after launch");
    }

    /// @notice A multi-hop forwarder that is itself an `IJBPayerTracker` resolves to its upstream payer.
    function test_launchProjectFor_resolvesUpstreamPayerFromForwarder() external {
        address upstream = makeAddr("upstreamPayer");

        (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchProjectConfig memory launchConfig) = _launchConfig();

        // A contract caller advertising an upstream payer.
        MockForwarder forwarder = new MockForwarder(upstream);

        vm.prank(address(forwarder));
        deployer.launchProjectFor(upstream, hookConfig, launchConfig, IJBController(address(mockCtrl)), bytes32(0));

        assertEq(
            RecordingMockProjects(payable(mockJBProjects)).observedPayerDuringCreate(),
            upstream,
            "deployer resolved the forwarder's upstream payer"
        );
    }

    function _launchConfig()
        internal
        view
        returns (JBDeploy721TiersHookConfig memory hookConfig, JBLaunchProjectConfig memory launchConfig)
    {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: uint104(10),
            initialSupply: uint32(100),
            votingUnits: uint16(0),
            reserveFrequency: uint16(0),
            reserveBeneficiary: reserveBeneficiary,
            encodedIpfsUri: tokenUris[0],
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
            scopeCashOutsToLocalBalances: true,
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

        launchConfig = JBLaunchProjectConfig({
            projectUri: "",
            rulesetConfigurations: rulesetConfigs,
            terminalConfigurations: terminalConfigs,
            memo: "launch"
        });
    }
}

/// @notice A minimal `IJBPayerTracker` forwarder used to prove upstream payer resolution.
contract MockForwarder is IJBPayerTracker {
    address public immutable override originalPayer;

    constructor(address payer) {
        originalPayer = payer;
    }
}
