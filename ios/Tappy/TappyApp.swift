import TappyKit
import SwiftUI

@main
struct TappyApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.light)
                .task {
                    #if DEBUG
                    // Lets a screenshot reach the real screens without a device or a face.
                    // Debug-only and opt-in: it fabricates a software key and never touches
                    // the Enclave, so it can never be mistaken for the real approval path.
                    if ProcessInfo.processInfo.arguments.contains("-uiPreview") {
                        // `-tab N` is picked up by UserDefaults' argument domain for free.
                        state.tab = UserDefaults.standard.integer(forKey: "tab")
                        await state.previewSetUp()
                    }
                    #endif
                }
        }
    }
}

/// One place that knows the hub URL, the key, the transcript and the pending proposal.
/// Small enough to hold in your head, which matters more than layering on a one-week build.
@MainActor
final class AppState: ObservableObject {
    /// 3100, because 3000 is the port every other Next project on a laptop already took.
    @AppStorage("hubURL") var hubURL: String = "http://localhost:3100"

    @Published var key: HumanKey?
    @Published var registration: Registration?
    @Published var wallet: WalletInfo?
    @Published var transcript: [Bubble] = []
    @Published var pending: MobileProposal?
    @Published var recent: [MobileProposal] = []
    @Published var banner: String?
    @Published var busy = false
    /// Shown once a proposal settles, so a send ends with a receipt rather than a silent list.
    @Published var settled: MobileProposal?
    let contacts = ContactStore()
    /// Remembers who a proposal was for, so the receipt can say a name instead of hex.
    private var payee: [String: String] = [:]
    /// Which tab is showing. Lives here, not in the view, so a wallet button can hand the user
    /// to the chat where its answer will actually appear.
    @Published var tab = 0
    /// The tab bar steps aside while typing. Without this the keyboard sits on top of the
    /// composer and the text box becomes unreachable at the bottom of a long conversation.
    @Published var keyboardUp = false

    struct Bubble: Identifiable {
        let id = UUID()
        let mine: Bool
        let text: String
    }

    private var poller: Task<Void, Never>?

    /// Dollars per ETH, from the hub. Zero until the first wallet fetch lands.
    var rate: Double { wallet?.ethUsd ?? 0 }

    /// Sends a message AND shows the chat, so a tap elsewhere visibly does something.
    func ask(_ text: String) async {
        tab = 1
        await send(text)
    }

    /// Fired from a recipient. Writes the sentence; the agent proposes; your face decides.
    func payAmount(_ dollars: Double, to contact: Contact) async {
        await pay(dollars, to: contact)
    }

    /// The Pay button. It does not move money — it asks the agent to propose, which is the
    /// whole product: a button that requests, and a face that approves.
    func pay(_ dollars: Double, to contact: Contact) async {
        pendingPayeeName = contact.name
        await ask("Send $\(String(format: "%.2f", dollars)) to \(contact.name) at \(contact.address).")
    }

    private var pendingPayeeName: String?

    func addContact(_ contact: Contact) {
        contacts.add(contact)
        Task { try? await client().syncContacts(contacts.contacts) }
    }

    func name(for proposal: MobileProposal) -> String? {
        if let remembered = payee[proposal.id] { return remembered }
        let target = proposal.action.counterparty.lowercased()
        return contacts.contacts.first { target.contains($0.address.lowercased()) }?.name
    }

    var keyStatus: String {
        switch key?.kind {
        case .enclave: return "Secure Enclave"
        case .software: return "Software key (Simulator)"
        case nil: return "No key"
        }
    }

    private func client() throws -> HubClient { try HubClient(baseURL: hubURL) }

    /// Generates the key on first launch and tells the hub about it. Prefers the Enclave and
    /// falls back to software only where there is no Enclave to use — and says which, loudly,
    /// because a demo that silently downgrades its own security claim is worse than one that
    /// fails.
    #if DEBUG
    /// Screenshot path: a software key and a real hub fetch, so layouts can be checked without
    /// a device or a face. Never touches the Enclave, so it cannot be confused for the real thing.
    func previewSetUp() async {
        key = try? SoftwareHumanKey()
        guard let hub = try? client() else { return }
        registration = try? await hub.register(publicKey: key?.publicKey ?? Data(),
                                               kind: .software, label: "Preview")
        wallet = try? await hub.wallet()
        try? await hub.syncContacts(contacts.contacts)
    }
    #endif

