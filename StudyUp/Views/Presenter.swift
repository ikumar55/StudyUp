import Observation
import SwiftData

/// Owns every sheet and study session so they're presented from one place, and the folders opened
/// from Home. iOS shows one modal at a time, so a reminder tap must close an open sheet before its
/// session can appear.
@Observable
final class Presenter {
    enum Sheet: Identifiable {
        case settings
        case newCard(Folder)
        case editCard(Card)

        var id: String {
            switch self {
            case .settings: "settings"
            case .newCard(let folder): "new-\(folder.persistentModelID.hashValue)"
            case .editCard(let card): "edit-\(card.persistentModelID.hashValue)"
            }
        }
    }

    var sheet: Sheet?
    var session: StudySession?
    /// The folders opened from Home, topic first.
    var folderPath: [Folder] = []
    /// Set by a sheet holding unsaved work (a card being written), so a reminder tap doesn't close it.
    var sheetHasUnsavedChanges = false
    private(set) var queuedSession: StudySession?

    /// Shows a session, closing any open sheet first (unless it has unsaved work, in which case the
    /// session waits until the sheet closes). Replaces a session already on screen.
    func present(_ newSession: StudySession) {
        if sheet != nil {
            queuedSession = newSession
            if !sheetHasUnsavedChanges { sheet = nil }
        } else {
            session = newSession
        }
    }

    /// Goes back to a folder above the one open, e.g. from a folder's path.
    func open(_ folder: Folder) {
        folderPath = Array(sequence(first: folder, next: \.parent).reversed())
    }

    func sheetDismissed() {
        sheetHasUnsavedChanges = false
        if let queuedSession {
            session = queuedSession
            self.queuedSession = nil
        }
    }
}
