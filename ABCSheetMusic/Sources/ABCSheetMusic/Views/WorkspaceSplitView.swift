import AppKit
import SwiftUI
import WebKit

/// Native NSSplitView: ABC editor (left) + score WKWebView (right). Avoids SwiftUI HSplitView editor bugs.
struct WorkspaceSplitView: NSViewRepresentable {
    let bridge: ABCBridge
    @ObservedObject var editor: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    func makeNSView(context: Context) -> NSSplitView {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.autosaveName = "ABCSheetMusicWorkspace"

        // ── Left: ABC editor ──
        let editorScroll = NSScrollView()
        editorScroll.hasVerticalScroller = true
        editorScroll.hasHorizontalScroller = false
        editorScroll.autohidesScrollers = true
        editorScroll.borderType = .noBorder
        editorScroll.drawsBackground = true
        editorScroll.backgroundColor = .textBackgroundColor

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

        editorScroll.documentView = textView
        editorScroll.translatesAutoresizingMaskIntoConstraints = false

        let editorPanel = NSView()
        editorPanel.translatesAutoresizingMaskIntoConstraints = false
        editorPanel.addSubview(editorScroll)
        NSLayoutConstraint.activate([
            editorScroll.leadingAnchor.constraint(equalTo: editorPanel.leadingAnchor),
            editorScroll.trailingAnchor.constraint(equalTo: editorPanel.trailingAnchor),
            editorScroll.topAnchor.constraint(equalTo: editorPanel.topAnchor),
            editorScroll.bottomAnchor.constraint(equalTo: editorPanel.bottomAnchor),
        ])

        // ── Right: score ──
        guard let webView = bridge.webView else { return split }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        let scorePanel = NSView()
        scorePanel.translatesAutoresizingMaskIntoConstraints = false
        scorePanel.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: scorePanel.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: scorePanel.trailingAnchor),
            webView.topAnchor.constraint(equalTo: scorePanel.topAnchor),
            webView.bottomAnchor.constraint(equalTo: scorePanel.bottomAnchor),
        ])

        split.addArrangedSubview(editorPanel)
        split.addArrangedSubview(scorePanel)
        split.setPosition(380, ofDividerAt: 0)

        context.coordinator.textView = textView
        editor.textView = textView

        DispatchQueue.main.async {
            editorPanel.window?.makeFirstResponder(textView)
        }

        return split
    }

    func updateNSView(_ split: NSSplitView, context: Context) {
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

/// Always accepts keyboard — click to focus.
private final class ABCPlainTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}