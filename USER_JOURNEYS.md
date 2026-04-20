# User Journeys

## Repo Purpose

This repo is the standard tiered NFT hook for V6 projects.
It owns tier issuance, reserve accounting, hook-aware mint and cash-out behavior, and deployer packaging for hook
clones or hook-shaped project launches. It does not own collection-specific rendering or app-layer policy built on top
of the hook.

## Primary Actors

- project owners selling or rewarding supporters with tiered NFTs
- operators managing tier supply, pricing, reserves, and ruleset-aware hook behavior
- supporters minting or cashing out tier positions through normal Juicebox flows
- integrators composing custom token URI resolvers or downstream products on top of the hook

## Key Surfaces

- `JB721TiersHook`: project-facing hook behavior for minting, reserves, metadata, and cash out
- `JB721TiersHookStore`: tier definitions and accounting backend
- `JB721TiersHookDeployer`: clone factory for existing projects
- `JB721TiersHookProjectDeployer`: project-launch packaging for new hook-backed projects

## Journey 1: Add A Tiered 721 Hook To An Existing Project

**Actor:** project owner or deployer.

**Intent:** attach tiered NFT behavior to an existing project without relaunching it.

**Preconditions**
- the project already exists in Juicebox
- the owner knows the tier config, reserve behavior, and resolver assumptions it wants
- the next ruleset metadata can be updated safely

**Main Flow**
1. Use `JB721TiersHookDeployer` to clone a hook for the project.
2. Define tier config, reserve behavior, resolver choice, and per-ruleset flags.
3. Queue or install ruleset metadata that points at the hook.
4. Future payments can now mint tiers under the configured constraints.

**Failure Modes**
- the hook is deployed correctly but the ruleset metadata does not actually activate it
- teams treat the resolver as cosmetic when it is part of the trusted surface

**Postconditions**
- the project has an attached hook and future rulesets can mint tiers under the configured constraints

## Journey 2: Launch A New Project With A 721 Hook Already Wired In

**Actor:** product team or deployer.

**Intent:** launch a project whose treasury and tiered NFT logic are aligned from the first ruleset.

**Preconditions**
- the team has launch config, terminal config, and initial tier config ready

**Main Flow**
1. Use `JB721TiersHookProjectDeployer` with launch and hook config.
2. Launch the project and deploy the hook in the same packaged flow.
3. Ensure the first ruleset already points at the created hook.
4. Start life as a hook-backed project instead of converting later.

**Failure Modes**
- deployers assume the package is purely convenience and miss the initial ruleset implications
- launch-time metadata drifts from the actual hook config

**Postconditions**
- the project launches with tiered NFT logic active from the first ruleset

## Journey 3: Mint Specific Tiers Through A Payment

**Actor:** payer.

**Intent:** mint one or more tiers through a normal payment flow.

**Preconditions**
- the project has live tiers
- the payer submits metadata encoding the intended tier selections

**Main Flow**
1. Submit a payment with tier-selection metadata.
2. `JB721TiersHook` validates availability, quantity rules, discounts, and ruleset flags.
3. `JB721TiersHookStore` updates supply and reserve accounting.
4. The hook mints the intended NFTs and the terminal completes treasury accounting.

**Failure Modes**
- sold-out tiers, malformed metadata, or cross-currency pricing mistakes
- pay-hook participation flags do not match the user's assumptions
- split-routing or hook behavior changes what part of the payment actually mints

**Postconditions**
- the intended tiers are minted and store accounting reflects the updated supply and reserve state

## Journey 4: Mint Reserves And Operate Tier Inventory Over Time

**Actor:** owner or authorized operator.

**Intent:** manage tier inventory and reserve behavior after launch.

**Preconditions**
- the collection is live
- the operator has the required permission surfaces to mutate tiers or mint reserves

**Main Flow**
1. Use tier-management surfaces to add, remove, or adjust tiers.
2. Mint reserves through the configured reserve logic.
3. Let the store preserve historical tier state so old token IDs still resolve correctly.
4. Keep downstream products assuming stable tier semantics whenever possible.

**Failure Modes**
- tier mutations surprise downstream products or resolvers
- reserve accounting is misread as ordinary minting

**Postconditions**
- live tier inventory and reserve state match the operator's configured collection policy

## Journey 5: Let Holders Cash Out Tier Positions

**Actor:** holder.

**Intent:** exit a tier position through the project's cash-out path.

**Preconditions**
- the holder owns one or more NFTs from the hook-enabled project
- the active ruleset allows a surplus-backed exit

**Main Flow**
1. Call the project's cash-out path on the terminal.
2. Let the hook participate in cash-out calculation so tier state is reflected.
3. Burn or consume the tier exposure as required by the exit path.
4. Receive the reclaim value through the terminal that holds the asset.

**Failure Modes**
- the project uses the hook for metadata only and the holder assumes an economic cash-out path exists
- terminal behavior or reserve drift changes reclaim expectations

**Postconditions**
- the holder exits the tier position through the hook-aware terminal path or learns that no such economic path is active

## Journey 6: Compose A Custom Product On Top Of The Standard Hook

**Actor:** integrator or downstream product team.

**Intent:** build collection-specific behavior without reimplementing hook economics.

**Preconditions**
- the team wants custom presentation or app-layer logic
- the team does not want to fork pricing, reserve, and treasury behavior

**Main Flow**
1. Plug a custom resolver or wrapper into the hook.
2. Keep collection-specific behavior outside this repo.
3. Audit hook-store interactions here first, then audit the downstream wrapper.

**Failure Modes**
- downstream products reimplement hook behavior and drift from canonical accounting
- teams blame the hook for bugs that actually live in the resolver or wrapper

**Postconditions**
- the custom product reuses canonical hook economics while isolating collection-specific behavior downstream

## Journey 7: Mint NFTs To The Correct Beneficiary During Cross-Chain Payments

**Actor:** cross-chain payer or integrator.

**Intent:** preserve the real remote beneficiary when a sucker relays a payment.

**Preconditions**
- a sucker or relay path pays on behalf of a remote user
- relay-beneficiary metadata is encoded correctly

**Main Flow**
1. The sucker calls `terminal.pay()` with relay-beneficiary metadata.
2. `_mintAndUpdateCredits` resolves the relay beneficiary when `payer == beneficiary`.
3. NFT minting and credit accounting use the resolved remote user.

**Failure Modes**
- relay metadata is missing or malformed
- downstream systems attribute NFTs or credits to the sucker instead of the user

**Postconditions**
- NFT minting and credit accounting attribute the remote payment to the correct beneficiary

## Trust Boundaries

- `JB721TiersHookStore` is the accounting backend and should be treated as part of the same economic surface as the hook
- custom token URI resolvers are part of the trusted collection surface
- core terminals remain the source of treasury accounting truth around the hook

## Hand-Offs

- Use [nana-core-v6](../nana-core-v6/USER_JOURNEYS.md) for the treasury, ruleset, and permission surfaces the hook plugs into.
- Use [banny-retail-v6](../banny-retail-v6/USER_JOURNEYS.md), [croptop-core-v6](../croptop-core-v6/USER_JOURNEYS.md), and [revnet-core-v6](../revnet-core-v6/USER_JOURNEYS.md) for product layers built on this hook.
