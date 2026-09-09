# Foundation: a 2-of-2 gate that accepts a Secure Enclave signature — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reshape the repo for a mobile-only product and extend `FlippyGate` so that a P-256
signature — the only kind an iPhone Secure Enclave can produce — satisfies the human half of the
2-of-2, verified on-chain and deployed to Sepolia.

**Architecture:** `FlippyGate` keeps its existing secp256k1 path for the Flipper and gains a
second one that dispatches on signature length: 65 bytes → `ECDSA.recover`, 64 bytes → a
staticcall to a P-256 verifier (the EIP-7951 precompile at `0x100`, or a deployed Solidity
verifier on chains that lack it). The EIP-712 digest is unchanged, so the existing frozen vector
and all existing digest tests keep passing. A second frozen vector pins the P-256 path across
Solidity, TypeScript and — in the next plan — Swift.

**Tech Stack:** Foundry (Solidity 0.8.24), TypeScript + vitest + viem, `@noble/curves` for P-256,
pnpm workspaces + Turborepo, Next.js 15 (API only).

**Spec:** `docs/superpowers/specs/2026-09-08-ios-approval-device-design.md`

## Global Constraints

- **Never edit `packages/protocol/vectors/execute.json`.** It is frozen. `vectors/p256.json`
  becomes equally frozen once Task 3 lands.
- **Never copy an ABI or a shared type between packages.** Import from `@flippy/contracts` /
  `@flippy/protocol`.
- **Errors are loud.** A missing signer, a mismatched digest, or an illegal state transition
  throws; it never warns and continues.
- Proposal status changes go through `ALLOWED_TRANSITIONS` in `packages/protocol/src/types.ts`.
- Solidity 0.8.24, `optimizer_runs = 200` (already set in `packages/contracts/foundry.toml`).
- Node >= 22, pnpm 11.25.0.
- The EIP-712 type string is fixed and must not change:
  `Execute(uint256 nonce,address to,uint256 value,bytes data,uint256 deadline)`
  with domain `{ name: "FlippyGate", version: "1", chainId, verifyingContract: gate }`.
- The Secure Enclave signs `SHA-256(digest)`, never `digest`. Any code that forgets the SHA-256
  layer produces `BadHumanSig` with no other diagnostic.
- If `forge` is not found it is at `~/.foundry/bin` or `~/.config/.foundry/bin`. Use
  `./scripts/setup.sh` to locate it; never hardcode either path.
- Branch names are `b/<thing>`. Commit at least once per task.

---

### Task 1: Reshape the repo for a mobile-only product

Renames `apps/web` to `apps/hub` and deletes every page, component and stylesheet. What remains is
a Next.js app that serves route handlers and nothing else. No behaviour changes; this is the
structural move that stops the directory name from lying.

**Files:**
- Rename: `apps/web/` → `apps/hub/`
- Modify: `apps/hub/package.json` (name field)
- Delete: `apps/hub/src/app/page.tsx`, `apps/hub/src/app/layout.tsx`,
  `apps/hub/src/app/_components/`, `apps/hub/src/trpc/`,
  `apps/hub/src/styles/`, `apps/hub/postcss.config.js`
- Modify: `apps/hub/package.json` (drop React/Tailwind/UI dependencies)
- Modify: `docs/HANDOFF.md`, `README.md` (paths)

**Interfaces:**
- Consumes: nothing.
- Produces: the package name `@flippy/hub`, importable by nothing (it is an app), and the
  directory `apps/hub/src/app/api/` where every later task adds route handlers.

- [ ] **Step 1: Move the directory with git so history follows**

```bash
git mv apps/web apps/hub
```

- [ ] **Step 2: Rename the package**

In `apps/hub/package.json`, change:

```json
"name": "@flippy/web",
```

to:

```json
"name": "@flippy/hub",
```

- [ ] **Step 3: Delete the UI**

```bash
rm -rf apps/hub/src/app/page.tsx \
       apps/hub/src/app/layout.tsx \
       apps/hub/src/app/_components \
       apps/hub/src/trpc \
       apps/hub/src/styles \
       apps/hub/postcss.config.js
```

The whole `src/trpc/` directory goes, not just the React file: `server.ts` imports
`createHydrationHelpers` from `@trpc/react-query/rsc`, `cache` from `react`, and
`./query-client`, so it cannot survive the dependency removal in Step 4. It exists only to call
tRPC from React Server Components, and there are none.

`src/app/api/trpc/[trpc]/route.ts` stays and is unaffected — it imports only from `~/server/api/*`
and `~/env`, never from `src/trpc/`. `src/server/**` and `src/env.js` stay. Next.js 15 is happy
serving only route handlers with no `layout.tsx` and no `page.tsx`.

- [ ] **Step 4: Drop the UI dependencies**

In `apps/hub/package.json`, remove these entries from `dependencies`:

```
"@tanstack/react-query", "@trpc/react-query", "react", "react-dom"
```

and these from `devDependencies`:

```
"@tailwindcss/postcss", "@types/react", "@types/react-dom", "postcss",
"prettier-plugin-tailwindcss", "tailwindcss"
```

Keep `@trpc/client` and `@trpc/server` — the bridge speaks tRPC over HTTP.

- [ ] **Step 5: Reinstall and typecheck**

Run: `pnpm install && pnpm typecheck`
Expected: PASS. Any remaining failure will name a file that imports `react` or
`@tanstack/react-query`; that file is UI and should be deleted too.

- [ ] **Step 6: Update the two docs that name the old path**

In `README.md` and `docs/HANDOFF.md`, replace every `apps/web` with `apps/hub`, and change the
description from "Chat UI, agent loop, wallet panel, mock shop, relayer" to
"API only: agent loop, proposal store, relayer, the iOS and bridge surfaces".

Run: `grep -rn "apps/web" --include=*.md --include=*.json --include=*.ts . | grep -v node_modules`
Expected: no output.

- [ ] **Step 7: Record the decisions this pivot changes**

`docs/DECISIONS.md` is the log the team argues from, and six of its entries are now wrong. Append
these rows to its table, dated today. Copy them verbatim from spec §10:

