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
        case swap(dex: String, sellWei: String, tokenOut: String)

        private enum Keys: String, CodingKey {
            case kind, to, valueWei, memo, dex, sellWei, tokenOut
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
            case .send: return "SEND"
            case .swap: return "SWAP"
            }
        }

        public var amountWei: String {
            switch self {
            case .send(_, let v, _): return v
            case .swap(_, let v, _): return v
            }
        }

        public var counterparty: String {
            switch self {
            case .send(let to, _, _): return to
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
    public let agent: String
    public let humanQx: String
    public let humanQy: String
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

    public var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "hub returned \(code): \(body)"
        case .badURL(let s): return "not a valid hub URL: \(s)"
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
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            // Surface the hub's own message — it explains *why* a signature was refused, which
            // an HTTP status never will.
            throw HubError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
