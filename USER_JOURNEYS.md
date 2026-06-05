# User Journeys

## Repo purpose

This repo adds tiered NFT logic to Juicebox payment and cash-out flows. It owns tier pricing, reserves, and NFT lifecycle state. It does not own project-specific artwork or game logic.

## Primary actors

- projects that want priced NFT tiers in their Juicebox flow
- operators managing tier configuration and hook permissions
- holders minting, transferring, and cashing out tiered NFTs
- auditors reviewing tier accounting, reserve behavior, and deployer wiring

## Key surfaces

- `JB721TiersHook`: runtime 721 hook behavior
- `JB721TiersHookStore`: tier accounting and supply state
- `JB721TiersHookDeployer` and `JB721TiersHookProjectDeployer`: wiring surfaces
- token URI resolver contracts in downstream repos: presentation layer

## Journey 1: Launch a project with a tiered NFT hook

**Actor:** project operator or deployer.

**Intent:** attach tiered NFT issuance to a project from the start.

**Preconditions**
- the project knows its tier structure and hook expectations
- the deployer path matches whether the project already exists
- if `JBProjects` has a creation fee, the launch caller sends that exact native-token amount

**Main Flow**
1. Deploy a hook clone or launch a project with the hook already attached.
2. Configure tier data, hook metadata, and resolver expectations.
3. Transfer hook ownership into the intended project control surface.

**Failure Modes**
- wrong hook wiring at launch
- wrong resolver assumptions
- teams treat deployer convenience as proof that runtime economics are correct

**Postconditions**
- the project has a tiered NFT hook wired into its Juicebox flow

## Journey 2: Pay and mint tiered NFTs

**Actor:** payer or integration acting for a payer.

**Intent:** mint NFTs from configured tiers while preserving the project's terminal flow.

**Preconditions**
- the project has active tiers
- payment metadata correctly names the intended tiers

**Main Flow**
1. A payment reaches the hook through the terminal.
2. The hook decodes tier selection and records mint state in the store.
3. NFTs mint, reserve implications update, and any split routing is applied.

**Failure Modes**
- malformed metadata
- currency mismatch or missing pricing support
- splits or discounts behave differently than the integration expected

**Postconditions**
- the payer or beneficiary receives the intended NFT tiers and tier state updates

## Journey 3: Mint or release reserve NFTs

**Actor:** reserve beneficiary, operator, or any caller using the reserve path.

**Intent:** realize pending reserves under the configured reserve rules.

**Preconditions**
- the relevant tiers have reserve logic enabled
- the ruleset does not pause pending reserve minting

**Main Flow**
1. Eligible reserve amounts accumulate as mint activity happens.
2. A caller triggers reserve minting for pending tiers.
3. The store moves reserve state forward and NFTs mint to the configured reserve beneficiary.

**Failure Modes**
- teams misunderstand that reserve minting timing is not owner-exclusive
- reserve assumptions drift from actual tier settings

**Postconditions**
- pending reserves mint according to tier configuration

## Journey 4: Cash out tiered NFTs

**Actor:** NFT holder.

**Intent:** redeem tiered NFT exposure through the terminal cash-out path.

**Preconditions**
- the holder owns valid NFTs
- the hook is active for the cash-out path

**Main Flow**
1. The holder requests a cash out with NFT-specific metadata.
2. The hook burns the selected NFTs and records the burn in the store.
3. The terminal completes reclaim logic using the hook-aware cash-out surface.

**Failure Modes**
- integrations mix fungible-token and NFT cash-out assumptions
- pending reserves or discounts are misunderstood in value calculations
- token IDs are invalid or already burned

**Postconditions**
- NFTs burn and reclaim value follows the intended tier model

**Voting and tier-scoped rewards note**
- Voting power and snapshot eligibility are tracked by the per-hook `JB721Checkpoints` module, lazily deployed on the first transfer.
- A freshly minted token immediately has ownership history through `ownerOfAt`; minting adds its tier voting units to the owner-tracked `getPastTierVotingUnits(tierId, blockNumber)` total, and burning removes them.
- Delegation is the active-participation switch. Active voting totals are tracked globally with `getPastTotalActiveVotes(blockNumber)` / `getTotalActiveVotes()` and per tier with `getPastTierActiveVotes(tierId, blockNumber)` / `getTierActiveVotes(tierId)`.
- A self-delegated holder is active, an undelegated AMM or custody address is inactive, and returned tokens become active again automatically if the holder's delegation is still set.

## Trust boundaries

- this repo trusts core terminals, directory checks, and pricing surfaces from `nana-core-v6`
- metadata resolvers are outside this repo but still affect user-visible trust
- the store is the main source of truth for tier lifecycle state

## Hand-offs

- Use [nana-core-v6](../nana-core-v6/USER_JOURNEYS.md) for the underlying terminal and accounting behavior.
- Use the downstream resolver repo when the question is about project-specific metadata or rendering.
