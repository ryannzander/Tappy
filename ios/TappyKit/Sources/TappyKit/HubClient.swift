import Foundation

public struct MobileProposal: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let chainId: Int
    public let gate: String
    public let nonce: String
    public let call: Call
    public let action: Action
    public let deadline: Int
    public let status: String
    public let txHash: String?
    public let error: String?
    public let explorer: String?

    public struct Call: Decodable, Sendable, Equatable {
        public let to: String
        public let value: String
        public let data: String
    }

    /// The human-readable intent. Derived from `call`, never the other way round — the phone
    /// re-derives the digest from `call` and refuses to sign if the two disagree.
    public enum Action: Decodable, Sendable, Equatable {
        case send(to: String, valueWei: String, memo: String?)
        case sendToken(token: String, to: String, amount: String, symbol: String, decimals: Int)
        case swap(dex: String, sellWei: String, tokenOut: String)

        private enum Keys: String, CodingKey {
            case kind, to, valueWei, memo, dex, sellWei, tokenOut, token, amount, symbol, decimals
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            switch try c.decode(String.self, forKey: .kind) {
            case "send":
                self = .send(
                    to: try c.decode(String.self, forKey: .to),
                    valueWei: try c.decode(String.self, forKey: .valueWei),
                    memo: try c.decodeIfPresent(String.self, forKey: .memo)
                )
            case "sendToken":
                self = .sendToken(
                    token: try c.decode(String.self, forKey: .token),
                    to: try c.decode(String.self, forKey: .to),
                    amount: try c.decode(String.self, forKey: .amount),
                    symbol: try c.decode(String.self, forKey: .symbol),
                    decimals: try c.decode(Int.self, forKey: .decimals)
                )
            case "swap":
                self = .swap(
                    dex: try c.decode(String.self, forKey: .dex),
                    sellWei: try c.decode(String.self, forKey: .sellWei),
                    tokenOut: try c.decode(String.self, forKey: .tokenOut)
                )
            case let other:
                // Loud, not lenient: an action this build cannot render is an action it must
                // not let you approve.
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c, debugDescription: "unknown action kind \"\(other)\""
                )
            }
        }

        public var verb: String {
            switch self {
            case .send, .sendToken: return "SEND"
            case .swap: return "SWAP"
            }
        }

        /// The raw amount in the asset's own base units.
        public var amountWei: String {
            switch self {
            case .send(_, let v, _): return v
            case .sendToken(_, _, let v, _, _): return v
            case .swap(_, let v, _): return v
            }
        }

        /// ETH has 18; USDC has 6. Formatting a token as ETH renders it as zero.
        public var decimals: Int {
            switch self {
            case .send, .swap: return 18
            case .sendToken(_, _, _, _, let d): return d
            }
        }

        public var symbol: String {
            switch self {
            case .send, .swap: return "ETH"
            case .sendToken(_, _, _, let s, _): return s
            }
        }

        /// True when the amount is the chain's own coin, so it can be priced from the ETH rate.
        public var isNative: Bool {
            if case .sendToken = self { return false }
            return true
        }

        public var counterparty: String {
            switch self {
            case .send(let to, _, _): return to
            case .sendToken(_, let to, _, _, _): return to
            case .swap(let dex, _, _): return "DEX \(dex)"
            }
        }
    }

    public var isPending: Bool { status == "PENDING_HUMAN" }
    public var isSettled: Bool { ["EXECUTED", "FAILED", "REJECTED", "EXPIRED"].contains(status) }
}

public struct WalletInfo: Decodable, Sendable {
    public let gate: String
    public let chain: String
    public let balanceEth: String
    public let balanceUsd: String
    public let ethUsd: Double
    public let totalUsd: String
    public let holdings: [Holding]

    public struct Holding: Decodable, Identifiable, Sendable, Equatable {
        public let symbol: String
        public let name: String
        public let decimals: Int
        public let address: String?
        public let amount: String
        public let usd: String

