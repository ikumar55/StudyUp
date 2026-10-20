import SwiftData
import SwiftUI

/// Pairs with the StudyUp web app on a Mac, and shows sync status once paired.
struct SyncSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var browser = MacBrowser()
    @State private var selectedMac: URL?
    @State private var manualAddress = ""
    @State private var code = ""
    @State private var isPairing = false
    @State private var pairingError: String?
    private let engine = SyncEngine.shared

    var body: some View {
        Form {
            if let server = engine.server, engine.isPaired {
                pairedSections(server)
            } else {
                pairingSections
            }
        }
        .navigationTitle("Sync with Mac")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !engine.isPaired { browser.start() } }
        .onDisappear { browser.stop() }
    }

    // MARK: - Paired

    @ViewBuilder
    private func pairedSections(_ server: SyncEngine.PairedServer) -> some View {
        Section {
            LabeledContent("Mac", value: server.name)
            LabeledContent("Last synced", value: lastSyncedText)
            if case .failed(let message) = engine.status {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Syncs automatically when you open or leave StudyUp while on the same Wi-Fi as your Mac.")
        }
        Section {
            Button {
                Task { await engine.sync(context: context) }
            } label: {
                HStack {
                    Label(engine.status == .syncing ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    if engine.status == .syncing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(engine.status == .syncing)
        }
        Section {
            Button("Unpair This iPhone", role: .destructive) {
                engine.unpair()
                browser.start()
            }
        } footer: {
            Text("Your cards stay on this iPhone and on the Mac; they just stop syncing.")
        }
    }

    private var lastSyncedText: String {
        guard let lastSyncedAt = engine.lastSyncedAt else { return "Never" }
        return lastSyncedAt.formatted(.relative(presentation: .named))
    }

    // MARK: - Pairing

    @ViewBuilder
    private var pairingSections: some View {
        Section {
            Text("On your Mac, open **localhost:8787** in a browser and click **Pair an iPhone**. If it doesn't load, run `web/scripts/install-service.sh`.")
                .font(.subheadline)
        } header: {
            Text("1. Open StudyUp on your Mac")
        }

        Section {
            if browser.macs.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for your Mac on this Wi-Fi…")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(browser.macs) { mac in
                Button {
                    selectedMac = mac.baseURL
                    manualAddress = ""
                } label: {
                    HStack {
                        Label(mac.name, systemImage: "laptopcomputer")
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedMac == mac.baseURL && manualAddress.isEmpty {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            TextField("Or type its address, e.g. 192.168.1.20:8787", text: $manualAddress)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("2. Choose your Mac")
        } footer: {
            if browser.isDenied {
                Text("StudyUp can't search your network. Allow it in iOS Settings → Privacy & Security → Local Network.")
            }
        }

        Section {
            TextField("6-digit code", text: $code)
                .keyboardType(.numberPad)
                .font(.title3.monospacedDigit())
            Button {
                Task { await pair() }
            } label: {
                HStack {
                    Text(isPairing ? "Pairing…" : "Pair")
                    if isPairing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(pairingTarget == nil || code.count != 6 || isPairing)
        } header: {
            Text("3. Enter the code shown on your Mac")
        } footer: {
            if let pairingError {
                Text(pairingError)
                    .foregroundStyle(.red)
            }
        }
    }

    /// The typed address if there is one, otherwise the Mac picked from the list.
    private var pairingTarget: URL? {
        let typed = manualAddress.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return selectedMac }
        let withScheme = typed.contains("://") ? typed : "http://\(typed)"
        guard var components = URLComponents(string: withScheme), components.host != nil else { return nil }
        if components.port == nil { components.port = 8787 }
        return components.url
    }

    private func pair() async {
        guard let target = pairingTarget else { return }
        isPairing = true
        pairingError = nil
        do {
            try await engine.pair(baseURL: target, code: code, context: context)
            browser.stop()
            code = ""
        } catch {
            pairingError = error.localizedDescription
        }
        isPairing = false
    }
}
