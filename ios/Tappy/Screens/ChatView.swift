import SwiftUI
import TappyKit

struct ChatView: View {
    @EnvironmentObject private var state: AppState
    @State private var draft = ""
    @FocusState private var typing: Bool

    private let suggestions: [(String, String)] = [
        ("Pay Vitalik $10", "from your recipients"),
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
            Text("Ask Tappy").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
            Spacer()
            if !state.transcript.isEmpty {
                Button { state.transcript.removeAll() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                        .background(Theme.surface, in: Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(state.transcript) { bubble in
                        BubbleView(bubble: bubble).id(bubble.id)
                    }
                    ForEach(state.recent.filter(\.isPending)) { proposal in
                        PendingCard(proposal: proposal, rate: state.rate).id(proposal.id)
                    }
                    if state.busy { TypingDots() }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: state.transcript.count) { _, _ in
                withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: typing) { _, focused in
                state.keyboardUp = focused
                guard focused else { return }
                // Opening the keyboard should reveal the newest message, not hide it.
                withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
        }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(suggestions, id: \.0) { title, subtitle in
                    Button { Task { await state.ask(title) } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.dim)
                        }
                        .multilineTextAlignment(.leading)
                        .padding(14)
                        .frame(width: 200, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 10)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask Tappy to move money", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .focused($typing)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .background(draft.isEmpty ? Theme.surfaceDeep : Theme.lime, in: Circle())
            }
            .disabled(state.busy || draft.isEmpty)
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Theme.surface, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, state.keyboardUp ? 8 : 10)
    }

    /// A zero-height marker at the end of the list. Scrolling to the last bubble stops short
    /// when a proposal card follows it; scrolling to the end never does.
    private var bottomAnchor: String { "bottom" }

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
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Theme.lime, in: RoundedRectangle(cornerRadius: 20))
            } else {
                // The assistant is the page, not a guest on it — plain text, no bubble.
                Text(bubble.text)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }
}

struct TypingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.dim)
                    .frame(width: 7, height: 7)
                    .opacity(on ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                        value: on
                    )
            }
        }
        .onAppear { on = true }
    }
}

/// Shown inline while a proposal waits on a face. Settled ones live on Home, not here — the
/// chat should not become a ledger.
struct PendingCard: View {
    let proposal: MobileProposal
    let rate: Double

    var body: some View {
        HStack(spacing: 14) {
            CircleGlyph(systemName: "faceid", filled: Theme.lime)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for you")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(Format.usd(wei: proposal.action.amountWei, rate: rate) + " · "
                     + Format.short(proposal.action.counterparty, lead: 6, tail: 4))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}
