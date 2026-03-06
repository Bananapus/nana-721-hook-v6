// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IJBCashOutHook} from "@bananapus/core-v6/src/interfaces/IJBCashOutHook.sol";
import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBPayHook} from "@bananapus/core-v6/src/interfaces/IJBPayHook.sol";
import {IJBRulesetDataHook} from "@bananapus/core-v6/src/interfaces/IJBRulesetDataHook.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBAfterPayRecordedContext} from "@bananapus/core-v6/src/structs/JBAfterPayRecordedContext.sol";
import {JBAfterCashOutRecordedContext} from "@bananapus/core-v6/src/structs/JBAfterCashOutRecordedContext.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core-v6/src/structs/JBBeforePayRecordedContext.sol";
import {JBBeforeCashOutRecordedContext} from "@bananapus/core-v6/src/structs/JBBeforeCashOutRecordedContext.sol";
import {JBCashOutHookSpecification} from "@bananapus/core-v6/src/structs/JBCashOutHookSpecification.sol";
import {JBPayHookSpecification} from "@bananapus/core-v6/src/structs/JBPayHookSpecification.sol";
import {JBRuleset} from "@bananapus/core-v6/src/structs/JBRuleset.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import {ERC721} from "./ERC721.sol";
import {IJB721Hook} from "../interfaces/IJB721Hook.sol";

