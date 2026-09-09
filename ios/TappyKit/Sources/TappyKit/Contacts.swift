import Foundation

/// Someone you can pay by name. Addresses are unreadable and unmemorable, and asking a person
/// to paste 42 hex characters into a chat box is the worst part of every crypto app.
public struct Contact: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var handle: String
    public var address: String

    public init(id: String = UUID().uuidString, name: String, handle: String, address: String) {
        self.id = id
        self.name = name
        self.handle = handle.hasPrefix("$") ? handle : "$" + handle
        self.address = address
    }

    /// Deterministic per contact, so the same person is always the same colour.
    public var colorIndex: Int {
        abs(name.hashValue) % 6
    }

    public var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

/// Contacts live on the phone and are mirrored to the hub so the agent can resolve a name to an
/// address. The mirror is a convenience for the agent, not a source of truth — the phone still
/// re-derives and verifies the digest of whatever gets proposed, so a tampered contact list
/// cannot make you sign something you did not read.
@MainActor
public final class ContactStore: ObservableObject {
    @Published public private(set) var contacts: [Contact] = []

    private let key = "tappy.contacts"

    public init() {
        load()
        if contacts.isEmpty { contacts = ContactStore.seed }
    }

    /// A couple of demo entries so the picker is never an empty box on stage. Both are real
    /// addresses on Sepolia that can receive testnet ETH.
    public static let seed: [Contact] = [
        Contact(name: "Vitalik", handle: "$vitalik", address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"),
        Contact(name: "Demo Wallet", handle: "$demo", address: "0x19dB7F38a16899C99a8917098B72FE6Cf3cA0235"),
    ]

    public func add(_ contact: Contact) {
        contacts.removeAll { $0.address.lowercased() == contact.address.lowercased() }
        contacts.insert(contact, at: 0)
        save()
    }

    public func remove(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        save()
    }

    public func search(_ query: String) -> [Contact] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return contacts }
        return contacts.filter {
            $0.name.lowercased().contains(q)
                || $0.handle.lowercased().contains(q)
                || $0.address.lowercased().contains(q)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Contact].self, from: data)
        else { return }
        contacts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
