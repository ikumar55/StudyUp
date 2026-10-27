import Foundation
import Observation

/// Paused and focused folders. A card comes up (in notifications, Home's Study now and the counts)
/// if it's inside a focused folder, or nothing is focused, and isn't inside a paused one.
/// A folder's own Study now ignores both, so a paused folder can still be studied on purpose.
/// Kept on this iPhone only (by folder sync id), so nothing changes in sync.
@Observable
final class FolderModes {
    enum Mode {
        case normal, paused, focused
    }

    static let shared = FolderModes(defaults: Persistence.isInMemory ? nil : .standard)

    private(set) var paused: Set<UUID>
    private(set) var focused: Set<UUID>

    /// Nil keeps the modes in memory only (UI tests, which start with an empty library).
    private let defaults: UserDefaults?
    private enum Key {
        static let paused = "folders.paused"
        static let focused = "folders.focused"
    }

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        paused = Self.load(Key.paused, from: defaults)
        focused = Self.load(Key.focused, from: defaults)
    }

    func mode(of folder: Folder) -> Mode {
        guard let id = folder.syncID else { return .normal }
        if paused.contains(id) { return .paused }
        if focused.contains(id) { return .focused }
        return .normal
    }

    func set(_ mode: Mode, for folder: Folder) {
        guard let id = folder.syncID else { return }
        paused.remove(id)
        focused.remove(id)
        switch mode {
        case .normal: break
        case .paused: paused.insert(id)
        case .focused: focused.insert(id)
        }
        save()
    }

    /// Forgets deleted folders, so a focus on a folder that's gone doesn't hide every card.
    func forget(_ ids: some Sequence<UUID>) {
        let ids = Set(ids)
        guard !paused.isDisjoint(with: ids) || !focused.isDisjoint(with: ids) else { return }
        paused.subtract(ids)
        focused.subtract(ids)
        save()
    }

    /// Whether the card comes up in notifications, Home's Study now and the counts.
    func includes(_ card: Card) -> Bool {
        let path = Self.ancestry(of: card.folder)
        if !paused.isDisjoint(with: path) { return false }
        return focused.isEmpty || !focused.isDisjoint(with: path)
    }

    /// Whether any of the folder's cards can come up. Rows of folders where none can are dimmed.
    func isActive(_ folder: Folder) -> Bool {
        let path = Self.ancestry(of: folder)
        if !paused.isDisjoint(with: path) { return false }
        if focused.isEmpty || !focused.isDisjoint(with: path) { return true }
        // A folder holding a focused subfolder still has cards that come up.
        return folder.allFolders.contains { $0.syncID.map(focused.contains) ?? false }
    }

    /// The sync ids of a folder and every folder above it.
    private static func ancestry(of folder: Folder?) -> Set<UUID> {
        var ids = Set<UUID>()
        var current = folder
        while let folder = current {
            if let id = folder.syncID { ids.insert(id) }
            current = folder.parent
        }
        return ids
    }

    private func save() {
        defaults?.set(paused.map(\.uuidString), forKey: Key.paused)
        defaults?.set(focused.map(\.uuidString), forKey: Key.focused)
    }

    private static func load(_ key: String, from defaults: UserDefaults?) -> Set<UUID> {
        Set((defaults?.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }
}
