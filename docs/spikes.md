# Spike log

One entry per unknown. Date it, answer it, and move on. An unrecorded spike gets re-run by
someone else on day three.

Template:

```
## <n>. <question>  — <owner>, <date>
**Answer:** …
**Evidence:** command run / file / screenshot
**Consequence:** what we do differently now
```

---

## 0. Can a Flipper Zero produce a valid secp256k1 signature? — resolved 2026-09-04, before build
**Answer:** Yes, but only from a C app, at roughly 110–250 ms per signature at 64 MHz.
**Evidence:**
- The JS engine (mJS) has no crypto, no bigint, and no USB access. Its modules are
  `flipper, event_loop, gui, notification, badusb, serial, gpio, math, storage`. `serial` is
  GPIO UART only (`usart`/`lpuart`), so JS cannot reach the USB port at all.
- FlipBIP (`github.com/xtruan/FlipBIP`) runs trezor-crypto's secp256k1 + keccak256 on this
  hardware today via `fap_private_libs`. It derives addresses; it does not sign.
- The firmware's mbedtls has `SECP256K1` disabled and its ECDSA symbols are not linkable from an
  app, so an app must bundle its own curve code.
- micro-ecc measured on Cortex-M4 at 180 MHz: 39.8 ms per secp256k1 sign; scaled to the WB55's
  64 MHz that is ~110–120 ms, and a second published measurement scales to ~250 ms.
- The STM32WB55 **does** have a PKA that natively supports secp256k1 ECDSA (RM0434 Table 150,
  ~82 ms). The SDK exports the LL header, but no Flipper app has used it. Stretch of the stretch.
**Consequence:** v1 uses the JS app as a physical approval button with the human key on the
laptop. On-device signing is M6 and cut line #1. The pitch says "nothing executes without a
physical press" — it only says "the key never leaves the device" if M6 lands. See SPEC §1.

---

## 1. Do Flipper CLI `storage` commands work while a JS app is in the foreground? — <owner C>, TODO hour 1
**Why it matters:** the whole bridge↔device channel depends on it. If it fails there is no other
route from the JS engine to the laptop.
**How to test:** see `docs/workstreams/device.md` → "Hour 0–1 Spike 1". Five steps, no code.
**Fallbacks if it fails:** (a) app polls instead of blocking in the dialog; (b) speak the RPC
protobuf protocol instead of the text CLI; (c) C app owning USB CDC.
**Answer:** _not yet run_

---

## 2. Does one hard-coded Claude turn reliably produce a `propose_send` tool call? — <owner B>, TODO hour 1
**Why it matters:** the agent loop is ours now, so its failure modes are ours. A model that
argues instead of calling the tool is a broken demo with nobody to blame.
**How to test:** one script, one message, one tool definition, print the parsed input. Read the
`claude-api` skill first — model ids and thinking parameters have changed.
**Also record:** turn latency, behaviour on a vague request, behaviour on the injected message.
**Answer:** _not yet run_

---

## 3. Where does the approval channel live, given Vercel can't hold a WebSocket? — <owner B>, TODO hour 2
**Options:** (a) bridge polls a `pending_approval` row and POSTs the result to tRPC; (b) run the
channel as a local Node process during the demo; (c) Supabase Realtime.
**Recommended:** (a). Boring, works on Vercel, ~1 s latency is invisible next to a human pressing
a button. The `HumanSigner` interface is unchanged either way.
**Answer:** _not yet decided_

---

## 4. Arc testnet chain id, RPC, faucet and explorer — <owner A>, TODO day 1
**Why it matters:** `packages/protocol/src/chains.ts` ships with `chainId: 0` and `chainByKey`
throws on it, deliberately, so nobody deploys against a guess.
**Answer:** _not yet looked up_

---

