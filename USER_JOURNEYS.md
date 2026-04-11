# User Journeys

## Who This Repo Serves

- project owners selling or rewarding supporters with tiered NFTs
- operators managing tier supply, pricing, reserves, and ruleset-aware hook behavior
- supporters minting or cashing out tier positions through normal Juicebox flows
- integrators composing custom token URI resolvers on top of the standard 721 hook

## Journey 1: Add A Tiered 721 Hook To An Existing Project

**Starting state:** the project already exists in Juicebox and needs tiered NFT issuance without relaunching.

**Success:** a hook clone is deployed, initialized, and attached to the project's ruleset metadata.

**Flow**
1. Use `JB721TiersHookDeployer` to clone a hook for the target project.
2. Define tier config, reserve behavior, token URI resolver, and per-ruleset flags.
3. Queue or install ruleset metadata that tells the project when the hook should participate in pay and cash-out flows.
4. Future payments into the project can now mint tiers under the configured constraints.

## Journey 2: Launch A New Project With A 721 Hook Already Wired In

**Starting state:** the product wants its project treasury and NFT logic created in one operation.

**Success:** the project launches with the hook, terminals, and initial tiers already aligned.

**Flow**
1. Use `JB721TiersHookProjectDeployer` with launch config, rulesets, and hook config.
2. The deployer launches the project through the core protocol and deploys the hook in the same packaged flow.
3. The initial ruleset metadata points at the newly created hook so there is no post-launch rewiring gap.
4. The project starts life as a tiered 721 project instead of becoming one later.

## Journey 3: Mint Specific Tiers Through A Payment

**Starting state:** the project has live tiers and the payer knows which tiers they want.

**Success:** the treasury receives funds and the beneficiary receives the intended NFT tiers plus any accompanying project-token behavior.

**Flow**
1. The payer submits a payment with metadata encoding the desired tier selections.
2. `JB721TiersHook` validates tier availability, quantity rules, discounts, category constraints, and any ruleset flags affecting minting.
3. `JB721TiersHookStore` updates supply and reserve accounting.
4. The hook mints the correct NFTs and the underlying terminal completes treasury accounting.

**Failure cases that matter:** sold-out tiers, bad metadata, cross-currency pricing mistakes, paused pay-hook behavior, and split-routing edge cases when part of the payment should bypass normal minting assumptions.

## Journey 4: Mint Reserves And Operate Tier Inventory Over Time

**Starting state:** the collection is live and the owner needs to manage what exists for future minters versus reserve recipients.

**Success:** reserves, new tiers, removed tiers, and editable fields evolve without corrupting ownership or supply history.

**Flow**
1. Authorized operators use the hook's tier-management surfaces to add, remove, or adjust tiers.
2. Reserve minting uses the configured reserve frequency and reserve beneficiary settings instead of ad hoc treasury actions.
3. The store keeps historical tier state coherent so existing token IDs continue to resolve correctly.
4. Downstream products such as Croptop, Banny, and Revnets can continue assuming stable tier semantics.

## Journey 5: Let Holders Cash Out Tier Positions

**Starting state:** a holder owns one or more NFTs from a hook-enabled project and the active ruleset allows surplus-backed exits.

**Success:** the holder burns the intended tier exposure and receives the correct reclaim value through the core terminal.

**Flow**
1. The holder calls the project's cash-out path on the terminal.
2. The hook participates in the cash-out calculation so tier-specific weight and store state are reflected correctly.
3. The terminal settles reclaim value and the NFT position is burned or otherwise marked as consumed by the exit path.

**Edge conditions that change user experience:** ERC-20 cash-out surfaces, tier splits, reserve accounting drift, broken downstream terminals, and projects that use the hook for metadata only versus economically binding flows.

## Journey 6: Compose A Custom Product On Top Of The Standard Hook

**Starting state:** the team wants product-specific rendering or business rules but does not want to fork tier issuance.

**Success:** the product resolver or wrapper composes with the hook instead of reimplementing pricing, tier accounting, and treasury logic.

**Flow**
1. Plug a custom resolver into the hook for metadata and product-specific presentation.
2. Keep collection-specific behavior in the downstream repo while leaving pay, reserve, and cash-out semantics in this repo.
3. Audit hook-store interactions here first, then audit the downstream resolver or wrapper.

## Journey 7: Mint NFTs To The Correct Beneficiary During Cross-Chain Payments

**Starting state:** a sucker pays the project on behalf of a remote user via `payRemote`, and the 721 hook needs to mint NFTs and accrue credits to the real user instead of the sucker contract.

**Success:** NFTs mint to and pay credits accrue to the real remote user.

**Flow**
1. The sucker calls `terminal.pay()` with itself as both payer and beneficiary, embedding the real user's address in the `JB_RELAY_BENEFICIARY` metadata key.
2. `_mintAndUpdateCredits` detects that `payer == beneficiary` and finds relay-beneficiary metadata.
3. All NFT minting and credit accounting uses the resolved relay beneficiary instead of the sucker address.

## Hand-Offs

- Use [nana-core-v6](../nana-core-v6/USER_JOURNEYS.md) for the treasury, ruleset, and permission surfaces the hook plugs into.
- Use [banny-retail-v6](../banny-retail-v6/USER_JOURNEYS.md), [croptop-core-v6](../croptop-core-v6/USER_JOURNEYS.md), and [revnet-core-v6](../revnet-core-v6/USER_JOURNEYS.md) for product layers built on this hook.