| # | Decision | Why | Date |
|---|---|---|---|
| 11 | The iPhone is the primary approval device; the Flipper is the second | The Secure Enclave gives custody the Flipper's JS app could not, and the phone is a screen and a CPU we already trust. | 2026-09-08 |
| 12 | The human key is P-256 in the Secure Enclave, verified on-chain by EIP-7951 | Makes "the key cannot leave the device" literally true and provable on-chain. Was impossible when #1 was written. | 2026-09-08 |
| 13 | Reverses #8 — "what you see is what you sign" ships in v1 | Infeasible on the Flipper, a day's work on the iPhone. The phone recomputes the digest and will not sign a mismatch. | 2026-09-08 |
| 14 | Narrows #9 — T3 stays, as an API with no pages, renamed `apps/hub` | The client is the iOS app. A web UI is out of scope. | 2026-09-08 |
| 15 | No sessions, no spending limits, no autonomous trading | The product is a chat bot that proposes one transaction at a time and a human who approves each one. | 2026-09-08 |
| 16 | The mock shop and `propose_buy` are dropped | They needed a web surface. `send` and `swap` carry the demo, including the attack scene. | 2026-09-08 |

Then add a line under the table: `Superseded by these: #1 (partly), #8, #9. Still binding: #2, #3,
#4, #5, #6, #10.`

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: apps/web becomes apps/hub, an API with no pages

The client is the iOS app. Nothing rendered a page here except the T3 scaffold."
```

---

### Task 2: Spike H1 — confirm the P-256 precompile is live on Sepolia

Everything in this plan assumes EIP-7951 shipped in Fusaka and is live on Sepolia. That is
inferred from the fork's published scope, not measured. Ten minutes now saves a day of debugging a
contract that cannot work. This task writes no production code — it produces an answer and a
recorded decision.

**Files:**
- Create: `packages/contracts/script/checkP256.ts`
- Modify: `docs/spikes.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the recorded value of `P256_VERIFIER` for Sepolia — either `0x0000000000000000000000000000000000000100`
  or the address of a deployed fallback verifier. Task 6 reads this decision.

- [ ] **Step 1: Write the probe script**

Create `packages/contracts/script/checkP256.ts`:

```ts
/**
 * Spike H1: is the EIP-7951 P256VERIFY precompile live on this RPC?
 * A known-good vector must return 32 bytes of 1. Anything else means the
 * fallback verifier is required (see spec §4.3).
 *
 * Run: pnpm --filter @flippy/contracts exec tsx script/checkP256.ts
 */
import { createPublicClient, http, concatHex, type Hex } from "viem";
import { p256 } from "@noble/curves/p256";
import { sha256 } from "@noble/hashes/sha256";
import { bytesToHex, hexToBytes } from "viem";

const RPC = process.env.SEPOLIA_RPC_URL;
if (!RPC) throw new Error("SEPOLIA_RPC_URL is not set");

const PRECOMPILE = "0x0000000000000000000000000000000000000100" as const;

function pad32(v: bigint): Hex {
  return `0x${v.toString(16).padStart(64, "0")}`;
}

const priv = hexToBytes("0x0101010101010101010101010101010101010101010101010101010101010101");
const pub = p256.getPublicKey(priv, false); // 65 bytes: 0x04 || qx || qy
const qx = bytesToHex(pub.slice(1, 33));
const qy = bytesToHex(pub.slice(33, 65));

const message = sha256(new TextEncoder().encode("flippy p256 spike"));
const sig = p256.sign(message, priv);

const input = concatHex([bytesToHex(message), pad32(sig.r), pad32(sig.s), qx, qy]);
if (hexToBytes(input).length !== 160) throw new Error(`input is ${hexToBytes(input).length} bytes, want 160`);

const client = createPublicClient({ transport: http(RPC) });
const res = await client.call({ to: PRECOMPILE, data: input });

console.log("chain    ", await client.getChainId());
console.log("input    ", input);
console.log("returned ", res.data ?? "0x (empty)");
console.log(
  res.data === "0x0000000000000000000000000000000000000000000000000000000000000001"
    ? "PRECOMPILE LIVE — use address(0x100)"
    : "PRECOMPILE ABSENT — deploy the fallback verifier",
);
```

- [ ] **Step 2: Add the dependencies the script needs**

```bash
pnpm --filter @flippy/contracts add -D @noble/curves @noble/hashes tsx
```

If `@noble/curves/p256` fails to resolve, check the installed version's export map with
`cat node_modules/@noble/curves/package.json | grep -A2 '"./p256"'`. Version 2.x moved it to
`@noble/curves/nist` exporting the same `p256` object. Use whichever the installed version
provides and note it in the spike entry — later tasks import the same path.

- [ ] **Step 3: Run the probe against Sepolia**

```bash
export SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
pnpm --filter @flippy/contracts exec tsx script/checkP256.ts
```

Expected: `PRECOMPILE LIVE — use address(0x100)`.

If it prints `PRECOMPILE ABSENT`, that is not a failure of this task — it is the answer. Record it
and Task 5 still works unchanged, because the verifier is a constructor argument. Only Task 6's
deploy inputs change.

- [ ] **Step 4: Record the answer in the spike log**

Append to `docs/spikes.md`:

```markdown
## 5. Is the EIP-7951 P256VERIFY precompile live on Sepolia? — <owner>, <date>
**Why it matters:** the human key is a Secure Enclave P-256 key. If the chain cannot verify a
P-256 signature natively, FlippyGate must staticcall a Solidity verifier instead (~330k gas).
**Answer:** _fill in: LIVE at 0x…0100, or ABSENT_
**Evidence:** `pnpm --filter @flippy/contracts exec tsx script/checkP256.ts` against
<rpc url>, returned <bytes>. `@noble/curves` p256 import path used: <path>.
**Consequence:** deploy with `P256_VERIFIER=<address>`. See spec §4.3.
```

- [ ] **Step 5: Commit**

```bash
git add packages/contracts/script/checkP256.ts packages/contracts/package.json docs/spikes.md pnpm-lock.yaml
git commit -m "spike: confirm the EIP-7951 P256 precompile on Sepolia"
```

---

### Task 3: Freeze the P-256 test vector

Creates `vectors/p256.json`, the second frozen cross-language vector. It reuses the digest already
pinned by `execute.json`, so the two compose: the same transaction, signed by a Flipper in one
vector and by an Enclave-shaped P-256 key in the other. Solidity asserts it in Task 5; Swift
asserts it in the next plan.

