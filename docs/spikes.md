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
**How to test:** `./scripts/flipper-check.sh` with the Flipper plugged in. It finds the port,
installs the app, and writes a request over the CLI while the app holds the foreground. One
command, and it names its own failure.
**Fallbacks if it fails:** (a) app polls instead of blocking in the dialog; (b) speak the RPC
protobuf protocol instead of the text CLI; (c) C app owning USB CDC.
**Answer:** _not yet run_

---

## 2. Does one hard-coded model turn reliably produce a `propose_send` tool call? — <owner B>, TODO hour 1
**Why it matters:** the agent loop is ours now, so its failure modes are ours. A model that
argues instead of calling the tool is a broken demo with nobody to blame.
**How to test:** the harness is written — `apps/web/src/server/agent/spike.ts`. Needs an
`OPENAI_API_KEY` in `apps/web/.env` (not in `.env.example` yet — add it), then:

```bash
pnpm --filter @tappy/web spike:agent                        # 4 scenarios x 3 runs, effort=low
pnpm --filter @tappy/web spike:agent -- --effort high       # same, for the latency comparison
pnpm --filter @tappy/web spike:agent -- --only injection --repeat 5
```

Scenarios are `clear`, `vague`, `units` and `injection`. Arguments are `JSON.parse`d and then
validated with zod, never string-matched.
**Known before running:** GPT-5.6 rejects function tools on `/v1/chat/completions` while reasoning
is on, so the spike uses `/v1/responses`. `reasoning.effort` defaults to `medium`; the spike
defaults to `low`.
**Also record:** turn latency at low vs medium effort, behaviour on a vague request, and whether
`injection` gets the model to propose the drain — if it declines, the attack scene (SPEC §9, 1:50)
needs the scripted replay button, and that is a build item, not a retake.
**Answer:** _not yet run — script committed, waiting on an API key_

---

## 3. Where does the approval channel live, given Vercel can't hold a WebSocket? — B, 2026-09-04
**Options:** (a) bridge polls a `pending_approval` row and POSTs the result to tRPC; (b) run the
channel as a local Node process during the demo; (c) Supabase Realtime.
**Answer:** (a). There is no WebSocket. The `web_proposal` row *is* the channel.

**Evidence:** `apps/web/src/server/api/routers/approvals.ts` and the two tables in
`src/server/db/schema.ts`. Four procedures, and the bridge only needs three of them:

| The bridge calls | Carries | Replaces the socket message |
|---|---|---|
| `approvals.hello` | `{ address, kind }` | `signer.hello` |
| `approvals.next` | `{ address }`, poll every 500 ms | `approval.request` |
| `approvals.submit` | `{ decision }` | `approval.result` |

`@tappy/protocol` did not change. The payloads are the same ones SPEC §3.4 defined for the
socket, so this was not a `protocol:` PR and workstream C is not blocked.

**Consequence 1 — nobody waits.** This is the part that is not obvious from the options list.
`propose_*` writes a `PENDING_HUMAN` row and returns immediately, and `approvals.submit` moves it
to `SUBMITTED`. No request is open while the human thinks, which is the only reason this works on
serverless at all. `HumanSigner.requestApproval` returning a `Promise<Decision>` still fits
`MockHumanSigner`, which runs in-process, but the external path never calls it. The relayer picks
the decision up from the row on its next tick.

**Consequence 2 — expiry needs a tick.** Only one proposal may be `PENDING_HUMAN` at a time or the
nonces collide, and a partial unique index enforces it. So a proposal nobody answers blocks every
later one. `approvals.expireStale` exists for the relayer to call; if the relayer is not running,
nothing expires on its own.

**Consequence 3 — polling is the heartbeat.** `approvals.next` bumps `lastSeenAt`, and a signer
counts as connected for 2 s after its last poll. A bridge that dies goes stale by itself. There is
no disconnect message to miss.

**Consequence 4 — the channel needs its own auth.** A socket the bridge dials into is at least a
connection we accept once. Four HTTP endpoints on a public Vercel URL are reachable by anyone who
finds them. So the bridge sends `x-tappy-bridge-token`, and the channel refuses everything while
`BRIDGE_TOKEN` is unset. `approvals.submit` also recovers `humanSig` against `HUMAN_ADDRESS`,
because a token in a laptop `.env` is a weaker secret than a signature. Without that check a leaked
token moves a proposal out of `PENDING_HUMAN` and the real press has nowhere to land. This is not
in tension with DECISIONS #10: that rule is about the agent's tools, not the device's API.

**Cost:** up to 500 ms before the Flipper buzzes, plus one relayer tick after the press. Against a
human reaching for a button and 12 to 30 s of Sepolia inclusion, nobody will see it.

**Verified against real Postgres** (Supabase, 2026-09-04). `pnpm --filter @tappy/web verify:channel`
drives announce, poll, sign, submit and then tries what the channel should refuse. 11 checks pass.
Running it found two bugs typecheck could not: `jsonb` columns go through `JSON.stringify`, which
throws on the `bigint` inside `Action`, so the column stores the zod *input* shape with amounts as
strings; and a raw ``sql`col > ${date}` `` template hands postgres-js a bare `Date` with no type to
bind, so both comparisons use `gt()` now.

**Still needed:** `BRIDGE_TOKEN` and `HUMAN_ADDRESS` are not in `.env.example`, and the channel
stays shut until both are set.

---

## 4. Arc testnet chain id, RPC, faucet and explorer — <owner A>, TODO day 1
**Why it matters:** `packages/protocol/src/chains.ts` ships with `chainId: 0` and `chainByKey`
throws on it, deliberately, so nobody deploys against a guess.
**Answer:** _not yet looked up_

---

## 5. Is the EIP-7951 P256VERIFY precompile live on Sepolia? — Claude (Ryan Zander), 2026-09-09,
corrected same day after code review
**Why it matters:** the human key is a Secure Enclave P-256 key. If the chain cannot verify a
P-256 signature natively, TappyGate must staticcall a Solidity verifier instead (~330k gas).
**Answer:** LIVE at `0x0000000000000000000000000000000000000100`. Sepolia (chain id 11155111)
returns `0x000...0001` for a valid signature as of 2026-09-09. An earlier run of this spike
reported ABSENT; that was a false negative in the probe, not the chain — see "what went wrong"
below. Fusaka's published scope was correct all along.
**Evidence:** `pnpm --filter @tappy/contracts exec tsx script/checkP256.ts` against two
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
