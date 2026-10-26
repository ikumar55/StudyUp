import Foundation
import Observation
import Security
import SwiftData
import UIKit

/// Pairs with the StudyUp server on a Mac and keeps this device's library in sync with it.
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var server: PairedServer?
    private(set) var lastSyncedAt: Date?

    struct PairedServer: Codable, Equatable {
        var baseURL: URL
        var name: String
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private let keychain: KeychainItem
    private let images: ImageStore

    private enum Key {
        static let server = "sync.server"
        static let cursor = "sync.cursor"
        static let lastPushStartedAt = "sync.lastPushStartedAt"
        static let lastSyncedAt = "sync.lastSyncedAt"
        static let databaseID = "sync.databaseID"
    }

    init(
        defaults: UserDefaults = .standard, session: URLSession = .shared,
        keychain: KeychainItem = KeychainItem(account: "token"), images: ImageStore = .shared
    ) {
        self.defaults = defaults
        self.session = session
        self.keychain = keychain
        self.images = images
        server = defaults.data(forKey: Key.server).flatMap { try? JSONDecoder().decode(PairedServer.self, from: $0) }
        lastSyncedAt = defaults.object(forKey: Key.lastSyncedAt) as? Date
    }

    var isPaired: Bool { server != nil && keychain.value != nil }

    // MARK: - Pairing

    /// Exchanges the code shown in the Mac's web app for a token, then runs a first full sync.
    func pair(baseURL: URL, code: String, context: ModelContext) async throws {
        let body = PairRequest(code: code.trimmingCharacters(in: .whitespaces), deviceName: UIDevice.current.name)
        let response: PairResponse = try await post(baseURL.appending(path: "pair"), body: body, token: nil)
        keychain.value = response.token
        server = PairedServer(baseURL: baseURL, name: response.serverName)
        defaults.set(try JSONEncoder().encode(server), forKey: Key.server)
        // A new pairing starts from scratch: send everything, receive everything.
        defaults.set(0, forKey: Key.cursor)
        defaults.removeObject(forKey: Key.lastPushStartedAt)
        defaults.removeObject(forKey: Key.databaseID)
        await sync(context: context)
    }

    func unpair() {
        keychain.value = nil
        server = nil
        lastSyncedAt = nil
        status = .idle
        for key in [Key.server, Key.cursor, Key.lastPushStartedAt, Key.lastSyncedAt, Key.databaseID] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Syncing

    /// Sends local changes and applies the Mac's. Safe to call often; overlapping calls are skipped.
    func sync(context: ModelContext, now: Date = .now) async {
        guard let server, let token = keychain.value, status != .syncing else { return }
        status = .syncing
        try? context.save()

        let url = server.baseURL.appending(path: "sync")
        let since = defaults.object(forKey: Key.lastPushStartedAt) as? Date ?? .distantPast
        var request = SyncMerger.pendingChanges(cursor: defaults.integer(forKey: Key.cursor), since: since, context: context)
        do {
            var response: SyncResponse = try await post(url, body: request, token: token)
            if let known = defaults.string(forKey: Key.databaseID), let current = response.databaseId, current != known {
                // The Mac's database was replaced (a restored backup or a new Mac), so it may lack things
                // this phone already sent, and the cursor means nothing there. Start over: send
                // everything, including review history, and receive everything.
                SyncMerger.markAllUnsent(context: context)
                request = SyncMerger.pendingChanges(cursor: 0, since: .distantPast, context: context)
                response = try await post(url, body: request, token: token)
            }
            SyncMerger.markSent(request, context: context)
            let changed = SyncMerger.apply(response, context: context)
            try context.save()
            defaults.set(response.cursor, forKey: Key.cursor)
            defaults.set(response.databaseId, forKey: Key.databaseID)
            // Edits made while this sync was in flight are newer than `now`, so the next sync sends them.
            defaults.set(now, forKey: Key.lastPushStartedAt)
            if changed { ReminderScheduler.shared.reschedule(context: context) }
            try await syncImages(server: server, token: token, context: context)
            lastSyncedAt = .now
            defaults.set(lastSyncedAt, forKey: Key.lastSyncedAt)
            status = .idle
        } catch {
            status = .failed(Self.describe(error))
        }
    }

    /// Images never change, so this only fills gaps: uploads the images cards use that the Mac is
    /// missing, then downloads the ones this iPhone is missing. Unused images are never sent, since
    /// the Mac would only clean them up again.
    private func syncImages(server: PairedServer, token: String, context: ModelContext) async throws {
        struct MissingRequest: Encodable { let ids: [UUID] }
        struct MissingResponse: Decodable { let missing: [UUID] }

        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let referenced = ImageStore.references(in: cards)
        let stored = images.storedIDs().filter(referenced.contains)
        if !stored.isEmpty {
            let response: MissingResponse = try await post(
                server.baseURL.appending(path: "images/missing"), body: MissingRequest(ids: stored), token: token
            )
            for id in response.missing {
                guard let file = images.data(for: id) else { continue }
                var request = imageRequest(server: server, id: id, token: token)
                request.httpMethod = "PUT"
                request.setValue(file.mime, forHTTPHeaderField: "Content-Type")
                request.httpBody = file.data
                _ = try await perform(request, token: token)
            }
        }

        for id in referenced where !images.contains(id) {
            let data = try await perform(imageRequest(server: server, id: id, token: token), token: token)
            try images.save(data, id: id)
        }
    }

    private func imageRequest(server: PairedServer, id: UUID, token: String) -> URLRequest {
        var request = URLRequest(url: server.baseURL.appending(path: "images/\(id.uuidString.lowercased())"), timeoutInterval: 60)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - HTTP

    private struct ServerError: Decodable, LocalizedError {
        let error: String
        var errorDescription: String? { error }
    }

    private func post<Body: Encodable, Response: Decodable>(_ url: URL, body: Body, token: String?) async throws -> Response {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try SyncCoding.encoder.encode(body)
        return try SyncCoding.decoder.decode(Response.self, from: try await perform(request, token: token))
    }

    /// Sends a request and returns the body of a successful response. A 401 means the Mac forgot
    /// this iPhone (e.g. "Unpair all"), so the pairing is cleared.
    private func perform(_ request: URLRequest, token: String?) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if statusCode == 401, token != nil { unpair() }
            throw (try? JSONDecoder().decode(ServerError.self, from: data)) ?? URLError(.badServerResponse)
        }
        return data
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return "Couldn’t reach your Mac. Make sure it’s awake, StudyUp is running, and you’re on the same Wi-Fi."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

/// A secret kept in the Keychain rather than UserDefaults, such as the pairing token.
nonisolated struct KeychainItem: Sendable {
    let account: String

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "StudyUp Sync",
            kSecAttrAccount as String: account,
        ]
    }

    var value: String? {
        get {
            var item: CFTypeRef?
            var lookup = query
            lookup[kSecReturnData as String] = true
            guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        nonmutating set {
            SecItemDelete(query as CFDictionary)
            guard let newValue else { return }
            var item = query
            item[kSecValueData as String] = Data(newValue.utf8)
            // Readable in the background after first unlock, so syncs after notification actions work.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
