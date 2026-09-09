import Foundation

/// The EIP-712 digest — the one hash the agent, the human and the contract all agree on.
///
/// The phone recomputes this from the raw call rather than trusting the id the hub sends.
/// That is what makes "what you see is what you sign" true here: if the hub lies about what
/// a proposal does, the digest will not match and the signature is worthless.
///
/// Must byte-for-byte match `packages/protocol/src/digest.ts` and `TappyGate.digestOf`.
/// Pinned by the frozen vector in `packages/protocol/vectors/execute.json`.
public enum EIP712 {
    static let domainTypeString =
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    static let executeTypeString =
        "Execute(uint256 nonce,address to,uint256 value,bytes data,uint256 deadline)"

    public static func domainSeparator(chainId: Int, gate: String) throws -> Data {
        var encoded = Data()
        encoded += Keccak.hash256(Data(domainTypeString.utf8))
        encoded += Keccak.hash256(Data("TappyGate".utf8))
        encoded += Keccak.hash256(Data("1".utf8))
        encoded += ABI.uint256(chainId)
        encoded += try ABI.address(gate)
        return Keccak.hash256(encoded)
    }

    /// `value` and `nonce` arrive as decimal strings because wei does not fit in Int64.
    public static func digest(
        chainId: Int,
        gate: String,
        nonce: String,
        to: String,
        value: String,
        data: String,
        deadline: Int
    ) throws -> Data {
        var structEncoded = Data()
        structEncoded += Keccak.hash256(Data(executeTypeString.utf8))
        structEncoded += try ABI.uint256(decimal: nonce)
        structEncoded += try ABI.address(to)
        structEncoded += try ABI.uint256(decimal: value)
        // `bytes` is hashed, not inlined — the one detail that silently breaks everything.
        structEncoded += Keccak.hash256(try ABI.bytes(data))
        structEncoded += ABI.uint256(deadline)

        var preimage = Data([0x19, 0x01])
        preimage += try domainSeparator(chainId: chainId, gate: gate)
        preimage += Keccak.hash256(structEncoded)
        return Keccak.hash256(preimage)
    }
}

public enum ABIError: Error, LocalizedError {
    case badHex(String)
    case badAddress(String)
    case badDecimal(String)
    case overflow(String)

    public var errorDescription: String? {
        switch self {
        case .badHex(let s): return "not valid hex: \(s)"
        case .badAddress(let s): return "not a 20-byte address: \(s)"
        case .badDecimal(let s): return "not a decimal integer: \(s)"
        case .overflow(let s): return "does not fit in 256 bits: \(s)"
        }
    }
}

public enum ABI {
    /// Left-pads to the 32-byte word every static ABI type occupies.
    public static func uint256(_ value: Int) -> Data {
        var word = Data(repeating: 0, count: 32)
        var v = UInt64(value)
        var i = 31
        while v > 0 && i >= 0 {
            word[i] = UInt8(v & 0xFF)
            v >>= 8
            i -= 1
        }
        return word
    }

    /// Wei does not fit in Int64, so amounts travel as decimal strings and are converted
    /// here by long multiplication rather than through any integer type.
    public static func uint256(decimal: String) throws -> Data {
        let trimmed = decimal.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber }) else {
            throw ABIError.badDecimal(decimal)
        }
        var word = [UInt8](repeating: 0, count: 32)
        for character in trimmed {
            guard let digit = character.wholeNumberValue else { throw ABIError.badDecimal(decimal) }
            var carry = UInt32(digit)
            for i in stride(from: 31, through: 0, by: -1) {
                let product = UInt32(word[i]) * 10 + carry
                word[i] = UInt8(product & 0xFF)
                carry = product >> 8
            }
            if carry != 0 { throw ABIError.overflow(decimal) }
        }
        return Data(word)
    }

    public static func address(_ hex: String) throws -> Data {
        let raw = try bytes(hex)
        guard raw.count == 20 else { throw ABIError.badAddress(hex) }
        return Data(repeating: 0, count: 12) + raw
    }

    public static func bytes(_ hex: String) throws -> Data {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count % 2 == 0 else { throw ABIError.badHex(hex) }
        var out = Data(capacity: s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else { throw ABIError.badHex(hex) }
            out.append(byte)
            index = next
        }
        return out
    }
}

extension Data {
    public var hexString: String { "0x" + map { String(format: "%02x", $0) }.joined() }
}