/// @title JB721Hook
/// @notice When a project which uses this hook is paid, this hook may mint NFTs to the payer, depending on this hook's
/// setup, the amount paid, and information specified by the payer. The project's owner can enable NFT cash outs.
/// through this hook, allowing the NFT holders to burn their NFTs to reclaim funds from the project (in proportion to
/// the NFT's price).
abstract contract JB721Hook is ERC721, IJB721Hook {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JB721Hook_InvalidCashOut();
    error JB721Hook_InvalidPay();
    error JB721Hook_UnauthorizedToken(uint256 tokenId, address holder);
    error JB721Hook_UnexpectedTokenCashedOut();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The ID used when parsing metadata.
    address public immutable override METADATA_ID_TARGET;

    //*********************************************************************//
    // -------------------- public stored properties --------------------- //
    //*********************************************************************//

    /// @notice The ID of the project that this contract is associated with.
    uint256 public override PROJECT_ID;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param directory A directory of terminals and controllers for projects.
    constructor(IJBDirectory directory) {
        DIRECTORY = directory;
        // Store the address of the original hook deploy. Clones will each use the address of the instance they're based
        // on.
        METADATA_ID_TARGET = address(this);
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice The data calculated before a payment is recorded in the terminal store. This data is provided to the
    /// terminal's `pay(...)` transaction.
    /// @dev Sets this contract as the pay hook. Part of `IJBRulesetDataHook`.
    /// @param context The payment context passed to this contract by the `pay(...)` function.
    /// @return weight The new `weight` to use, overriding the ruleset's `weight`.
    /// @return hookSpecifications The amount and data to send to pay hooks (this contract) instead of adding to the
    /// terminal's balance.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        public
        view
        virtual
        override
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Forward the received weight and memo, and use this contract as the only pay hook.
        weight = context.weight;
        hookSpecifications = new JBPayHookSpecification[](1);
        hookSpecifications[0] = JBPayHookSpecification({hook: this, amount: 0, metadata: bytes("")});
    }

    /// @notice The data calculated before a cash out is recorded in the terminal store. This data is provided to the
    /// terminal's `cashOutTokensOf(...)` transaction.
    /// @dev Sets this contract as the cash out hook. Part of `IJBRulesetDataHook`.
    /// @dev This function is used for NFT cash outs, and will only be called if the project's ruleset has
    /// `useDataHookForCashOut` set to `true`.
    /// @param context The cash out context passed to this contract by the `cashOutTokensOf(...)` function.
    /// @return cashOutTaxRate The cash out tax rate influencing the reclaim amount.
    /// @return cashOutCount The amount of tokens that should be considered cashed out.
    /// @return totalSupply The total amount of tokens that are considered to be existing.
    /// @return hookSpecifications The amount and data to send to cash out hooks (this contract) instead of returning to
    /// the beneficiary.
    function beforeCashOutRecordedWith(JBBeforeCashOutRecordedContext calldata context)
        public
        view
        virtual
        override
        returns (
            uint256 cashOutTaxRate,
            uint256 cashOutCount,
            uint256 totalSupply,
            JBCashOutHookSpecification[] memory hookSpecifications
        )
    {
        // Make sure (fungible) project tokens aren't also being cashed out.
        if (context.cashOutCount > 0) revert JB721Hook_UnexpectedTokenCashedOut();

        // Fetch the cash out hook metadata using the corresponding metadata ID.
        (bool metadataExists, bytes memory metadata) = JBMetadataResolver.getDataFor({
            id: JBMetadataResolver.getId({purpose: "cashOut", target: METADATA_ID_TARGET}), metadata: context.metadata
        });

        // Use this contract as the only cash out hook.
        hookSpecifications = new JBCashOutHookSpecification[](1);
        hookSpecifications[0] = JBCashOutHookSpecification({hook: this, amount: 0, metadata: bytes("")});

        uint256[] memory decodedTokenIds;

        // Decode the metadata.
        if (metadataExists) decodedTokenIds = abi.decode(metadata, (uint256[]));

        // Use the cash out weight of the provided 721s.
        cashOutCount = cashOutWeightOf({tokenIds: decodedTokenIds, context: context});

        // Use the total cash out weight of the 721s.
        totalSupply = totalCashOutWeight(context);

        // Use the cash out tax rate from the context.
        cashOutTaxRate = context.cashOutTaxRate;
    }

    /// @notice Required by the IJBRulesetDataHook interfaces. Return false to not leak any permissions.
    function hasMintPermissionFor(uint256, JBRuleset memory, address) external pure returns (bool) {
        return false;
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the cumulative cash out weight of the specified token IDs relative to the
    /// `totalCashOutWeight`.
    /// @param tokenIds The NFT token IDs to calculate the cumulative cash out weight of.
    /// @param context The cash out context passed to this contract by the `cashOutTokensOf(...)` function.
    /// @return The cumulative cash out weight of the specified token IDs.
    function cashOutWeightOf(
        uint256[] memory tokenIds,
        JBBeforeCashOutRecordedContext calldata context
    )
        public
        view
        virtual
        returns (uint256)
    {
        tokenIds; // Prevents unused var compiler and natspec complaints.
        context; // Prevents unused var compiler and natspec complaints.
        return 0;
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param interfaceId The ID of the interface to check for adherence to.
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IJB721Hook).interfaceId || interfaceId == type(IJBRulesetDataHook).interfaceId
            || interfaceId == type(IJBPayHook).interfaceId || interfaceId == type(IJBCashOutHook).interfaceId
            || interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Calculates the cumulative cash out weight of all NFT token IDs.
    /// @param context The cash out context passed to this contract by the `cashOutTokensOf(...)` function.
    /// @return The total cumulative cash out weight of all NFT token IDs.
    function totalCashOutWeight(JBBeforeCashOutRecordedContext calldata context) public view virtual returns (uint256) {
        context; // Prevents unused var compiler and natspec complaints.
        return 0;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Mints one or more NFTs to the `context.beneficiary` upon payment if conditions are met. Part of
    /// `IJBPayHook`.
    /// @dev Reverts if the calling contract is not one of the project's terminals.
    /// @param context The payment context passed in by the terminal.
    // slither-disable-next-line locked-ether
    function afterPayRecordedWith(JBAfterPayRecordedContext calldata context) external payable virtual override {
        uint256 projectId = PROJECT_ID;

        // Make sure the caller is a terminal of the project, and that the call is being made on behalf of an
        // interaction with the correct project.
        if (
            !DIRECTORY.isTerminalOf(projectId, IJBTerminal(msg.sender))
                || context.projectId != projectId
        ) revert JB721Hook_InvalidPay();

        // Process the payment.
        _processPayment(context);
    }

    /// @notice Burns the specified NFTs upon token holder cash out, reclaiming funds from the project's balance for
    /// `context.beneficiary`. Part of `IJBCashOutHook`.
    /// @dev Reverts if the calling contract is not one of the project's terminals.
    /// @param context The cash out context passed in by the terminal.
    // slither-disable-next-line locked-ether
    function afterCashOutRecordedWith(JBAfterCashOutRecordedContext calldata context)
        external
        payable
        virtual
        override
    {
        // Keep a reference to the project ID.
        uint256 projectId = PROJECT_ID;

        // Make sure the caller is a terminal of the project, and that the call is being made on behalf of an
        // interaction with the correct project.
        if (
            msg.value != 0 || !DIRECTORY.isTerminalOf({projectId: projectId, terminal: IJBTerminal(msg.sender)})
                || context.projectId != projectId
        ) revert JB721Hook_InvalidCashOut();

        // Fetch the cash out hook metadata using the corresponding metadata ID.
        (bool metadataExists, bytes memory metadata) = JBMetadataResolver.getDataFor({
            id: JBMetadataResolver.getId({purpose: "cashOut", target: METADATA_ID_TARGET}),
            metadata: context.cashOutMetadata
        });

        uint256[] memory decodedTokenIds;

        // Decode the metadata.
        if (metadataExists) decodedTokenIds = abi.decode(metadata, (uint256[]));

        // Iterate through the NFTs, burning them if the owner is correct.
        for (uint256 i; i < decodedTokenIds.length; i++) {
            // Set the current NFT's token ID.
            uint256 tokenId = decodedTokenIds[i];

            // Make sure the token's owner is correct.
            if (_ownerOf(tokenId) != context.holder) revert JB721Hook_UnauthorizedToken(tokenId, context.holder);

            // Burn the token.
            _burn(tokenId);
        }

        // Call the hook.
        _didBurn(decodedTokenIds);
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    /// @notice Initializes the contract by associating it with a project and adding ERC721 details.
    /// @param projectId The ID of the project that this contract is associated with.
    /// @param name The name of the NFT collection.
    /// @param symbol The symbol representing the NFT collection.
    function _initialize(uint256 projectId, string memory name, string memory symbol) internal {
        ERC721._initialize({name_: name, symbol_: symbol});
        PROJECT_ID = projectId;
    }

    /// @notice Executes after NFTs have been burned via cash out.
    /// @param tokenIds The token IDs of the NFTs that were burned.
    function _didBurn(uint256[] memory tokenIds) internal virtual;

    /// @notice Process a received payment.
    /// @param context The payment context passed in by the terminal.
    function _processPayment(JBAfterPayRecordedContext calldata context) internal virtual;
}
