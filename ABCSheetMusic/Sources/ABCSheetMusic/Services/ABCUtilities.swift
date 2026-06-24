import Foundation

enum ABCUtilities {
    static func miniAbc(key: String, body: String) -> String {
        ["X:1", "M:4/4", "L:1/8", "Q:1/4=88", "K:\(key)", body].joined(separator: "\n")
    }

    static func keyFromAbc(_ abc: String) -> String {
        let inline = abc.components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("[K:"), let end = t.firstIndex(of: "]") else { return nil }
                return String(t[t.index(t.startIndex, offsetBy: 3)..<end])
            }
        if let last = inline.last { return last.trimmingCharacters(in: .whitespaces) }
        for line in abc.components(separatedBy: .newlines) {
            if line.hasPrefix("K:") {
                return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
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
}