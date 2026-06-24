import AppKit
import WebKit

/// WKWebView that does not take keyboard focus — keeps typing in the ABC editor.
final class NonFocusWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }

    override func becomeFirstResponder() -> Bool { false }

    override func mouseDown(with event: NSEvent) {
        // Allow scroll / click on score without stealing editor focus.
        super.mouseDown(with: event)
    }
}