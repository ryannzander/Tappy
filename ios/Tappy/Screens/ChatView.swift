import SwiftUI
import TappyKit

struct ChatView: View {
    @EnvironmentObject private var state: AppState
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private let suggestions: [(String, String)] = [
        ("Send $25", "to an address"),
        ("Buy $25 of FLIP", "on the demo exchange"),
        ("What's in my wallet?", "balance and keys"),
        ("Tell me about FLIP", "read the token listing"),
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                transcript
                if state.transcript.isEmpty { suggestionRow }
                composer
            }
        }
    }

    private var header: some View {
        HStack {
            Spacer().frame(width: 38)
            Spacer()

            HStack(spacing: 4) {
                TappyMark(size: 18)
                Text("tappy").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
            }

            Spacer()

            Button {
                state.transcript.removeAll()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .liquidGlass(.circle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(state.transcript) { bubble in
                        BubbleView(bubble: bubble).id(bubble.id)
                    }
                    ForEach(state.recent) { proposal in
                        ProposalCard(proposal: proposal, rate: state.rate).id(proposal.id)
                    }
                    if state.busy { TypingDots() }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: state.transcript.count) { _, _ in
                withAnimation { proxy.scrollTo(state.transcript.last?.id, anchor: .bottom) }
            }
        }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(suggestions, id: \.0) { title, subtitle in
                    Button {
                        Task { await state.ask(title) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(subtitle)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.dim)
                        }
                        .multilineTextAlignment(.leading)
                        .padding(14)
                        .frame(width: 210, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, 10)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.ink)

            TextField("Ask Tappy", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(Theme.ink)
                .focused($composerFocused)
                .lineLimit(1...5)

            Button(action: submit) {
                Image(systemName: draft.isEmpty ? "waveform" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(draft.isEmpty ? Theme.ink : Theme.accent, in: Circle())
            }
            .disabled(state.busy || draft.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(.capsule)
        .overlay(Capsule().stroke(Theme.hairline.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 3)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await state.send(text) }
    }
}

struct BubbleView: View {
    let bubble: AppState.Bubble

    var body: some View {
        HStack {
            if bubble.mine {
                Spacer(minLength: 50)
                Text(bubble.text)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            } else {
                // The assistant speaks in plain text, not a bubble — it is the page, not a guest
                // on it. Same shape as every chat app anyone already uses.
                Text(bubble.text)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }
}

struct TypingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.dim)
                    .frame(width: 7, height: 7)
                    .opacity(phase == Double(i) ? 1 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever()) { phase = 2 }
        }
    }
}

struct ProposalCard: View {
    let proposal: MobileProposal
    let rate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(proposal.action.verb)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(statusColor)
                }
            }

            Text(Format.usd(wei: proposal.action.amountWei, rate: rate))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(Format.eth(wei: proposal.action.amountWei))
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)

            Text(Format.short(proposal.action.counterparty, lead: 12, tail: 6))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.dim)

            if let explorer = proposal.explorer, let url = URL(string: explorer) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("View on Etherscan")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }
            if let error = proposal.error {
                Text(error).font(.caption2).foregroundStyle(Theme.down)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var statusLabel: String {
        switch proposal.status {
        case "PENDING_HUMAN": return "Waiting for you"
        case "SUBMITTED": return "Submitting"
        case "EXECUTED": return "Done"
        case "REJECTED": return "Declined"
        case "EXPIRED": return "Expired"
        default: return "Failed"
        }
    }

    private var statusColor: Color {
        switch proposal.status {
        case "EXECUTED": return Theme.up
        case "REJECTED", "FAILED", "EXPIRED": return Theme.down
        default: return .orange
        }
    }
}
