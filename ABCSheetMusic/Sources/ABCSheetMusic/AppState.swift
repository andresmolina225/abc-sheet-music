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
    @Published var lastRenderNote = ""
    @Published private(set) var bridge: ABCBridge?
    @Published private(set) var isBootstrapping = true

    let editor = EditorController()

    private var didBootstrap = false
    private var lastConcertABC = ""
    private var renderTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let abcKey = "abc-sheet-swift-abc-v13"
    private let instKey = "abc-sheet-inst-v13"

    init() {
        if let raw = defaults.string(forKey: instKey), let inst = Instrument(rawValue: raw) {
            instrument = inst
        }
        editor.onTextChange = { [weak self] text in
            self?.userEdited(concertABC: text)
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
        isBootstrapping = true
        do {
            try await withTimeout(seconds: 20) {
                try await bridge.waitUntilReady()
            }
            bridgeSignature = bridge.signature
            audioSupported = bridge.audioSupported
            let initial: String
            if let saved = defaults.string(forKey: abcKey), !saved.isEmpty {
                initial = ABCUtilities.fixRhythmBarlines(saved)
            } else {
                initial = ABCUtilities.fixRhythmBarlines(ABCUtilities.defaultTestABC)
            }
            editor.setProgrammatically(initial)
            await renderNow(concertABC: initial)
        } catch {
            warnings = [error.localizedDescription] + (bridge.jsErrors)
            BridgeDiagnostics.log("bootstrap failed: \(error)")
        }
        isBootstrapping = false
    }

    func userEdited(concertABC: String) {
        lastConcertABC = concertABC
        guard liveRender else { return }
        scheduleRender(concertABC: concertABC)
    }

    func scheduleRender(concertABC: String) {
        guard bridge != nil else { return }
        renderTask?.cancel()
        let snapshot = concertABC
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await renderNow(concertABC: snapshot)
        }
    }

    func renderNow(concertABC: String) async {
        guard let bridge else {
            lastRenderNote = "Bridge not ready"
            return
        }
        let concert = ABCUtilities.fixRhythmBarlines(concertABC)
        lastConcertABC = concert
        title = ABCUtilities.parseTitle(concert)
        guard !concert.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            warnings = []
            lastRenderNote = "Empty ABC"
            return
        }
        do {
            let toRender = try await scoreABC(from: concert)
            let result = try await bridge.render(toRender, measuresPerLine: measuresPerLine)
            var msgs = result.warnings
            msgs.append(contentsOf: bridge.jsErrors)
            warnings = msgs
            defaults.set(concert, forKey: abcKey)
            lastRenderNote = "Rendered \(instrument.shortName) · \(Date().formatted(date: .omitted, time: .standard))"
            BridgeDiagnostics.log("render OK \(instrument.shortName)")
        } catch {
            warnings = [error.localizedDescription] + bridge.jsErrors
            lastRenderNote = "Render failed"
            BridgeDiagnostics.log("render FAIL: \(error)")
        }
    }

    private func scoreABC(from concert: String) async throws -> String {
        guard let bridge, instrument.transposeSteps != 0 else { return concert }
        var out = try await bridge.transpose(concert, steps: instrument.transposeSteps)
        if let extra = instrument.displayOctaveShift {
            out = try await bridge.transpose(out, steps: extra)
        }
        out = try await ABCUtilities.fitWrittenRange(out, range: instrument.writtenRange) { abc, steps in
            try await bridge.transpose(abc, steps: steps)
        }
        return out
    }

    func generate12Keys() async {
        guard let bridge else { return }
        measuresPerLine = 1
        let source = editor.liveText()
        do {
            let gen = Keys12Generator(bridge: bridge)
            let merged = try await gen.complete(from: source)
            editor.setProgrammatically(merged)
            await renderNow(concertABC: merged)
        } catch {
            warnings = [error.localizedDescription]
        }
    }

    func instrumentChanged() async {
        defaults.set(instrument.rawValue, forKey: instKey)
        await renderNow(concertABC: editor.liveText())
        await reloadSynthForInstrument()
    }

    private func reloadSynthForInstrument() async {
        guard let bridge else { return }
        do {
            try await bridge.stop()
            try await bridge.loadSynth(
                midiTranspose: instrument.playbackMidiShift,
                program: instrument.midiProgram
            )
            lastRenderNote = "Synth ready · \(instrument.shortName) (program \(instrument.midiProgram))"
        } catch {
            BridgeDiagnostics.log("reloadSynth: \(error)")
        }
    }

    func play() async {
        guard let bridge else { return }
        isPlaying = true
        let concert = editor.liveText()
        do {
            try await bridge.stop()
            await renderNow(concertABC: concert)
            try await bridge.loadSynth(
                midiTranspose: instrument.playbackMidiShift,
                program: instrument.midiProgram
            )
            try await bridge.play()
            lastRenderNote = "Playing \(instrument.shortName) · program \(instrument.midiProgram)"
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
            editor.setProgrammatically(fixed)
            Task { await renderNow(concertABC: fixed) }
        }
    }

    func saveABC() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "abc") ?? .plainText]
        panel.nameFieldStringValue = sanitizedFilename(from: title) + ".abc"
        if panel.runModal() == .OK, let url = panel.url {
            try? editor.liveText().write(to: url, atomically: true, encoding: .utf8)
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