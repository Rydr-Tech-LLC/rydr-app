//
//  MailComposerView.swift
//  RydrPlayground
//
//  Native email composer wrapper for support fallback.
//

import SwiftUI
import MessageUI

struct SupportEmailDraft {
    var subject: String
    var body: String
    var to: String = "support@rydr-go.com"

    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

struct MailComposerView: UIViewControllerRepresentable {
    let draft: SupportEmailDraft
    var onFinish: () -> Void

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            onFinish()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.to])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) { }
}
