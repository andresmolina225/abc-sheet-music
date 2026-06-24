import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var abcText = ""
    @Published var warnings: [String] = []
    @Published var title = "—"
    @Published var instrument: Instrument = .tenor
    @Published var measuresPerLine = 1
    @Published var liveRender = true
    @Published var isCokerTune = true
    @Published var isPlaying = false
    @Published var bridgeSignature = "abcjs…"
    @Published var audioSupported = false
    @Published private(set) var bridge: ABCBridge?

    private var didBootstrap = false
    private var renderTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let abcKey = "abc-sheet-swift-abc"
    private let instKey = "abc-sheet-inst-v8"

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
            if let saved = defaults.string(forKey: abcKey), saved.contains("Coker Pattern") {
                isCokerTune = true
                await generateCoker()
            } else if let saved = defaults.string(forKey: abcKey), !saved.isEmpty {
                isCokerTune = false
                abcText = saved
                await renderNow()
            } else {
                await generateCoker()
            }
        } catch {
            warnings = [error.localizedDescription] + (bridge.jsErrors)
            BridgeDiagnostics.log("bootstrap failed: \(error)")
        }
    }

    func scheduleRender() {
        guard liveRender, bridge != nil else { return }
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await renderNow()
        }
    }

    func renderNow() async {
        guard let bridge else { return }
        title = ABCUtilities.parseTitle(abcText)
        guard !abcText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            warnings = []
            return
        }
        do {
            let result = try await bridge.render(abcText, measuresPerLine: measuresPerLine)
            var msgs = result.warnings
            msgs.append(contentsOf: bridge.jsErrors)
            warnings = msgs
            defaults.set(abcText, forKey: abcKey)
        } catch {
            warnings = [error.localizedDescription] + bridge.jsErrors
        }
    }

    func generateCoker() async {
        guard let bridge else { return }
        isCokerTune = true
        measuresPerLine = 1
        do {
            let gen = CokerGenerator(bridge: bridge)
            abcText = try await gen.generate(for: instrument)
            await renderNow()
        } catch {
            warnings = [error.localizedDescription]
        }
    }

    func instrumentChanged() async {
        defaults.set(instrument.rawValue, forKey: instKey)
        if isCokerTune { await generateCoker() }
        else { await renderNow() }
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
            isCokerTune = false
            abcText = text
            Task { await renderNow() }
        }
    }

    func saveABC() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "abc") ?? .plainText]
        panel.nameFieldStringValue = sanitizedFilename(from: title) + ".abc"
        if panel.runModal() == .OK, let url = panel.url {
            try? abcText.write(to: url, atomically: true, encoding: .utf8)
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