import SwiftUI
import TappyKit

/// Wise's home: who you are, what you have, what you can do with it, and what just happened.
/// Every action here is a sentence sent to the agent — there is no direct path from a button
/// to the chain, because the agent proposes and only your face approves.
struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var showSecurity = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    topBar
                    Text("Welcome to Tappy")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    chips
                    balanceCard
                    holdings
                    security
                    transactions
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
            .refreshable { await state.refresh() }
        }
        .sheet(isPresented: $showSecurity) { SecuritySheet() }
    }

    private var topBar: some View {
        HStack {
            ZStack(alignment: .bottomTrailing) {
                Circle().stroke(Theme.hairline, lineWidth: 1.5).frame(width: 46, height: 46)
                Text("TY").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 46, height: 46)
                Circle()
                    .fill(state.registration?.matchesGate == false ? Theme.down : Theme.up)
                    .frame(width: 12, height: 12)
            }
            Spacer()
            Text(state.wallet?.chain ?? "Sepolia")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Theme.lime, in: Capsule())
            Button { Task { await state.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { Task { await state.ask("I want to send money — who should it go to?") } } label: {
                    Chip(label: "Send", selected: true)
                }
                Button { Task { await state.ask("Swap $25 of ETH for FLIP.") } } label: {
                    Chip(label: "Swap")
                }
                Button { Task { await state.ask("What is my wallet address?") } } label: {
                    Chip(label: "Receive")
                }
                Button { state.tab = 2 } label: { Chip(label: "Recipients") }
            }
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.ink).frame(width: 46, height: 46)
                    Text("Ξ").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.lime)
                }
                Text("Total").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
            }
            Spacer(minLength: 40)
            HStack(spacing: 6) {
                Image(systemName: "building.columns").font(.system(size: 13)).foregroundStyle(Theme.dim)
                Text(state.wallet.map { Format.short($0.gate, lead: 6, tail: 4) } ?? "not connected")
                    .font(.system(size: 14)).foregroundStyle(Theme.dim)
            }
            Text(state.wallet.map { "$\($0.totalUsd)" } ?? "—")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(state.wallet.map { "\($0.holdings.count) coin\($0.holdings.count == 1 ? "" : "s")" } ?? " ")
                .font(.system(size: 14)).foregroundStyle(Theme.dim)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    /// What the wallet actually holds. Empty tokens are filtered out by the hub, so this is
    /// holdings rather than a catalogue of everything that exists.
    private var holdings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coins").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
            ForEach(state.wallet?.holdings ?? []) { coin in
                Button {
                    Task { await state.ask("I want to send some \(coin.symbol) — who should it go to?") }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(coin.isNative ? Theme.ink : Theme.lime)
                                .frame(width: 42, height: 42)
                            Text(String(coin.symbol.prefix(2)).uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(coin.isNative ? Theme.lime : Theme.ink)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coin.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(coin.name).font(.system(size: 13)).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("$" + coin.usd)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(coin.amount).font(.system(size: 13)).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var security: some View {
        Button { showSecurity = true } label: {
            HStack(spacing: 14) {
                CircleGlyph(systemName: ok ? "lock.fill" : "exclamationmark.triangle.fill",
                            filled: ok ? Theme.lime : Theme.dangerSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ok ? "This iPhone can approve" : "This iPhone cannot approve yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(state.keyStatus).font(.system(size: 14)).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.dim)
            }
        }
    }

    private var ok: Bool {
        state.key?.kind == .enclave && (state.registration?.matchesGate ?? true)
    }

    private var transactions: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Transactions").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
                if !state.recent.isEmpty {
                    Button { Task { await state.ask("List my recent transactions.") } } label: {
                        Text("See all")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .underline()
                    }
                }
            }
            if state.recent.isEmpty {
                Text("Nothing yet. Ask Tappy to move some money.")
                    .font(.system(size: 15)).foregroundStyle(Theme.dim)
            } else {
                ForEach(state.recent) { proposal in
                    Button { state.settled = proposal } label: {
                        TransactionRow(proposal: proposal, rate: state.rate, name: state.name(for: proposal))
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

/// Wise's transaction row: circle, two lines of text, amount on the right.
struct TransactionRow: View {
    let proposal: MobileProposal
    let rate: Double
    let name: String?

    var body: some View {
        HStack(spacing: 14) {
            CircleGlyph(systemName: glyph)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("- " + Format.usd(wei: proposal.action.amountWei, rate: rate))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colour)
                Text(Format.asset(proposal.action, rate: rate))
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 6)
    }

    private var title: String {
        if proposal.action.verb == "SWAP" { return "Swap to FLIP" }
        return "To " + (name ?? Format.short(proposal.action.counterparty, lead: 6, tail: 4))
    }

    private var subtitle: String {
        switch proposal.status {
        case "PENDING_HUMAN": return "Waiting for you"
        case "SUBMITTED": return "Sending"
        case "EXECUTED": return "Sent"
        case "REJECTED": return "Declined"
        case "EXPIRED": return "Expired"
        default: return "Failed"
        }
    }

    private var glyph: String {
        switch proposal.status {
        case "PENDING_HUMAN": return "faceid"
        case "SUBMITTED": return "arrow.up"
        case "EXECUTED": return "checkmark"
        default: return "xmark"
        }
    }

    private var colour: Color {
        switch proposal.status {
        case "EXECUTED": return Theme.up
        case "REJECTED", "FAILED", "EXPIRED": return Theme.dim
        default: return Theme.ink
        }
    }
}

struct SecuritySheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("HOW YOUR\nMONEY IS HELD")
                        .font(.display(32))
                        .foregroundStyle(Theme.ink)
                        .padding(.bottom, 20)

                    row("This device", state.keyStatus, ok: state.key?.kind == .enclave)
                    if let registration = state.registration {
                        row("Accepted by the wallet",
                            registration.matchesGate ? "Yes" : "No — approvals will be rejected",
                            ok: registration.matchesGate)
                    }
                    if let wallet = state.wallet {
                        row("Wallet", Format.short(wallet.gate, lead: 12, tail: 8), mono: true)
                        row("The AI's key", Format.short(wallet.agent, lead: 12, tail: 8), mono: true)
                    }

                    Text("""
                        This wallet needs two signatures to move anything.

                        The AI holds one and can only ever propose. The other is sealed inside \
                        this iPhone's Secure Enclave — it cannot be exported, copied or backed \
                        up, and it signs only after your face.

                        The contract checks both on-chain. Either key alone moves nothing.
                        """)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.dim)
                        .padding(.top, 18)
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false, ok: Bool? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.dim)
            Text(value)
                .font(mono ? .system(size: 14, design: .monospaced) : .system(size: 16, weight: .semibold))
                .foregroundStyle(ok == false ? Theme.down : Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 0.5) }
    }
}
