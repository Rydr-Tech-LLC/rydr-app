//
//  View+Extension.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/14/25.
//

import SwiftUI
import UIKit

extension View {
    func hideKeyboardOnTap() -> some View {
        background(KeyboardDismissInstallerView().frame(width: 0, height: 0))
    }
}

private struct KeyboardDismissInstallerView: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissInstallationView {
        KeyboardDismissInstallationView()
    }

    func updateUIView(_ uiView: KeyboardDismissInstallationView, context: Context) {}
}

private final class KeyboardDismissInstallationView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            KeyboardDismissGestureHandler.install(on: window)
        }
    }
}

private final class KeyboardDismissGestureHandler: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissGestureHandler()
    private static let tapName = "com.rydr.keyboard-dismiss-tap"
    private static let swipeName = "com.rydr.keyboard-dismiss-swipe"

    static func install(on window: UIWindow) {
        guard window.gestureRecognizers?.contains(where: {
            $0.name == tapName || $0.name == swipeName
        }) != true else { return }

        let tap = UITapGestureRecognizer(target: shared, action: #selector(dismissKeyboard))
        tap.name = tapName
        tap.cancelsTouchesInView = false
        tap.delegate = shared

        let swipe = UIPanGestureRecognizer(target: shared, action: #selector(handleSwipe(_:)))
        swipe.name = swipeName
        swipe.cancelsTouchesInView = false
        swipe.delegate = shared

        window.addGestureRecognizer(tap)
        window.addGestureRecognizer(swipe)
    }

    @objc private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @objc private func handleSwipe(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: gesture.view)
        guard translation.y > 24, abs(translation.y) > abs(translation.x) else { return }
        dismissKeyboard()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.name == Self.tapName else { return true }
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView {
                return false
            }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
extension View {
    func inputFieldStyle() -> some View {
        self
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        LinearGradient(
                            colors: [Color.red, Color(red: 0.5, green: 0.0, blue: 0.13).opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )
            )
    }
}
