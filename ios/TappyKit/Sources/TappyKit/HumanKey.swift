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
            return "This device has no Secure Enclave. Run on a real iPhone."
        case .keychainFailure(let status):
            return "Keychain error \(status)"
        case .noKey:
            return "No key has been generated yet"
        }
    }
}

/// LocalAuthentication reports almost everything as "Authentication failed", which tells you
/// nothing and is impossible to act on. These are the cases that actually happen, with the fix
/// in the message — a demo that fails silently at the biometric is a demo that is over.
public func readableAuthError(_ error: Error) -> String {
    if let la = error as? LAError {
        switch la.code {
        case .biometryNotEnrolled:
            return "No Face ID is enrolled. On Simulator: Features ▸ Face ID ▸ Enrolled. On iPhone: set up Face ID in Settings."
        case .passcodeNotSet:
            return "This device has no passcode. The key requires one — set a passcode in Settings, then try again."
        case .biometryNotAvailable:
            return "Face ID is unavailable to this app. Check that NSFaceIDUsageDescription is in Info.plist."
        case .biometryLockout:
            return "Face ID is locked out after too many failures. Unlock the device with its passcode first."
        case .userCancel, .appCancel, .systemCancel:
            return "Cancelled."
        case .authenticationFailed:
            return "Face ID did not match. On Simulator use Features ▸ Face ID ▸ Matching Face."
        default:
            // LocalAuthentication returns codes that are not in LAError.Code — -1020 shows up
            // when the Secure Enclave refuses because no biometric is enrolled. Say the thing
            // that fixes it rather than printing a number nobody can look up.
            return enrollmentHint("Face ID could not be used (error \(la.code.rawValue)).")
        }
    }
    let ns = error as NSError
    // -25293 is errSecAuthFailed, which the Enclave returns when the ACL cannot be satisfied.
    if ns.code == -25293 {
        return "The Secure Enclave refused the key. The passcode or enrolled face probably changed since it was created — delete and reinstall the app to make a fresh one."
    }
    if ns.domain.contains("LocalAuthentication") || ns.code == -1020 {
        return enrollmentHint("The Secure Enclave refused (error \(ns.code)).")
    }
    return error.localizedDescription
}

/// Every route to a failed Enclave key on a fresh device comes down to the same two setup steps,
/// so say them rather than making someone search an error number.
private func enrollmentHint(_ lead: String) -> String {
    lead + " On Simulator: Features ▸ Face ID ▸ Enrolled, then relaunch. "
        + "On iPhone: set a device passcode and enrol Face ID in Settings."
}

public enum HumanKeySigning {
    /// What actually gets signed. `SecureEnclave.P256.Signing.PrivateKey.signature(for:)` runs
    /// SHA-256 over its input and offers no way to opt out, so the message is sha256(digest),
    /// never the digest. `TappyGate` verifies exactly this, and `vectors/p256.json` pins it.
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

    // Deliberately still says "flippy". These are opaque Keychain identifiers, and renaming
    // them orphans the key already generated on a real device — the phone would silently make
    // a second key that the deployed gate does not accept.
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
        do {
            key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        } catch {
            // Rethrow with a message that names the fix rather than "Authentication failed".
            throw NSError(
                domain: "Tappy", code: (error as NSError).code,
                userInfo: [NSLocalizedDescriptionKey: readableAuthError(error)]
            )
        }
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
        do {
            return try authed.signature(for: digest).rawRepresentation
        } catch {
            throw NSError(
                domain: "Tappy", code: (error as NSError).code,
                userInfo: [NSLocalizedDescriptionKey: readableAuthError(error)]
            )
        }
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
