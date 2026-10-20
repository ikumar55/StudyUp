import Foundation
import Network
import Observation

/// Finds StudyUp servers on the local network. The Mac advertises `_studyup._tcp` over Bonjour
/// with its hostname and port in the TXT record (see web/server/index.ts).
@Observable
final class MacBrowser {
    struct DiscoveredMac: Identifiable, Equatable {
        var name: String
        var baseURL: URL
        var id: URL { baseURL }
    }

    private(set) var macs: [DiscoveredMac] = []
    private(set) var isDenied = false
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_studyup._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let macs = results.compactMap(Self.discoveredMac).sorted { $0.name < $1.name }
            Task { @MainActor in self?.macs = macs }
        }
        browser.stateUpdateHandler = { [weak self] state in
            // A failed or waiting browser here almost always means Local Network permission was denied.
            let denied: Bool
            switch state {
            case .failed, .waiting: denied = true
            default: denied = false
            }
            Task { @MainActor in self?.isDenied = denied }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    private nonisolated static func discoveredMac(_ result: NWBrowser.Result) -> DiscoveredMac? {
        guard case .bonjour(let txt) = result.metadata,
              let host = txt["host"], let port = txt["port"],
              let url = URL(string: "http://\(host):\(port)")
        else { return nil }
        return DiscoveredMac(name: txt["name"] ?? host, baseURL: url)
    }
}
