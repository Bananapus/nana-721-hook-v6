# Held fallbacks: no try/catch branch may redirect value

- [x] Refactor first: extract the leftover routing block of `_distributeSingleSplit` into `_routeLeftover`
      (behavior-preserving), so a single-split retry can reuse it.
- [x] JB721TiersHookLib: a tier split whose recipient reverts (hook, terminal, or beneficiary transfer) has its
      amount held in the hook under `keccak256(abi.encode(token, groupId, decimals, split))` instead of being routed
      to the project's own balance. `processHeldPayout` retries by running the same code and reverting if the amount
      was re-held.
- [x] JB721TiersHook: `heldPayoutOf` ledger and `processHeldPayoutOf(token, tierId, decimals, split)`.
- [ ] Size: `JB721TiersHook` is 24,783 bytes, about 207 over EIP-170 (main has 204 bytes of margin). The retry
      wrapper costs about 400 bytes, most of it ABI validation of the `JBSplit` calldata struct on the way into the
      library. Options before landing: take the split as opaque `bytes` and decode in the library, or move another
      chunk of the hook into `JB721TiersHookLib`.
- [ ] Tests: out of scope for this PR.
