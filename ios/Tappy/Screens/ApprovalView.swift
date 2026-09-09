import SwiftUI
import TappyKit

/// The one screen that matters, shaped like Phantom's amount sheet: one enormous number,
/// everything else quiet around it. Every value here is derived from the call this phone
/// re-hashed itself — nothing on screen is text the server asked us to display.
struct ApprovalView: View {
    let proposal: MobileProposal
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var recomputed: String? { try? Approval.recomputeDigest(proposal).hexString }
    private var verified: Bool { recomputed?.lowercased() == proposal.id.lowercased() }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                grabber
                title
                Spacer()
                amount
                counterparty
                Spacer()
                verification
                buttons
            }
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Theme.hairline)
            .frame(width: 38, height: 5)
            .padding(.top, 10)
    }

    private var title: some View {
        HStack {
            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 36, height: 36)
                Image(systemName: proposal.action.verb == "SEND" ? "paperplane.fill" : "arrow.2.squarepath")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
            }
            Text(proposal.action.verb == "SEND" ? "Send ETH" : "Swap ETH")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                Task { await state.reject(proposal); dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    private var amount: some View {
        VStack(spacing: 6) {
            Text(Format.usd(wei: proposal.action.amountWei, rate: state.rate))
                .font(.system(size: 62, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.horizontal, 20)
            Text(Format.eth(wei: proposal.action.amountWei))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
    }

    private var counterparty: some View {
        VStack(spacing: 8) {
            Text(proposal.action.verb == "SEND" ? "TO" : "VIA")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Theme.dim)
            Text(proposal.action.counterparty)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
        .padding(.top, 30)
    }

    private var verification: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                Text(verified ? "Verified on this iPhone" : "Digest mismatch — do not approve")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(verified ? Theme.up : Theme.down)

            Text(verified
                 ? "This phone rebuilt the transaction hash itself. The server cannot change what you are signing."
                 : "What the server sent does not hash to what it claims. Signing is disabled.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 36)

            Text(Format.short(proposal.id, lead: 10, tail: 8))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.dim.opacity(0.7))
        }
        .padding(.bottom, 22)
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            if verified {
                Button {
                    Task { await state.approve(proposal); dismiss() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                        Text(state.busy ? "Signing…" : "Approve")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(state.busy)
            }

            Button {
                Task { await state.reject(proposal); dismiss() }
            } label: {
                Text("Decline")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.down)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
    }
}
