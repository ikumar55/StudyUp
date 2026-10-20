import Foundation
import SwiftData
import Testing
@testable import StudyUp

/// Syncs against a real StudyUp server. Runs only when the server's address is given, e.g.
///   (cd web && STUDYUP_DB=/tmp/test.db PORT=8799 node server/index.ts) &
///   TEST_RUNNER_STUDYUP_SERVER=http://localhost:8799 xcodebuild test … -only-testing:StudyUpTests/SyncIntegrationTests
/// The simulator shares the Mac's network, so localhost reaches the server and counts as "this Mac".
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["STUDYUP_SERVER"] != nil))
struct SyncIntegrationTests {
    let server = URL(string: ProcessInfo.processInfo.environment["STUDYUP_SERVER"] ?? "http://localhost:8799")!
    let container: ModelContainer
    let context: ModelContext
    let engine: SyncEngine

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        context = container.mainContext
        let defaults = UserDefaults(suiteName: "SyncIntegrationTests")!
        defaults.removePersistentDomain(forName: "SyncIntegrationTests")
        engine = SyncEngine(defaults: defaults, keychain: KeychainItem(account: "integration-test"))
    }

    private func api(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> Any? {
        var request = URLRequest(url: server.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, _) = try await URLSession.shared.data(for: request)
        return data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data)
    }

    private func pairAndSync() async throws {
        let pairing = try #require(try await api("POST", "api/pairing-code") as? [String: Any])
        try await engine.pair(baseURL: server, code: try #require(pairing["code"] as? String), context: context)
        #expect(engine.status == .idle, "\(engine.status)")
    }

    @Test func cardsFlowBothWays() async throws {
        defer { engine.unpair() }

        // Written on the phone before pairing.
        let phoneFolder = Folder(name: "Phone Topic \(UUID().uuidString.prefix(6))")
        context.insert(phoneFolder)
        let phoneCard = Card(front: "Written on the phone", back: "A")
        context.insert(phoneCard)
        phoneCard.folder = phoneFolder
        phoneCard.record(.good, fsrs: FSRS(), context: context, now: .now)

        try await pairAndSync()
        #expect(engine.isPaired)

        // The Mac now has the phone's folder, card, and progress.
        let library = try #require(try await api("GET", "api/library") as? [String: Any])
        let macCards = try #require(library["cards"] as? [[String: Any]])
        let uploaded = try #require(macCards.first { ($0["id"] as? String) == phoneCard.syncID!.uuidString.lowercased() })
        #expect(uploaded["front"] as? String == "Written on the phone")
        #expect((uploaded["progress"] as? [String: Any])?["reps"] as? Int == 1)

        // Written on the Mac, then synced to the phone.
        let macFolderID = phoneFolder.syncID!.uuidString.lowercased()
        _ = try await api("POST", "api/cards", ["folderId": macFolderID, "front": "Written on the Mac", "back": "B"])
        await engine.sync(context: context)
        #expect(engine.status == .idle, "\(engine.status)")
        #expect(phoneFolder.cards.map(\.front).sorted() == ["Written on the Mac", "Written on the phone"])

        // Deleted on the phone, then gone on the Mac.
        context.deleteSyncing(phoneFolder)
        await engine.sync(context: context)
        let after = try #require(try await api("GET", "api/library") as? [String: Any])
        let remaining = (after["folders"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        #expect(!remaining.contains(macFolderID))
    }

    @Test func wrongCodeIsRejected() async throws {
        await #expect(throws: (any Error).self) {
            try await engine.pair(baseURL: server, code: "000000", context: context)
        }
        #expect(!engine.isPaired)
    }
}
