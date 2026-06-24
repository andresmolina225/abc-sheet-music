import Foundation

/// Expands a one-bar ABC template into 12 chromatic keys (book style).
struct Keys12Generator {
    private let bridge: ABCBridge

    private static let chromatic: [(label: String, key: String)] = [
        ("C", "C"), ("Db", "Db"), ("D", "D"), ("Eb", "Eb"), ("E", "E"), ("F", "F"),
        ("Gb", "Gb"), ("G", "G"), ("Ab", "Ab"), ("A", "A"), ("Bb", "Bb"), ("B", "B"),
    ]

    init(bridge: ABCBridge) {
        self.bridge = bridge
    }

    func generate(from templateABC: String, for instrument: Instrument) async throws -> String {
        let templateKey = ABCUtilities.keyFromAbc(templateABC)
        guard let templateBody = ABCUtilities.firstBarBody(from: templateABC) else {
            throw Keys12Error.noBarFound
        }

        var lines = [
            "X:1",
            "T:12 Keys (\(instrument.shortName))",
            "C:ABC Sheet Music",
            "M:4/4",
            "L:1/8",
            "Q:1/4=88",
            "%%stretchlast 0.04",
            "%%annotationfont Helvetica 14",
            "V:1",
            "K:none",
            "% Book style — key name above each bar, no key signature.",
            "% Rhythm: (3 asc (3 desc N4 — no | before the half note.",
        ]

        for (index, target) in Self.chromatic.enumerated() {
            let shift = ABCUtilities.semitoneOffset(from: templateKey, to: target.key)
            var mini = ABCUtilities.miniAbc(key: templateKey, body: templateBody)
            if shift != 0 {
                mini = try await bridge.transpose(mini, steps: shift)
            }
            var transposed = try await bridge.transpose(mini, steps: instrument.transposeSteps)
            transposed = try await ABCUtilities.fitWrittenRange(transposed, range: instrument.writtenRange) { abc, steps in
                try await bridge.transpose(abc, steps: steps)
            }
            let writtenKey = ABCUtilities.keyFromAbc(transposed)
            let body = ABCUtilities.notesFromAbc(transposed)
            let end = index == Self.chromatic.count - 1 ? " ||" : " |"
            lines.append("% \(writtenKey) (concert \(target.key))")
            lines.append("[K:none]")
            lines.append(ABCUtilities.bookBarLine(keyName: writtenKey, body: body) + end)
        }
        return ABCUtilities.fixRhythmBarlines(lines.joined(separator: "\n"))
    }
}

enum Keys12Error: LocalizedError {
    case noBarFound

    var errorDescription: String? {
        switch self {
        case .noBarFound: return "No music bar found — add one bar like (3 C E G (3 c G E C4 |"
        }
    }
}