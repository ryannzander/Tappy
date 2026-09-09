import XCTest
@testable import TappyKit

/// The third language to assert the frozen vector. Solidity and TypeScript already agree;
/// if Swift disagrees by one byte, every signature this phone makes is rejected on-chain
/// with `BadHumanSig`, which tells you nothing about the cause. So we find out here instead.
final class DigestTests: XCTestCase {

    private func vector(_ name: String) throws -> [String: Any] {
        // ios/TappyKit/Tests/TappyKitTests/ -> repo root -> packages/protocol/vectors/
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("packages/protocol/vectors/\(name).json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Known-answer tests. If these fail, nothing downstream is worth debugging.
    func testKeccakKnownAnswers() {
        XCTAssertEqual(
            Keccak.hash256(Data()).hexString,
            "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
            "keccak256('') — this is also the `dataHash` in execute.json"
        )
        XCTAssertEqual(
            Keccak.hash256(Data("abc".utf8)).hexString,
            "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
        )
        // Guards the padding byte: SHA3-256 of "" would be 0xa7ff...80a, not this.
        XCTAssertNotEqual(
            Keccak.hash256(Data()).hexString,
            "0xa7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"
        )
    }

    func testMatchesTheFrozenExecuteVector() throws {
        let v = try vector("execute")

        let digest = try EIP712.digest(
            chainId: try XCTUnwrap(v["chainId"] as? Int),
            gate: try XCTUnwrap(v["gate"] as? String),
            nonce: try XCTUnwrap(v["nonce"] as? String),
            to: try XCTUnwrap(v["to"] as? String),
            value: try XCTUnwrap(v["value"] as? String),
            data: try XCTUnwrap(v["data"] as? String),
            deadline: Int(try XCTUnwrap(v["deadline"] as? String)) ?? 0
        )

        XCTAssertEqual(
            digest.hexString,
            try XCTUnwrap(v["digest"] as? String),
            "Swift digest != the digest Solidity and TypeScript produce"
        )
    }

    /// The Secure Enclave signs sha256(digest), never the digest — CryptoKit hashes its input
    /// and gives no way to opt out, so the contract verifies sha256(digest) too.
    func testEnclaveMessageIsSha256OfTheDigest() throws {
        let v = try vector("p256")
        let digest = try ABI.bytes(try XCTUnwrap(v["digest"] as? String))
        XCTAssertEqual(
            HumanKeySigning.enclaveMessage(for: digest).hexString,
            try XCTUnwrap(v["messageSha256"] as? String)
        )
    }

    func testUint256HandlesWeiSizedValues() throws {
        XCTAssertEqual(
            try ABI.uint256(decimal: "10000000000000000").hexString,
            "0x000000000000000000000000000000000000000000000000002386f26fc10000"
        )
        // 2^256 - 1 must fit exactly; one more must not.
        let max = String(repeating: "", count: 0)
            + "115792089237316195423570985008687907853269984665640564039457584007913129639935"
        XCTAssertEqual(try ABI.uint256(decimal: max).hexString, "0x" + String(repeating: "ff", count: 32))
        XCTAssertThrowsError(try ABI.uint256(decimal: max.dropLast() + "36"))
    }
}
