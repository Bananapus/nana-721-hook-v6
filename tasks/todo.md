# Held fallbacks: no try/catch branch may redirect value

- [x] Refactor first: extract the leftover routing block of `_distributeSingleSplit` into `_routeLeftover`
      (behavior-preserving), so a single-split retry can reuse it.
- [x] JB721TiersHookLib: a tier split whose recipient reverts (hook, terminal, or beneficiary transfer) has its
      amount held in the hook under `keccak256(abi.encode(token, groupId, decimals, split))` instead of being routed
      to the project's own balance. `processHeldPayout` retries by running the same code and reverting if the amount
      was re-held.
- [x] JB721TiersHook: `heldPayoutOf` ledger and `processHeldPayoutOf(token, tierId, decimals, split)`.
- [x] Size: ships after Glamsterdam, where EIP-7954 raises the code limit to 65,536 bytes. `JB721TiersHook` is
      24,783 bytes, about 207 over today's 24,576 (main has 204 of margin), fine post-fork. The `--sizes` CI step
      stays red until Foundry targets the fork. Do not merge before the fork.
- [ ] Tests: out of scope for this PR.
