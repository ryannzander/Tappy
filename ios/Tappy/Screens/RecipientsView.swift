import SwiftUI
import TappyKit

/// Wise's Recipients tab. Addresses are 42 characters of hex nobody can read or remember, and
/// asking someone to paste one into a chat box is the worst part of every crypto app. Save the
/// person once, then say their name.
struct RecipientsView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var adding = false
    @State private var paying: Contact?

    private var results: [Contact] { state.contacts.search(query) }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recipients").font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Button { adding = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                            .background(Theme.lime, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                search.padding(.horizontal, 20).padding(.top, 14)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { contact in
                            Button { paying = contact } label: { row(contact) }
                        }
                        if results.isEmpty {
                            Text(query.isEmpty
                                 ? "Nobody saved yet. Add someone so you never paste an address again."
                                 : "Nobody matches “\(query)”.")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.dim)
                                .padding(.vertical, 26)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .sheet(isPresented: $adding) { AddRecipientView() }
        .sheet(item: $paying) { contact in PayRecipientView(contact: contact) }
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
            TextField("Name, handle or address", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Theme.ink)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.surface, in: Capsule())
    }

    private func row(_ contact: Contact) -> some View {
        HStack(spacing: 14) {
            Avatar(contact: contact)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(contact.handle).font(.system(size: 14)).foregroundStyle(Theme.dim)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// Amount first, then hand it to the agent. This screen never touches the chain — it writes a
/// sentence, the agent proposes, and your face decides.
struct PayRecipientView: View {
    let contact: Contact
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""

    private var dollars: Double { Double(amount) ?? 0 }
    private var valid: Bool { dollars > 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Avatar(contact: contact, size: 72).padding(.top, 26)
                Text(contact.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 12)
                Text(Format.short(contact.address, lead: 10, tail: 6))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.dim)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("$").font(.system(size: 42, weight: .bold)).foregroundStyle(Theme.dim)
                    TextField("0", text: $amount)
                        .textFieldStyle(.plain)
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .keyboardType(.decimalPad)
                        .fixedSize()
                }
                .padding(.top, 34)

                Text(state.wallet.map { "$\($0.balanceUsd) available" } ?? " ")
                    .font(.system(size: 14)).foregroundStyle(Theme.dim)

                Spacer()

                Button {
                    let value = dollars
                    dismiss()
                    Task { await state.pay(value, to: contact) }
                } label: { Text("Continue") }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(!valid)
                    .opacity(valid ? 1 : 0.45)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                Text("Tappy will prepare it. Nothing moves until you approve with your face.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
            }
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct AddRecipientView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && address.hasPrefix("0x") && address.count == 42
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("ADD SOMEONE").font(.display(30)).foregroundStyle(Theme.ink)
                field("Name", text: $name, mono: false)
                field("Wallet address", text: $address, mono: true)
                Text("Addresses are 42 characters and start with 0x.")
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
                Spacer()
                Button {
                    let handle = "$" + name.lowercased().replacingOccurrences(of: " ", with: "")
                    state.addContact(Contact(name: name, handle: handle, address: address))
                    dismiss()
                } label: { Text("Save") }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(!valid)
                    .opacity(valid ? 1 : 0.45)
            }
            .padding(20)
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func field(_ label: String, text: Binding<String>, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.dim)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(mono ? .system(size: 15, design: .monospaced) : .system(size: 17))
                .autocorrectionDisabled()
                .textInputAutocapitalization(mono ? .never : .words)
                .foregroundStyle(Theme.ink)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
