import Foundation

/// Keccak-256, the hash Ethereum uses everywhere.
///
/// This is *not* SHA3-256. The two differ only in the padding byte — Keccak pads with 0x01,
/// SHA3 with 0x06 — which is exactly the kind of difference that produces a valid-looking
/// hash that nothing else agrees with. Apple ships neither, so we carry our own.
///
/// Correctness is pinned by `DigestTests`, which reproduces the frozen vector that Solidity
/// and TypeScript already agree on.
public enum Keccak {
    private static let rounds = 24

    private static let roundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808a, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808b, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008a, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000a,
        0x0000_0000_8000_808b, 0x8000_0000_0000_008b, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800a, 0x8000_0000_8000_000a,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
    ]

    /// Rotation offsets for rho, indexed [x + 5y].
    private static let rotations: [Int] = [
        0, 1, 62, 28, 27,
        36, 44, 6, 55, 20,
        3, 10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2, 61, 56, 14,
    ]

    /// 256-bit output means a 136-byte rate (1600 bits of state minus 2×256 of capacity).
    private static let rate = 136

    public static func hash256(_ input: Data) -> Data {
        var state = [UInt64](repeating: 0, count: 25)

        var padded = input
        // Keccak's original padding: 0x01 … 0x80. SHA3 uses 0x06 here. Do not "fix" this.
        padded.append(0x01)
        while padded.count % rate != 0 { padded.append(0x00) }
        padded[padded.count - 1] |= 0x80

        var offset = 0
        while offset < padded.count {
            for lane in 0..<(rate / 8) {
                var value: UInt64 = 0
                for byte in 0..<8 {
                    value |= UInt64(padded[offset + lane * 8 + byte]) << (8 * UInt64(byte))
                }
                state[lane] ^= value
            }
            permute(&state)
            offset += rate
        }

        var out = Data(capacity: 32)
        for lane in 0..<4 {
            let value = state[lane]
            for byte in 0..<8 {
                out.append(UInt8((value >> (8 * UInt64(byte))) & 0xFF))
            }
        }
        return out
    }

    private static func permute(_ state: inout [UInt64]) {
        for round in 0..<rounds {
            // theta
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                c[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
            }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1)
                for y in stride(from: 0, to: 25, by: 5) { state[x + y] ^= d }
            }

            // rho and pi
            var b = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(state[x + 5 * y], rotations[x + 5 * y])
                }
            }

            // chi
            for y in stride(from: 0, to: 25, by: 5) {
                for x in 0..<5 {
                    state[x + y] = b[x + y] ^ (~b[(x + 1) % 5 + y] & b[(x + 2) % 5 + y])
                }
            }

            // iota
            state[0] ^= roundConstants[round]
        }
    }

    private static func rotl(_ value: UInt64, _ shift: Int) -> UInt64 {
        shift == 0 ? value : (value << UInt64(shift)) | (value >> UInt64(64 - shift))
    }
}
