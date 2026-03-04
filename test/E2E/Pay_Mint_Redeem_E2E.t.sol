// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@bananapus/address-registry-v6/src/JBAddressRegistry.sol";

import "../../src/JB721TiersHook.sol";
import "../../src/JB721TiersHookProjectDeployer.sol";
import "../../src/JB721TiersHookDeployer.sol";
import "../../src/JB721TiersHookStore.sol";

import "../utils/TestBaseWorkflow.sol";
import "../../src/interfaces/IJB721TiersHook.sol";
import {MetadataResolverHelper} from "@bananapus/core-v6/test/helpers/MetadataResolverHelper.sol";

contract Test_TiersHook_E2E is TestBaseWorkflow {
    using JBRulesetMetadataResolver for JBRuleset;

    uint256 totalSupplyAfterPay;

    address reserveBeneficiary = address(bytes20(keccak256("reserveBeneficiary")));
    address trustedForwarder = address(123_456);

    JB721TiersHook hook;

    MetadataResolverHelper metadataHelper;

    event Mint(
        uint256 indexed tokenId,
        uint256 indexed tierId,
        address indexed beneficiary,
        uint256 totalAmountPaid,
        address caller
    );
    event Burn(uint256 indexed tokenId, address owner, address caller);

    string name = "NAME";
    string symbol = "SYM";
    string baseUri = "http://www.null.com/";
    string contractUri = "ipfs://null";
    //QmWmyoMoctfbAaiEs2G46gpeUmhqFRDW6KWo64y5r581Vz
    bytes32[] tokenUris = [
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89),
        bytes32(0x7D5A99F603F231D53A4F39D1521F98D2E8BB279CF29BEBFD0687DC98458E7F89)
    ];

    JB721TiersHookProjectDeployer deployer;
    JB721TiersHookStore store;
    JBAddressRegistry addressRegistry;

    function setUp() public override {
        super.setUp();
        store = new JB721TiersHookStore();
        hook = new JB721TiersHook(jbDirectory, jbPermissions, jbRulesets, store, trustedForwarder);
        addressRegistry = new JBAddressRegistry();
        JB721TiersHookDeployer hookDeployer = new JB721TiersHookDeployer(hook, store, addressRegistry, trustedForwarder);
        deployer = new JB721TiersHookProjectDeployer(
            IJBDirectory(jbDirectory), IJBPermissions(jbPermissions), hookDeployer, address(0)
        );

        metadataHelper = new MetadataResolverHelper();
    }

    function testLaunchProjectAndAddHookToRegistry(bytes32 salt) external {
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        (uint256 projectId, IJB721TiersHook _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, bytes32(0));
        // Check: is the first project's ID 1?
        assertEq(projectId, 1);
        // Check: was the hook added to the address registry?
        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);
        assertEq(addressRegistry.deployerOf(dataHook), address(deployer.HOOK_DEPLOYER()));

        // Laucnh another project with a salt
        (projectId, _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, salt);
        // Check: is the second project's ID 2?
        assertEq(projectId, 2);
        // Check: was the hook added to the address registry?
        dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);
        assertEq(addressRegistry.deployerOf(dataHook), address(deployer.HOOK_DEPLOYER()));

        // Laucnh another project with no salt
        (projectId, _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, bytes32(0));

        // Check: is the third project's ID 3?
        assertEq(projectId, 3);

        // Check: was the hook added to the address registry?
        dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);
        assertEq(addressRegistry.deployerOf(dataHook), address(deployer.HOOK_DEPLOYER()));
    }

    function testMintOnPayIfOneTierIsPassed(uint256 valueSent, bytes32 salt) external {
        valueSent = bound(valueSent, 10, 2000);
        // Cap the highest tier ID possible to 10.
        uint256 highestTier = valueSent <= 100 ? (valueSent / 10) : 10;
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        (uint256 projectId, IJB721TiersHook _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, salt);

        // Crafting the payment metadata: add the highest tier ID.
        uint16[] memory rawMetadata = new uint16[](1);
        rawMetadata[0] = uint16(highestTier);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, rawMetadata);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);
        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = JBMetadataResolver.getId("pay", address(hook));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Check: was an NFT with the correct tier ID and token ID minted?
        vm.expectEmit(true, true, true, true);
        emit Mint(
            _generateTokenId(highestTier, 1),
            highestTier,
            beneficiary,
            valueSent,
            address(jbMultiTerminal) // msg.sender
        );

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });
        uint256 tokenId = _generateTokenId(highestTier, 1);
        // Check: did the beneficiary receive the NFT?
        if (valueSent < 10) {
            assertEq(IERC721(dataHook).balanceOf(beneficiary), 0);
        } else {
            assertEq(IERC721(dataHook).balanceOf(beneficiary), 1);
        }

        // Check: is the beneficiary the first owner of the NFT?
        assertEq(IERC721(dataHook).ownerOf(tokenId), beneficiary);
        assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);

        // Check: after a transfer, are the `firstOwnerOf` and `ownerOf` still correct?
        vm.prank(beneficiary);
        IERC721(dataHook).transferFrom(beneficiary, address(696_969_420), tokenId);
        assertEq(IERC721(dataHook).ownerOf(tokenId), address(696_969_420));
        assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);

        // Check: is the same true after a second transfer?
        vm.prank(address(696_969_420));
        IERC721(dataHook).transferFrom(address(696_969_420), address(123_456_789), tokenId);
        assertEq(IERC721(dataHook).ownerOf(tokenId), address(123_456_789));
        assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);
    }

    function testFuzzMintWithDiscountOnPayIfOneTierIsPassed(uint256 tierStartPrice, uint256 discountPercent) external {
        // Cap our fuzzed params
        tierStartPrice = bound(tierStartPrice, 1, type(uint208).max - 1);
        discountPercent = bound(discountPercent, 1, 200);

        {
            uint256 amountMinted = (tierStartPrice * 1000) / 2;
            totalSupplyAfterPay += amountMinted;
        }

        // Cap the highest tier ID.
        uint256 highestTier = 1;

        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createDiscountedData(tierStartPrice, uint8(discountPercent));
        (uint256 projectId, IJB721TiersHook _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, bytes32(0));

        // Crafting the payment metadata: add the highest tier ID.
        uint16[] memory rawMetadata = new uint16[](1);
        rawMetadata[0] = uint16(highestTier);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, rawMetadata);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);
        bytes memory hookMetadata;
        {
            // Pass the hook ID.
            bytes4[] memory ids = new bytes4[](1);
            ids[0] = JBMetadataResolver.getId("pay", address(hook));

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        /* // Check: was an NFT with the correct tier ID and token ID minted?
        vm.expectEmit(true, true, true, true);
        emit Mint(
            _generateTokenId(highestTier, 1),
            highestTier,
            beneficiary,
            tierStartPrice,
            address(jbMultiTerminal) // msg.sender
        ); */

        if (totalSupplyAfterPay > type(uint208).max) {
            vm.expectRevert(
                abi.encodeWithSelector(JBTokens.JBTokens_OverflowAlert.selector, totalSupplyAfterPay, type(uint208).max)
            );
        }

        // Pay the terminal to mint the NFTs.
        vm.deal(caller, type(uint256).max);
        vm.prank(caller);
        jbMultiTerminal.pay{value: tierStartPrice}({
            projectId: projectId,
            amount: tierStartPrice,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        if (totalSupplyAfterPay < type(uint208).max) {
            if (tierStartPrice > type(uint104).max) {
                uint256 expectedDiscount =
                    mulDiv(uint104(tierStartPrice), discountPercent, JB721Constants.MAX_DISCOUNT_PERCENT);
                uint256 paidForNft = uint104(tierStartPrice) - expectedDiscount;

                // Check: should be credited tierStartPrice minus what you paid for the NFT plus the discount
                assertEq(IJB721TiersHook(dataHook).payCreditsOf(beneficiary), tierStartPrice - paidForNft);
            } else {
                uint256 expectedCredits = mulDiv(tierStartPrice, discountPercent, JB721Constants.MAX_DISCOUNT_PERCENT);
                assertEq(IJB721TiersHook(dataHook).payCreditsOf(beneficiary), expectedCredits);
            }

            {
                // Check: did the beneficiary receive the NFT?
                assertEq(IERC721(dataHook).balanceOf(beneficiary), 1);

                uint256 tokenId = _generateTokenId(highestTier, 1);

                // Check: is the beneficiary the first owner of the NFT?
                assertEq(IERC721(dataHook).ownerOf(tokenId), beneficiary);
                assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);

                // Check: after a transfer, are the `firstOwnerOf` and `ownerOf` still correct?
                vm.prank(beneficiary);
                IERC721(dataHook).transferFrom(beneficiary, address(696_969_420), tokenId);
                assertEq(IERC721(dataHook).ownerOf(tokenId), address(696_969_420));
                assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);

                // Check: is the same true after a second transfer?
                vm.prank(address(696_969_420));
                IERC721(dataHook).transferFrom(address(696_969_420), address(123_456_789), tokenId);
                assertEq(IERC721(dataHook).ownerOf(tokenId), address(123_456_789));
                assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);
            }
        }
    }

    function testMintOnPayIfMultipleTiersArePassed(bytes32 salt) external {
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        (uint256 projectId, IJB721TiersHook _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, salt);

        // Prices of the first 5 tiers (10 * `tierId`)
        uint256 amountNeeded = 50 + 40 + 30 + 20 + 10;
        uint16[] memory rawMetadata = new uint16[](5);

        // Mint one NFT per tier from the first 5 tiers.
        for (uint256 i = 0; i < 5; i++) {
            rawMetadata[i] = uint16(i + 1); // Start at `tierId` 1.
            // Check: correct tier IDs and token IDs?
            vm.expectEmit(true, true, true, true);
            emit Mint(
                _generateTokenId(i + 1, 1),
                i + 1,
                beneficiary,
                amountNeeded,
                address(jbMultiTerminal) // `msg.sender`
            );
        }

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, rawMetadata);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = JBMetadataResolver.getId("pay", address(hook));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: amountNeeded}({
            projectId: projectId,
            amount: amountNeeded,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        // Check: were the NFTs actually received?
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 5);
        for (uint256 i = 1; i <= 5; i++) {
            uint256 tokenId = _generateTokenId(i, 1);
            assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);
            // Check: are `firstOwnerOf` and `ownerOf` correct after a transfer?
            vm.prank(beneficiary);
            IERC721(dataHook).transferFrom(beneficiary, address(696_969_420), tokenId);
            assertEq(IERC721(dataHook).ownerOf(tokenId), address(696_969_420));
            assertEq(IJB721TiersHook(dataHook).firstOwnerOf(tokenId), beneficiary);
        }
    }

    function testNoMintOnPayWhenNotIncludingTierIds(uint256 valueSent, bytes32 salt) external {
        valueSent = bound(valueSent, 10, 2000);
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        (uint256 projectId, IJB721TiersHook _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, salt);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);

        // Build the metadata with no tiers specified and the overspending flag.
        bool allowOverspending = true;
        uint16[] memory rawMetadata = new uint16[](0);
        bytes memory metadata =
            abi.encode(bytes32(0), bytes32(0), type(IJB721TiersHook).interfaceId, allowOverspending, rawMetadata);

        // Pay the terminal and pass the metadata.
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: metadata
        });

        // Ensure that no NFT was minted.
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 0);

        // Ensure the beneficiary received pay credits (since no NFTs were minted).
        assertEq(IJB721TiersHook(dataHook).payCreditsOf(beneficiary), valueSent);
    }

    function testNoMintOnPayWhenNotIncludingMetadata(uint256 valueSent, bytes32 salt) external {
        valueSent = bound(valueSent, 10, 2000);
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        (uint256 projectId, IJB721TiersHook _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, salt);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);

        // Pay the terminal with empty metadata (`bytes(0)`).
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        // Ensure that no NFTs were minted.
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 0);

        // Ensure that the beneficiary received pay credits (since no NFTs were minted).
        assertEq(IJB721TiersHook(dataHook).payCreditsOf(beneficiary), valueSent);
    }

    function testMintReservedNft(uint256 valueSent, bytes32 salt) external {
        // cheapest tier is worth 10
        valueSent = bound(valueSent, 10, 20 ether);

        // Cap the highest tier ID possible to 10.
        uint256 highestTier = valueSent <= 100 ? valueSent / 10 : 10;

        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        (uint256 projectId, IJB721TiersHook _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, salt);
        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);

        // Check: Ensure no pending reserves at start (since no minting has happened).
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, highestTier), 0);

        // Check: cannot mint pending reserves (since none should be pending)?
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientPendingReserves.selector, 1, 0)
        );
        vm.prank(projectOwner);
        IJB721TiersHook(dataHook).mintPendingReservesFor(highestTier, 1);

        // Crafting the payment metadata: add the highest tier ID.
        uint16[] memory rawMetadata = new uint16[](1);
        rawMetadata[0] = uint16(highestTier);

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, rawMetadata);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = JBMetadataResolver.getId("pay", address(hook));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Check: were an NFT with the correct tier ID and token ID minted?
        vm.expectEmit(true, true, true, true);
        emit Mint(
            _generateTokenId(highestTier, 1), // First one
            highestTier,
            beneficiary,
            valueSent,
            address(jbMultiTerminal) // msg.sender
        );

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        // Check: is there now 1 pending reserve? 1 mint should yield 1 pending reserve, due to rounding up.
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, highestTier), 1);

        JB721Tier memory tierBeforeMintingReserves =
            JB721TiersHook(dataHook).STORE().tierOf(dataHook, highestTier, false);

        // Mint the pending reserve NFT.
        vm.prank(projectOwner);
        IJB721TiersHook(dataHook).mintPendingReservesFor(highestTier, 1);
        // Check: did the reserve beneficiary receive the NFT?
        assertEq(IERC721(dataHook).balanceOf(reserveBeneficiary), 1);

        JB721Tier memory tierAfterMintingReserves =
            JB721TiersHook(dataHook).STORE().tierOf(dataHook, highestTier, false);
        // The tier's remaining supply should have decreased by 1.
        assertLt(tierAfterMintingReserves.remainingSupply, tierBeforeMintingReserves.remainingSupply);

        // Check: there should now be 0 pending reserves.
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, highestTier), 0);
        // Check: it should not be possible to mint pending reserves now (since there are none left).
        vm.expectRevert(
            abi.encodeWithSelector(JB721TiersHookStore.JB721TiersHookStore_InsufficientPendingReserves.selector, 1, 0)
        );
        vm.prank(projectOwner);
        IJB721TiersHook(dataHook).mintPendingReservesFor(highestTier, 1);
    }

    // - Mint an NFT.
    // - Check the number of pending reserve mints available within that NFT's tier, which should be non-zero due to
    // rounding up.
    // - Burn an NFT from that tier.
    // - Check the number of pending reserve mints available within the NFT's tier again.
    // This number should be back to 0, since the NFT was burned.
    function testCashOutToken(uint256 valueSent, bytes32 salt) external {
        valueSent = bound(valueSent, 10, 2000);

        // Cap the highest tier ID possible to 10.
        uint256 highestTier = valueSent <= 100 ? (valueSent / 10) : 10;
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();

        // rr of 1.
        tiersHookConfig.tiersConfig.tiers[highestTier - 1].reserveFrequency = 1;

        (uint256 projectId, IJB721TiersHook _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, salt);

        // Craft the metadata: buy 1 NFT from the highest tier.
        bytes memory hookMetadata;
        bytes[] memory data;
        bytes4[] memory ids;
        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);
        {
            uint16[] memory rawMetadata = new uint16[](1);
            rawMetadata[0] = uint16(highestTier);

            // Build the metadata using the tiers to mint and the overspending flag.
            data = new bytes[](1);
            data[0] = abi.encode(true, rawMetadata);

            // Pass the hook ID.
            ids = new bytes4[](1);
            ids[0] = metadataHelper.getId("pay", address(hook));

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        {
            // Get the token ID of the NFT that was minted.
            uint256 tokenId = _generateTokenId(highestTier, 1);

            // Craft the metadata: cash out the `tokenId` which was minted.
            uint256[] memory cashOutId = new uint256[](1);
            cashOutId[0] = tokenId;

            // Build the metadata with the tiers to cash out.
            data[0] = abi.encode(cashOutId);

            // Pass the hook ID.
            ids[0] = metadataHelper.getId("cashOut", address(hook));

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Check: was the beneficiary's NFT balance decreased by 1?
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 1);

        // Cash out the NFT.
        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: hookMetadata
        });

        // Check: was the beneficiary's NFT balance decreased by 1?
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 0);

        // Check: was the burn accounted for in the store?
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfBurnedFor(dataHook, highestTier), 1);

        // Check: the number of pending reserves should be equal to the calculated figure which accounts for rounding.
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, highestTier), 1);

        {
            uint16[] memory rawMetadata = new uint16[](1);
            rawMetadata[0] = uint16(highestTier);

            // Build the metadata using the tiers to mint and the overspending flag.
            data = new bytes[](1);
            data[0] = abi.encode(true, rawMetadata);

            // Pass the hook ID.
            ids = new bytes4[](1);
            ids[0] = metadataHelper.getId("pay", address(hook));

            // Generate the metadata.
            hookMetadata = metadataHelper.createMetadata(ids, data);
        }

        // Pay the terminal to mint one more NFT.
        vm.prank(caller);
        jbMultiTerminal.pay{value: valueSent}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        // Check: was the beneficiary's NFT balance is 1.
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 1);

        // Check: the number of pending reserves shouldn't have changed.
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, highestTier), 2);
    }

    // - Mint 5 NFTs from a tier.
    // - Check the remaining supply within that NFT's tier. (highest tier == 10, reserved percent is maximum -> 5)
    // - Cash out all of the corresponding token from that tier
    function testCashOutAll(bytes32 salt) external {
        (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig) =
            createData();
        uint256 tier = 10;
        uint256 tierPrice = tiersHookConfig.tiersConfig.tiers[tier - 1].price;
        (uint256 projectId, IJB721TiersHook _hook) =
            deployer.launchProjectFor(projectOwner, tiersHookConfig, launchProjectConfig, jbController, salt);

        // Craft the metadata: buy 5 NFTs from tier 10.
        uint16[] memory rawMetadata = new uint16[](5);
        for (uint256 i; i < rawMetadata.length; i++) {
            rawMetadata[i] = uint16(tier);
        }

        // Build the metadata using the tiers to mint and the overspending flag.
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(true, rawMetadata);

        address dataHook = jbRulesets.currentOf(projectId).dataHook();
        assertEq(address(_hook), dataHook);

        // Pass the hook ID.
        bytes4[] memory ids = new bytes4[](1);
        ids[0] = metadataHelper.getId("pay", address(hook));

        // Generate the metadata.
        bytes memory hookMetadata = metadataHelper.createMetadata(ids, data);

        // Pay the terminal to mint the NFTs.
        vm.prank(caller);
        jbMultiTerminal.pay{value: tierPrice * rawMetadata.length}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        // Get the beneficiary's new NFT balance.
        uint256 nftBalance = IERC721(dataHook).balanceOf(beneficiary);
        // Check: are the NFT balance and pending reserves correct?
        assertEq(rawMetadata.length, nftBalance);
        // Add 1 to the pending reserves check, as we round up for non-null values.
        assertEq(
            IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, tier),
            (nftBalance / tiersHookConfig.tiersConfig.tiers[tier - 1].reserveFrequency) + 1
        );
        // Craft the metadata to cash out the `tokenId`s.
        uint256[] memory cashOutId = new uint256[](5);
        for (uint256 i; i < rawMetadata.length; i++) {
            uint256 tokenId = _generateTokenId(tier, i + 1);
            cashOutId[i] = tokenId;
        }

        // Build the metadata with the tiers to cash out.
        data[0] = abi.encode(cashOutId);

        // Pass the hook ID.
        ids[0] = metadataHelper.getId("cashOut", address(hook));

        // Generate the metadata.
        hookMetadata = metadataHelper.createMetadata(ids, data);

        // Cash out the NFTs.
        vm.prank(beneficiary);
        jbMultiTerminal.cashOutTokensOf({
            holder: beneficiary,
            projectId: projectId,
            tokenToReclaim: JBConstants.NATIVE_TOKEN,
            cashOutCount: 0,
            minTokensReclaimed: 0,
            beneficiary: payable(beneficiary),
            metadata: hookMetadata
        });

        // Check: did the beneficiary's NFT balance decrease by 5 (to 0)?
        assertEq(IERC721(dataHook).balanceOf(beneficiary), 0);
        // Check: were the NFT burns accounted for in the store?
        assertEq(IJB721TiersHook(dataHook).STORE().numberOfBurnedFor(dataHook, tier), 5);
        // Check: did the number of pending reserves didnt change due to the burn.
        assertEq(
            IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, tier),
            (nftBalance / tiersHookConfig.tiersConfig.tiers[tier - 1].reserveFrequency) + 1
        );

        // Craft the metadata: buy *1* NFT from tier 10.
        uint16[] memory rawMetadata2 = new uint16[](1);
        for (uint256 i; i < rawMetadata2.length; i++) {
            rawMetadata2[i] = uint16(tier);
        }

        // Build the metadata using the tiers to mint and the overspending flag.
        data[0] = abi.encode(true, rawMetadata2);

        // Pass the hook ID.
        ids[0] = metadataHelper.getId("pay", address(hook));

        // Generate the metadata.
        hookMetadata = metadataHelper.createMetadata(ids, data);

        // Check: can more NFTs be minted (now that the previous ones were burned)?
        vm.prank(caller);
        jbMultiTerminal.pay{value: tierPrice * rawMetadata2.length}({
            projectId: projectId,
            amount: 100,
            token: JBConstants.NATIVE_TOKEN,
            beneficiary: beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: hookMetadata
        });

        // Get the new NFT balance.
        nftBalance = IERC721(dataHook).balanceOf(beneficiary);
        // Check: are the NFT balance and pending reserves correct?
        assertEq(rawMetadata2.length, nftBalance);
        // Add 1 to the pending reserves check, as we round up for non-null values.
        assertEq(
            IJB721TiersHook(dataHook).STORE().numberOfPendingReservesFor(dataHook, tier),
            (nftBalance / tiersHookConfig.tiersConfig.tiers[tier - 1].reserveFrequency) + 1
        );
    }

    // ----- internal helpers ------
    // Creates a `launchProjectFor(...)` payload.
    function createData()
        internal
        view
        returns (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig)
    {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](10);
        for (uint256 i; i < 10; i++) {
            tierConfigs[i] = JB721TierConfig({
                price: uint104((i + 1) * 10),
                initialSupply: uint32(10),
                votingUnits: uint32((i + 1) * 10),
                reserveFrequency: 10,
                reserveBeneficiary: reserveBeneficiary,
                encodedIPFSUri: tokenUris[i],
                category: uint24(100),
                discountPercent: uint8(0),
                allowOwnerMint: false,
                useReserveBeneficiaryAsDefault: false,
                transfersPausable: false,
                useVotingUnits: false,
                cannotBeRemoved: false,
                cannotIncreaseDiscountPercent: false
            });
        }
        tiersHookConfig = JBDeploy721TiersHookConfig({
            name: name,
            symbol: symbol,
            baseUri: baseUri,
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: contractUri,
            tiersConfig: JB721InitTiersConfig({
                tiers: tierConfigs,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                decimals: 18,
                prices: IJBPrices(address(0))
            }),
            reserveBeneficiary: reserveBeneficiary,
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: true
            })
        });

        JBPayDataHookRulesetMetadata memory metadata = JBPayDataHookRulesetMetadata({
            reservedPercent: 5000, //50%
            cashOutTaxRate: 5000, //50%
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            ownerMustSendPayouts: false,
            allowAddAccountingContext: false,
            allowAddPriceFeed: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForCashOut: true,
            metadata: 0x00
        });

        JBPayDataHookRulesetConfig[] memory rulesetConfigurations = new JBPayDataHookRulesetConfig[](1);
        // Package up the ruleset configuration.
        rulesetConfigurations[0].mustStartAtOrAfter = 0;
        rulesetConfigurations[0].duration = 14;
        rulesetConfigurations[0].weight = 1000 * 10 ** 18;
        rulesetConfigurations[0].weightCutPercent = 450_000_000;
        rulesetConfigurations[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfigurations[0].metadata = metadata;

        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContext[] memory accountingContextsToAccept = new JBAccountingContext[](1);
        accountingContextsToAccept[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            decimals: 18
        });
        terminalConfigurations[0] =
            JBTerminalConfig({terminal: jbMultiTerminal, accountingContextsToAccept: accountingContextsToAccept});

        launchProjectConfig = JBLaunchProjectConfig({
            projectUri: projectUri,
            rulesetConfigurations: rulesetConfigurations,
            terminalConfigurations: terminalConfigurations,
            memo: ""
        });
    }

    function createDiscountedData(
        uint256 _price,
        uint8 _discountPercent
    )
        internal
        view
        returns (JBDeploy721TiersHookConfig memory tiersHookConfig, JBLaunchProjectConfig memory launchProjectConfig)
    {
        JB721TierConfig[] memory tierConfigs = new JB721TierConfig[](1);
        tierConfigs[0] = JB721TierConfig({
            price: uint104(_price),
            initialSupply: uint32(10),
            votingUnits: uint32(10),
            reserveFrequency: 10,
            reserveBeneficiary: reserveBeneficiary,
            encodedIPFSUri: tokenUris[0],
            category: uint24(100),
            discountPercent: _discountPercent,
            allowOwnerMint: false,
            useReserveBeneficiaryAsDefault: false,
            transfersPausable: false,
            useVotingUnits: false,
            cannotBeRemoved: false,
            cannotIncreaseDiscountPercent: false
        });

        tiersHookConfig = JBDeploy721TiersHookConfig({
            name: name,
            symbol: symbol,
            baseUri: baseUri,
            tokenUriResolver: IJB721TokenUriResolver(address(0)),
            contractUri: contractUri,
            tiersConfig: JB721InitTiersConfig({
                tiers: tierConfigs,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                decimals: 18,
                prices: IJBPrices(address(0))
            }),
            reserveBeneficiary: reserveBeneficiary,
            flags: JB721TiersHookFlags({
                preventOverspending: false,
                noNewTiersWithReserves: false,
                noNewTiersWithVotes: false,
                noNewTiersWithOwnerMinting: true
            })
        });

        JBPayDataHookRulesetMetadata memory metadata = JBPayDataHookRulesetMetadata({
            reservedPercent: 5000, //50%
            cashOutTaxRate: 5000, //50%
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            ownerMustSendPayouts: false,
            allowAddAccountingContext: false,
            allowAddPriceFeed: false,
            holdFees: false,
            useTotalSurplusForCashOuts: false,
            useDataHookForCashOut: true,
            metadata: 0x00
        });

        JBPayDataHookRulesetConfig[] memory rulesetConfigurations = new JBPayDataHookRulesetConfig[](1);
        // Package up the ruleset configuration.
        rulesetConfigurations[0].mustStartAtOrAfter = 0;
        rulesetConfigurations[0].duration = 14;
        rulesetConfigurations[0].weight = 1000 * 10 ** 18;
        rulesetConfigurations[0].weightCutPercent = 450_000_000;
        rulesetConfigurations[0].approvalHook = IJBRulesetApprovalHook(address(0));
        rulesetConfigurations[0].metadata = metadata;

        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContext[] memory accountingContextsToAccept = new JBAccountingContext[](1);
        accountingContextsToAccept[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            decimals: 18
        });
        terminalConfigurations[0] =
            JBTerminalConfig({terminal: jbMultiTerminal, accountingContextsToAccept: accountingContextsToAccept});

        launchProjectConfig = JBLaunchProjectConfig({
            projectUri: projectUri,
            rulesetConfigurations: rulesetConfigurations,
            terminalConfigurations: terminalConfigurations,
            memo: ""
        });
    }

    // Generate `tokenId`s based on the tier ID and token number provided.
    function _generateTokenId(uint256 tierId, uint256 tokenNumber) internal pure returns (uint256) {
        return (tierId * 1_000_000_000) + tokenNumber;
    }
}
