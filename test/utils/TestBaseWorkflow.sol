// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/core-v6/src/JBController.sol";
import "@bananapus/core-v6/src/JBDirectory.sol";
import "@bananapus/core-v6/src/JBMultiTerminal.sol";
import "@bananapus/core-v6/src/JBFundAccessLimits.sol";
import "@bananapus/core-v6/src/JBFeelessAddresses.sol";
import "@bananapus/core-v6/src/JBTerminalStore.sol";
import "@bananapus/core-v6/src/JBRulesets5_1.sol";
import "@bananapus/core-v6/src/JBPermissions.sol";
import "@bananapus/core-v6/src/JBPrices.sol";
import {JBProjects} from "@bananapus/core-v6/src/JBProjects.sol";
import "@bananapus/core-v6/src/JBSplits.sol";
import "@bananapus/core-v6/src/JBERC20.sol";
import "@bananapus/core-v6/src/JBTokens.sol";

import "@bananapus/core-v6/src/structs/JBAfterPayRecordedContext.sol";
import "@bananapus/core-v6/src/structs/JBAfterCashOutRecordedContext.sol";
import "@bananapus/core-v6/src/structs/JBFee.sol";
import "@bananapus/core-v6/src/structs/JBFundAccessLimitGroup.sol";
import "@bananapus/core-v6/src/structs/JBRuleset.sol";
import "@bananapus/core-v6/src/structs/JBRulesetConfig.sol";
import "@bananapus/core-v6/src/structs/JBRulesetMetadata.sol";
import "@bananapus/core-v6/src/structs/JBPermissionsData.sol";
import "@bananapus/core-v6/src/structs/JBBeforePayRecordedContext.sol";
import "@bananapus/core-v6/src/structs/JBBeforeCashOutRecordedContext.sol";
import "@bananapus/core-v6/src/structs/JBSplit.sol";

import "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import "@bananapus/core-v6/src/interfaces/IJBToken.sol";

import "@bananapus/permission-ids-v6/src/JBPermissionIds.sol";
import "@bananapus/core-v6/src/libraries/JBRulesetMetadataResolver.sol";

import {mulDiv} from "@prb/math/src/Common.sol";

import "forge-std/Test.sol";

import "./AccessJBLib.sol";

import "../../src/structs/JBPayDataHookRulesetConfig.sol";
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
    JBRulesets5_1 internal jbRulesets;
    JBTokens internal jbTokens;
    JBFundAccessLimits internal jbFundAccessLimits;
    JBFeelessAddresses internal jbFeelessAddresses;
    JBSplits internal jbSplits;
    JBController internal jbController;
    JBTerminalStore internal jbTerminalStore;
    JBMultiTerminal internal jbMultiTerminal;
    string internal projectUri;
    IJBToken internal tokenV2;

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

        jbRulesets = new JBRulesets5_1(jbDirectory);
        vm.label(address(jbRulesets), "JBRulesets5_1");

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
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), origin, uint8(nonce));
        } else if (nonce <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), origin, bytes1(0x81), uint8(nonce));
        } else if (nonce <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), origin, bytes1(0x82), uint16(nonce));
        } else if (nonce <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), origin, bytes1(0x83), uint24(nonce));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), origin, bytes1(0x84), uint32(nonce));
        }
        bytes32 hash = keccak256(data);
        assembly ("memory-safe") {
            mstore(0, hash)
            addr := mload(0)
        }
    }
}
