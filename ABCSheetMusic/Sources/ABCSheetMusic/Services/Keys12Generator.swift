import Foundation

/// Fills in missing chromatic keys using the pattern from the first bar.
struct Keys12Generator {
    private let bridge: ABCBridge

    init(bridge: ABCBridge) {
        self.bridge = bridge
    }

    /// Keep existing bars; generate only keys not already present (e.g. 5 → add 7 more).
    func complete(from abc: String) async throws -> String {
        let fixed = ABCUtilities.fixRhythmBarlines(abc)
        var (header, existingBars) = ABCUtilities.parseScore(fixed)

        guard let template = existingBars.first else {
            throw Keys12Error.noBarFound
        }

        let templateKey = template.concertKey
        let templateBody = template.body
        var byKey: [String: ABCBar] = [:]
        for bar in existingBars {
            byKey[bar.concertKey] = bar
        }

        for targetKey in ABCUtilities.chromaticKeys {
            guard byKey[targetKey] == nil else { continue }
            let shift = ABCUtilities.semitoneOffset(from: templateKey, to: targetKey)
            var mini = ABCUtilities.miniAbc(key: templateKey, body: templateBody)
            if shift != 0 {
                mini = try await bridge.transpose(mini, steps: shift)
            }
            let key = ABCUtilities.keyFromAbc(mini)
            let body = ABCUtilities.notesFromAbc(mini)
            byKey[targetKey] = ABCBar(concertKey: key, body: body)
        }

        let ordered = ABCUtilities.chromaticKeys.compactMap { byKey[$0] }
        if header.isEmpty {
            header = [
                "X:1",
                "T:12 Keys",
                "M:4/4",
                "L:1/8",
                "Q:1/4=88",
                "K:C",
            ]
        } else if let ti = header.firstIndex(where: { $0.hasPrefix("T:") }) {
            header[ti] = "T:12 Keys"
        }

        return ABCUtilities.rebuildScore(header: header, bars: ordered)
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