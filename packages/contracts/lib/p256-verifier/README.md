# p256-verifier (vendored)

Vendored from [daimo-eth/p256-verifier](https://github.com/daimo-eth/p256-verifier) at commit
`607d3ec8377a3f59d65eca60d87dee8485d2ebcc`. Only `src/P256Verifier.sol` is kept — it has no imports, and the rest of
that repo (WebAuthn, a website, test vectors, audit PDFs) is weight we do not use.

Checked in as plain files rather than a git submodule, for the same reason `lib/forge-std` is:
`git clone && pnpm install && pnpm contracts:test` has to work without a submodule init step.

## Why it is here

`FlippyGate` verifies the iPhone's P-256 signature by staticcall to `p256Verifier`, a
constructor argument. On chains with EIP-7951 that is the precompile at `0x100`; on chains
without it, this contract is deployed and passed instead. Identical 160-byte input either way,
so the gate never branches on which one it got. Tests use this contract so they do not depend on
the local Foundry build supporting the precompile.

## The one local edit

The pragma was widened from `0.8.21` to `^0.8.21`. Nothing else was touched; diff against
upstream to confirm. The versions in between change codegen (0.8.22 loop increments, 0.8.24
MCOPY) but not semantics, and upstream's exact pin exists to make deployed bytecode
reproducible, which is not a property we rely on.