**Files:**
- Create: `packages/protocol/scripts/genP256Vector.ts`
- Create: `packages/protocol/vectors/p256.json`
- Create: `packages/protocol/test/p256.test.ts`
- Modify: `packages/protocol/package.json`

**Interfaces:**
- Consumes: `digest` from `packages/protocol/vectors/execute.json`
  (`0xc56ce0a94d4eca26131f5503a69d659d1aea43e8bb835943e0a463719f6862ad`).
- Produces: `packages/protocol/vectors/p256.json` with the fields
  `digest`, `messageSha256`, `privateKey`, `qx`, `qy`, `r`, `s`, `signature64`,
  `highS`, `signature64HighS`. Task 5's Solidity test and the Swift test in the next plan both
  parse exactly these names.

- [ ] **Step 1: Write the failing test**

Create `packages/protocol/test/p256.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { p256 } from "@noble/curves/p256";
import { sha256 } from "@noble/hashes/sha256";
import { hexToBytes, bytesToHex } from "viem";
import execute from "../vectors/execute.json" with { type: "json" };

const v = JSON.parse(readFileSync(new URL("../vectors/p256.json", import.meta.url), "utf8"));

describe("p256 vector", () => {
  it("signs the same digest the execute vector pins", () => {
    expect(v.digest).toBe(execute.digest);
  });

  it("message is sha256 of the digest, which is what the Secure Enclave signs", () => {
    expect(bytesToHex(sha256(hexToBytes(v.digest)))).toBe(v.messageSha256);
  });

  it("public key is the one the private key produces", () => {
    const pub = p256.getPublicKey(hexToBytes(v.privateKey), false);
    expect(bytesToHex(pub.slice(1, 33))).toBe(v.qx);
    expect(bytesToHex(pub.slice(33, 65))).toBe(v.qy);
  });

  it("signature verifies", () => {
    const pub = p256.getPublicKey(hexToBytes(v.privateKey), false);
    expect(p256.verify(hexToBytes(v.signature64), hexToBytes(v.messageSha256), pub)).toBe(true);
  });

  it("signature64 is r concatenated with s, 64 bytes", () => {
    expect(hexToBytes(v.signature64).length).toBe(64);
    expect(v.signature64).toBe(`${v.r}${v.s.slice(2)}`);
  });

  it("the high-s twin has the same r and verifies with lowS disabled", () => {
    const pub = p256.getPublicKey(hexToBytes(v.privateKey), false);
    expect(v.signature64HighS.slice(0, 66)).toBe(v.r);
    expect(
      p256.verify(hexToBytes(v.signature64HighS), hexToBytes(v.messageSha256), pub, { lowS: false }),
    ).toBe(true);
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `pnpm --filter @flippy/protocol test`
Expected: FAIL — `ENOENT ... vectors/p256.json`.

- [ ] **Step 3: Add the dependencies**

```bash
pnpm --filter @flippy/protocol add -D @noble/curves @noble/hashes tsx
```

Use the same `@noble/curves` import path Task 2 recorded in the spike log.

- [ ] **Step 4: Write the generator**

Create `packages/protocol/scripts/genP256Vector.ts`:

```ts
/**
 * Generates the frozen P-256 vector. Run once. The output is committed and never
 * regenerated — regenerating it invalidates every P-256 signature in the system,
 * and the symptom is an unhelpful "bad signature".
 *
 * Run: pnpm --filter @flippy/protocol exec tsx scripts/genP256Vector.ts
 */
import { writeFileSync } from "node:fs";
import { p256 } from "@noble/curves/p256";
import { sha256 } from "@noble/hashes/sha256";
import { bytesToHex, hexToBytes, type Hex } from "viem";
import execute from "../vectors/execute.json" with { type: "json" };

/** Fixed, not random: the vector must be reproducible by anyone reading this file. */
const PRIVATE_KEY = "0x2b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfe" as const;

const digest = execute.digest as Hex;
const message = sha256(hexToBytes(digest));
const pub = p256.getPublicKey(hexToBytes(PRIVATE_KEY), false);

const sig = p256.sign(message, hexToBytes(PRIVATE_KEY)); // noble normalises to low-s
const r = `0x${sig.r.toString(16).padStart(64, "0")}` as Hex;
const s = `0x${sig.s.toString(16).padStart(64, "0")}` as Hex;

/** The curve order. s' = n - s is an equally valid signature; EIP-7951 accepts it. */
const N = p256.CURVE.n;
const sHigh = `0x${(N - sig.s).toString(16).padStart(64, "0")}` as Hex;

const out = {
  _comment:
    "Frozen cross-language P-256 vector. The Secure Enclave signs sha256(digest), so the " +
    "message here is sha256 of the digest pinned by execute.json. Solidity, TypeScript and " +
    "Swift must all reproduce it. Changing any field breaks every signature.",
  digest,
  messageSha256: bytesToHex(message),
  privateKey: PRIVATE_KEY,
  qx: bytesToHex(pub.slice(1, 33)),
  qy: bytesToHex(pub.slice(33, 65)),
  r,
  s,
  signature64: `${r}${s.slice(2)}`,
  highS: sHigh,
  signature64HighS: `${r}${sHigh.slice(2)}`,
};

writeFileSync(new URL("../vectors/p256.json", import.meta.url), JSON.stringify(out, null, 2) + "\n");
console.log("wrote vectors/p256.json");
```

- [ ] **Step 5: Generate the vector**

Run: `pnpm --filter @flippy/protocol exec tsx scripts/genP256Vector.ts`
Expected: `wrote vectors/p256.json`.

If `p256.CURVE.n` is undefined, the installed noble version exposes it as `p256.CURVE.n` on the
curve object or as `p256.Point.Fn.ORDER`. Print `Object.keys(p256.CURVE)` to find it. Do not
hardcode the order as a literal — a typo there produces a vector that silently fails to verify.

- [ ] **Step 6: Run the tests**

Run: `pnpm --filter @flippy/protocol test`
Expected: PASS — the original 8 digest tests plus 6 new ones.

- [ ] **Step 7: Write the vector's protection into the repo's rules**

In `CLAUDE.md`, extend the existing rule so it covers both files:

```markdown
- **Never edit `packages/protocol/vectors/execute.json` or `vectors/p256.json`.** They are the
  frozen proof that Solidity, TypeScript and Swift produce the same digest and the same P-256
  message. `execute.json` is asserted by `test/Digest.t.sol` and `digest.test.ts`; `p256.json` by
  `test/FlippyGateP256.t.sol`, `p256.test.ts` and `FlippyKitTests`. If either changes, every
  signature breaks and the symptom is an unhelpful "bad signature".
