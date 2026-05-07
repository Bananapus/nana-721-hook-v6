// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {JB721CheckpointsDeployer} from "../../src/JB721CheckpointsDeployer.sol";
import {IJB721CheckpointsDeployer} from "../../src/interfaces/IJB721CheckpointsDeployer.sol";
import {IJB721Checkpoints} from "../../src/interfaces/IJB721Checkpoints.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";

/// @notice regression fix: access control tests for JB721CheckpointsDeployer.deploy().
/// @dev The deployer must only allow the hook address itself (msg.sender == hook) to call deploy().
contract Test_JB721CheckpointsDeployer_AccessControl is Test {
    JB721CheckpointsDeployer deployer;
    address mockStore;

    function setUp() public {
        mockStore = makeAddr("mockStore");
        vm.etch(mockStore, new bytes(0x69));
        deployer = new JB721CheckpointsDeployer(IJB721TiersHookStore(mockStore));
    }

    // ═══════════════════════════════════════════════════════════
    // Test 1: Calling deploy() from the hook address succeeds
    // ═══════════════════════════════════════════════════════════

    /// @notice deploy() succeeds when msg.sender == hook parameter.
    function test_deploy_succeedsWhenCallerIsHook() public {
        address hookAddr = makeAddr("hook");

        // Call deploy from the hook address, passing itself as the hook parameter.
        vm.prank(hookAddr);
        IJB721Checkpoints module = deployer.deploy(hookAddr);

        // Verify the module was deployed (non-zero address).
        assertTrue(address(module) != address(0), "Module should be deployed");
    }

    // ═══════════════════════════════════════════════════════════
    // Test 2: Calling deploy() from any other address reverts
    // ═══════════════════════════════════════════════════════════

    /// @notice deploy() reverts with Unauthorized when msg.sender != hook.
    function test_deploy_revertsWhenCallerIsNotHook() public {
        address hookAddr = makeAddr("hook");
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        vm.expectRevert(IJB721CheckpointsDeployer.JB721CheckpointsDeployer_Unauthorized.selector);
        deployer.deploy(hookAddr);
    }

    /// @notice deploy() reverts when caller passes their own address as hook but is not the actual hook.
    function test_deploy_revertsWhenCallerPassesSelfButIsNotHook() public {
        address attacker = makeAddr("attacker");
        address realHook = makeAddr("realHook");

        // Attacker tries to pass realHook as the hook parameter but calls from their own address.
        vm.prank(attacker);
        vm.expectRevert(IJB721CheckpointsDeployer.JB721CheckpointsDeployer_Unauthorized.selector);
        deployer.deploy(realHook);
    }

    // ═══════════════════════════════════════════════════════════
    // Test 3: Front-running scenario
    // ═══════════════════════════════════════════════════════════

    /// @notice An attacker cannot front-run the hook by calling deploy() with the hook's address.
    ///         Since msg.sender must equal hook, the attacker's tx reverts.
    function test_deploy_frontRunningRevertsForAttacker() public {
        address hookAddr = makeAddr("hook");
        address frontRunner = makeAddr("frontRunner");

        // Front-runner attempts to call deploy with the hook's address before the hook does.
        vm.prank(frontRunner);
        vm.expectRevert(IJB721CheckpointsDeployer.JB721CheckpointsDeployer_Unauthorized.selector);
        deployer.deploy(hookAddr);

        // The legitimate hook can still deploy successfully after the failed front-run attempt.
        vm.prank(hookAddr);
        IJB721Checkpoints module = deployer.deploy(hookAddr);
        assertTrue(address(module) != address(0), "Hook should deploy successfully after failed front-run");
    }

    /// @notice An attacker who calls deploy(attacker) from their own address gets a clone
    ///         for themselves, but this does NOT affect the real hook's future deployment.
    function test_deploy_attackerDeploysOwnClone_doesNotAffectRealHook() public {
        address hookAddr = makeAddr("hook");
        address attacker = makeAddr("attacker");

        // Attacker deploys their own clone (msg.sender == attacker == hook param).
        // This succeeds because msg.sender == hook parameter.
        vm.prank(attacker);
        IJB721Checkpoints attackerModule = deployer.deploy(attacker);
        assertTrue(address(attackerModule) != address(0), "Attacker can deploy their own clone");

        // The real hook can still deploy its own clone (different salt = different CREATE2 address).
        vm.prank(hookAddr);
        IJB721Checkpoints hookModule = deployer.deploy(hookAddr);
        assertTrue(address(hookModule) != address(0), "Real hook can still deploy its own clone");

        // The two clones are at different addresses.
        assertTrue(
            address(attackerModule) != address(hookModule),
            "Attacker clone and hook clone should be different addresses"
        );
    }

    /// @notice Fuzz: any random caller that is not the hook reverts.
    function testFuzz_deploy_revertsForArbitraryCaller(address caller, address hookAddr) public {
        vm.assume(caller != hookAddr);

        vm.prank(caller);
        vm.expectRevert(IJB721CheckpointsDeployer.JB721CheckpointsDeployer_Unauthorized.selector);
        deployer.deploy(hookAddr);
    }
}
