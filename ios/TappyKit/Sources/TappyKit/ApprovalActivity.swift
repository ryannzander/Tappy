// os(iOS), not canImport: ActivityKit imports fine on macOS but its types are unavailable there,
// so a canImport guard still fails to compile for the `swift build` we run on the Mac.
#if os(iOS)
import ActivityKit
import Foundation

/// What the Dynamic Island shows while a transaction waits on you.
///
/// Shared between the app and the widget extension so there is one definition of the payload —
/// ActivityKit matches activities by attribute type, and two near-identical copies would fail to
/// match at runtime in a way that looks like the Live Activity simply never appearing.
public struct ApprovalAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String
        public var amountUsd: String
        public var amountEth: String
        public var counterparty: String

        public init(status: String, amountUsd: String, amountEth: String, counterparty: String) {
            self.status = status
            self.amountUsd = amountUsd
            self.amountEth = amountEth
            self.counterparty = counterparty
        }

        public var isPending: Bool { status == "PENDING_HUMAN" }

        public var headline: String {
            switch status {
            case "PENDING_HUMAN": return "Waiting for you"
            case "SUBMITTED": return "Submitting"
            case "EXECUTED": return "Sent"
            case "REJECTED": return "Declined"
            case "EXPIRED": return "Expired"
            default: return "Failed"
            }
        }
    }

    public var verb: String
    public var proposalId: String

    public init(verb: String, proposalId: String) {
        self.verb = verb
        self.proposalId = proposalId
    }
}
#endif
