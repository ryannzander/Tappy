import SwiftUI
import TappyKit

/// The one screen that matters. Everything on it is derived from the call this phone re-hashed
/// itself — nothing here is text the server asked us to display, which is the difference
/// between a hardware wallet and a screen that shows whatever it is told.
struct ApprovalView: View {
    let proposal: MobileProposal
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var recomputed: String? { try? Approval.recomputeDigest(proposal).hexString }
    private var verified: Bool { recomputed?.lowercased() == proposal.id.lowercased() }
    private var name: String? { state.name(for: proposal) }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                summary
                Spacer(minLength: 0)
                detail
                Spacer(minLength: 0)
                buttons
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 10) {
            HStack {
                Button { Task { await state.reject(proposal); dismiss() } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 42, height: 42)
                        .background(Theme.surfaceDeep, in: Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            CircleGlyph(systemName: proposal.action.verb == "SWAP" ? "arrow.2.squarepath" : "arrow.up",
                        size: 62, filled: Theme.lime)

            Text(proposal.action.verb == "SWAP" ? "Swapping" : "Sending")
                .font(.system(size: 15)).foregroundStyle(Theme.dim)

            Text(Format.usd(wei: proposal.action.amountWei, rate: state.rate))
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.horizontal, 20)

            Text(Format.eth(wei: proposal.action.amountWei))
                .font(.system(size: 15)).foregroundStyle(Theme.dim)

            HStack(spacing: 6) {
                Image(systemName: "arrow.right").font(.system(size: 12))
                Text(name ?? Format.short(proposal.action.counterparty, lead: 10, tail: 6))
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Theme.bg, in: Capsule())
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            step(done: true, "Tappy prepared this", "The AI can propose. It cannot send.")
            step(done: verified,
                 verified ? "This iPhone checked it" : "This iPhone rejected it",
                 verified
                    ? "The transaction hash was rebuilt here. The server cannot change what you sign."
                    : "What the server sent does not hash to what it claims. Signing is disabled.",
                 bad: !verified)
            step(done: false, "Your face approves it", "The key never leaves the Secure Enclave.")

            Text(Format.short(proposal.id, lead: 12, tail: 10))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.dim.opacity(0.8))
                .padding(.leading, 34)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    private func step(done: Bool, _ title: String, _ body: String, bad: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                if bad {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.down)
                } else if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.up)
                } else {
                    Circle().fill(Theme.lime).frame(width: 11, height: 11)
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(bad ? Theme.down : Theme.ink)
                Text(body).font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if verified {
                Button { Task { await state.approve(proposal); dismiss() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                        Text(state.busy ? "Signing…" : "Approve")
                    }
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(state.busy)
            }
            Button { Task { await state.reject(proposal); dismiss() } } label: {
                Text("Decline")
            }
            .buttonStyle(QuietButtonStyle(tint: Theme.dangerSoft, ink: Theme.down))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 16)
    }
}

/// Wise's transaction detail: grey summary on top, a timeline of what happened underneath.
struct TransactionView: View {
    let proposal: MobileProposal
    let contactName: String?

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                summary
                timeline
                Spacer()
                buttons
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 8) {
            CircleGlyph(systemName: glyph, size: 62, filled: tint)
            Text(verb).font(.system(size: 15)).foregroundStyle(Theme.dim).padding(.top, 4)
            Text(Format.usd(wei: proposal.action.amountWei, rate: state.rate))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("To " + (contactName ?? Format.short(proposal.action.counterparty, lead: 8, tail: 6)))
                .font(.system(size: 15)).foregroundStyle(Theme.dim)
            Text(status)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Theme.bg, in: Capsule())
                .padding(.top, 6)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .background(Theme.surface)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            line(true, "Tappy prepared it")
            line(proposal.status != "REJECTED", "You approved it with Face ID")
            line(["SUBMITTED", "EXECUTED"].contains(proposal.status), "Sent to Sepolia")
            line(proposal.status == "EXECUTED", "The network confirmed it")
        }
        .padding(20)
    }

    private func line(_ done: Bool, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: done ? "checkmark" : "circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(done ? Theme.up : Theme.dim.opacity(0.5))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 15, weight: done ? .semibold : .regular))
                .foregroundStyle(done ? Theme.ink : Theme.dim)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if let explorer = proposal.explorer, let url = URL(string: explorer) {
                Button { openURL(url) } label: { Text("View receipt") }
                    .buttonStyle(QuietButtonStyle())
            }
            Button { dismiss() } label: { Text("Done") }
                .buttonStyle(LimeButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
    }

    private var verb: String { proposal.action.verb == "SWAP" ? "Swapped" : "Sent" }

    private var status: String {
        switch proposal.status {
        case "EXECUTED": return "Completed"
        case "SUBMITTED": return "On its way"
        case "REJECTED": return "You declined it"
        case "EXPIRED": return "Expired"
        default: return "Failed"
        }
    }

    private var glyph: String {
        switch proposal.status {
        case "EXECUTED": return "checkmark"
        case "SUBMITTED": return "arrow.up"
        default: return "xmark"
        }
    }

    private var tint: Color {
        switch proposal.status {
        case "EXECUTED": return Theme.lime
        case "SUBMITTED": return Theme.surfaceDeep
        default: return Theme.dangerSoft
        }
    }
}
