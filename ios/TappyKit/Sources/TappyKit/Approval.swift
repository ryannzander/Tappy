import Foundation

public enum ApprovalError: Error, LocalizedError {
    case digestMismatch(expected: String, recomputed: String)

    public var errorDescription: String? {
        switch self {
        case .digestMismatch(let expected, let recomputed):
            return """
                This proposal does not hash to the id the server sent. Refusing to sign.
                  server:     \(expected)
                  recomputed: \(recomputed)
                """
        }
    }
}

/// What you see is what you sign.
///
/// The phone rebuilds the EIP-712 digest from the raw call — `to`, `value`, `data`, `nonce`,
/// `deadline`, chain and gate — and refuses to continue unless it equals the id the hub sent.
/// A hub that lied about what a proposal does cannot get a signature out of this device, which
/// is the difference between a hardware wallet and a screen that displays whatever it is told.
public enum Approval {
    public static func recomputeDigest(_ p: MobileProposal) throws -> Data {
        try EIP712.digest(
            chainId: p.chainId,
            gate: p.gate,
            nonce: p.nonce,
            to: p.call.to,
            value: p.call.value,
            data: p.call.data,
            deadline: p.deadline
        )
    }

    /// Verifies the proposal, then signs it. Order matters: never prompt for a face over a
    /// digest we have not checked.
    public static func sign(_ p: MobileProposal, with key: HumanKey, reason: String) async throws -> Data {
        let recomputed = try recomputeDigest(p)
        guard recomputed.hexString.lowercased() == p.id.lowercased() else {
            throw ApprovalError.digestMismatch(expected: p.id, recomputed: recomputed.hexString)
        }
        return try await key.sign(digest: recomputed, reason: reason)
    }
}

public enum Format {
    /// Wei is an integer of up to 78 digits, so this is string surgery rather than arithmetic —
    /// no Double, which would quietly lose precision on anything above ~0.009 ETH.
    public static func eth(wei: String, decimals: Int = 18, places: Int = 4) -> String {
        let digits = wei.filter(\.isNumber)
        guard !digits.isEmpty else { return "0 ETH" }
        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let whole = String(padded.dropLast(decimals))
        let fraction = String(padded.suffix(decimals)).prefix(places)
        return "\(whole).\(fraction) ETH"
    }

    /// Wei -> dollars. The ETH figure is still the truth on-chain; dollars are what a person
    /// can judge at a glance, and judging the amount is the entire job of the approval screen.
    public static func usd(wei: String, rate: Double, decimals: Int = 18) -> String {
        let digits = wei.filter(\.isNumber)
        guard !digits.isEmpty, rate > 0 else { return "$0.00" }
        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let whole = Double(String(padded.dropLast(decimals))) ?? 0
        let fraction = Double("0." + String(padded.suffix(decimals))) ?? 0
        let dollars = (whole + fraction) * rate

        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        // Sub-cent amounts would all render as $0.00 and look identical, which is exactly the
        // confusion an approval screen must not create.
        f.maximumFractionDigits = dollars < 1 ? 4 : 2
        return f.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }

    /// Renders an amount in whatever asset it is, with the asset's own decimals. Falls back to
    /// the symbol when there is no price, because a made-up dollar figure is worse than none.
    public static func asset(_ action: MobileProposal.Action, rate: Double) -> String {
        let amount = eth(wei: action.amountWei, decimals: action.decimals, places: 4)
            .replacingOccurrences(of: " ETH", with: "")
        return "\(amount) \(action.symbol)"
    }

    public static func short(_ hex: String, lead: Int = 6, tail: Int = 4) -> String {
        hex.count <= lead + tail + 2 ? hex : "\(hex.prefix(lead))…\(hex.suffix(tail))"
    }
}