    func setUp() async {
        busy = true
        defer { busy = false }
        do {
            if key == nil {
                key = EnclaveHumanKey.isAvailable
                    ? try EnclaveHumanKey()
                    : try SoftwareHumanKey()
            }
            guard let key else { return }
            let hub = try client()
            registration = try await hub.register(
                publicKey: key.publicKey,
                kind: key.kind,
                label: UIDevice.current.name
            )
            wallet = try await hub.wallet()
            try? await hub.syncContacts(contacts.contacts)
            if let warning = registration?.warning { banner = warning }
            startPolling()
        } catch {
            banner = error.localizedDescription
        }
    }

    func send(_ text: String) async {
        transcript.append(Bubble(mine: true, text: text))
        busy = true
        defer { busy = false }
        do {
            let reply = try await client().send(message: text)
            if !reply.text.isEmpty { transcript.append(Bubble(mine: false, text: reply.text)) }
            await track(reply.proposalIds)
            await refresh()
        } catch {
            let message = error.localizedDescription
            transcript.append(Bubble(mine: false, text: "⚠️ \(message)"))
            banner = message
        }
    }

    /// The proposal is verified and signed here; the Face ID prompt comes from the Enclave.
    func approve(_ proposal: MobileProposal) async {
        guard let key else { return }
        busy = true
        defer { busy = false }
        do {
            let signature = try await Approval.sign(
                proposal,
                with: key,
                reason: "Authorize \(proposal.action.verb.capitalized) \(Format.usd(wei: proposal.action.amountWei, rate: rate))"
            )
            _ = try await client().approve(proposal.id, signature: signature)
            pending = nil
            await refresh()
        } catch {
            banner = error.localizedDescription
        }
    }

    func reject(_ proposal: MobileProposal) async {
        do {
            _ = try await client().reject(proposal.id)
            pending = nil
            await refresh()
        } catch {
            banner = error.localizedDescription
        }
    }

    func refresh() async {
        guard let hub = try? client() else { return }
        wallet = try? await hub.wallet()
        var updated: [MobileProposal] = []
        for proposal in recent + (pending.map { [$0] } ?? []) {
            if let fresh = try? await hub.proposal(proposal.id) { updated.append(fresh) }
        }
        recent = updated
    }

    /// One second is invisible next to a human picking up a phone, and it needs no socket.
    private func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() async {
        guard let hub = try? client() else { return }
        // Anything still awaiting a human comes to the front of the app immediately.
        for proposal in recent where proposal.isPending {
            if let fresh = try? await hub.proposal(proposal.id), fresh.isPending {
                if pending?.id != fresh.id {
                    pending = fresh
                    LiveActivity.start(fresh, rate: rate)
                }
                return
            }
        }
        if let current = pending, let fresh = try? await hub.proposal(current.id) {
            await LiveActivity.update(fresh, rate: rate)
            if fresh.isSettled {
                pending = nil
                settled = fresh
            }
        }
        await refreshStatusesOnly(hub)
    }

    private func refreshStatusesOnly(_ hub: HubClient) async {
        var updated: [MobileProposal] = []
        for proposal in recent {
            let fresh = proposal.isSettled ? proposal : ((try? await hub.proposal(proposal.id)) ?? proposal)
            if fresh.status != proposal.status { await LiveActivity.update(fresh, rate: rate) }
            updated.append(fresh)
        }
        if updated != recent { recent = updated }
    }

    func track(_ ids: [String]) async {
        guard let hub = try? client() else { return }
        for id in ids where !recent.contains(where: { $0.id == id }) {
            if let proposal = try? await hub.proposal(id) {
                recent.insert(proposal, at: 0)
                if proposal.isPending {
                    if let name = pendingPayeeName {
                        payee[proposal.id] = name
                        pendingPayeeName = nil
                    }
                    pending = proposal
                    LiveActivity.start(proposal, rate: rate)
                }
            }
        }
    }
}