```

- [ ] **Step 8: Commit**

```bash
git add packages/protocol/vectors/p256.json packages/protocol/scripts/genP256Vector.ts \
        packages/protocol/test/p256.test.ts packages/protocol/package.json CLAUDE.md pnpm-lock.yaml
git commit -m "protocol: freeze the P-256 vector

The Secure Enclave signs sha256(digest), not digest. This vector pins that layer
across languages so nobody rediscovers it through a reverted transaction."
```

---

### Task 4: Protocol — drop `buy`, add the mobile schemas

The mock shop needed a web surface that no longer exists, so `buy` goes. In its place come the
three schemas the iOS app needs: the proposal shape it can verify, the device it registers, and
the NFC station it taps.

**Files:**
- Modify: `packages/protocol/src/types.ts`
- Modify: `packages/protocol/src/digest.ts:toView`
- Delete: `packages/contracts/src/MockMerchant.sol`, `packages/contracts/abi/MockMerchant.json`
- Modify: `packages/contracts/script/Deploy.s.sol`
- Modify: `packages/contracts/scripts/export-abi.mjs`
- Create: `packages/protocol/test/mobile.test.ts`

**Interfaces:**
- Consumes: `hexSchema`, `addressSchema`, `callSchema`, `actionSchema`, `proposalStatusSchema`
  from `packages/protocol/src/types.ts`.
- Produces: `mobileProposalSchema` / `MobileProposal`, `deviceSchema` / `Device`,
  `stationSchema` / `Station`, `humanKeyKindSchema` / `HumanKeyKind`, and
  `toMobileProposal(p: Proposal): MobileProposal`. The hub's `/api/m/*` handlers and the Swift
  `HubClient` both bind to these exact names.

- [ ] **Step 1: Write the failing test**

Create `packages/protocol/test/mobile.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { mobileProposalSchema, deviceSchema, stationSchema, toMobileProposal } from "../src/index.js";
import type { Proposal } from "../src/index.js";

const proposal: Proposal = {
  id: "0xc56ce0a94d4eca26131f5503a69d659d1aea43e8bb835943e0a463719f6862ad",
  chainId: 11155111,
  gate: "0x1111111111111111111111111111111111111111",
  nonce: 0n,
  call: { to: "0x2222222222222222222222222222222222222222", value: 10000000000000000n, data: "0x" },
  action: { kind: "send", to: "0x2222222222222222222222222222222222222222", valueWei: 10000000000000000n },
  deadline: 2000000000,
  status: "PENDING_HUMAN",
  createdAt: 1757280000,
  originator: "chat",
};

describe("mobile schemas", () => {
  it("carries every field the phone needs to recompute the digest", () => {
    const m = toMobileProposal(proposal);
    expect(mobileProposalSchema.parse(m)).toBeTruthy();
    for (const k of ["chainId", "gate", "nonce", "call", "deadline"]) {
      expect(m).toHaveProperty(k);
    }
  });

  it("never leaks the agent signature to the phone", () => {
    expect(toMobileProposal({ ...proposal, agentSig: "0xdead" })).not.toHaveProperty("agentSig");
  });

  it("accepts a P-256 enclave device", () => {
    expect(
      deviceSchema.parse({
        id: "dev_1",
        kind: "p256-enclave",
        publicKey: `0x${"ab".repeat(64)}`,
        label: "Ryan's iPhone",
        registeredAt: 1757280000,
      }),
    ).toBeTruthy();
  });

  it("rejects an unknown key kind", () => {
    expect(() =>
      deviceSchema.parse({
        id: "dev_1",
        kind: "rsa",
        publicKey: "0xab",
        label: "x",
        registeredAt: 1,
      }),
    ).toThrow();
  });

  it("accepts a station whose tag has not been pinned yet", () => {
    expect(stationSchema.parse({ stationId: "desk", label: "Desk puck" })).toBeTruthy();
  });
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `pnpm --filter @flippy/protocol test`
Expected: FAIL — `mobileProposalSchema` is not exported.

- [ ] **Step 3: Remove `buy` from the action union**

In `packages/protocol/src/types.ts`, delete the third member of `actionSchema` (the
`kind: "buy"` object) so the union is `send | swap` only. In the same file, change
`proposalViewSchema.action` from `z.enum(["SEND", "SWAP", "BUY"])` to `z.enum(["SEND", "SWAP"])`.

- [ ] **Step 4: Fix the view builder**

In `packages/protocol/src/digest.ts`, `toView` currently has a three-way conditional ending in the
`buy` branch. Replace the whole expression with:

```ts
  const [action, amount, counterparty] =
    a.kind === "send"
      ? (["SEND", amountLabel(a.valueWei, chain), shortHex(a.to)] as const)
      : (["SWAP", amountLabel(a.sellWei, chain), `DEX ${shortHex(a.dex)}`] as const);
```

- [ ] **Step 5: Add the mobile schemas**

Append to `packages/protocol/src/types.ts`:

```ts
/* ---- The iOS surface ------------------------------------------------------ */

export const humanKeyKindSchema = z.enum(["p256-enclave", "p256-software", "secp256k1"]);
export type HumanKeyKind = z.infer<typeof humanKeyKindSchema>;

/**
 * Everything the phone needs to independently verify a proposal and render it.
 * Deliberately carries the raw call: the phone recomputes the digest rather than
 * trusting the id the hub sent. Deliberately omits agentSig — the phone has no use
 * for it, and a signature it does not need is a signature it cannot leak.
 */
export const mobileProposalSchema = z.object({
  id: hexSchema,
  chainId: z.number(),
  gate: addressSchema,
  nonce: bigintish,
  call: callSchema,
  action: actionSchema,
  deadline: z.number(),
  status: proposalStatusSchema,
  txHash: hexSchema.optional(),
  error: z.string().optional(),
});
export type MobileProposal = z.infer<typeof mobileProposalSchema>;

/** A registered approval device. `publicKey` is 64 bytes qx‖qy for P-256, a 20-byte address for secp256k1. */
export const deviceSchema = z.object({
  id: z.string(),
  kind: humanKeyKindSchema,
  publicKey: hexSchema,
  label: z.string(),
  registeredAt: z.number(),
});
export type Device = z.infer<typeof deviceSchema>;

