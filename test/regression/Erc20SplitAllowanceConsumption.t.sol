// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../utils/UnitTestSetup.sol";
import {IJB721TiersHookStore} from "../../src/interfaces/IJB721TiersHookStore.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {IJBSplits} from "@bananapus/core-v6/src/interfaces/IJBSplits.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JB721TiersHookLib} from "../../src/libraries/JB721TiersHookLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract _RegressionMockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice A terminal mock that returns successfully from `pay`/`addToBalanceOf` without pulling the granted
/// allowance. Pre-fix, this would leave a dangling allowance on the hook and let the hook treat the unconsumed
/// amount as fully delivered.
contract _NonPullingTerminal {
    function pay(
        uint256,
        address,
        uint256,
        address,
        uint256,
        string calldata,
        bytes calldata
    )
        external
        payable
        returns (uint256)
    {
        return 0;
    }

    function addToBalanceOf(uint256, address, uint256, bool, string calldata, bytes calldata) external payable {}
}

/// @notice ERC-20 split terminal paths must measure consumption by allowance delta and
/// fail closed when the destination terminal does not pull the full granted amount. The library's leftover routing
/// is the last resort; if even that terminal does not pull, the whole payment must revert rather than leaving
/// funds + allowance stuck on the hook.
contract Erc20SplitAllowanceConsumption is UnitTestSetup {
    address internal alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();
        vm.etch(mockJBSplits, new bytes(0x69));
    }

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

    function _setupHookAndTier(_RegressionMockERC20 token)
        internal
        returns (JB721TiersHook hook, uint256[] memory tierIds)
    {
        hook = _initHookDefaultTiers(0, false, uint32(uint160(address(token))), 18);
        IJB721TiersHookStore hookStore = hook.STORE();

        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = _tierConfigWithSplit(100, 500_000_000); // 50%
        vm.prank(address(hook));
        tierIds = hookStore.recordAddTiers(tierConfigs);

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.isTerminalOf.selector, projectId, mockTerminalAddress),
            abi.encode(true)
        );
    }

    function _buildPayCtx(
        JB721TiersHook hook,
        uint256[] memory tierIds,
        address token
    )
        internal
        view
        returns (JBAfterPayRecordedContext memory)
    {
        uint16[] memory mintIds = new uint16[](1);
        mintIds[0] = uint16(tierIds[0]);
        bytes memory payerMetadata = _buildPayerMetadata(address(hook), mintIds);

        uint16[] memory splitTierIds = new uint16[](1);
        splitTierIds[0] = uint16(tierIds[0]);
        uint256[] memory splitAmounts = new uint256[](1);
        splitAmounts[0] = 50;

        return JBAfterPayRecordedContext({
            payer: beneficiary,
            projectId: projectId,
            rulesetId: 0,
            // forge-lint: disable-next-line(unsafe-typecast)
            amount: JBTokenAmount({token: token, value: 100, decimals: 18, currency: uint32(uint160(token))}),
            forwardedAmount: JBTokenAmount({
                token: token,
                value: 50,
                decimals: 18,
                // forge-lint: disable-next-line(unsafe-typecast)
                currency: uint32(uint160(token))
            }),
            weight: 10e18,
            newlyIssuedTokenCount: 0,
            beneficiary: beneficiary,
            hookMetadata: abi.encode(beneficiary, beneficiary, abi.encode(splitTierIds, splitAmounts)),
            payerMetadata: payerMetadata
        });
    }

    /// @notice Non-pulling target terminal on the `preferAddToBalance` split route routes the unsent amount through
    /// the leftover fallback; that terminal also does not pull, so the whole payment reverts. No allowance leaks.
    function test_erc20_splitPreferAddToBalance_nonPullingTerminalReverts() public {
        _RegressionMockERC20 token = new _RegressionMockERC20();
        (JB721TiersHook hook, uint256[] memory tierIds) = _setupHookAndTier(token);

        uint256 targetProjectId = 99;
        _NonPullingTerminal targetTerminal = new _NonPullingTerminal();
        _NonPullingTerminal projectTerminal = new _NonPullingTerminal();

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            // forge-lint: disable-next-line(unsafe-typecast)
            projectId: uint56(targetProjectId),
            beneficiary: payable(address(0)),
            preferAddToBalance: true,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(hook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        // Split target terminal does not pull → consumed = 0, unsent routes to project's leftover terminal.
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, targetProjectId, address(token)),
            abi.encode(address(targetTerminal))
        );
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, projectId, address(token)),
            abi.encode(address(projectTerminal))
        );

        token.mint(mockTerminalAddress, 100);
        vm.prank(mockTerminalAddress);
        token.approve(address(hook), 50);

        // Build the context first — `_buildPayCtx` calls into `metadataHelper.getId`, which would otherwise consume
        // the `vm.expectRevert` guard before the contract call we actually want to assert against.
        JBAfterPayRecordedContext memory ctx = _buildPayCtx(hook, tierIds, address(token));

        vm.prank(mockTerminalAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                JB721TiersHookLib.JB721TiersHookLib_SplitFallbackFailed.selector,
                projectId,
                address(token),
                uint256(50),
                bytes("")
            )
        );
        hook.afterPayRecordedWith(ctx);
    }

    /// @notice Same path for the `pay` split branch.
    function test_erc20_splitPay_nonPullingTerminalReverts() public {
        _RegressionMockERC20 token = new _RegressionMockERC20();
        (JB721TiersHook hook, uint256[] memory tierIds) = _setupHookAndTier(token);

        uint256 targetProjectId = 99;
        _NonPullingTerminal targetTerminal = new _NonPullingTerminal();
        _NonPullingTerminal projectTerminal = new _NonPullingTerminal();

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            // forge-lint: disable-next-line(unsafe-typecast)
            projectId: uint56(targetProjectId),
            beneficiary: payable(alice),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(hook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, targetProjectId, address(token)),
            abi.encode(address(targetTerminal))
        );
        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, projectId, address(token)),
            abi.encode(address(projectTerminal))
        );

        token.mint(mockTerminalAddress, 100);
        vm.prank(mockTerminalAddress);
        token.approve(address(hook), 50);

        // Build the context first — `_buildPayCtx` calls into `metadataHelper.getId`, which would otherwise consume
        // the `vm.expectRevert` guard before the contract call we actually want to assert against.
        JBAfterPayRecordedContext memory ctx = _buildPayCtx(hook, tierIds, address(token));

        vm.prank(mockTerminalAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                JB721TiersHookLib.JB721TiersHookLib_SplitFallbackFailed.selector,
                projectId,
                address(token),
                uint256(50),
                bytes("")
            )
        );
        hook.afterPayRecordedWith(ctx);
    }

    /// @notice Direct leftover fallback (no projectId, no beneficiary) reverts when its terminal does not pull.
    function test_erc20_leftoverFallback_nonPullingTerminalReverts() public {
        _RegressionMockERC20 token = new _RegressionMockERC20();
        (JB721TiersHook hook, uint256[] memory tierIds) = _setupHookAndTier(token);

        _NonPullingTerminal projectTerminal = new _NonPullingTerminal();

        JBSplit[] memory splits = new JBSplit[](1);
        splits[0] = JBSplit({
            percent: uint32(JBConstants.SPLITS_TOTAL_PERCENT),
            projectId: 0,
            beneficiary: payable(address(0)),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: IJBSplitHook(address(0))
        });

        uint256 groupId = uint256(uint160(address(hook))) | (uint256(tierIds[0]) << 160);
        mockAndExpect(
            mockJBSplits, abi.encodeWithSelector(IJBSplits.splitsOf.selector, projectId, 0, groupId), abi.encode(splits)
        );

        mockAndExpect(
            address(mockJBDirectory),
            abi.encodeWithSelector(IJBDirectory.primaryTerminalOf.selector, projectId, address(token)),
            abi.encode(address(projectTerminal))
        );

        token.mint(mockTerminalAddress, 100);
        vm.prank(mockTerminalAddress);
        token.approve(address(hook), 50);

        // Build the context first — `_buildPayCtx` calls into `metadataHelper.getId`, which would otherwise consume
        // the `vm.expectRevert` guard before the contract call we actually want to assert against.
        JBAfterPayRecordedContext memory ctx = _buildPayCtx(hook, tierIds, address(token));

        vm.prank(mockTerminalAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                JB721TiersHookLib.JB721TiersHookLib_SplitFallbackFailed.selector,
                projectId,
                address(token),
                uint256(50),
                bytes("")
            )
        );
        hook.afterPayRecordedWith(ctx);
    }
}
