import SwiftUI
import UIKit

enum MobileKeyboardDismissal {
    static let notification = Notification.Name("herdrm.mobile.dismissKeyboard")
}

/// A passive window observer, never a hit-testing overlay. Native controls,
/// WebKit links/copy/selection and terminal gestures still receive their tap.
struct MobileOutsideInputDismissal: UIViewRepresentable {
    var enabled: Bool
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) { view.enabled = enabled }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        private weak var observedWindow: UIWindow?
        private weak var originalResponder: UIView?
        var enabled = true { didSet { tap.isEnabled = enabled } }
        private lazy var tap: UITapGestureRecognizer = {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(outsideTap))
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            return gesture
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observedWindow?.removeGestureRecognizer(tap)
            observedWindow = window
            window?.addGestureRecognizer(tap)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touched = touch.view
            while let view = touched {
                if view is UITextField || view is UITextView { return false }
                touched = view.superview
            }
            originalResponder = observedWindow.flatMap(findResponder)
            // Capture before the tap: the keyboard button may open Ghostty's
            // keyboard on this same tap, and must not immediately close it.
            return originalResponder != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func outsideTap() {
            guard let window = observedWindow, let responder = originalResponder, responder.isFirstResponder else { return }
            NotificationCenter.default.post(name: MobileKeyboardDismissal.notification, object: window)
            window.endEditing(true)
        }

        private func findResponder(_ view: UIView) -> UIView? {
            if view.isFirstResponder { return view }
            return view.subviews.lazy.compactMap(findResponder).first
        }
    }
}
