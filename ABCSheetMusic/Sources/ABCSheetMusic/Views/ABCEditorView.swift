import AppKit
import SwiftUI

/// Monospaced ABC editor — NSTextView stays first responder; never overwritten while typing.
struct ABCEditorView: NSViewRepresentable {
    @Binding var text: String
    var onEdit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = EditorScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let textView = EditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = text

        scroll.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            scroll.window?.makeFirstResponder(textView)
        }

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? EditorTextView else { return }

        // Never push SwiftUI state into the text view while the user is typing.
        if textView.window?.firstResponder === textView { return }
        if context.coordinator.isApplyingEdit { return }
        if textView.string == text { return }

        let selection = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = selection
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ABCEditorView
        weak var textView: NSTextView?
        var isApplyingEdit = false

        init(_ parent: ABCEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isApplyingEdit = true
            parent.text = textView.string
            parent.onEdit()
            isApplyingEdit = false
        }
    }
}

/// Click anywhere in the editor pane to focus the text view.
private final class EditorScrollView: NSScrollView {
    override func mouseDown(with event: NSEvent) {
        if let tv = documentView as? NSTextView {
            window?.makeFirstResponder(tv)
        }
        super.mouseDown(with: event)
    }
}

private final class EditorTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { needsDisplay = true }
        return ok
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}