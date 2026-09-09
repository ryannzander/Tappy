import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { p256 } from "@noble/curves/nist.js";
import { sha256 } from "@noble/hashes/sha2.js";
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
    // prehash: false — v.messageSha256 is already the digest the Enclave signs, not raw
    // material to hash again. Omitting this defaults to prehash: true and fails silently.
    expect(
      p256.verify(hexToBytes(v.signature64), hexToBytes(v.messageSha256), pub, { prehash: false }),
    ).toBe(true);
  });

  it("signature64 is r concatenated with s, 64 bytes", () => {
    expect(hexToBytes(v.signature64).length).toBe(64);
    expect(v.signature64).toBe(`${v.r}${v.s.slice(2)}`);
  });

  it("the high-s twin has the same r and verifies with lowS disabled", () => {
    const pub = p256.getPublicKey(hexToBytes(v.privateKey), false);
    expect(v.signature64HighS.slice(0, 66)).toBe(v.r);
    expect(
      p256.verify(hexToBytes(v.signature64HighS), hexToBytes(v.messageSha256), pub, {
        lowS: false,
        prehash: false, // see above — the input is already a digest, not raw message bytes
      }),
    ).toBe(true);
  });
});
