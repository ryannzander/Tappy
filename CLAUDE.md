# Tappy — working notes for Claude

A 2-of-2 agent wallet. You ask an AI to move money; it can only ever *propose*. The second
signature comes from a key sealed in an iPhone's Secure Enclave, released by your face, and the
contract checks both on-chain. Either key alone moves nothing. ETHOnline 2026, testnet only.

Read `docs/superpowers/specs/2026-09-08-ios-approval-device-design.md` first — it supersedes
`docs/SPEC.md`, which describes the earlier Flipper-only design. `docs/DECISIONS.md` is the
settled list; do not reopen those without being asked.

## Layout

- `ios/` — **Tappy**, the iPhone app. `TappyKit` holds everything testable without a phone
  (keccak256, the EIP-712 digest, the Secure Enclave key, the hub client); the app target is
  SwiftUI. `xcodegen generate` writes the `.xcodeproj`, which is not committed.
- `apps/hub` — Next.js 15, API routes only, no pages and no database. Agent loop, proposal
  store, relayer, and the surfaces the phone and the bridge talk to. Runs on **port 3100**.
- `apps/bridge` — Node process on the laptop with the Flipper. USB serial, holds the human key in v1.
- `packages/protocol` — shared types, the EIP-712 digest, `HumanSigner`, `MockHumanSigner`.
- `packages/contracts` — Foundry. `TappyGate` is the 2-of-2 gate.
- `device/tappy-js` — the Flipper app, written in mJS.

## Rules specific to this repo

- **Never edit `packages/protocol/vectors/execute.json` or `vectors/p256.json`.** They are the
  frozen proof that Solidity, TypeScript and Swift produce the same digest and the same P-256
  message. `execute.json` is asserted by `test/Digest.t.sol` and `digest.test.ts`; `p256.json` by
  `test/TappyGateP256.t.sol`, `p256.test.ts` and `TappyKitTests`. If either changes, every
  signature breaks and the symptom is an unhelpful "bad signature".
- **Never copy an ABI or a shared type.** Import from `@tappy/contracts` / `@tappy/protocol`.
- **Anything reaching the chain or the device goes through `HumanSigner`.** That interface is why
  two thirds of the team can work without hardware. Do not add a code path that bypasses it.
- **Proposal status changes go through the state machine** (`ALLOWED_TRANSITIONS` in protocol).
  An illegal transition should throw, not warn.
- The Flipper JS engine has **no crypto, no bigint, no USB, no exceptions, and no closures**. It
  is mJS, not JavaScript. Do not suggest signing there.
- **The Secure Enclave signs `sha256(digest)`, never the digest.** CryptoKit hashes its input
  and offers no way to opt out, so `TappyGate` verifies `sha256(digest)` and every off-chain
  check must too. Getting this wrong produces `BadHumanSig` and no other information.
- **`@noble/curves` v2 defaults to `prehash: true`.** Leaving it on double-hashes an already
  hashed digest, producing a signature that verifies locally and is rejected on-chain — a
  self-consistent bug that passes its own self-check. Pass `prehash: false` everywhere.
- **Next's dev server gives each route handler its own module instance.** Anything held in a
  module-level variable is not shared between routes; the hub's store is a JSON file for that
  reason. Do not "simplify" it back into a Map.
- The hub reads the **repo-root `.env`** as well as its own, because that is where the
  contracts scripts and the bridge already look.

## Commands

```bash
pnpm install
pnpm contracts:test                   # forge test, 23 tests incl. both frozen vectors
pnpm --filter @tappy/protocol test    # vitest, 19 tests
pnpm typecheck
pnpm --filter @tappy/hub exec next dev -p 3100    # the hub

cd ios && xcodegen generate && open Tappy.xcodeproj   # the iPhone app
cd ios/TappyKit && swift run tappy-verify             # crypto vs the frozen vectors, no Xcode needed
```

If `forge` is not found, Foundry is at `~/.foundry/bin` or `~/.config/.foundry/bin` (when
`XDG_CONFIG_HOME` is set). `./scripts/setup.sh` locates it; do not hardcode either path.

## Style

- Comments explain *why*, not *what*. The existing code is the reference for density.
- Errors should be loud. A missing signer, a mismatched digest or an illegal state transition
  should stop the process, not degrade quietly — a silent failure on stage is unrecoverable.
- Testnet keys are checked in on purpose. Do not treat them as secrets, and do not add real ones.

## The agent model

The chat agent runs on **OpenAI**, not Anthropic — `apps/hub/src/server/agent/loop.ts` uses the
`openai` SDK. Model id comes from `OPENAI_MODEL` (default `gpt-5`) so it can be changed without a
code edit. Do not reintroduce `@anthropic-ai/sdk` here; see `docs/DECISIONS.md` #20.
