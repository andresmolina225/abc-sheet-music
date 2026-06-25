import AppKit
import SwiftUI

/// Monospaced ABC editor — binding stored on coordinator so Live updates always fire.
struct ABCEditorView: NSViewRepresentable {
    @Binding var text: String
    var scrollRef: Binding<NSScrollView?>?
    var onEdit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEdit: onEdit)
    }

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
        scrollRef?.wrappedValue = scroll

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onEdit = onEdit
        scrollRef?.wrappedValue = scroll
        guard let textView = scroll.documentView as? EditorTextView else { return }
        guard !context.coordinator.isApplyingEdit else { return }
        guard textView.window?.firstResponder !== textView else { return }
        guard textView.string != text else { return }

        let selection = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = selection
    }

    static func currentText(in scrollView: NSScrollView?) -> String? {
        (scrollView?.documentView as? NSTextView)?.string
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onEdit: (String) -> Void
        weak var textView: NSTextView?
        var isApplyingEdit = false

        init(text: Binding<String>, onEdit: @escaping (String) -> Void) {
            self.text = text
            self.onEdit = onEdit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            publish(textView.string)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            true
        }

        private func publish(_ value: String) {
            isApplyingEdit = true
            text.wrappedValue = value
            onEdit(value)
            isApplyingEdit = false
        }
    }
}

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