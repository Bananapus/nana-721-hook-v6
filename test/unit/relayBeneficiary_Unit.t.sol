// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";

/// @notice Tests that the 721 hook resolves the relay beneficiary from payment metadata.
contract Test_relayBeneficiary_Unit is UnitTestSetup {
    /// @notice The metadata ID the 721 hook uses to look up the relay beneficiary.
    /// Must match `_721_BENEFICIARY_METADATA_ID` in JB721TiersHook.
    bytes4 constant RELAY_BENEFICIARY_ID = bytes4(keccak256("JB_RELAY_BENEFICIARY"));

    address relayUser = makeAddr("relayUser");
    address sucker = makeAddr("sucker");

    function setUp() public override {
        super.setUp();

        // Mock directory: terminal is valid for all calls.
        vm.mockCall(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );
    }

    /// @notice When metadata contains a relay beneficiary, the spec should use that address (not context.beneficiary).
    function test_beforePay_relayBeneficiary_usedInSpec() public {
        JB721TiersHook tiersHook = _initHookDefaultTiers(3);

        // Build metadata with tier selection + relay beneficiary.
        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;

        // Encode tier selection metadata (for the hook's own metadata ID).
        bytes memory tierData = abi.encode(false, tierIdsToMint, new bytes[](0));

        // Build metadata with two entries: hook tier data + relay beneficiary.
        bytes4[] memory ids = new bytes4[](2);
        bytes[] memory datas = new bytes[](2);

        ids[0] = JBMetadataResolver.getId({purpose: "pay", target: address(tiersHook)});
        datas[0] = tierData;
        ids[1] = RELAY_BENEFICIARY_ID;
        datas[1] = abi.encode(relayUser);

        bytes memory metadata = metadataHelper.createMetadata(ids, datas);

        // Build pay context with sucker as beneficiary (simulating cross-chain payment).
        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: sucker,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 10,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: block.timestamp,
            beneficiary: sucker,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: metadata
        });

        (, JBPayHookSpecification[] memory specs) = tiersHook.beforePayRecordedWith(context);

        // The spec's metadata should encode relayUser as the beneficiary, not sucker.
        assertEq(specs.length, 1, "should return one spec");
        (address specBeneficiary,,) = abi.decode(specs[0].metadata, (address, address, bytes));
        assertEq(specBeneficiary, relayUser, "spec should use relay beneficiary, not context.beneficiary");
    }

    /// @notice When no relay metadata is present, the spec should use context.beneficiary as-is.
    function test_beforePay_noRelayMetadata_usesContextBeneficiary() public {
        JB721TiersHook tiersHook = _initHookDefaultTiers(3);

        // Build metadata with only tier selection (no relay beneficiary).
        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes memory tierData = abi.encode(false, tierIdsToMint, new bytes[](0));

        bytes4[] memory ids = new bytes4[](1);
        bytes[] memory datas = new bytes[](1);
        ids[0] = JBMetadataResolver.getId({purpose: "pay", target: address(tiersHook)});
        datas[0] = tierData;

        bytes memory metadata = metadataHelper.createMetadata(ids, datas);

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: makeAddr("payer"),
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 10,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: block.timestamp,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: metadata
        });

        (, JBPayHookSpecification[] memory specs) = tiersHook.beforePayRecordedWith(context);

        assertEq(specs.length, 1, "should return one spec");
        (address specBeneficiary,,) = abi.decode(specs[0].metadata, (address, address, bytes));
        assertEq(specBeneficiary, beneficiary, "spec should use context.beneficiary when no relay metadata");
    }

    /// @notice When relay metadata is present but the address is zero, fall back to context.beneficiary.
    function test_beforePay_relayBeneficiaryZero_fallsBackToContext() public {
        JB721TiersHook tiersHook = _initHookDefaultTiers(3);

        uint16[] memory tierIdsToMint = new uint16[](1);
        tierIdsToMint[0] = 1;
        bytes memory tierData = abi.encode(false, tierIdsToMint, new bytes[](0));

        bytes4[] memory ids = new bytes4[](2);
        bytes[] memory datas = new bytes[](2);
        ids[0] = JBMetadataResolver.getId({purpose: "pay", target: address(tiersHook)});
        datas[0] = tierData;
        ids[1] = RELAY_BENEFICIARY_ID;
        datas[1] = abi.encode(address(0));

        bytes memory metadata = metadataHelper.createMetadata(ids, datas);

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: sucker,
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 10,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: block.timestamp,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: metadata
        });

        (, JBPayHookSpecification[] memory specs) = tiersHook.beforePayRecordedWith(context);

        (address specBeneficiary,,) = abi.decode(specs[0].metadata, (address, address, bytes));
        assertEq(specBeneficiary, beneficiary, "zero relay address should fall back to context.beneficiary");
    }

    /// @notice When metadata is empty, use context.beneficiary.
    function test_beforePay_emptyMetadata_usesContextBeneficiary() public {
        JB721TiersHook tiersHook = _initHookDefaultTiers(3);

        JBBeforePayRecordedContext memory context = JBBeforePayRecordedContext({
            terminal: mockTerminalAddress,
            payer: makeAddr("payer"),
            amount: JBTokenAmount({
                token: JBConstants.NATIVE_TOKEN,
                value: 10,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            projectId: projectId,
            rulesetId: block.timestamp,
            beneficiary: beneficiary,
            weight: 10e18,
            reservedPercent: 5000,
            metadata: ""
        });

        (, JBPayHookSpecification[] memory specs) = tiersHook.beforePayRecordedWith(context);

        (address specBeneficiary,,) = abi.decode(specs[0].metadata, (address, address, bytes));
        assertEq(specBeneficiary, beneficiary, "empty metadata should use context.beneficiary");
    }
}
