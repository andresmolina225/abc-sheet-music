import Foundation

struct ABCBar: Equatable {
    let concertKey: String
    let body: String
}

enum ABCUtilities {
    static let defaultTestABC = """
        X:1
        T:Test Pattern - One Key (C)
        M:4/4
        L:1/8
        Q:1/4=88
        K:C
        (3 C E G (3 c G E C4 |
        """

    static let chromaticKeys: [String] = [
        "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B",
    ]

    private static let keySemitones: [String: Int] = [
        "C": 0, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5,
        "Gb": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11,
    ]

    static func semitoneOffset(from source: String, to target: String) -> Int {
        let f = keySemitones[source] ?? 0
        let t = keySemitones[target] ?? 0
        return (t - f + 12) % 12
    }

    static func normalizeKey(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespaces)
        if k.isEmpty || k.lowercased() == "none" { return "C" }
        return k
    }

    /// First measure body (no barlines) for 12-keys expansion.
    static func firstBarBody(from abc: String) -> String? {
        parseScore(abc).bars.first?.body
    }

    /// Parse header + concert bars already in the editor.
    static func parseScore(_ abc: String) -> (header: [String], bars: [ABCBar]) {
        var header: [String] = []
        var bars: [ABCBar] = []
        var currentKey = "C"
        var sawMusic = false

        for raw in abc.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let k = keyFromComment(line) {
                currentKey = k
                continue
            }
            if line.hasPrefix("[K:"), let end = line.firstIndex(of: "]") {
                currentKey = normalizeKey(String(line[line.index(line.startIndex, offsetBy: 3)..<end]))
                continue
            }
            if line.hasPrefix("K:") {
                currentKey = normalizeKey(String(line.dropFirst(2)))
                if !sawMusic { header.append(raw) }
                continue
            }
            if !sawMusic, isHeaderLine(line) {
                header.append(raw)
                continue
            }
            if isMusicLine(line) {
                sawMusic = true
                let cleaned = line
                    .replacingOccurrences(of: #"^\^"[^"]*"\s*"#, with: "", options: .regularExpression)
                let parts = cleaned.split(separator: "|", omittingEmptySubsequences: false)
                for (idx, part) in parts.enumerated() {
                    let body = String(part).trimmingCharacters(in: .whitespaces)
                    if body.isEmpty { continue }
                    bars.append(ABCBar(concertKey: currentKey, body: body))
                    if idx < parts.count - 1 {
                        // inline [K:] on same line rare — keep currentKey
                    }
                }
            }
        }
        return (header, bars)
    }

    static func rebuildScore(header: [String], bars: [ABCBar]) -> String {
        var lines = header
        if lines.isEmpty {
            lines = ["X:1", "M:4/4", "L:1/8", "Q:1/4=88", "K:C"]
        }
        for (index, bar) in bars.enumerated() {
            if index > 0 || !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("K:") }) {
                lines.append("% \(bar.concertKey)")
                lines.append("[K:\(bar.concertKey)]")
            }
            let end = index == bars.count - 1 ? " ||" : " |"
            lines.append(bar.body + end)
        }
        return fixRhythmBarlines(lines.joined(separator: "\n"))
    }

    private static func keyFromComment(_ line: String) -> String? {
        guard line.hasPrefix("%") else { return nil }
        let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
        if let open = body.range(of: "(concert "),
           let close = body[open.upperBound...].firstIndex(of: ")") {
            return normalizeKey(String(body[open.upperBound..<close]))
        }
        let token = body.components(separatedBy: .whitespaces).first ?? ""
        if chromaticKeys.contains(token) { return token }
        return nil
    }

    private static func isHeaderLine(_ line: String) -> Bool {
        guard let c = line.first, c.isLetter, c.isUppercase else { return false }
        return line.contains(":") && !line.hasPrefix("%%")
    }

    private static func isMusicLine(_ line: String) -> Bool {
        if line.hasPrefix("%") || line.hasPrefix("%%") { return false }
        return line.contains(where: { "ABCDEFGabcdefg(3".contains($0) })
    }

    static func miniAbc(key: String, body: String) -> String {
        ["X:1", "M:4/4", "L:1/8", "Q:1/4=88", "K:\(key)", body].joined(separator: "\n")
    }

    static func keyFromAbc(_ abc: String) -> String {
        let parsed = parseScore(abc)
        if let first = parsed.bars.first { return first.concertKey }
        let inline = abc.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("[K:"), let end = t.firstIndex(of: "]") else { return nil }
                return String(t[t.index(t.startIndex, offsetBy: 3)..<end])
            }
        if let last = inline.last { return normalizeKey(last) }
        for line in abc.components(separatedBy: .newlines) {
            if line.hasPrefix("K:") {
                return normalizeKey(String(line.dropFirst(2)))
            }
        }
        return "C"
    }

    static func notesFromAbc(_ abc: String) -> String {
        var out: [String] = []
        var pastKey = false
        for raw in abc.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[K:") {
                if let close = line.firstIndex(of: "]") {
                    line = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                }
                if line.isEmpty { continue }
            }
            if line.hasPrefix("K:") { pastKey = true; continue }
            if !pastKey { continue }
            if line.first.map({ $0.isLetter && $0.isUppercase }) == true && line.contains(":") { continue }
            if line.hasPrefix("%%") || line.hasPrefix("%") { continue }
            line = line.replacingOccurrences(of: #"^\^"[^"]*"\s*"#, with: "", options: .regularExpression)
            out.append(line)
        }
        return out.joined(separator: " ")
            .replacingOccurrences(of: #"\|+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func parseTitle(_ abc: String) -> String {
        for line in abc.components(separatedBy: .newlines) {
            if line.hasPrefix("T:") {
                let t = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? "Untitled" : t
            }
        }
        return "Untitled"
    }

    static func midiRange(_ abc: String) -> (lo: Int, hi: Int)? {
        let scale = [0, 2, 4, 5, 7, 9, 11]
        var body = abc
        body = body.replacingOccurrences(of: #"\[K:[^\]]+\]"#, with: "", options: .regularExpression)
        for line in body.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("%") || (t.first?.isUppercase == true && t.contains(":")) {
                body = body.replacingOccurrences(of: line, with: "")
            }
        }
        guard let re = try? NSRegularExpression(pattern: #"[_^=]*[A-Ga-g][,']*"#) else { return nil }
        let ns = body as NSString
        let matches = re.matches(in: body, range: NSRange(location: 0, length: ns.length))
        var lo = 127, hi = 0, found = false
        for m in matches {
            let token = ns.substring(with: m.range)
            guard let midi = midiForToken(token, scale: scale) else { continue }
            found = true
            lo = min(lo, midi)
            hi = max(hi, midi)
        }
        return found ? (lo, hi) : nil
    }

    private static func midiForToken(_ token: String, scale: [Int]) -> Int? {
        guard let re = try? NSRegularExpression(pattern: #"^([_^=]*)([A-Ga-g])([,']*)$"#),
              let m = re.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) else { return nil }
        func slice(_ i: Int) -> String {
            String(token[Range(m.range(at: i), in: token)!])
        }
        let acc = slice(1)
        let note = slice(2)
        let octMarks = slice(3)
        let letter = note.uppercased()
        guard let idx = "CDEFGAB".firstIndex(of: Character(letter)) else { return nil }
        let scaleIdx = "CDEFGAB".distance(from: "CDEFGAB".startIndex, to: idx)
        var octave = note == note.uppercased() ? 4 : 5
        octave -= octMarks.filter { $0 == "," }.count
        octave += octMarks.filter { $0 == "'" }.count
        var midi = 12 * (octave + 1) + scale[scaleIdx]
        midi += acc.filter { $0 == "^" }.count
        midi -= acc.filter { $0 == "_" }.count
        return midi
    }

    static func fitWrittenRange(
        _ abc: String,
        range: ClosedRange<Int>?,
        transpose: (String, Int) async throws -> String
    ) async rethrows -> String {
        guard let range else { return abc }
        var out = abc
        for _ in 0..<3 {
            guard let span = midiRange(out) else { break }
            if span.hi > range.upperBound {
                out = try await transpose(out, -12)
            } else if span.lo < range.lowerBound {
                out = try await transpose(out, 12)
            } else {
                break
            }
        }
        return out
    }

    static func bookBarLine(keyName: String, body: String) -> String {
        let clean = body.trimmingCharacters(in: .whitespaces)
        return #"^"\#(keyName)" \#(clean)"#
    }

    static func fixRhythmBarlines(_ abc: String) -> String {
        var out = abc
        let rules: [(String, String)] = [
            (#"\(3([^|\n]*)\|\s*\(3"#, "(3$1 (3"),
            (#"\(3([^|\n]*)\|\s*([_^=]*[A-Ga-g][,']*[24])"#, "(3$1 $2"),
        ]
        for (pattern, template) in rules {
            while let regex = try? NSRegularExpression(pattern: pattern) {
                let ns = out as NSString
                guard let m = regex.firstMatch(in: out, range: NSRange(location: 0, length: ns.length)) else { break }
                let rep = regex.replacementString(for: m, in: out, offset: 0, template: template)
                out = (out as NSString).replacingCharacters(in: m.range, with: rep)
            }
        }
        return out
    }

    static func needsRhythmFix(_ abc: String) -> Bool {
        abc.range(of: #"\(3[^|\n]*\|\s*(\(3|[_^=]*[A-Ga-g])"#, options: .regularExpression) != nil
    }
}