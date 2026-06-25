import AppKit
import Foundation

/// Owns ABC editor text — NSTextView is source of truth while typing.
@MainActor
final class EditorController: ObservableObject {
    @Published private(set) var revision = 0
    private(set) var storedText: String

    weak var textView: NSTextView?
    var onTextChange: ((String) -> Void)?

    init(text: String = ABCUtilities.defaultTestABC) {
        storedText = ABCUtilities.fixRhythmBarlines(text)
    }

    func liveText() -> String {
        if let tv = textView { return tv.string }
        return storedText
    }

    func userDidEdit(_ text: String) {
        let fixed = ABCUtilities.fixRhythmBarlines(text)
        storedText = fixed
        onTextChange?(fixed)
    }

    func setProgrammatically(_ text: String) {
        let fixed = ABCUtilities.fixRhythmBarlines(text)
        storedText = fixed
        revision += 1
        if let tv = textView {
            let sel = tv.selectedRanges
            tv.string = fixed
            tv.selectedRanges = sel
        }
    }
}