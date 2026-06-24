import Foundation

/// Builds the Jerry Coker chromatic cycle in ABC notation.
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
            "V:1",
            "K:C",
        ]

        let bars = ConcertBar.fullCycle
        for (index, bar) in bars.enumerated() {
            let mini = ABCUtilities.miniAbc(key: bar.key, body: bar.body)
            let transposed = try await bridge.transpose(mini, steps: instrument.transposeSteps)
            let key = ABCUtilities.keyFromAbc(transposed)
            let body = ABCUtilities.notesFromAbc(transposed)
            let end = index == bars.count - 1 ? " ||" : " |"
            lines.append("% ── \(bar.label) (concert \(bar.key)) ──")
            lines.append("[K:\(key)]")
            lines.append(body + end)
        }
        return lines.joined(separator: "\n")
    }
}