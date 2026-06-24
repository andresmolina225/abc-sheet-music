import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var warnings: [String] = []
    @Published var title = "—"
    @Published var instrument: Instrument = .tenor
    @Published var measuresPerLine = 1
    @Published var liveRender = true
    @Published var isPlaying = false
    @Published var bridgeSignature = "abcjs…"
    @Published var audioSupported = false
    @Published private(set) var bridge: ABCBridge?
    @Published private(set) var isBootstrapping = true
    @Published private(set) var editorRevision = 0
    private(set) var programmaticEditorText = ""

    private var didBootstrap = false
    private var lastConcertABC = ""
    private var renderTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let abcKey = "abc-sheet-swift-abc-v11"
    private let instKey = "abc-sheet-inst-v11"

    init() {
        if let raw = defaults.string(forKey: instKey), let inst = Instrument(rawValue: raw) {
            instrument = inst
        }
    }

    func startIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        bridge = ABCBridge()
        await bootstrap()
    }

    private func bootstrap() async {
        guard let bridge else { return }
        do {
            try await withTimeout(seconds: 20) {
                try await bridge.waitUntilReady()
            }
            bridgeSignature = bridge.signature
            audioSupported = bridge.audioSupported
            if let saved = defaults.string(forKey: abcKey), !saved.isEmpty {
                let fixed = ABCUtilities.fixRhythmBarlines(saved)
                pushEditorContent(fixed)
                await renderNow(concertABC: fixed)
            } else {
                let starter = ABCUtilities.fixRhythmBarlines(ABCUtilities.defaultTestABC)
                pushEditorContent(starter)
                await renderNow(concertABC: starter)
            }
        } catch {
            warnings = [error.localizedDescription] + (bridge.jsErrors)
            BridgeDiagnostics.log("bootstrap failed: \(error)")
        }
        isBootstrapping = false
    }

    func userEdited(concertABC: String) {
        let fixed = ABCUtilities.fixRhythmBarlines(concertABC)
        lastConcertABC = fixed
        if liveRender { scheduleRender(concertABC: fixed) }
    }

    func scheduleRender(concertABC: String) {
        guard bridge != nil else { return }
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await renderNow(concertABC: concertABC)
        }
    }

    /// Always renders current editor ABC (transposed for instrument on the score).
    func renderNow(concertABC: String) async {
        guard let bridge else { return }
        let concert = ABCUtilities.fixRhythmBarlines(concertABC)
        lastConcertABC = concert
        title = ABCUtilities.parseTitle(concert)
        guard !concert.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            warnings = []
            return
        }
        do {
            let toRender = try await scoreABC(from: concert)
            let result = try await bridge.render(toRender, measuresPerLine: measuresPerLine)
            var msgs = result.warnings
            msgs.append(contentsOf: bridge.jsErrors)
            warnings = msgs
            defaults.set(concert, forKey: abcKey)
        } catch {
            warnings = [error.localizedDescription] + bridge.jsErrors
        }
    }

    private func scoreABC(from concert: String) async throws -> String {
        guard let bridge, instrument.transposeSteps != 0 else { return concert }
        var out = try await bridge.transpose(concert, steps: instrument.transposeSteps)
        out = try await ABCUtilities.fitWrittenRange(out, range: instrument.writtenRange) { abc, steps in
            try await bridge.transpose(abc, steps: steps)
        }
        return out
    }

    /// Add missing chromatic keys using the first bar's pattern; writes result into editor.
    func generate12Keys(from concertABC: String) async {
        guard let bridge else { return }
        measuresPerLine = 1
        do {
            let gen = Keys12Generator(bridge: bridge)
            let merged = try await gen.complete(from: concertABC)
            pushEditorContent(merged)
            await renderNow(concertABC: merged)
        } catch {
            warnings = [error.localizedDescription]
        }
    }

    func instrumentChanged(concertABC: String) async {
        defaults.set(instrument.rawValue, forKey: instKey)
        await renderNow(concertABC: concertABC)
    }

    func pushEditorContent(_ text: String) {
        let fixed = ABCUtilities.fixRhythmBarlines(text)
        programmaticEditorText = fixed
        lastConcertABC = fixed
        editorRevision += 1
    }

    func play() async {
        guard let bridge else { return }
        isPlaying = true
        do {
            try await bridge.loadSynth(
                midiTranspose: instrument.midiTranspose,
                program: instrument.midiProgram
            )
            try await bridge.play()
        } catch {
            warnings = [error.localizedDescription] + bridge.jsErrors
            isPlaying = false
            BridgeDiagnostics.log("play failed: \(error)")
        }
    }

    func stop() async {
        try? await bridge?.stop()
        isPlaying = false
    }

    func openABC() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText]
        if let abc = UTType(filenameExtension: "abc") { types.append(abc) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let fixed = ABCUtilities.fixRhythmBarlines(text)
            pushEditorContent(fixed)
            Task { await renderNow(concertABC: fixed) }
        }
    }

    func saveABC() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "abc") ?? .plainText]
        panel.nameFieldStringValue = sanitizedFilename(from: title) + ".abc"
        if panel.runModal() == .OK, let url = panel.url {
            try? lastConcertABC.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func sanitizedFilename(from title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return cleaned.isEmpty ? "tune" : cleaned
    }
}

private func withTimeout(seconds: Double, operation: @escaping () async throws -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw BridgeError.timeout
        }
        try await group.next()
        group.cancelAll()
    }
}