import AppKit
import SwiftUI

/// Native NSTextView ABC editor — left pane only (score uses ScoreWebView).
struct EditorOnlyView: NSViewRepresentable {
    @ObservedObject var editor: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let textView = ABCPlainTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = editor.storedText

        scroll.documentView = textView
        context.coordinator.textView = textView
        editor.textView = textView

        DispatchQueue.main.async {
            scroll.window?.makeFirstResponder(textView)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        editor.textView = context.coordinator.textView
        guard let tv = context.coordinator.textView else { return }
        guard tv.window?.firstResponder !== tv else { return }
        guard context.coordinator.lastRevision != editor.revision else { return }
        context.coordinator.lastRevision = editor.revision
        if tv.string != editor.storedText {
            let sel = tv.selectedRanges
            tv.string = editor.storedText
            tv.selectedRanges = sel
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let editor: EditorController
        weak var textView: NSTextView?
        var lastRevision = -1

        init(editor: EditorController) { self.editor = editor }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            editor.userDidEdit(tv.string)
        }
    }
}

private final class ABCPlainTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}