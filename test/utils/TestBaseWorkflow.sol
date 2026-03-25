// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
import "@bananapus/core-v6/src/structs/JBAfterPayRecordedContext.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBAfterCashOutRecordedContext.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBFee.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBRuleset.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBBeforePayRecordedContext.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBBeforeCashOutRecordedContext.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/structs/JBSplit.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/interfaces/IJBToken.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/libraries/JBRulesetMetadataResolver.sol";

// forge-lint: disable-next-line(unused-import)
import {mulDiv} from "@prb/math/src/Common.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "forge-std/Test.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "./AccessJBLib.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBPayDataHookRulesetConfig.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBPayDataHookRulesetMetadata.sol";

/// @notice Base contract for Juicebox system tests.
/// @dev Provides common functionality, such as deploying contracts on test setup.
contract TestBaseWorkflow is Test {
    //*********************************************************************//
    // --------------------- internal stored properties ------------------- //
    //*********************************************************************//

    address internal projectOwner = address(123);
    address internal beneficiary = address(69_420);
    address internal caller = address(696_969);

    JBPermissions internal jbPermissions;
    JBProjects internal jbProjects;
    JBPrices internal jbPrices;
    JBDirectory internal jbDirectory;
    JBRulesets internal jbRulesets;
    JBTokens internal jbTokens;
    JBFundAccessLimits internal jbFundAccessLimits;
    JBFeelessAddresses internal jbFeelessAddresses;
    JBSplits internal jbSplits;
    JBController internal jbController;
    JBTerminalStore internal jbTerminalStore;
    JBMultiTerminal internal jbMultiTerminal;
    string internal projectUri;
    IJBToken internal tokenV2;

    // forge-lint: disable-next-line(mixed-case-variable)
    AccessJBLib internal accessJBLib;

    //*********************************************************************//
    // --------------------------- test setup ---------------------------- //
    //*********************************************************************//

    // Deploys and initializes contracts for testing.
    function setUp() public virtual {
        // ---- Set up project ---- //
        jbPermissions = new JBPermissions(address(0));
        vm.label(address(jbPermissions), "JBPermissions");

        jbProjects = new JBProjects(projectOwner, address(0), address(0));
        vm.label(address(jbProjects), "JBProjects");

        jbDirectory = new JBDirectory(jbPermissions, jbProjects, projectOwner);
        vm.label(address(jbDirectory), "JBDirectory");

        jbPrices = new JBPrices(jbDirectory, jbPermissions, jbProjects, projectOwner, address(0));
        vm.label(address(jbPrices), "JBPrices");

        jbRulesets = new JBRulesets(jbDirectory);
        vm.label(address(jbRulesets), "JBRulesets");

        jbFundAccessLimits = new JBFundAccessLimits(jbDirectory);
        vm.label(address(jbFundAccessLimits), "JBFundAccessLimits");

        jbFeelessAddresses = new JBFeelessAddresses(address(69));
        vm.label(address(jbFeelessAddresses), "JBFeelessAddresses");

        jbTokens = new JBTokens(jbDirectory, new JBERC20());
        vm.label(address(jbTokens), "JBTokens");

        jbSplits = new JBSplits(jbDirectory);
        vm.label(address(jbSplits), "JBSplits");

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
        vm.label(address(jbController), "JBController");

        vm.prank(projectOwner);
        jbDirectory.setIsAllowedToSetFirstController(address(jbController), true);

        jbTerminalStore = new JBTerminalStore(jbDirectory, jbPrices, jbRulesets);
        vm.label(address(jbTerminalStore), "JBTerminalStore");

        accessJBLib = new AccessJBLib();

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
        vm.label(address(jbMultiTerminal), "JBMultiTerminal");

        projectUri = "myIPFSHash";

        // ---- general setup ---- //
        vm.deal(beneficiary, 100 ether);
        vm.deal(projectOwner, 100 ether);
        vm.deal(caller, 100 ether);

        vm.label(projectOwner, "projectOwner");
        vm.label(beneficiary, "beneficiary");
        vm.label(caller, "caller");
    }

    //https://ethereum.stackexchange.com/questions/24248/how-to-calculate-an-ethereum-contracts-address-during-its-creation-using-the-so
    function addressFrom(address origin, uint256 nonce) internal pure returns (address addr) {
        bytes memory data;
        if (nonce == 0x00) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), origin, bytes1(0x80));
        } else if (nonce <= 0x7f) {
            // forge-lint: disable-next-line(unsafe-typecast)
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), origin, uint8(nonce));
        } else if (nonce <= 0xff) {
            // forge-lint: disable-next-line(unsafe-typecast)
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), origin, bytes1(0x81), uint8(nonce));
        } else if (nonce <= 0xffff) {
            // forge-lint: disable-next-line(unsafe-typecast)
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), origin, bytes1(0x82), uint16(nonce));
        } else if (nonce <= 0xffffff) {
            // forge-lint: disable-next-line(unsafe-typecast)
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), origin, bytes1(0x83), uint24(nonce));
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), origin, bytes1(0x84), uint32(nonce));
        }
        bytes32 hash = keccak256(data);
        assembly ("memory-safe") {
            mstore(0, hash)
            addr := mload(0)
        }
    }
}
