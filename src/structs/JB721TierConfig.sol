// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";

import {JB721TierConfigFlags} from "./JB721TierConfigFlags.sol";

/// @notice Config for a single NFT tier within a `JB721TiersHook`.
/// @custom:member price The price to buy an NFT in this tier, in terms of the currency in its `JBInitTiersConfig`.
/// @custom:member initialSupply The total number of NFTs which can be minted from this tier.
/// @custom:member votingUnits The number of votes that each NFT in this tier gets if `useVotingUnits` is true.
/// @custom:member reserveFrequency The frequency at which an extra NFT is minted for the `reserveBeneficiary` from this
/// tier. With a `reserveFrequency` of 5, an extra NFT will be minted for the `reserveBeneficiary` for every 5 NFTs
/// purchased.
/// @custom:member reserveBeneficiary The address which receives any reserve NFTs from this tier. Overrides the default
/// reserve beneficiary if one is set.
/// @custom:member encodedIpfsUri The IPFS URI to use for each NFT in this tier.
/// @custom:member category The category that NFTs in this tier belongs to. Used to group NFT tiers.
/// @custom:member discountPercent The discount that should be applied to the tier.
/// @custom:member flags Boolean flags for this tier config (allowOwnerMint, useReserveBeneficiaryAsDefault,
/// transfersPausable, useVotingUnits, cantBeRemoved, cantIncreaseDiscountPercent, cantBuyWithCredits).
/// @custom:member splitPercent The percentage of the tier's price that gets routed to the tier's split group when
/// an NFT from this tier is minted. Out of `JBConstants.SPLITS_TOTAL_PERCENT`.
/// @custom:member splits The splits to use for this tier's split group. These define where the split portion of the
/// tier's price gets routed when an NFT from this tier is minted.
struct JB721TierConfig {
    uint104 price;
    uint32 initialSupply;
    uint32 votingUnits;
    uint16 reserveFrequency;
    address reserveBeneficiary;
    bytes32 encodedIpfsUri;
    uint24 category;
    uint8 discountPercent;
    JB721TierConfigFlags flags;
    uint32 splitPercent;
    JBSplit[] splits;
}
