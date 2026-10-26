import Foundation

// Mirrors web/shared/protocol.ts — keep both in sync.
// Dates travel as milliseconds since 1970; UUIDs as strings (the Mac lowercases them).

nonisolated struct FolderRecord: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var parentId: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deleted: Bool
}

nonisolated struct ProgressRecord: Codable, Equatable, Sendable {
    var state: Int
    var due: Date
    var stability: Double
    var difficulty: Double
    var step: Int
    var reps: Int
    var lapses: Int
    var lastReview: Date?
    var updatedAt: Date
}

nonisolated struct CardRecord: Codable, Equatable, Sendable {
    var id: UUID
    var folderId: UUID?
    var front: String
    var back: String
    var createdAt: Date
    var updatedAt: Date
    var deleted: Bool
    var progress: ProgressRecord?
}

nonisolated struct ReviewLogRecord: Codable, Equatable, Sendable {
    var id: UUID
    var cardId: UUID
    var reviewedAt: Date
    var rating: Int
    var stateBefore: Int
}

nonisolated struct SyncRequest: Codable, Equatable, Sendable {
    var cursor: Int
    var folders: [FolderRecord]
    var cards: [CardRecord]
    var reviewLogs: [ReviewLogRecord]
}

nonisolated struct SyncResponse: Codable, Equatable, Sendable {
    /// Identifies the Mac's database. If it changes (a restored backup, a new Mac), the cursor means
    /// nothing anymore, so the phone starts over with a full sync. Nil from servers before 2026-10-26.
    var databaseId: String?
    var cursor: Int
    var folders: [FolderRecord]
    var cards: [CardRecord]
    var reviewLogs: [ReviewLogRecord]
}

nonisolated struct PairRequest: Codable, Sendable {
    var code: String
    var deviceName: String
}

nonisolated struct PairResponse: Codable, Sendable {
    var token: String
    var serverName: String
}

nonisolated enum SyncCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