## 5. Is the EIP-7951 P256VERIFY precompile live on Sepolia? — Claude (Ryan Zander), 2026-09-09,
corrected same day after code review
**Why it matters:** the human key is a Secure Enclave P-256 key. If the chain cannot verify a
P-256 signature natively, FlippyGate must staticcall a Solidity verifier instead (~330k gas).
**Answer:** LIVE at `0x0000000000000000000000000000000000000100`. Sepolia (chain id 11155111)
returns `0x000...0001` for a valid signature as of 2026-09-09. An earlier run of this spike
reported ABSENT; that was a false negative in the probe, not the chain — see "what went wrong"
below. Fusaka's published scope was correct all along.
**Evidence:** `pnpm --filter @flippy/contracts exec tsx script/checkP256.ts` against two
independent Sepolia RPCs, both now printing `PRECOMPILE LIVE`:
- `https://ethereum-sepolia-rpc.publicnode.com` → `chain 11155111`,
  `returned 0x0000000000000000000000000000000000000000000000000000000000000001`.
- `https://1rpc.io/sepolia` → same chain id, same non-empty result.
(`https://rpc.sepolia.org` is dead — 404 on every request — not usable evidence either way; the
script throws loudly on it instead of masking the failure.)
**What went wrong the first time:** the script's local self-check (`p256.verify(sig, message,
pub)`) passed even though the on-chain signature was invalid, because `@noble/curves` v2's
`sign()`/`verify()` default to `{ prehash: true }` — they hash the `message` argument themselves
before signing/verifying. `message` here was already a digest (hashed by hand with
`@noble/hashes/sha2.js`'s `sha256`), so with defaults left on, `sign()` silently signed
`sha256(message)` while the on-chain input carried the literal `message` as EIP-7951's `h` field
(the precompile does no hashing of its own — see EIP-7951 "ABI for P256VERIFY Operation"). Local
`verify()` made the identical mistake, so it agreed with `sign()` while disagreeing with the
chain — a self-consistent bug that looked like a passing self-check. Fix: pass
`{ prehash: false }` explicitly to both `p256.sign()` and `p256.verify()` so `message` is treated
as the literal digest. Confirmed independently before accepting the corrected result:
1. `eth_estimateGas` on `0x100` with 160 zero bytes costs `0x70d7` (28887) vs `0x5998` (22936) for
   a genuinely code-free address and `0x6194` (24980) for ecrecover (`0x01`) — real precompile
   dispatch logic runs at `0x100`, it isn't a bare account.
2. Verified the `eth_call` plumbing itself against the well-known ecrecover precompile with a
   real secp256k1 signature and a known private-key-to-address vector (privkey `1` →
   `0x7e5f...95bdf`, matches the well-known value) before trusting the P-256 result.
3. With `{ prehash: false }` on both sides, `p256.verify()` still returns `true` locally, and the
   *same* 160-byte input that previously came back empty now returns
   `0x000...0001` on-chain — the fix closes the gap between local and on-chain verification, not
   just a coincidence.
`@noble/curves` p256 import path used: `@noble/curves/nist.js` (curves 2.4.0; v2's export map
requires the `.js` suffix). `@noble/hashes` sha256 path: `@noble/hashes/sha2.js` (hashes 2.4.0,
same reason). Two API-shape changes for Task 3 to carry forward:
- `p256.sign()` returns a raw 64-byte compact `r || s` `Uint8Array` by default, not a `{r, s}`
  bigint object as in v1 — slice bytes directly instead of calling `.toString(16)` on `.r`/`.s`.
- `sign()`/`verify()` default to `{ prehash: true }` in v2. Always pass `{ prehash: false }`
  explicitly when `message` is already a digest you hashed yourself — otherwise it gets hashed
  again silently, with no error, no warning, and a signature that still locally self-verifies.
**Consequence:** deploy with `P256_VERIFIER=0x0000000000000000000000000000000000000100`. Task 6's
deploy inputs use the precompile address directly; no fallback Solidity verifier is needed. Spec
§4.3's fallback-verifier path is available but unnecessary for Sepolia as of this measurement —
re-run this script if Sepolia is later reset or if targeting a different network.
