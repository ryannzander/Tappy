import CryptoKit
import Foundation
import TappyKit

/// Asserts that Swift reproduces the frozen cross-language vectors. Solidity and TypeScript
/// already agree; if Swift does not, every signature this phone makes is rejected on-chain
/// with `BadHumanSig`, which says nothing about the cause. Run it before trusting the app.
///
///     swift run tappy-verify

var failures = 0

func check(_ label: String, _ got: String, _ want: String) {
    if got == want {
        print("  ok   \(label)")
    } else {
        failures += 1
        print("  FAIL \(label)\n         got  \(got)\n         want \(want)")
    }
}

func vector(_ name: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("packages/protocol/vectors/\(name).json")
    let data = try Data(contentsOf: url)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

print("keccak256 known answers")
check("keccak256(\"\")", Keccak.hash256(Data()).hexString,
      "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
check("keccak256(\"abc\")", Keccak.hash256(Data("abc".utf8)).hexString,
      "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")

print("abi uint256")
check("0.01 ether", try ABI.uint256(decimal: "10000000000000000").hexString,
      "0x000000000000000000000000000000000000000000000000002386f26fc10000")
check("2^256-1",
      try ABI.uint256(decimal: "115792089237316195423570985008687907853269984665640564039457584007913129639935").hexString,
      "0x" + String(repeating: "ff", count: 32))

print("frozen vector: execute.json")
let e = try vector("execute")
let digest = try EIP712.digest(
    chainId: e["chainId"] as! Int,
    gate: e["gate"] as! String,
    nonce: e["nonce"] as! String,
    to: e["to"] as! String,
    value: e["value"] as! String,
    data: e["data"] as! String,
    deadline: Int(e["deadline"] as! String)!
)
check("EIP-712 digest", digest.hexString, e["digest"] as! String)

print("frozen vector: p256.json")
let p = try vector("p256")
let raw = try ABI.bytes(p["digest"] as! String)
check("sha256(digest) is what the Enclave signs",
      HumanKeySigning.enclaveMessage(for: raw).hexString, p["messageSha256"] as! String)

// A signature made the way the app makes one must verify against the vector's public key.
let priv = try P256.Signing.PrivateKey(rawRepresentation: try ABI.bytes(p["privateKey"] as! String))
let software = try SoftwareHumanKey(raw: priv.rawRepresentation)
check("software key reproduces the vector's public key",
      software.publicKey.hexString,
      (p["qx"] as! String) + (p["qy"] as! String).dropFirst(2))

let sig = try await software.sign(digest: raw, reason: "verify")
// Verify the way the CHAIN does: against the already-computed sha256(digest), with no further
// hashing. CryptoKit's Data-taking isValidSignature would hash again and disagree with itself —
// the same prehash trap that @noble/curves v2 sprang on the TypeScript side.
let ok = priv.publicKey.isValidSignature(
    try P256.Signing.ECDSASignature(rawRepresentation: sig),
    for: SHA256.hash(data: raw)
)
check("a fresh signature verifies over sha256(digest)", ok ? "true" : "false", "true")

// And prove the trap is real, so nobody "simplifies" sign() later and breaks the chain silently.
let doubleHashed = priv.publicKey.isValidSignature(
    try P256.Signing.ECDSASignature(rawRepresentation: sig),
    for: HumanKeySigning.enclaveMessage(for: raw)
)
check("double-hashing does NOT verify (guards the prehash trap)",
      doubleHashed ? "true" : "false", "false")

print(failures == 0 ? "\nall vectors match" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
