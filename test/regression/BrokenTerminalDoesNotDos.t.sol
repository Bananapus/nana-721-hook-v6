// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
// forge-lint: disable-next-line(unused-import)
import {JB721TiersHookLib} from "../../src/libraries/JB721TiersHookLib.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJB721TiersHook} from "../../src/interfaces/IJB721TiersHook.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Regression tests: a broken project terminal in _addToBalance should not DOS payments.
contract Test_BrokenTerminalDoesNotDos is UnitTestSetup {
    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        vm.etch(mockJBSplits, new bytes(0x69));
    }

    // Helper: build payer metadata for tier IDs.
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

    /// @notice Helper to build an ERC-20 afterPay context (reduces stack depth).
    function _buildErc20PayContext(
        address hookAddress,
        address token,
        uint32 currency,
        uint8 decimals,
        uint256[] memory tierIds,
        uint256 amount
    )
        internal
        view
        returns (JBAfterPayRecordedContext memory)
    {
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(hookAddress, mintIds);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = amount;

        return JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            amount: JBTokenAmount({token: token, value: amount, decimals: decimals, currency: currency}),
            forwardedAmount: JBTokenAmount({token: token, value: amount, decimals: decimals, currency: currency}),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(splitTierIds, splitAmounts),
            payerMetadata: payerMetadata
        });
    }

    // ──────────────────────────────────────────────────────────────────────
    // ETH: broken own-project terminal in _addToBalance should not revert
    // ──────────────────────────────────────────────────────────────────────

    /// @notice When a split has no valid recipient (projectId==0, beneficiary==address(0)),
    /// funds route to the project's own terminal via _addToBalance. If that terminal reverts,
    /// the old code would propagate the revert and DOS the entire payment. With the try-catch
    /// fix, the function silently catches the failure and the payment succeeds (funds stay in
    /// the hook contract).
    function test_brokenOwnTerminal_eth_doesNotDosPayments() public {
        ForTest_JB721TiersHook testHook = _initializeForTestHook(0);
        IJB721TiersHookStore hookStore = testHook.STORE();

        // Add a tier with 100% split, priced at 1 ETH.
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 1 ether;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tierConfigs[0].splitPercent = 1_000_000_000; // 100%

        vm.prank(address(testHook));
        uint256[] memory tierIds = hookStore.recordAddTiers(tierConfigs);

        // Mock directory checks.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mock splits: a split with no valid recipient (projectId==0, beneficiary==address(0)),
        // so funds route to _addToBalance.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        // Mock the project's primary terminal to a contract that reverts on addToBalanceOf.
        address brokenTerminal = makeAddr("brokenTerminal");
        vm.etch(brokenTerminal, new bytes(0x69));
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, projectId, JBConstants.NATIVE_TOKEN),
            abi.encode(brokenTerminal)
        );
        // Make addToBalanceOf revert.
        vm.mockCallRevert(
            brokenTerminal, abi.encodeWithSelector(IJBTerminal.addToBalanceOf.selector), "terminal broken"
        );

        // Build payer metadata.
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(testHook), mintIds);

        // Build hook metadata (per-tier split breakdown).
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

        vm.deal(mockTerminalAddress, 2 ether);

        // Expect AddToBalanceReverted event when the broken terminal reverts.
        vm.expectEmit(true, false, false, false);
        emit IJB721TiersHook.AddToBalanceReverted(projectId, JBConstants.NATIVE_TOKEN, 1 ether, "");

        vm.prank(mockTerminalAddress);
        // Before the fix, this would revert with "terminal broken".
        // With the try-catch, it succeeds, emits the event, and the ETH stays in the hook contract.
        testHook.afterPayRecordedWith{value: 1 ether}(payContext);

        // The ETH should remain in the hook contract since the terminal call failed.
        assertGe(address(testHook).balance, 1 ether, "ETH should stay in hook when terminal reverts");
    }

    // ──────────────────────────────────────────────────────────────────────
    // ERC-20: broken own-project terminal in _addToBalance should not revert
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Same scenario as above but with ERC-20 tokens. On terminal failure, the
    /// approval should be reset to 0 for safety, and the payment should not revert.
    function test_brokenOwnTerminal_erc20_doesNotDosPayments() public {
        BrokenTerminalERC20 usdc = new BrokenTerminalERC20("USD Coin", "USDC", 6);
        uint32 usdcCurrency = uint32(uint160(address(usdc)));

        JB721TiersHook testHook = _initHookDefaultTiers(0, false, usdcCurrency, 6);

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0].price = 100e6;
        tierConfigs[0].initialSupply = uint32(100);
        tierConfigs[0].category = uint24(1);
        tierConfigs[0].encodedIPFSUri = bytes32(uint256(0x1234));
        tierConfigs[0].splitPercent = 1_000_000_000; // 100%

        vm.prank(address(testHook));
        uint256[] memory tierIds = testHook.STORE().recordAddTiers(tierConfigs);

        _setupErc20Mocks(testHook, tierIds, address(usdc), usdcCurrency);

        JBAfterPayRecordedContext memory payContext =
            _buildErc20PayContext(address(testHook), address(usdc), usdcCurrency, 6, tierIds, 100e6);

        // Fund the terminal and approve the hook to pull tokens.
        usdc.mint(mockTerminalAddress, 100e6);
        vm.prank(mockTerminalAddress);
        usdc.approve(address(testHook), 100e6);

        address brokenTerminal = makeAddr("brokenTerminal");

        // Expect AddToBalanceReverted event when the broken terminal reverts.
        vm.expectEmit(true, false, false, false);
        emit IJB721TiersHook.AddToBalanceReverted(projectId, address(usdc), 100e6, "");

        vm.prank(mockTerminalAddress);
        // Before the fix, this would revert with "terminal broken".
        // With the try-catch, it succeeds and emits the event.
        testHook.afterPayRecordedWith(payContext);

        // Tokens should remain in the hook (terminal call failed).
        assertEq(usdc.balanceOf(address(testHook)), 100e6, "ERC20 should stay in hook when terminal reverts");

        // Approval to the broken terminal should have been reset to 0.
        assertEq(
            usdc.allowance(address(testHook), brokenTerminal),
            0,
            "Approval to broken terminal should be reset to 0"
        );
    }

    /// @notice Sets up mocks for the ERC-20 broken terminal test (extracted to avoid stack-too-deep).
    function _setupErc20Mocks(
        JB721TiersHook testHook,
        uint256[] memory tierIds,
        address token,
        uint32 /* usdcCurrency */
    )
        internal
    {
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );

        // Mock splits: no valid recipient, so funds route to _addToBalance.
        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(testHook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        // Mock the project's primary terminal to a contract that reverts on addToBalanceOf.
        address brokenTerminal = makeAddr("brokenTerminal");
        vm.etch(brokenTerminal, new bytes(0x69));
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, projectId, token),
            abi.encode(brokenTerminal)
        );
        // Make addToBalanceOf revert.
        vm.mockCallRevert(
            brokenTerminal, abi.encodeWithSelector(IJBTerminal.addToBalanceOf.selector), "terminal broken"
        );
    }
}

/// @notice A simple mintable ERC20 for testing.
contract BrokenTerminalERC20 is ERC20 {
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