/** A physical NFC token the hub recognises. The tag is a trigger, not a secret. */
export const stationSchema = z.object({
  stationId: z.string(),
  label: z.string(),
  tagUid: hexSchema.optional(),
});
export type Station = z.infer<typeof stationSchema>;
```

- [ ] **Step 6: Add the projection**

Append to `packages/protocol/src/digest.ts`:

```ts
/** Projects a Proposal onto exactly what the phone is allowed to see. */
export function toMobileProposal(p: Proposal): MobileProposal {
  return {
    id: p.id,
    chainId: p.chainId,
    gate: p.gate,
    nonce: p.nonce,
    call: p.call,
    action: p.action,
    deadline: p.deadline,
    status: p.status,
    ...(p.txHash ? { txHash: p.txHash } : {}),
    ...(p.error ? { error: p.error } : {}),
  };
}
```

Add `MobileProposal` to the type import at the top of the file, and confirm
`packages/protocol/src/index.ts` re-exports `./types.js` and `./digest.js` with `export *` — if it
lists names individually, add the five new ones.

- [ ] **Step 7: Delete the merchant contract**

```bash
rm packages/contracts/src/MockMerchant.sol packages/contracts/abi/MockMerchant.json
```

In `packages/contracts/script/Deploy.s.sol`, remove the `MockMerchant` import, the
`MockMerchant merchant = new MockMerchant();` line, the `console2.log("merchant ", ...)` line, and
the `vm.serializeAddress(obj, "merchant", address(merchant));` line.

- [ ] **Step 8: Fix the ABI generator, which hardcodes the contract list and emits broken TypeScript**

`packages/contracts/scripts/export-abi.mjs` names `MockMerchant` in its `CONTRACTS` array, so the
next `pnpm contracts:build` would regenerate an import of a file you just deleted. Change:

```js
const CONTRACTS = ["FlippyGate", "MockToken", "MockSwap", "MockMerchant"];
```

to:

```js
const CONTRACTS = ["FlippyGate", "MockToken", "MockSwap"];
```

The generator also emits `export const abis = { FlippyGate, MockToken, MockSwap }` while importing
those ABIs as `FlippyGateAbi`, `MockTokenAbi`, `MockSwapAbi` — the object references identifiers
that do not exist. It has gone unnoticed because `@flippy/contracts` has no real `typecheck`
script (it echoes a message), and no app imports it yet. Task 6 is the first thing that does, so
fix it now. Change the `abis` line in the generated-template array from:

```js
  `export const abis = { ${CONTRACTS.join(", ")} } as const;`,
```

to:

```js
  `export const abis = { ${CONTRACTS.map((n) => `${n}: ${n}Abi`).join(", ")} } as const;`,
```

Also delete the stray `'import { readFileSync } from "node:fs";'` line from the `lines` array near
the top — `lines` is never used to write anything, and the import it injects is not in the output.

Then regenerate and confirm the output compiles:

```bash
pnpm contracts:build
npx tsc --noEmit --module esnext --moduleResolution bundler --target es2022   --resolveJsonModule packages/contracts/src-ts/index.ts
```

Expected: `exported 3 ABIs …` and no TypeScript errors.

- [ ] **Step 9: Run everything**

Run: `pnpm --filter @flippy/protocol test && pnpm contracts:test && pnpm typecheck`
Expected: PASS on all three. If `apps/bridge` fails to typecheck on the removed `buy` branch, fix
the switch there — a bridge that cannot render an action must throw, not fall through.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "protocol: drop buy, add the mobile schemas

The shop needed a web surface that no longer exists. In its place: the proposal
shape the phone can verify for itself, plus devices and NFC stations."
```

---

### Task 5: FlippyGate accepts a P-256 human signature

The core of this plan. `execute` dispatches on `humanSig.length`: 65 bytes is the Flipper,
64 bytes is the iPhone. Tests run against a deployed Solidity verifier so they pass on any
Foundry version, with a separate fork test for the real precompile.

**Files:**
- Modify: `packages/contracts/src/FlippyGate.sol`
- Create: `packages/contracts/test/FlippyGateP256.t.sol`
- Modify: `packages/contracts/test/FlippyGate.t.sol` (constructor calls)
- Modify: `packages/contracts/test/Digest.t.sol` (constructor calls)
- Modify: `packages/contracts/foundry.toml` (remapping)

**Interfaces:**
- Consumes: `packages/protocol/vectors/p256.json` fields from Task 3.
- Produces: the constructor
  `FlippyGate(address agent, address humanK1, bytes32 humanQx, bytes32 humanQy, address p256Verifier)`
  and public getters `humanK1()`, `humanQx()`, `humanQy()`, `p256Verifier()`. Task 6's deploy
  script and the hub's relayer bind to this exact signature. The errors `NoK1Human()`,
  `NoP256Human()`, `BadHumanSigLength()`, `NoHumanAuthority()` are new; `BadHumanSig()`,
  `BadAgentSig()`, `Expired()`, `CallFailed(bytes)`, `ZeroAddress()` are unchanged.

- [ ] **Step 1: Vendor a Solidity P-256 verifier**

```bash
cd packages/contracts && forge install daimo-eth/p256-verifier --no-commit
```

Add to `remappings` in `packages/contracts/foundry.toml`:

```
  "p256-verifier/=lib/p256-verifier/src/",
```

Verify the contract exists and note its name:

```bash
ls packages/contracts/lib/p256-verifier/src/
```

Expected: a `P256Verifier.sol` whose `fallback` takes the same 160-byte input as the precompile.
If the path or filename differs, use what is there — the only requirement is a contract whose
fallback implements the EIP-7951 input/output contract.

- [ ] **Step 2: Write the failing test**

