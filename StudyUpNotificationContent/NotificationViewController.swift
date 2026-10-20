import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// Shown when a reminder is long-pressed: the question and its answer, above the Wrong/Right/Easy buttons.
/// Reads the payload the app writes in ReminderPayload (StudyUp/Reminders/NotificationHandling.swift),
/// so the keys and action identifiers here must match it.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private enum Key {
        static let front = "front"
        static let back = "back"
        static let path = "path"
        static let intervals = "intervals"
    }

    /// Matches GradeAction in the app: Wrong, Right, Easy.
    private static let actions = [("grade.1", "Wrong"), ("grade.3", "Right"), ("grade.4", "Easy")]

    private let host = UIHostingController(rootView: AnswerView(path: "", front: "", back: ""))

    override func viewDidLoad() {
        super.viewDidLoad()
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let info = content.userInfo
        host.rootView = AnswerView(
            path: info[Key.path] as? String ?? content.title,
            front: info[Key.front] as? String ?? content.body,
            back: info[Key.back] as? String ?? ""
        )

        let width = max(view.bounds.width, 1)
        let fitted = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        preferredContentSize = CGSize(width: width, height: fitted.height)

        // Show where each answer sends the card next, e.g. "Right · 3d".
        if let intervals = info[Key.intervals] as? [String], intervals.count == Self.actions.count {
            extensionContext?.notificationActions = zip(Self.actions, intervals).map { action, interval in
                let (identifier, title) = action
                return UNNotificationAction(
                    identifier: identifier,
                    title: interval.isEmpty ? title : "\(title) · \(interval)",
                    options: identifier == "grade.1" ? [.destructive] : []
                )
            }
        }
    }
}

private struct AnswerView: View {
    let path: String
    let front: String
    let back: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !path.isEmpty {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(Self.markdown(front))
                .font(.headline)
            Divider()
            Text(Self.markdown(back))
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    /// Inline Markdown (**bold**, *italic*, `code`), matching how the app renders cards.
    private static func markdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
