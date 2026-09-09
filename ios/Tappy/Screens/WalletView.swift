import SwiftUI
import TappyKit

/// The Phantom shape — big balance, action tiles, holdings list — in light.
struct WalletView: View {
    @EnvironmentObject private var state: AppState
    @State private var showSecurity = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    header
                    balance
                    actions
                    securityCard
                    activity
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, 18)
            }
            .refreshable { await state.refresh() }
        }
        .sheet(isPresented: $showSecurity) { SecuritySheet() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 42, height: 42)
                TappyMark(size: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(state.wallet.map { Format.short($0.gate, lead: 6, tail: 4) } ?? "not connected")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.dim)
                Text("Tappy Wallet").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { Task { await state.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .background(Theme.surface, in: Circle())
            }
        }
        .padding(.top, 8)
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.wallet.map { "\($0.balanceEth.prefix(8)) ETH" } ?? "—")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(state.wallet?.chain ?? "Sepolia")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accentSoft, in: Capsule())
                    .foregroundStyle(Theme.accent)
                Text("testnet").font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionTile("paperplane.fill", "Send", "send 0.01 ETH to ")
            actionTile("arrow.2.squarepath", "Swap", "swap 0.01 ETH for FLIP")
            actionTile("qrcode", "Receive", "what's my wallet address?")
            actionTile("chart.line.uptrend.xyaxis", "Activity", "list my recent transactions")
        }
    }

    /// Every action is a sentence sent to the agent. There is no direct path from a button to
    /// the chain — the agent proposes, you approve. That is the product, not a limitation.
    private func actionTile(_ icon: String, _ label: String, _ prompt: String) -> some View {
        Button {
            Task { await state.send(prompt) }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.accent)
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var securityCard: some View {
        Button { showSecurity = true } label: {
            HStack(spacing: 12) {
                Image(systemName: enclave ? "lock.shield.fill" : "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(enclave ? Theme.up : Theme.down)
                VStack(alignment: .leading, spacing: 2) {
                    Text(enclave ? "Protected by Secure Enclave" : "Software key in use")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(gateOK ? "This iPhone can approve transactions" : "This key is not accepted by the wallet")
                        .font(.system(size: 13))
                        .foregroundStyle(gateOK ? Theme.dim : Theme.down)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.dim)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var enclave: Bool { state.key?.kind == .enclave }
    private var gateOK: Bool { state.registration?.matchesGate ?? true }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
            if state.recent.isEmpty {
                Text("Nothing yet. Ask Tappy to move some money.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.dim)
                    .padding(.vertical, 8)
            } else {
                ForEach(state.recent) { ProposalCard(proposal: $0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SecuritySheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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

                    Text("How it works")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 10)

                    Text("""
                        This wallet needs two signatures to move anything.

                        The AI holds one and can only ever propose. The other is sealed inside \
                        this iPhone's Secure Enclave — it cannot be exported, copied or backed \
                        up, and it signs only after your face.

                        The contract checks both on-chain. Either key alone moves nothing.
                        """)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.dim)
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false, ok: Bool? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.dim)
            Text(value)
                .font(mono ? .system(size: 14, design: .monospaced) : .system(size: 16, weight: .medium))
                .foregroundStyle(ok == false ? Theme.down : Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
