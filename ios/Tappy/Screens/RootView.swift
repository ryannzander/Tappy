import SwiftUI
import TappyKit

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView().transition(.opacity)
            } else if state.key == nil {
                OnboardingView()
            } else {
                MainTabs()
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeInOut(duration: 0.3)) { showSplash = false }
        }
        // The approval owns the whole screen. It is the only moment in this app that matters.
        .fullScreenCover(item: $state.pending) { ApprovalView(proposal: $0) }
        .sheet(item: $state.settled) { proposal in
            TransactionView(proposal: proposal, contactName: state.name(for: proposal))
        }
        .overlay(alignment: .top) {
            if let banner = state.banner {
                Text(banner)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.down)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 14)
                    .onTapGesture { state.banner = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.lime.ignoresSafeArea()
            TappyMark(size: 130, color: Theme.ink)
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @State private var editingHub = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Rectangle().fill(Theme.ink).frame(height: 5)
                    .padding(.horizontal, 22).padding(.top, 10)

                Spacer()

                ZStack {
                    Circle().fill(Theme.lime).frame(width: 230, height: 230)
                    TappyMark(size: 150, color: Theme.ink)
                }

                Spacer()

                Text("ONE WALLET\nYOUR AI CAN ASK\nAND ONLY YOU\nCAN OPEN")
                    .font(.display(40))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
                    .padding(.horizontal, 20)

                if editingHub {
                    TextField("http://192.168.1.20:3100", text: $state.hubURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                }

                Spacer()

                VStack(spacing: 10) {
                    Button { Task { await state.setUp() } } label: {
                        Text(state.busy ? "Creating your key…" : "Create my key")
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(state.busy)

                    Button { editingHub.toggle() } label: {
                        Text(editingHub ? "Hide server settings" : "Server settings")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                    .padding(.top, 4)

                    Text(EnclaveHumanKey.isAvailable
                         ? "Sealed in this iPhone's Secure Enclave"
                         : "No Secure Enclave here — a software key will be used")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(EnclaveHumanKey.isAvailable ? Theme.dim : Theme.down)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch state.tab {
                case 1: ChatView()
                case 2: RecipientsView()
                default: HomeView()
                }
            }
            .frame(maxHeight: .infinity)

            bar
        }
        .background(Theme.bg)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// A real bar in the layout rather than an overlay floating on top — the previous version
    /// hovered over the chat composer and made the text box unreachable.
    private var bar: some View {
        VStack(spacing: 0) {
            Theme.hairline.frame(height: 0.5)
            HStack(spacing: 0) {
                item(0, "house", "house.fill", "Home")
                item(1, "bubble.left", "bubble.left.fill", "Chat")
                item(2, "person.2", "person.2.fill", "Recipients")
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .background(Theme.bg)
    }

    private func item(_ index: Int, _ icon: String, _ active: String, _ label: String) -> some View {
        Button { state.tab = index } label: {
            VStack(spacing: 4) {
                Image(systemName: state.tab == index ? active : icon)
                    .font(.system(size: 20, weight: .medium))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(state.tab == index ? Theme.ink : Theme.dim)
            .frame(maxWidth: .infinity)
        }
    }
}
