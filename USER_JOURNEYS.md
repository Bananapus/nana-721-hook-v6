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
1. Authorized operators use `adjustTiers(...)` to add or remove future inventory without rewriting existing token history.
2. Reserve minting uses `mintPendingReservesFor(...)` plus the configured reserve frequency and reserve beneficiary settings instead of ad hoc treasury actions.
3. The store keeps historical tier state coherent so existing token IDs continue to resolve correctly even after future inventory changes.
4. Downstream products such as Croptop, Banny, and Revnets can continue assuming stable tier semantics.

**Failure cases that matter:** removing tiers that downstream products still expect, reserve beneficiary mistakes, and large multi-tier adjustments that are valid but operationally easy to mis-handle.

## Journey 5: Use Manual Minting Or Pay Credits Deliberately

**Starting state:** the project needs to issue tiers outside the default "payer picks tiers during payment" path.

**Success:** operators or integrators use the hook's alternate issuance surfaces without confusing them with normal public sale behavior.

**Flow**
1. Use `mintFor(...)` when an authorized actor needs to issue specific tiers directly to a beneficiary.
2. Use the hook's pay-credit behavior only when the project intentionally wants partially paid or previously earned value to count toward future tier minting.
3. Keep public sale assumptions, operator mint assumptions, and credit-based mint assumptions distinct in docs and product UX.

## Journey 6: Queue New Rulesets Without Reinitializing The Collection

**Starting state:** the project already uses the hook and future rulesets need different hook behavior.

**Success:** the project changes future minting, transfer, reserve, or cash-out participation through ruleset updates instead of redeploying the collection.

**Flow**
1. Queue future rulesets through the project or use `JB721TiersHookProjectDeployer.queueRulesetsOf(...)` when the packaged deployer path is the right control surface.
2. Update the hook-related metadata and flags that should apply only once the next ruleset starts.
3. Let the existing collection keep its identity and past mint history while future behavior changes on schedule.

## Journey 7: Let Holders Cash Out Tier Positions

**Starting state:** a holder owns one or more NFTs from a hook-enabled project and the active ruleset allows surplus-backed exits.

**Success:** the holder burns the intended tier exposure and receives the correct reclaim value through the core terminal.

**Flow**
1. The holder calls the project's cash-out path on the terminal.
2. The hook participates in the cash-out calculation so tier-specific weight and store state are reflected correctly.
3. The terminal settles reclaim value and the NFT position is burned or otherwise marked as consumed by the exit path.

**Edge conditions that change user experience:** ERC-20 cash-out surfaces, tier splits, reserve accounting drift, broken downstream terminals, and projects that use the hook for metadata only versus economically binding flows.

## Journey 8: Compose A Custom Product On Top Of The Standard Hook

**Starting state:** the team wants product-specific rendering or business rules but does not want to fork tier issuance.

**Success:** the product resolver or wrapper composes with the hook instead of reimplementing pricing, tier accounting, and treasury logic.

**Flow**
1. Plug a custom resolver into the hook for metadata and product-specific presentation.
2. Keep collection-specific behavior in the downstream repo while leaving pay, reserve, and cash-out semantics in this repo.
3. Audit hook-store interactions here first, then audit the downstream resolver or wrapper.

## Hand-Offs

- Use [nana-core-v6](../nana-core-v6/USER_JOURNEYS.md) for the treasury, ruleset, and permission surfaces the hook plugs into.
- Use [banny-retail-v6](../banny-retail-v6/USER_JOURNEYS.md), [croptop-core-v6](../croptop-core-v6/USER_JOURNEYS.md), and [revnet-core-v6](../revnet-core-v6/USER_JOURNEYS.md) for product layers built on this hook.
