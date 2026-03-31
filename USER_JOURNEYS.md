# User Journeys

## Who This Repo Serves

- project owners selling or rewarding with tiered NFTs
- supporters minting specific tiers on payment
- operators managing tier inventories and per-ruleset sale behavior

## Journey 1: Launch A Tiered NFT Collection On A Project

**Starting state:** you know the tiers you want to sell or issue and how they should interact with normal Juicebox payments.

**Success:** the project has a 721 hook that mints the right tiered NFTs as supporters pay.

**Flow**
1. Deploy or initialize the 721 hook for the target project.
2. Define tiers with pricing, supply caps, voting units, reserve frequency, category, and transfer settings.
3. Configure per-ruleset flags such as whether the hook should mint on payment, pause transfers, or use pay credits.
4. Attach the hook to the project's ruleset metadata so normal payments can target NFT minting.

## Journey 2: Mint A Specific Tier As A Supporter

**Starting state:** the project has live tiers and the payment metadata identifies which tier or tiers to mint.

**Success:** the payer receives the intended NFT tier and the project's treasury receives the payment.

**Flow**
1. Submit a payment through the project's terminal with metadata that encodes the desired tiers.
2. The terminal records the payment.
3. The 721 hook validates tier availability, pricing, and quantity rules.
4. Matching tiers mint to the beneficiary, and any normal token issuance behavior follows the active ruleset.

**Failure cases that matter:** sold-out tiers, mispriced payments, paused minting behavior, and invalid metadata.

## Journey 3: Reconfigure Tiers Without Breaking Existing Holders

**Starting state:** the collection is live and needs new tiers, price changes, or metadata changes.

**Success:** the collection evolves within the hook's permission and ruleset boundaries.

**Flow**
1. Use the appropriate permissioned surface to add, remove, or edit tiers.
2. Keep in mind that some changes affect only future minting while others affect transfer or redemption behavior.
3. If the collection is part of a larger system such as Croptop, Banny, or a revnet, confirm the downstream assumptions before changing a tier definition.

## Hand-Offs

- Use [nana-core-v6](../nana-core-v6/USER_JOURNEYS.md) for the treasury and ruleset layer beneath the hook.
- Use [croptop-core-v6](../croptop-core-v6/USER_JOURNEYS.md), [banny-retail-v6](../banny-retail-v6/USER_JOURNEYS.md), or [revnet-core-v6](../revnet-core-v6/USER_JOURNEYS.md) for product-specific uses of the hook.
