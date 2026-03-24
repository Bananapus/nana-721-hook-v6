// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Import the shared unit test setup which deploys a hook clone with 10 tiers.
import "../utils/UnitTestSetup.sol";

// Import IERC2981 to compute its interface ID for the supportsInterface test.
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

// Import IERC721Errors for the ERC721NonexistentToken error selector.
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @notice Regression tests covering five audit findings for nana-721-hook-v6.
contract AuditRegressions is UnitTestSetup {
    // -----------------------------------------------------------------------
    // 1. balanceOf(address(0)) must revert with JB721TiersHook_ZeroAddress
    // -----------------------------------------------------------------------

    /// @notice Calling balanceOf with address(0) must revert, not return zero.
    function test_balanceOf_zeroAddress_reverts() public {
        // Expect a revert with the custom ZeroAddress error.
        vm.expectRevert(JB721TiersHook.JB721TiersHook_ZeroAddress.selector);

        // Call balanceOf with address(0) — must revert.
        hook.balanceOf(address(0));
    }

    // -----------------------------------------------------------------------
    // 2. tokenURI reverts on a nonexistent token ID
    // -----------------------------------------------------------------------

    /// @notice Calling tokenURI with a token ID that has never been minted must revert.
    function test_tokenURI_nonexistentToken_reverts() public {
        // Pick a token ID that has never been minted.
        uint256 nonExistentTokenId = 999_999_999;

        // Expect a revert with ERC721NonexistentToken carrying the token ID.
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nonExistentTokenId));

        // Call tokenURI — must revert because the token does not exist.
        hook.tokenURI(nonExistentTokenId);
    }

    // -----------------------------------------------------------------------
    // 3. Double-initialization guard
    // -----------------------------------------------------------------------

    /// @notice Calling initialize on an already-initialized clone must revert.
    function test_doubleInitialization_reverts() public {
        // The `hook` from setUp() is already initialized via the deployer.
        // Expect a revert with AlreadyInitialized carrying the existing project ID.
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHook.JB721TiersHook_AlreadyInitialized.selector, projectId));

        // Attempt to initialize the hook again with valid parameters — must revert.
        hook.initialize(
            projectId,
            "AnotherName",
            "AN",
            baseUri,
            IJB721TokenUriResolver(mockTokenUriResolver),
            contractUri,
            JB721InitTiersConfig({
                tiers: new JB721TierConfig[](0), currency: uint32(uint160(JBConstants.NATIVE_TOKEN)), decimals: 18
            }),
            JB721TiersHookFlags({
                preventOverspending: false,
                issueTokensForSplits: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: false
            })
        );
    }

    // -----------------------------------------------------------------------
    // 4. recordSetDiscountPercentOf on a removed tier must revert
    // -----------------------------------------------------------------------

    /// @notice Setting the discount percent on a tier that has been removed must revert.
    function test_setDiscountPercent_removedTier_reverts() public {
        // The hook from setUp() has 10 tiers (IDs 1-10). Remove tier 1.
        uint256[] memory tierIdsToRemove = new uint256[](1);

        // Select tier 1 to remove.
        tierIdsToRemove[0] = 1;

        // Remove tier 1 as the hook owner.
        vm.prank(owner);
        hook.adjustTiers(new JB721TierConfig[](0), tierIdsToRemove);

        // Expect a revert with TierRemoved when setting discount on the removed tier.
        vm.expectRevert(abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_TierRemoved.selector, 1));

        // Attempt to set a discount on the removed tier — must revert.
        vm.prank(owner);
        hook.setDiscountPercentOf(1, 50);
    }

    // -----------------------------------------------------------------------
    // 5. ERC-2981 supportsInterface returns false (support was removed)
    // -----------------------------------------------------------------------

    /// @notice supportsInterface must return false for IERC2981 since royalty support was removed.
    function test_supportsInterface_erc2981_returnsFalse() public {
        // Compute the IERC2981 interface ID from the imported interface.
        bytes4 erc2981InterfaceId = type(IERC2981).interfaceId;

        // Query supportsInterface on the hook.
        bool supported = hook.supportsInterface(erc2981InterfaceId);

        // Assert that ERC-2981 is NOT supported.
        assertFalse(supported, "ERC-2981 must not be supported after royalty removal");
    }
}
