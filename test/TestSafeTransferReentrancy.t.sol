// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../src/interfaces/IJB721TiersHookStore.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// =====================================================================
// Malicious ERC721 receiver that attempts reentrancy via safeTransferFrom
// =====================================================================

/// @notice A malicious ERC721 receiver that attempts to re-enter the hook contract during onERC721Received.
contract MaliciousReceiver is IERC721Receiver {
    address public target;
    bytes public reentryCalldata;
    bool public reentryAttempted;
    bool public reentrySucceeded;

    function setReentryTarget(address _target, bytes memory _calldata) external {
        target = _target;
        reentryCalldata = _calldata;
    }

    function onERC721Received(address, address, uint256, bytes memory) external override returns (bytes4) {
        if (reentryCalldata.length > 0) {
            reentryAttempted = true;
            (bool success,) = target.call(reentryCalldata);
            reentrySucceeded = success;
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}

/// @notice A malicious ERC721 receiver that attempts to transfer the NFT it just received back to itself during
/// onERC721Received, testing reentrancy via safeTransferFrom.
contract MaliciousRetransferReceiver is IERC721Receiver {
    address public hookAddress;
    bool public reentryAttempted;
    bool public reentryReverted;
    uint256 public receivedTokenId;
    address public nextRecipient;

    constructor(address _hook, address _nextRecipient) {
        hookAddress = _hook;
        nextRecipient = _nextRecipient;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes memory) external override returns (bytes4) {
        receivedTokenId = tokenId;
        reentryAttempted = true;
        // Attempt to transfer the just-received NFT to another address during the callback.
        try IERC721(hookAddress).safeTransferFrom(address(this), nextRecipient, tokenId) {
            reentryReverted = false;
        } catch {
            reentryReverted = true;
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}

// =====================================================================
// Test Contract: Reentrancy via safeTransferFrom / onERC721Received
// =====================================================================

/// @title TestSafeTransferReentrancy
/// @notice Tests that malicious ERC721 receivers cannot exploit reentrancy during safeTransferFrom.
/// @dev The safeTransferFrom flow calls _checkOnERC721Received AFTER the transfer is complete
/// (state already updated), so the receiver's onERC721Received callback fires with consistent state.
/// These tests verify that re-entering the hook during that callback does not corrupt state.
contract TestSafeTransferReentrancy is UnitTestSetup {
    using stdStorage for StdStorage;

    // ---------------------------------------------------------------
    // Test 1: Malicious receiver tries to re-enter afterPayRecordedWith
    // ---------------------------------------------------------------
    /// @notice A malicious receiver tries to call afterPayRecordedWith when receiving an NFT via safeTransferFrom.
    /// The re-entry fails because the receiver is not registered as a terminal.
    function test_safeTransferFrom_maliciousReceiver_cannotReenterAfterPay() public {
        // Set up hook with tiers and mint an NFT.
        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        ForTest_JB721TiersHook testHook = _initializeForTestHook(10);

        // Mint an NFT to the beneficiary.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        testHook.mintFor(tiersToMint, beneficiary);

        uint256 tokenId = _generateTokenId(1, 1);
        assertEq(testHook.ownerOf(tokenId), beneficiary, "Beneficiary should own the NFT");

        // Deploy the malicious receiver.
        MaliciousReceiver malicious = new MaliciousReceiver();

        // Build reentrant calldata: try to call afterPayRecordedWith.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = 1;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, mintIds);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(testHook));
        bytes memory payerMetadata = metadataHelper.createMetadata(ids, data);

        JBAfterPayRecordedContext memory reentrantContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            forwardedAmount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 0,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: address(malicious),
            hookMetadata: bytes(""),
            payerMetadata: payerMetadata
        });

        malicious.setReentryTarget(address(testHook), abi.encodeCall(testHook.afterPayRecordedWith, (reentrantContext)));

        // Mock: the malicious receiver is NOT a terminal.
        vm.mockCall(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, address(malicious)),
            abi.encode(false)
        );

        // Transfer the NFT to the malicious receiver via safeTransferFrom.
        vm.prank(beneficiary);
        testHook.safeTransferFrom(beneficiary, address(malicious), tokenId);

        // Verify the transfer succeeded (state is consistent).
        assertEq(testHook.ownerOf(tokenId), address(malicious), "Malicious receiver should own the NFT");

        // Verify the reentrancy was attempted but failed.
        assertTrue(malicious.reentryAttempted(), "Reentrancy should have been attempted");
        assertFalse(malicious.reentrySucceeded(), "Reentrancy should have failed");
    }

    // ---------------------------------------------------------------
    // Test 2: Malicious receiver tries to re-enter adjustTiers
    // ---------------------------------------------------------------
    /// @notice A malicious receiver tries to call adjustTiers during onERC721Received.
    /// The call is blocked by permission checks.
    function test_safeTransferFrom_maliciousReceiver_cannotReenterAdjustTiers() public {
        // Set up hook with tiers and mint an NFT.
        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        ForTest_JB721TiersHook testHook = _initializeForTestHook(10);

        // Mint an NFT to the beneficiary.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        testHook.mintFor(tiersToMint, beneficiary);

        uint256 tokenId = _generateTokenId(1, 1);

        // Deploy the malicious receiver that tries to remove tiers.
        MaliciousReceiver malicious = new MaliciousReceiver();

        // Build reentrant calldata: try to remove tier 1 via adjustTiers.
        uint256[] memory tierIdsToRemove = new uint256[](1);
        tierIdsToRemove[0] = 1;
        malicious.setReentryTarget(
            address(testHook), abi.encodeCall(testHook.adjustTiers, (new JB721TierConfig[](0), tierIdsToRemove))
        );

        // Mock: the malicious receiver does NOT have permission.
        vm.mockCall(mockJBPermissions, abi.encodeWithSelector(IJBPermissions.hasPermission.selector), abi.encode(false));

        // Transfer the NFT.
        vm.prank(beneficiary);
        testHook.safeTransferFrom(beneficiary, address(malicious), tokenId);

        // Verify state consistency.
        assertEq(testHook.ownerOf(tokenId), address(malicious), "Malicious receiver should own the NFT");
        assertTrue(malicious.reentryAttempted(), "Reentrancy should have been attempted");
        assertFalse(malicious.reentrySucceeded(), "adjustTiers reentrancy should have failed");
    }

    // ---------------------------------------------------------------
    // Test 3: Malicious receiver re-transfers NFT during callback
    // ---------------------------------------------------------------
    /// @notice A malicious receiver tries to transfer the NFT it just received to another address
    /// during onERC721Received. This tests the re-entrant safeTransferFrom scenario.
    /// Since _update completes BEFORE _checkOnERC721Received is called, state is already settled
    /// and a re-transfer should succeed with correct state.
    function test_safeTransferFrom_maliciousReceiver_retransferDuringCallback() public {
        // Set up hook with tiers and mint an NFT.
        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        ForTest_JB721TiersHook testHook = _initializeForTestHook(10);

        // Mint an NFT to the beneficiary.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        testHook.mintFor(tiersToMint, beneficiary);

        uint256 tokenId = _generateTokenId(1, 1);

        // The final recipient is a simple EOA.
        address finalRecipient = makeAddr("finalRecipient");

        // Deploy the malicious re-transfer receiver.
        MaliciousRetransferReceiver malicious = new MaliciousRetransferReceiver(address(testHook), finalRecipient);

        // Transfer to the malicious receiver.
        vm.prank(beneficiary);
        testHook.safeTransferFrom(beneficiary, address(malicious), tokenId);

        // The re-transfer should have succeeded (not reverted) because state was fully settled
        // before onERC721Received was called.
        assertTrue(malicious.reentryAttempted(), "Re-transfer should have been attempted");
        assertFalse(malicious.reentryReverted(), "Re-transfer should have succeeded");

        // Verify final state: the finalRecipient should own the NFT.
        assertEq(testHook.ownerOf(tokenId), finalRecipient, "Final recipient should own the NFT");

        // Verify voting units are tracked correctly after the double transfer.
        // Beneficiary should have 0, malicious should have 0, finalRecipient should have the tier's balance.
        IJB721TiersHookStore hookStore = testHook.STORE();
        assertEq(
            hookStore.tierBalanceOf(address(testHook), beneficiary, 1), 0, "Beneficiary should have 0 tier balance"
        );
        assertEq(
            hookStore.tierBalanceOf(address(testHook), address(malicious), 1), 0, "Malicious should have 0 tier balance"
        );
        assertEq(
            hookStore.tierBalanceOf(address(testHook), finalRecipient, 1),
            1,
            "Final recipient should have 1 tier balance"
        );
    }

    // ---------------------------------------------------------------
    // Test 4: State consistency after safeTransferFrom (no reentrancy)
    // ---------------------------------------------------------------
    /// @notice Verifies that a normal safeTransferFrom to a contract receiver keeps
    /// tier balances, voting units, and firstOwner tracking consistent.
    function test_safeTransferFrom_normalReceiver_stateConsistent() public {
        // Set up hook with tiers and mint an NFT.
        defaultTierConfig.allowOwnerMint = true;
        defaultTierConfig.reserveFrequency = 0;
        ForTest_JB721TiersHook testHook = _initializeForTestHook(10);

        // Mint an NFT to the beneficiary.
        uint16[] memory tiersToMint = new uint16[](1);
        tiersToMint[0] = 1;
        vm.prank(owner);
        testHook.mintFor(tiersToMint, beneficiary);

        uint256 tokenId = _generateTokenId(1, 1);

        // Deploy a clean receiver (no reentrancy).
        MaliciousReceiver cleanReceiver = new MaliciousReceiver();
        // Don't set any reentrancy target — it will just accept the NFT.

        IJB721TiersHookStore hookStore = testHook.STORE();

        // Verify pre-transfer state.
        assertEq(
            hookStore.tierBalanceOf(address(testHook), beneficiary, 1), 1, "Beneficiary should have 1 NFT pre-xfer"
        );
        assertEq(
            hookStore.tierBalanceOf(address(testHook), address(cleanReceiver), 1),
            0,
            "Receiver should have 0 NFTs pre-xfer"
        );

        // Transfer.
        vm.prank(beneficiary);
        testHook.safeTransferFrom(beneficiary, address(cleanReceiver), tokenId);

        // Verify post-transfer state.
        assertEq(testHook.ownerOf(tokenId), address(cleanReceiver), "Receiver should own the NFT");
        assertEq(
            hookStore.tierBalanceOf(address(testHook), beneficiary, 1), 0, "Beneficiary should have 0 NFTs post-xfer"
        );
        assertEq(
            hookStore.tierBalanceOf(address(testHook), address(cleanReceiver), 1),
            1,
            "Receiver should have 1 NFT post-xfer"
        );
        assertEq(testHook.firstOwnerOf(tokenId), beneficiary, "First owner should still be beneficiary");
    }
}
