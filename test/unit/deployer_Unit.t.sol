// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/interfaces/IJBController.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/interfaces/IJBRulesets.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@bananapus/core-v6/src/interfaces/IJBPrices.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/JB721TiersHookProjectDeployer.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/JB721TiersHookStore.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/interfaces/IJB721TiersHookProjectDeployer.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JBLaunchProjectConfig.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../../src/structs/JB721InitTiersConfig.sol";

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";

/// @dev A minimal mock for IJBProjects whose `count()` can be bumped by the mock controller.
contract MockJBProjectsCount {
    uint256 private _count;
    address private _owner;

    function setup(uint256 initialCount, address projectOwner) external {
        _count = initialCount;
        _owner = projectOwner;
    }

    function count() external view returns (uint256) {
        return _count;
    }

    function setCount(uint256 newCount) external {
        _count = newCount;
    }

    function ownerOf(uint256) external view returns (address) {
        return _owner;
    }
}

/// @dev A mock controller whose fallback bumps the projects mock count by 1 (simulating real behaviour)
/// and returns a truthy value for any function call.
contract MockLaunchController {
    MockJBProjectsCount private _projects;

    constructor(MockJBProjectsCount projects) {
        _projects = projects;
    }

    fallback() external payable {
        // Bump projects count by 1 -- simulates a new project being created.
        _projects.setCount(_projects.count() + 1);
        // Return `uint256(1)` which is truthy for the deployer's expected return.
        bytes memory result = abi.encode(uint256(1));
        assembly {
            return(add(result, 32), mload(result))
        }
    }
}

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

        // Deploy a real MockJBProjectsCount implementation and etch its code onto the existing mockJBProjects address.
        // This is necessary because the hook's immutable PROJECTS is set to mockJBProjects during the hook
        // implementation's constructor (in UnitTestSetup.setUp). By etching real contract code there, both the
        // deployer's DIRECTORY.PROJECTS().count() path and the hook's PROJECTS.count() path hit the same contract.
        MockJBProjectsCount projectsImpl = new MockJBProjectsCount();
        vm.etch(mockJBProjects, address(projectsImpl).code);
        MockJBProjectsCount(mockJBProjects).setup(previousProjectId, owner);

        // Mock DIRECTORY.PROJECTS() to return mockJBProjects (which now has real code).
        vm.mockCall(mockJBDirectory, abi.encodeWithSelector(IJBDirectory.PROJECTS.selector), abi.encode(mockJBProjects));

        // Deploy a mock controller that bumps count when launchProjectFor is called.
        MockLaunchController mockController = new MockLaunchController(MockJBProjectsCount(mockJBProjects));

        // Launch the project using our mock controller that bumps count.
        (uint256 projectId,) = deployer.launchProjectFor(
            owner, deploy721TiersHookConfig, launchProjectConfig, IJBController(address(mockController)), salt
        );

        // Check: does the project have the correct project ID (the previous ID incremented by 1)?
        assertEq(previousProjectId, projectId - 1);
    }
}
