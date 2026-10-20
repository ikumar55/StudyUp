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

    /// Image references in card text (`![](image:<id>)`); the images arrive as attachments instead.
    private static let imageReference = /!\[[^\]]*\]\(image:[0-9a-fA-F-]{36}\)/

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
            front: Self.withoutImages(info[Key.front] as? String ?? content.body),
            back: Self.withoutImages(info[Key.back] as? String ?? ""),
            frontImages: Self.images(in: content.attachments, prefix: "question-"),
            backImages: Self.images(in: content.attachments, prefix: "answer-")
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

extension NotificationViewController {
    static func withoutImages(_ text: String) -> String {
        text.replacing(imageReference, with: "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    /// Images the app attached to the reminder, identified by "question-" or "answer-" prefixes.
    static func images(in attachments: [UNNotificationAttachment], prefix: String) -> [UIImage] {
        attachments.filter { $0.identifier.hasPrefix(prefix) }.compactMap { attachment in
            // Attachments live in the notification system's store, outside the extension's sandbox.
            let url = attachment.url
            guard url.startAccessingSecurityScopedResource() else { return UIImage(contentsOfFile: url.path) }
            defer { url.stopAccessingSecurityScopedResource() }
            return UIImage(contentsOfFile: url.path)
        }
    }
}

private struct AnswerView: View {
    let path: String
    let front: String
    let back: String
    var frontImages: [UIImage] = []
    var backImages: [UIImage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !path.isEmpty {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !front.isEmpty {
                Text(Self.markdown(front))
                    .font(.headline)
            }
            images(frontImages)
            Divider()
            if !back.isEmpty {
                Text(Self.markdown(back))
                    .font(.body)
            }
            images(backImages)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private func images(_ images: [UIImage]) -> some View {
        ForEach(Array(images.enumerated()), id: \.offset) { _, image in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 260, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Inline Markdown (**bold**, *italic*, `code`), matching how the app renders cards.
    private static func markdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
