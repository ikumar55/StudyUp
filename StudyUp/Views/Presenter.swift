import Observation
import SwiftData

/// Owns every sheet and study session so they're presented from one place.
/// iOS shows one modal at a time, so a reminder tap must close an open sheet before its session can appear.
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
    private var queuedSession: StudySession?

    /// Shows a session, closing any open sheet first. Replaces a session already on screen.
    func present(_ newSession: StudySession) {
        if sheet != nil {
            queuedSession = newSession
            sheet = nil
        } else {
            session = newSession
        }
    }

    func sheetDismissed() {
        if let queuedSession {
            session = queuedSession
            self.queuedSession = nil
        }
    }
}