Create `packages/contracts/test/FlippyGateP256.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FlippyGate} from "../src/FlippyGate.sol";
import {P256Verifier} from "p256-verifier/P256Verifier.sol";

/// @notice The iPhone half of the 2-of-2. The Secure Enclave can only sign P-256, and it
///         hashes with SHA-256 before signing, so the gate verifies sha256(digest).
///         Pinned by the frozen vector so Solidity, TypeScript and Swift cannot drift.
contract FlippyGateP256Test is Test {
    string constant VECTOR = "../protocol/vectors/p256.json";

    FlippyGate gate;
    address verifier;
    address agent;
    uint256 agentKey;

    bytes32 qx;
    bytes32 qy;
    bytes sig64;
    bytes sig64HighS;

    function setUp() public {
        verifier = address(new P256Verifier());

        string memory json = vm.readFile(VECTOR);
        qx = vm.parseJsonBytes32(json, ".qx");
        qy = vm.parseJsonBytes32(json, ".qy");
        sig64 = vm.parseJsonBytes(json, ".signature64");
        sig64HighS = vm.parseJsonBytes(json, ".signature64HighS");

        (agent, agentKey) = makeAddrAndKey("agent");
        gate = new FlippyGate(agent, address(0), qx, qy, verifier);
        vm.deal(address(gate), 1 ether);
    }

    /// The vector signs the digest from execute.json, so reproduce that exact call.
    function _vectorCall()
        internal
        pure
        returns (address to, uint256 value, bytes memory data, uint256 deadline)
    {
        return (0x2222222222222222222222222222222222222222, 0.01 ether, "", 2000000000);
    }

    function _agentSig(bytes32 digest) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(agentKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _pinnedGate() internal returns (FlippyGate) {
        // The vector's digest is bound to chainId 11155111 and gate 0x1111…1111.
        vm.chainId(11155111);
        FlippyGate fresh = new FlippyGate(agent, address(0), qx, qy, verifier);
        address pinnedAddr = 0x1111111111111111111111111111111111111111;
        vm.etch(pinnedAddr, address(fresh).code);
        // immutables live in code, so the etched copy keeps agent/qx/qy/verifier
        vm.deal(pinnedAddr, 1 ether);
        return FlippyGate(payable(pinnedAddr));
    }

    function test_p256_signature_from_the_vector_executes() public {
        FlippyGate g = _pinnedGate();
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = g.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        g.execute(to, value, data, deadline, _agentSig(digest), sig64);

        assertEq(g.nonce(), 1, "nonce consumed");
        assertEq(to.balance, value, "value moved");
    }

    function test_high_s_p256_signature_is_accepted() public {
        FlippyGate g = _pinnedGate();
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = g.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        // EIP-7951 does not require low-s, and neither do we: the nonce makes replay moot.
        g.execute(to, value, data, deadline, _agentSig(digest), sig64HighS);
        assertEq(g.nonce(), 1);
    }

    function test_replaying_a_p256_signature_reverts() public {
        FlippyGate g = _pinnedGate();
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = g.digestOf(0, to, value, data, deadline);
        bytes memory aSig = _agentSig(digest);

        vm.warp(deadline - 1);
        g.execute(to, value, data, deadline, aSig, sig64);

        vm.expectRevert(FlippyGate.BadAgentSig.selector); // nonce moved, so the digest changed
        g.execute(to, value, data, deadline, aSig, sig64);
    }

    function test_wrong_public_key_reverts() public {
        vm.chainId(11155111);
        FlippyGate fresh = new FlippyGate(agent, address(0), bytes32(uint256(qx) ^ 1), qy, verifier);
        vm.etch(0x1111111111111111111111111111111111111111, address(fresh).code);
        FlippyGate g = FlippyGate(payable(0x1111111111111111111111111111111111111111));
        vm.deal(address(g), 1 ether);

        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = g.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        vm.expectRevert(FlippyGate.BadHumanSig.selector);
        g.execute(to, value, data, deadline, _agentSig(digest), sig64);
    }

    function test_a_signature_of_any_other_length_reverts() public {
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = gate.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        vm.expectRevert(FlippyGate.BadHumanSigLength.selector);
        gate.execute(to, value, data, deadline, _agentSig(digest), hex"1234");
    }

    function test_secp256k1_signature_rejected_when_no_k1_human_configured() public {
        (address to, uint256 value, bytes memory data, uint256 deadline) = _vectorCall();
        bytes32 digest = gate.digestOf(0, to, value, data, deadline);

        vm.warp(deadline - 1);
        vm.expectRevert(FlippyGate.NoK1Human.selector);
        gate.execute(to, value, data, deadline, _agentSig(digest), _agentSig(digest));
    }

    function test_constructor_with_no_human_authority_reverts() public {
        vm.expectRevert(FlippyGate.NoHumanAuthority.selector);
        new FlippyGate(agent, address(0), bytes32(0), bytes32(0), verifier);
    }
}
```

- [ ] **Step 3: Run it and watch it fail**

Run: `pnpm contracts:test`
Expected: FAIL to compile — `FlippyGate` has a two-argument constructor.

- [ ] **Step 4: Rewrite the human half of the gate**

In `packages/contracts/src/FlippyGate.sol`, replace `address public immutable human;` with:

```solidity
    /// @notice secp256k1 human — the Flipper. May be address(0) if only the phone is configured.
    address public immutable humanK1;

    /// @notice P-256 human — the iPhone's Secure Enclave key, as an uncompressed point.
    ///         May be (0,0) if only the Flipper is configured.
    bytes32 public immutable humanQx;
    bytes32 public immutable humanQy;

    /// @notice EIP-7951 precompile (0x100) where it exists, a deployed verifier where it does not.
    ///         Same 160-byte input either way, so this contract never branches on which it is.
    address public immutable p256Verifier;
```

Replace the constructor:

```solidity
    constructor(address _agent, address _humanK1, bytes32 _humanQx, bytes32 _humanQy, address _p256Verifier)
        EIP712("FlippyGate", "1")
    {
        if (_agent == address(0)) revert ZeroAddress();
        if (_humanK1 == address(0) && _humanQx == bytes32(0)) revert NoHumanAuthority();
        if (_humanQx != bytes32(0) && _p256Verifier == address(0)) revert ZeroAddress();
        agent = _agent;
        humanK1 = _humanK1;
        humanQx = _humanQx;
        humanQy = _humanQy;
        p256Verifier = _p256Verifier;
    }
```

Add the new errors beside the existing ones:

```solidity
    error NoHumanAuthority();
    error NoK1Human();
    error NoP256Human();
    error BadHumanSigLength();
```

Replace the single line `if (ECDSA.recover(digest, humanSig) != human) revert BadHumanSig();` with:

```solidity
        _requireHuman(digest, humanSig);
```

and add the function:

