import Foundation

/// Builds the Jerry Coker chromatic cycle — book style (K:none, key name above each bar).
struct CokerGenerator {
    private let bridge: ABCBridge

    init(bridge: ABCBridge) {
        self.bridge = bridge
    }

    func generate(for instrument: Instrument) async throws -> String {
        var lines = [
            "X:1",
            "T:Coker Pattern - Full Cycle (\(instrument.shortName))",
            "C:Jerry Coker · ABC Sheet Music",
            "M:4/4",
            "L:1/8",
            "Q:1/4=88",
            "%%stretchlast 0.04",
            "%%annotationfont Helvetica 14",
            "V:1",
            "K:none",
            "% Book style: no key signature — accidentals on notes, key name above each bar.",
            "% 4/4 rhythm: (3 asc (3 desc N4 — never | between triplets and half note.",
        ]

        let bars = ConcertBar.fullCycle
        for (index, bar) in bars.enumerated() {
            let mini = ABCUtilities.miniAbc(key: bar.key, body: bar.body)
            var transposed = try await bridge.transpose(mini, steps: instrument.transposeSteps)
            transposed = try await ABCUtilities.fitWrittenRange(transposed, range: instrument.writtenRange) { abc, steps in
                try await bridge.transpose(abc, steps: steps)
            }
            let writtenKey = ABCUtilities.keyFromAbc(transposed)
            let body = ABCUtilities.notesFromAbc(transposed)
            let end = index == bars.count - 1 ? " ||" : " |"
            lines.append("% \(writtenKey) (concert \(bar.key))")
            lines.append("[K:none]")
            lines.append(ABCUtilities.bookBarLine(keyName: writtenKey, body: body) + end)
        }
        return ABCUtilities.fixRhythmBarlines(lines.joined(separator: "\n"))
    }
}