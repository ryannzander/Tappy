/**
 * Generates the frozen P-256 vector. Run once. The output is committed and never
 * regenerated — regenerating it invalidates every P-256 signature in the system,
 * and the symptom is an unhelpful "bad signature".
 *
 * Run: pnpm --filter @tappy/protocol exec tsx scripts/genP256Vector.ts
 */
import { writeFileSync } from "node:fs";
import { p256 } from "@noble/curves/nist.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { bytesToHex, hexToBytes, type Hex } from "viem";
import execute from "../vectors/execute.json" with { type: "json" };

/** Fixed, not random: the vector must be reproducible by anyone reading this file. */
const PRIVATE_KEY = "0x2b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfe" as const;

const digest = execute.digest as Hex;
const message = sha256(hexToBytes(digest));
const pub = p256.getPublicKey(hexToBytes(PRIVATE_KEY), false);

// prehash: false — `message` is already sha256(digest), the exact bytes the Secure
// Enclave signs. Leaving prehash at its v2 default (true) hashes it a second time,
// producing a signature that verifies against the wrong message: it checks out
// locally and is rejected by the chain and the Enclave, a self-consistent bug.
const sig = p256.sign(message, hexToBytes(PRIVATE_KEY), { prehash: false }); // raw 64-byte r‖s, noble normalises to low-s
const r = bytesToHex(sig.slice(0, 32)) as Hex;
const s = bytesToHex(sig.slice(32, 64)) as Hex;

// The curve order. s' = n - s is an equally valid signature; EIP-7951 accepts it.
// v2 exposes it at p256.Point.Fn.ORDER (there is no top-level p256.CURVE.n) — read it
// from the library rather than hardcoding the literal, since a typo here would
// produce a vector that silently fails to verify.
const N = p256.Point.Fn.ORDER;
const sHigh = `0x${(N - BigInt(s)).toString(16).padStart(64, "0")}` as Hex;

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

// Errors are loud: verify the vector against both curve checks before writing it, so a
// bad vector never gets committed silently.
const lowSOk = p256.verify(hexToBytes(out.signature64), message, pub, { prehash: false });
const highSOk = p256.verify(hexToBytes(out.signature64HighS), message, pub, {
  lowS: false,
  prehash: false,
});
if (!lowSOk || !highSOk) {
  throw new Error(
    `generated p256 vector does not self-verify (lowS: ${lowSOk}, highS: ${highSOk})`,
  );
}

writeFileSync(new URL("../vectors/p256.json", import.meta.url), JSON.stringify(out, null, 2) + "\n");
console.log("wrote vectors/p256.json");
