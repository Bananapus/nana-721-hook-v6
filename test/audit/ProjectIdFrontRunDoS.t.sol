// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

contract ProjectIdFrontRunDoSTest is Test {
    function test_vulnerableCountBased721ProjectLaunchCanBeFrontRun() public {
        MockProjects projects = new MockProjects(12, 14);
        MockController controller = new MockController(14);
        MockHookDeployer hookDeployer = new MockHookDeployer();
        VulnerableHookProjectDeployerHarness harness = new VulnerableHookProjectDeployerHarness(projects, hookDeployer);

        vm.expectRevert();
        harness.launchProjectFor(controller);
    }

    function test_reserved721ProjectIdCannotBeInvalidatedByEarlierCreations() public {
        MockProjects projects = new MockProjects(12, 14);
        MockController controller = new MockController(14);
        MockHookDeployer hookDeployer = new MockHookDeployer();
        FixedHookProjectDeployerHarness harness = new FixedHookProjectDeployerHarness(projects, hookDeployer);

        uint256 projectId = harness.launchProjectFor(controller);

        assertEq(projectId, 14);
        assertEq(projects.lastOwner(), address(harness));
        assertEq(hookDeployer.lastHookProjectId(), 14);
        assertEq(controller.lastLaunchedProjectId(), 14);
    }
}

contract VulnerableHookProjectDeployerHarness {
    MockProjects internal immutable PROJECTS;
    MockHookDeployer internal immutable HOOK_DEPLOYER;

    constructor(MockProjects projects, MockHookDeployer hookDeployer) {
        PROJECTS = projects;
        HOOK_DEPLOYER = hookDeployer;
    }

    function launchProjectFor(MockController controller) external returns (uint256 projectId) {
        projectId = PROJECTS.count() + 1;
        HOOK_DEPLOYER.deployHookFor(projectId);

        controller.launchProjectFor();
        assert(projectId == controller.lastLaunchedProjectId());
    }
}

contract FixedHookProjectDeployerHarness {
    MockProjects internal immutable PROJECTS;
    MockHookDeployer internal immutable HOOK_DEPLOYER;

    constructor(MockProjects projects, MockHookDeployer hookDeployer) {
        PROJECTS = projects;
        HOOK_DEPLOYER = hookDeployer;
    }

    function launchProjectFor(MockController controller) external returns (uint256 projectId) {
        projectId = PROJECTS.createFor(address(this));
        HOOK_DEPLOYER.deployHookFor(projectId);

        controller.launchRulesetsFor(projectId);
    }
}

contract MockProjects {
    uint256 internal immutable _count;
    uint256 internal immutable _reservedId;

    address public lastOwner;

    constructor(uint256 count_, uint256 reservedId_) {
        _count = count_;
        _reservedId = reservedId_;
    }

    function count() external view returns (uint256) {
        return _count;
    }

    function createFor(address owner) external returns (uint256) {
        lastOwner = owner;
        return _reservedId;
    }
}

contract MockController {
    uint256 internal immutable _launchedId;

    constructor(uint256 launchedId_) {
        _launchedId = launchedId_;
    }

    function launchProjectFor() external view returns (uint256) {
        return _launchedId;
    }

    function lastLaunchedProjectId() external view returns (uint256) {
        return _launchedId;
    }

    function launchRulesetsFor(uint256 projectId) external view {
        require(projectId == _launchedId, "BAD_PROJECT_ID");
    }
}

contract MockHookDeployer {
    uint256 public lastHookProjectId;

    function deployHookFor(uint256 projectId) external {
        lastHookProjectId = projectId;
    }
}
