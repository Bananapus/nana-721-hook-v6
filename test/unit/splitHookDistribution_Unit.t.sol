// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice A mock split hook that records calls and accepts ETH/ERC20.
contract MockSplitHook is IJBSplitHook {
    address public lastToken;
    uint256 public lastAmount;
    uint256 public lastDecimals;
    uint256 public lastProjectId;
    uint256 public lastGroupId;
    JBSplit public lastSplit;
    uint256 public callCount;

    function processSplitWith(JBSplitHookContext calldata context) external payable override {
        lastToken = context.token;
        lastAmount = context.amount;
        lastDecimals = context.decimals;
        lastProjectId = context.projectId;
        lastGroupId = context.groupId;
        lastSplit = context.split;
        callCount++;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IJBSplitHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

/// @notice A mock ERC20 with configurable decimals (for USDC-like 6-decimal tokens).
contract MockERC20WithDecimals is ERC20 {
    uint8 internal _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Tests for split hook distribution in JB721TiersHookLib, covering ETH (18 decimals) and USDC (6 decimals).
contract Test_SplitHookDistribution is UnitTestSetup {
    using stdStorage for StdStorage;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    MockSplitHook splitHook;

    function setUp() public override {
        super.setUp();
        vm.etch(mockJBSplits, new bytes(0x69));
        splitHook = new MockSplitHook();
    }

    // ───────────────────────────────────────────────────
    // Helpers
    // ───────────────────────────────────────────────────

    function _tierConfigWithSplit(
        uint104 price,
        uint32 splitPercent
    )
        internal
        pure
        returns (JB721TierConfig memory config)
    {
        config.price = price;
        config.initialSupply = uint32(100);
        config.category = uint24(1);
        config.encodedIPFSUri = bytes32(uint256(0x1234));
        config.splitPercent = splitPercent;
    }

    function _buildPayerMetadata(
        address hookAddress,
        uint16[] memory tierIdsToMint
    )
        internal
        view
        returns (bytes memory)
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(false, tierIdsToMint);
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", hookAddress);
        return metadataHelper.createMetadata(ids, data);
    }

    // ───────────────────────────────────────────────────
    // ETH Tests (18 decimals)
    // ───────────────────────────────────────────────────

    /// @notice Split hook receives ETH with correct context (decimals=18).
    function test_splitHook_eth_receivesContextWithCorrectDecimals() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add tier with 50% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 500_000_000);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Mock directory.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Splits: 100% to split hook.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(splitHook))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        // Build metadata.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 0.5 ether;

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
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
                value: 0.5 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 0.5 ether}(payContext);

        // Verify split hook was called.
        assertEq(splitHook.callCount(), 1);

        // Verify ETH was received.
        assertEq(address(splitHook).balance, 0.5 ether);

        // Verify context decimals.
        assertEq(splitHook.lastDecimals(), 18);
        assertEq(splitHook.lastAmount(), 0.5 ether);
        assertEq(splitHook.lastToken(), JBConstants.NATIVE_TOKEN);
        assertEq(splitHook.lastProjectId(), projectId);
        assertEq(splitHook.lastGroupId(), groupId);
    }

    /// @notice Split hook + beneficiary split together with ETH.
    function test_splitHook_eth_mixedWithBeneficiarySplit() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Tier with 100% split, priced at 1 ETH.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 1_000_000_000);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Two splits: 60% to hook, 40% to alice.
        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            percent: uint32(600_000_000), // 60%
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(splitHook))
        });
        splits[1] = JBSplit({
            percent: uint32(400_000_000), // 40% (of remaining)
            projectId: 0,
            beneficiary: payable(alice),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 1 ether;

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
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
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        uint256 aliceBalanceBefore = alice.balance;

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        // Hook gets 60% of 1 ETH = 0.6 ETH.
        assertEq(address(splitHook).balance, 0.6 ether);
        assertEq(splitHook.callCount(), 1);
        assertEq(splitHook.lastDecimals(), 18);

        // Alice gets 40% of remaining 0.4 ETH = 0.4 ETH.
        // Note: second split is 400_000_000 / 400_000_000 (remaining percent) = 100% of leftover.
        assertEq(alice.balance - aliceBalanceBefore, 0.4 ether);
    }

    // ───────────────────────────────────────────────────
    // ERC20 / USDC Tests (6 decimals)
    // ───────────────────────────────────────────────────

    /// @notice Split hook receives USDC (6 decimals) with correct context.
    function test_splitHook_usdc_receivesContextWith6Decimals() public {
        MockERC20WithDecimals usdc = new MockERC20WithDecimals("USD Coin", "USDC", 6);

        // Initialize hook with USDC pricing (6 decimals).
        JB721TiersHook testHook = _initHookDefaultTiers(0, false, uint32(uint160(address(usdc))), 6);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Tier priced at 100 USDC (100e6), 50% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(100e6, 500_000_000);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Split: 100% to hook.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(splitHook))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 50e6; // 50 USDC

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: address(usdc), value: 100e6, decimals: 6, currency: uint32(uint160(address(usdc)))
            }),
            forwardedAmount: JBTokenAmount({
                token: address(usdc), value: 50e6, decimals: 6, currency: uint32(uint160(address(usdc)))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        // Give terminal USDC and approve the hook.
        usdc.mint(mockTerminalAddress, 100e6);
        vm.prank(mockTerminalAddress);
        usdc.approve(address(testHook), 50e6);

        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith(payContext);

        // Verify split hook received USDC.
        assertEq(usdc.balanceOf(address(splitHook)), 50e6);
        assertEq(splitHook.callCount(), 1);

        // Key assertion: decimals in context should be 6, not 18.
        assertEq(splitHook.lastDecimals(), 6);
        assertEq(splitHook.lastAmount(), 50e6);
        assertEq(splitHook.lastToken(), address(usdc));
    }

    /// @notice USDC split with hook + beneficiary split alongside.
    function test_splitHook_usdc_mixedWithBeneficiarySplit() public {
        MockERC20WithDecimals usdc = new MockERC20WithDecimals("USD Coin", "USDC", 6);

        JB721TiersHook testHook = _initHookDefaultTiers(0, false, uint32(uint160(address(usdc))), 6);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Tier priced at 1000 USDC (1000e6), 100% split.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1000e6, 1_000_000_000);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Two splits: 70% to hook, 30% to bob.
        JBSplit[] memory splits = new JBSplit[](2);
        splits[0] = JBSplit({
            percent: uint32(700_000_000), // 70%
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(splitHook))
        });
        splits[1] = JBSplit({
            percent: uint32(300_000_000), // 30% (of remaining)
            projectId: 0,
            beneficiary: payable(bob),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 1000e6;

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({
                token: address(usdc), value: 1000e6, decimals: 6, currency: uint32(uint160(address(usdc)))
            }),
            forwardedAmount: JBTokenAmount({
                token: address(usdc), value: 1000e6, decimals: 6, currency: uint32(uint160(address(usdc)))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        usdc.mint(mockTerminalAddress, 1000e6);
        vm.prank(mockTerminalAddress);
        usdc.approve(address(testHook), 1000e6);

        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith(payContext);

        // Hook gets 70% of 1000 USDC = 700 USDC.
        assertEq(usdc.balanceOf(address(splitHook)), 700e6);
        assertEq(splitHook.lastDecimals(), 6);

        // Bob gets 30% of remaining 300 USDC = 300 USDC.
        assertEq(usdc.balanceOf(bob), 300e6);
    }

    // ───────────────────────────────────────────────────
    // Split hook priority tests
    // ───────────────────────────────────────────────────

    /// @notice Split hook takes priority over projectId.
    function test_splitHook_takesPriorityOverProjectId() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 1_000_000_000);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Split has BOTH hook AND projectId — hook should take priority.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: uint64(99), // Also has a project ID
            beneficiary: payable(alice), // Also has a beneficiary
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(splitHook)) // Hook set — should take priority
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 1 ether;

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
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
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        // Hook received the ETH (not the project or alice).
        assertEq(address(splitHook).balance, 1 ether);
        assertEq(splitHook.callCount(), 1);
        // Alice got nothing.
        assertEq(alice.balance, 0);
    }

    /// @notice Verifies the split context contains the correct split struct.
    function test_splitHook_contextContainsCorrectSplit() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(1 ether, 1_000_000_000);
        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: uint64(42),
            beneficiary: payable(bob),
            preferAddToBalance: true,
            lockedUntil: 0,
            hook: IJBSplitHook(address(splitHook))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 1 ether;

        JBAfterPayRecordedContext memory payContext = JBAfterPayRecordedContext({
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
                value: 1 ether,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });

        vm.deal(mockTerminalAddress, 1 ether);
        vm.prank(mockTerminalAddress);
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        // Verify split struct was passed through correctly.
        (, uint64 pid, address payable ben, bool pref,, IJBSplitHook hk) = splitHook.lastSplit();
        assertEq(pid, 42);
        assertEq(ben, bob);
        assertEq(pref, true);
        assertEq(address(hk), address(splitHook));
    }
}
