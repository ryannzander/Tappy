import CryptoKit
import Foundation
import LocalAuthentication

public enum HumanKeyKind: String, Codable, Sendable {
    case enclave = "p256-enclave"
    case software = "p256-software"
}

public enum HumanKeyError: Error, LocalizedError {
    case enclaveUnavailable
    case keychainFailure(OSStatus)
    case noKey

    public var errorDescription: String? {
        switch self {
        case .enclaveUnavailable:
            return "This device has no Secure Enclave. The Simulator never does — run on a real iPhone."
        case .keychainFailure(let status):
            return "Keychain error \(status)"
        case .noKey:
            return "No key has been generated yet"
        }
    }
}

public enum HumanKeySigning {
    /// What actually gets signed. `SecureEnclave.P256.Signing.PrivateKey.signature(for:)` runs
    /// SHA-256 over its input and offers no way to opt out, so the message is sha256(digest),
    /// never the digest. `FlippyGate` verifies exactly this, and `vectors/p256.json` pins it.
    public static func enclaveMessage(for digest: Data) -> Data {
        Data(SHA256.hash(data: digest))
    }
}

/// The human half of the 2-of-2, as the phone sees it.
public protocol HumanKey {
    var kind: HumanKeyKind { get }
    /// 64 bytes: qx ‖ qy. This is what the gate is deployed with.
    var publicKey: Data { get }
    /// 64 bytes: r ‖ s. Prompts Face ID on the Enclave implementation.
    func sign(digest: Data, reason: String) async throws -> Data
}

/// The real thing. The private key is generated inside the Secure Enclave and never exists
/// outside it — not in this app's memory, not in a backup, not after a jailbreak. All we ever
/// hold is an opaque blob that only this Enclave can use.
public struct EnclaveHumanKey: HumanKey {
    public let kind = HumanKeyKind.enclave
    private let key: SecureEnclave.P256.Signing.PrivateKey

    public var publicKey: Data {
        // x963 is 0x04 ‖ qx ‖ qy; the gate wants the point without the prefix byte.
        key.publicKey.x963Representation.dropFirst()
    }

    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    private static let account = "flippy.human.enclave"

    public init(loadingOrCreating: Bool = true) throws {
        guard SecureEnclave.isAvailable else { throw HumanKeyError.enclaveUnavailable }
        if let blob = try? Self.loadBlob() {
            key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
            return
        }
        guard loadingOrCreating else { throw HumanKeyError.noKey }

        // .biometryCurrentSet destroys the key if a face or fingerprint is enrolled later, so
        // adding a face cannot be used to steal signing authority. ...ThisDeviceOnly keeps the
        // blob out of iCloud backups.
        var error: Unmanaged<CFError>?
        guard
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [.privateKeyUsage, .biometryCurrentSet],
                &error
            )
        else {
            throw error!.takeRetainedValue() as Error
        }
        key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        try Self.storeBlob(key.dataRepresentation)
    }

    public func sign(digest: Data, reason: String) async throws -> Data {
        let context = LAContext()
        context.localizedReason = reason
        // Re-open the key with this context so the Face ID prompt carries our wording.
        let authed = try SecureEnclave.P256.Signing.PrivateKey(
            dataRepresentation: key.dataRepresentation,
            authenticationContext: context
        )
        return try authed.signature(for: digest).rawRepresentation
    }

    private static func loadBlob() throws -> Data {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw HumanKeyError.keychainFailure(status)
        }
        return data
    }

    private static func storeBlob(_ blob: Data) throws {
        var query = baseQuery()
        query[kSecValueData as String] = blob
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw HumanKeyError.keychainFailure(status) }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "flippy",
            kSecAttrAccount as String: account,
        ]
    }
}

/// For the Simulator and for tests, which have no Secure Enclave. Signs with the same curve
/// over the same message, so everything downstream is identical — but the key is ordinary
/// memory, so the UI must never present it as though it were the real thing.
public struct SoftwareHumanKey: HumanKey {
    public let kind = HumanKeyKind.software
    private let key: P256.Signing.PrivateKey

    public var publicKey: Data { key.publicKey.x963Representation.dropFirst() }

    public init(raw: Data? = nil) throws {
        key = try raw.map { try P256.Signing.PrivateKey(rawRepresentation: $0) } ?? P256.Signing.PrivateKey()
    }

    public var rawRepresentation: Data { key.rawRepresentation }

    public func sign(digest: Data, reason: String) async throws -> Data {
        try key.signature(for: digest).rawRepresentation
    }
}
