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
            try? await Task.sleep(for: .milliseconds(1000))
            withAnimation(.easeInOut(duration: 0.35)) { showSplash = false }
        }
        // The approval owns the whole screen. It is the only moment in this app that matters.
        .fullScreenCover(item: $state.pending) { ApprovalView(proposal: $0) }
        .overlay(alignment: .top) {
            if let banner = state.banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.down, in: RoundedRectangle(cornerRadius: 14))
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
            Theme.accent.ignoresSafeArea()
            TappyMark(size: 120, color: .white)
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
                HStack {
                    HStack(spacing: 9) {
                        TappyMark(size: 26)
                        Text("tappy")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Button { editingHub.toggle() } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(Theme.dim)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)

                Spacer()
                TappyMark(size: 180)
                Spacer()

                Text("The smarter and faster wallet")
                    .font(.system(size: 33, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 24)

                Text("Ask for anything. Nothing moves until you approve it with your face.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 44)
                    .padding(.top, 14)

                if editingHub {
                    TextField("http://192.168.1.20:3000", text: $state.hubURL)
                        .textFieldStyle(.plain)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                }

                Spacer()

                Button { Task { await state.setUp() } } label: {
                    Text(state.busy ? "Creating…" : "Create My Key")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(state.busy)
                .padding(.horizontal, 24)

                Text(EnclaveHumanKey.isAvailable
                     ? "Secured by the Secure Enclave"
                     : "No Secure Enclave here — a software key will be used")
                    .font(.footnote)
                    .foregroundStyle(EnclaveHumanKey.isAvailable ? Theme.dim : Theme.down)
                    .padding(.vertical, 22)
            }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch state.tab {
                case 1: WalletView()
                default: ChatView()
                }
            }

            HStack(spacing: 0) {
                tabButton(0, "bubble.left.fill", "Chat")
                tabButton(1, "wallet.bifold.fill", "Wallet")
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .liquidGlass(.capsule)
            .padding(.horizontal, 60)
            .padding(.bottom, 6)
        }
        .ignoresSafeArea(.keyboard)
    }

    private func tabButton(_ index: Int, _ icon: String, _ label: String) -> some View {
        Button { state.tab = index } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 19))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(state.tab == index ? Theme.accent : Theme.dim)
            .frame(maxWidth: .infinity)
        }
    }
}
