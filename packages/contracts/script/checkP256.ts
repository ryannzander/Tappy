/**
 * Spike H1: is the EIP-7951 P256VERIFY precompile live on this RPC?
 * A known-good vector must return 32 bytes of 1. Anything else means the
 * fallback verifier is required (see spec §4.3).
 *
 * Run: pnpm --filter @tappy/contracts exec tsx script/checkP256.ts
 *
 * Import paths below are for @noble/curves@2.x / @noble/hashes@2.x, the
 * versions pnpm actually installed here. v1.x used @noble/curves/p256 and
 * @noble/hashes/sha256; v2.x renamed the modules to nist.js/sha2.js and its
 * export map requires the .js suffix (checked against node_modules/.pnpm's
 * package.json "exports"). Task 3 should import the same paths.
 *
 * Also new in v2: p256.sign() returns a raw 64-byte compact signature
 * (r || s), not a Signature object with .r/.s bigints as in v1. Slicing the
 * bytes directly is simpler than the v1 approach and needs no bigint padding
 * since each half is already a fixed 32 bytes.
 *
 * CRITICAL v2 default: sign()/verify() default to { prehash: true } and hash
 * the "message" argument themselves before signing. `message` here is
 * already a digest (we hashed it ourselves below) — EIP-7951's `h` field is
 * used completely literally by the precompile, with no hashing at all. Left
 * on defaults, sign() and verify() both silently re-hash `message`, so they
 * agree with *each other* (making a naive local self-check pass) while
 * signing over a different 32 bytes than the `h` we send on-chain. This
 * produced a real false negative here: the precompile rejected the
 * mismatched signature, which looks identical to "no precompile deployed"
 * from the outside. { prehash: false } makes both calls treat `message` as
 * the literal digest, matching the precompile's semantics.
 */
import { createPublicClient, http, concatHex } from "viem";
import { p256 } from "@noble/curves/nist.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { bytesToHex, hexToBytes } from "viem";

const RPC = process.env.SEPOLIA_RPC_URL;
if (!RPC) throw new Error("SEPOLIA_RPC_URL is not set");

const PRECOMPILE = "0x0000000000000000000000000000000000000100" as const;

const priv = hexToBytes("0x0101010101010101010101010101010101010101010101010101010101010101");
const pub = p256.getPublicKey(priv, false); // 65 bytes: 0x04 || qx || qy
const qx = bytesToHex(pub.slice(1, 33));
const qy = bytesToHex(pub.slice(33, 65));

const message = sha256(new TextEncoder().encode("tappy p256 spike"));
const sig = p256.sign(message, priv, { prehash: false }); // compact: 32-byte r || 32-byte s
if (sig.length !== 64) throw new Error(`signature is ${sig.length} bytes, want 64`);
const r = bytesToHex(sig.slice(0, 32));
const s = bytesToHex(sig.slice(32, 64));

// A probe that can't tell "my vector is broken" from "the chain lacks the
// precompile" isn't a probe. eth_call to 0x100 returns empty data in BOTH
// cases — nothing deployed there, and a live EIP-7951 precompile rejecting
// an invalid signature (the EIP mandates "MUST NOT revert; return empty on
// invalid input"). Rule out the local cause before trusting an empty result.
// { prehash: false } here too — verify() must check the same literal digest
// sign() signed, not re-hash `message` again.
if (!p256.verify(sig, message, pub, { prehash: false })) {
  throw new Error(
    "local p256.verify(sig, message, pub, {prehash:false}) failed — the signature vector itself is broken; " +
      "an empty eth_call result below would be meaningless, fix this before reading it",
  );
}

const input = concatHex([bytesToHex(message), r, s, qx, qy]);
if (hexToBytes(input).length !== 160) throw new Error(`input is ${hexToBytes(input).length} bytes, want 160`);

const client = createPublicClient({ transport: http(RPC) });
const res = await client.call({ to: PRECOMPILE, data: input });

console.log("local verify ok (signature is valid before it ever reaches the chain)");
console.log("chain    ", await client.getChainId());
console.log("input    ", input);
console.log("returned ", res.data ?? "0x (empty)");
console.log(
  res.data === "0x0000000000000000000000000000000000000000000000000000000000000001"
    ? "PRECOMPILE LIVE — use address(0x100)"
    : "PRECOMPILE ABSENT — deploy the fallback verifier",
);