```solidity
    /// @dev Two physical devices, one gate. Length is the discriminator: a secp256k1 signature is
    ///      65 bytes (r,s,v) and a P-256 one is 64 (r,s) — the Secure Enclave has no recovery id.
    function _requireHuman(bytes32 digest, bytes calldata humanSig) internal view {
        if (humanSig.length == 65) {
            if (humanK1 == address(0)) revert NoK1Human();
            if (ECDSA.recover(digest, humanSig) != humanK1) revert BadHumanSig();
            return;
        }
        if (humanSig.length != 64) revert BadHumanSigLength();
        if (humanQx == bytes32(0)) revert NoP256Human();

        // CryptoKit's SecureEnclave signer hashes its input with SHA-256 before signing and
        // offers no way to opt out, so the message is sha256(digest), not digest. Pinned by
        // packages/protocol/vectors/p256.json.
        bytes32 message = sha256(abi.encodePacked(digest));

        (bool ok, bytes memory ret) =
            p256Verifier.staticcall(abi.encodePacked(message, humanSig, humanQx, humanQy));

        // High-s signatures are accepted. EIP-7951 does not reject them, and neither do we: the
        // nonce is consumed by the first execution, so a malleated twin has nothing to replay.
        if (!ok || ret.length != 32 || bytes32(ret) != bytes32(uint256(1))) revert BadHumanSig();
    }
```

- [ ] **Step 5: Update the two existing test files to the new constructor**

Every `new FlippyGate(agent, human)` becomes
`new FlippyGate(agent, human, bytes32(0), bytes32(0), address(0))`. There are calls in
`test/FlippyGate.t.sol` and one in `test/Digest.t.sol`. Change nothing else in either file — if a
test that passed before now fails, the secp256k1 path has regressed and that is the bug.

- [ ] **Step 6: Run the whole suite**

Run: `pnpm contracts:test`
Expected: PASS — the original 13 plus 7 new ones.

If `test_p256_signature_from_the_vector_executes` reverts with `BadHumanSig`, the failure is
almost certainly the SHA-256 layer or byte order. Debug by asserting the verifier directly before
touching the gate:

```solidity
(bool ok, bytes memory ret) = verifier.staticcall(
    abi.encodePacked(sha256(abi.encodePacked(digest)), sig64, qx, qy)
);
assertTrue(ok && bytes32(ret) == bytes32(uint256(1)), "verifier rejected the frozen vector");
```

If that assertion fails, the vector and the contract disagree; if it passes and `execute` still
reverts, the digest differs and the problem is in `_pinnedGate`, not the crypto.

- [ ] **Step 7: Add the fork test for the real precompile**

Append to `test/FlippyGateP256.t.sol`:

```solidity
    /// @notice Proves the frozen vector also satisfies the real EIP-7951 precompile, not just the
    ///         Solidity verifier the other tests use. Skipped unless SEPOLIA_RPC_URL is set.
    function test_fork_precompile_accepts_the_vector() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);

        (bool ok, bytes memory ret) = address(0x100).staticcall(
            abi.encodePacked(sha256(abi.encodePacked(bytes32(0))), sig64, qx, qy)
        );
        // A signature over the wrong message must fail cleanly, never revert.
        assertTrue(ok, "precompile reverted, which EIP-7951 forbids");
        assertEq(ret.length, 0, "wrong message should not verify");

        string memory json = vm.readFile(VECTOR);
        bytes32 message = vm.parseJsonBytes32(json, ".messageSha256");
        (ok, ret) = address(0x100).staticcall(abi.encodePacked(message, sig64, qx, qy));
        assertTrue(ok && bytes32(ret) == bytes32(uint256(1)), "precompile rejected the frozen vector");
    }
```

Run: `SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com pnpm contracts:test`
Expected: PASS. If this test fails while everything else passes, Spike H1's answer was wrong —
update `docs/spikes.md` and deploy with the fallback verifier in Task 6.

- [ ] **Step 8: Re-export the ABI**

Run: `pnpm contracts:build`
Expected: `packages/contracts/abi/FlippyGate.json` now shows the five-argument constructor.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "contracts: accept a Secure Enclave P-256 signature as the human half

Signature length is the discriminator: 65 bytes is the Flipper, 64 is the iPhone.
The Enclave signs sha256(digest) because CryptoKit gives no way to opt out, so the
gate verifies that. High-s is accepted deliberately — the nonce makes replay moot."
```

---

### Task 6: Deploy the gate to Sepolia

Turns the passing tests into an address the iOS app can talk to. This is milestone M2.

**Files:**
- Modify: `packages/contracts/script/Deploy.s.sol`
- Modify: `.env.example`
- Create: `packages/contracts/deployments/sepolia.json` (written by the script)

**Interfaces:**
- Consumes: the constructor from Task 5; the `P256_VERIFIER` decision from Task 2.
- Produces: `packages/contracts/deployments/sepolia.json` with keys
  `chainId, gate, token, swap, agent, humanK1, humanQx, humanQy, p256Verifier`. Every later task
  in every later plan reads the gate address from this file.

- [ ] **Step 1: Update the deploy script's inputs**

In `packages/contracts/script/Deploy.s.sol`, replace the `human` env read and the `FlippyGate`
construction with:

```solidity
        address humanK1 = vm.envOr("HUMAN_K1_ADDRESS", address(0));
        bytes32 humanQx = vm.envOr("HUMAN_QX", bytes32(0));
        bytes32 humanQy = vm.envOr("HUMAN_QY", bytes32(0));
        address p256Verifier = vm.envOr("P256_VERIFIER", address(0x100));

        require(humanK1 != address(0) || humanQx != bytes32(0), "set HUMAN_K1_ADDRESS or HUMAN_QX/QY");
```

```solidity
        FlippyGate gate = new FlippyGate(agent, humanK1, humanQx, humanQy, p256Verifier);
```

and extend the JSON block:

```solidity
        vm.serializeAddress(obj, "humanK1", humanK1);
        vm.serializeBytes32(obj, "humanQx", humanQx);
        vm.serializeBytes32(obj, "humanQy", humanQy);
        vm.serializeAddress(obj, "p256Verifier", p256Verifier);
