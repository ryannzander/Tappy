import TappyKit
import SwiftUI

@main
struct TappyApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(state).preferredColorScheme(.light)
        }
    }
}

/// One place that knows the hub URL, the key, the transcript and the pending proposal.
/// Small enough to hold in your head, which matters more than layering on a one-week build.
@MainActor
final class AppState: ObservableObject {
    @AppStorage("hubURL") var hubURL: String = "http://localhost:3000"

    @Published var key: HumanKey?
    @Published var registration: Registration?
    @Published var wallet: WalletInfo?
    @Published var transcript: [Bubble] = []
    @Published var pending: MobileProposal?
    @Published var recent: [MobileProposal] = []
    @Published var banner: String?
    @Published var busy = false
    /// Which tab is showing. Lives here, not in the view, so a wallet button can hand the user
    /// to the chat where its answer will actually appear.
    @Published var tab = 0

    struct Bubble: Identifiable {
        let id = UUID()
        let mine: Bool
        let text: String
    }

    private var poller: Task<Void, Never>?

    /// Dollars per ETH, from the hub. Zero until the first wallet fetch lands.
    var rate: Double { wallet?.ethUsd ?? 0 }

    /// Sends a message AND shows the chat, so a tap on the wallet screen visibly does something.
    func ask(_ text: String) async {
        tab = 0
        await send(text)
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
            if fresh.isSettled { pending = nil }
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
                    pending = proposal
                    LiveActivity.start(proposal, rate: rate)
                }
            }
        }
    }
}
