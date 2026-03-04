// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
import "@bananapus/core-v6/src/interfaces/IJBController.sol";
import "@bananapus/core-v6/src/interfaces/IJBRulesets.sol";
import "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../../src/JB721TiersHookProjectDeployer.sol";
import "../../src/JB721TiersHookStore.sol";
import "../../src/interfaces/IJB721TiersHookProjectDeployer.sol";
import "../../src/structs/JBLaunchProjectConfig.sol";
import "../../src/structs/JB721InitTiersConfig.sol";

import "../utils/UnitTestSetup.sol";

contract Test_ProjectDeployer_Unit is UnitTestSetup {
    using stdStorage for StdStorage;

    IJB721TiersHookProjectDeployer deployer;

    function setUp() public override {
        super.setUp();

        deployer = new JB721TiersHookProjectDeployer(
            IJBDirectory(mockJBDirectory), IJBPermissions(mockJBPermissions), jbHookDeployer, address(0)
        );
    }

    function test_launchProjectFor_shouldLaunchProject(uint256 previousProjectId, bytes32 salt) external {
        // Include launching the protocol project (project ID 1).
        previousProjectId = bound(previousProjectId, 0, type(uint88).max - 1);

        (JBDeploy721TiersHookConfig memory deploy721TiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();

        // Mock and check.
        mockAndExpect(
            mockJBDirectory, abi.encodeWithSelector(IJBDirectory.PROJECTS.selector), abi.encode(mockJBProjects)
        );
        mockAndExpect(mockJBProjects, abi.encodeWithSelector(IERC721.ownerOf.selector), abi.encode(owner));
        mockAndExpect(mockJBProjects, abi.encodeWithSelector(IJBProjects.count.selector), abi.encode(previousProjectId));
        mockAndExpect(
            mockJBController, abi.encodeWithSelector(IJBController.launchProjectFor.selector), abi.encode(true)
        );

        // Launch the project.
        (uint256 projectId,) = deployer.launchProjectFor(
            owner, deploy721TiersHookConfig, launchProjectConfig, IJBController(mockJBController), salt
        );

        // Check: does the project have the correct project ID (the previous ID incremented by 1)?
        assertEq(previousProjectId, projectId - 1);
    }
}