```

Keep `vm.serializeAddress(obj, "human", human)` out — the key is gone, and a stale `human` field
would be read by something eventually.

- [ ] **Step 2: Document the new environment variables**

In `.env.example`, replace `HUMAN_ADDRESS` with:

```
# The Flipper's secp256k1 address. Optional if the iPhone is configured.
HUMAN_K1_ADDRESS=
# The iPhone Secure Enclave public key, as two 32-byte halves. The app prints these on
# its Setup screen. Optional if the Flipper is configured.
HUMAN_QX=
HUMAN_QY=
# EIP-7951 precompile where it exists. Set to a deployed verifier's address on chains
# that lack it — see docs/spikes.md entry 5.
P256_VERIFIER=0x0000000000000000000000000000000000000100
```

- [ ] **Step 3: Deploy with the frozen vector's key, so there is something to test against**

Until the iOS app exists (next plan), use the vector's public key as the human authority. That
makes M2 demonstrable today and the key is a published test value, which is exactly right.

```bash
export HUMAN_QX=$(jq -r .qx packages/protocol/vectors/p256.json)
export HUMAN_QY=$(jq -r .qy packages/protocol/vectors/p256.json)
export CHAIN_KEY=sepolia
export AGENT_ADDRESS=<your funded agent address>
export DEPLOYER_KEY=<your funded deployer key>
cd packages/contracts && forge script script/Deploy.s.sol \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast
```

Expected: addresses printed, and `deployments/sepolia.json` written.

- [ ] **Step 4: Prove it end to end on the real chain**

Write `packages/contracts/script/proveP256.ts` — a script that reads `deployments/sepolia.json`
and `vectors/p256.json`, builds the same call the vector signs, signs the digest with the agent
key, and submits `execute`:

```ts
/**
 * M2 proof: a P-256 signature, produced off-chain the way a Secure Enclave produces
 * one, executes a real transfer through the deployed gate.
 *
 * Run: pnpm --filter @flippy/contracts exec tsx script/proveP256.ts
 */
import { readFileSync } from "node:fs";
import { createWalletClient, createPublicClient, http, concatHex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";
import { proposalDigest } from "@flippy/protocol";
import { FlippyGateAbi } from "@flippy/contracts";

const d = JSON.parse(readFileSync("./deployments/sepolia.json", "utf8"));
const v = JSON.parse(readFileSync("../protocol/vectors/p256.json", "utf8"));

const agent = privateKeyToAccount(process.env.AGENT_KEY as `0x${string}`);
const relayer = privateKeyToAccount(process.env.RELAYER_KEY as `0x${string}`);
const pub = createPublicClient({ chain: sepolia, transport: http(process.env.SEPOLIA_RPC_URL) });
const wallet = createWalletClient({ account: relayer, chain: sepolia, transport: http(process.env.SEPOLIA_RPC_URL) });

const nonce = await pub.readContract({ address: d.gate, abi: FlippyGateAbi, functionName: "nonce" });
const call = { to: agent.address, value: 1n, data: "0x" as const };
const deadline = Math.floor(Date.now() / 1000) + 600;

const digest = proposalDigest({ chainId: sepolia.id, gate: d.gate, nonce, call, deadline });
const agentSig = await agent.sign({ hash: digest });

// The vector's signature is over the vector's digest, so this only works if they match.
if (digest !== v.digest) {
  throw new Error(
    `digest ${digest} != vector ${v.digest}. The vector signs one exact call; re-run the ` +
      `deploy so nonce is 0 and use the vector's to/value/deadline, or sign with a live key.`,
  );
}

const hash = await wallet.writeContract({
  address: d.gate,
  abi: FlippyGateAbi,
  functionName: "execute",
  args: [call.to, call.value, call.data, BigInt(deadline), agentSig, concatHex([v.r, v.s.slice(2) as `0x${string}`])],
});
console.log("submitted", hash);
console.log(await pub.waitForTransactionReceipt({ hash }));
```

The digest guard will fire on the first run — that is the point. The vector signs one exact call
(`to = 0x2222…2222`, `value = 0.01 ether`, `deadline = 2000000000`, `nonce = 0`, `gate = 0x1111…1111`),
and a freshly deployed gate has a different address, so the digests cannot match. **Use it as a
gate-address check, then run the real proof against a live P-256 key** by generating a signature
in the script with `@noble/curves` over the live digest instead of reading `v.r`/`v.s`. Replace
the two lines that read the vector's signature with:

```ts
import { p256 } from "@noble/curves/p256";
import { sha256 } from "@noble/hashes/sha256";
import { hexToBytes } from "viem";
const sig = p256.sign(sha256(hexToBytes(digest)), hexToBytes(v.privateKey));
const humanSig = `0x${sig.r.toString(16).padStart(64, "0")}${sig.s.toString(16).padStart(64, "0")}` as const;
```

and delete the digest-equality guard.

Run: `pnpm --filter @flippy/contracts exec tsx script/proveP256.ts`
Expected: a transaction hash and a receipt with `status: "success"`.

- [ ] **Step 5: Commit the deployment**

```bash
git add packages/contracts/deployments/sepolia.json packages/contracts/script .env.example
git commit -m "chore: deploy FlippyGate to Sepolia with a P-256 human authority

M2. A P-256 signature shaped exactly like a Secure Enclave's executes a real
transfer through the gate. The phone comes next; the chain is ready for it."
```

- [ ] **Step 6: Record the milestone**

Append the transaction hash and the gate address to `docs/spikes.md` entry 5 under
**Evidence**. An unrecorded proof gets re-derived by someone on day four.

---

## What this plan does not cover

This plan ends at a deployed gate that accepts Enclave-shaped signatures. Three plans follow, in
this order:

1. **iOS core loop (M3)** — `ios/` scaffolding, `FlippyKit` with the Swift EIP-712 digest asserted
   against both frozen vectors, `EnclaveHumanKey`, device registration, and a single button that
   makes a Secure Enclave signature land on Sepolia. This is the authorization loop the brief
   asked to build first, and the plan for it should be written once Task 6 is green — its shape
   depends on what the deployment actually looks like.
2. **Chat and the agent (M4, M6)** — the Claude tool loop in `apps/hub`, `/api/m/*`, the SSE
   stream, the Chat and Approval screens, `propose_swap`, and the attack scene.
3. **NFC and the second device (M5, M7, M9)** — `NFCTrigger`, stations, the printed puck, the
   Flipper regression, and background tag reading.

Writing bite-sized steps for those now would be guessing: M5 depends on Apple enrolment
completing, and M3's structure depends on Spike H1's answer. Each plan gets written when its
predecessor is green.