        public var id: String { address ?? symbol }
        public var isNative: Bool { address == nil }
    }
    public let agent: String
    public let humanQx: String
    public let humanQy: String
    /// Ids of the hub's recent proposals, so a fresh launch can pick up anything still pending.
    public let proposals: [ProposalRef]?

    public struct ProposalRef: Decodable, Sendable { public let id: String }
    public var proposalIds: [String] { (proposals ?? []).map(\.id) }
}

public struct ChatTurn: Decodable, Sendable {
    public let role: String
    public let text: String
    public var mine: Bool { role == "user" }
}

public struct ChatReply: Decodable, Sendable {
    public let text: String
    public let proposalIds: [String]
}

public struct Registration: Decodable, Sendable {
    public let deviceId: String
    public let matchesGate: Bool
    public let gateHumanKey: String
    public let warning: String?
}

public enum HubError: Error, LocalizedError {
    case http(Int, String)
    case badURL(String)
    case unreachable(String, String)

    public var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "Hub returned \(code): \(body)"
        case .badURL(let s):
            return "Not a valid hub URL: \(s)"
        case .unreachable(let url, let why):
            return "Cannot reach \(url) — \(why). Check the Mac is running the hub and that "
                + "both devices are on the same Wi-Fi. On a phone, localhost means the phone."
        }
    }
}

/// Talks to the hub over plain HTTP on the local network. There is no auth: the security
/// boundary is the signature, not the transport, and everything here is testnet.
public actor HubClient {
    private let base: URL
    private let session: URLSession

    public init(baseURL: String) throws {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)) else {
            throw HubError.badURL(baseURL)
        }
        base = url
        let config = URLSessionConfiguration.default
        // A tool-calling turn can take a while; the default 60s is not always enough.
        config.timeoutIntervalForRequest = 120
        session = URLSession(configuration: config)
    }

    public func wallet() async throws -> WalletInfo {
        try await get("api/m/wallet")
    }

    public func register(publicKey: Data, kind: HumanKeyKind, label: String) async throws -> Registration {
        try await post(
            "api/m/device/register",
            ["publicKey": publicKey.hexString, "kind": kind.rawValue, "label": label]
        )
    }

    /// Mirrors the phone's contacts so the agent can turn "pay Jake $20" into an address.
    public func syncContacts(_ contacts: [Contact]) async throws {
        var request = URLRequest(url: base.appendingPathComponent("api/m/contacts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["contacts": contacts])
        _ = try await session.data(for: request)
    }

    /// Forgets the conversation on the hub as well as on the phone.
    public func clearChat() async throws {
        var request = URLRequest(url: base.appendingPathComponent("api/m/chat"))
        request.httpMethod = "DELETE"
        _ = try await session.data(for: request)
    }

    /// The conversation so far. The hub keeps it, so the chat survives closing the app —
    /// otherwise every relaunch looks like the agent has amnesia.
    public func history() async throws -> [ChatTurn] {
        struct Envelope: Decodable { let messages: [ChatTurn] }
        let envelope: Envelope = try await get("api/m/chat")
        return envelope.messages
    }

    public func send(message: String) async throws -> ChatReply {
        try await post("api/m/chat", ["text": message])
    }

    public func proposal(_ id: String) async throws -> MobileProposal {
        try await get("api/m/proposals/\(id)")
    }

    public func approve(_ id: String, signature: Data) async throws -> MobileProposal {
        try await post("api/m/proposals/\(id)/approve", ["signature": signature.hexString])
    }

    public func reject(_ id: String) async throws -> MobileProposal {
        try await post("api/m/proposals/\(id)/reject", [:])
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await run(URLRequest(url: base.appendingPathComponent(path)))
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: String]) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await run(request)
    }

    private func run<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // "Could not connect to the server" says nothing about which server or why.
            throw HubError.unreachable(base.absoluteString, error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            // Surface the hub's own message — it explains *why* a signature was refused, which
            // an HTTP status never will.
            throw HubError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
