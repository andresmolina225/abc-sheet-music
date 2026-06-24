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

    let bridge = ABCBridge()

    private var renderTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let abcKey = "abc-sheet-swift-abc"
    private let instKey = "abc-sheet-swift-inst"

    init() {
        bridgeSignature = bridge.signature
        if let raw = defaults.string(forKey: instKey), let inst = Instrument(rawValue: raw) {
            instrument = inst
        }
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        do {
            try await bridge.waitUntilReady()
            bridgeSignature = bridge.signature
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
            warnings = [error.localizedDescription]
        }
    }

    func scheduleRender() {
        guard liveRender else { return }
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await renderNow()
        }
    }

    func renderNow() async {
        title = ABCUtilities.parseTitle(abcText)
        guard !abcText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            warnings = []
            return
        }
        do {
            let result = try await bridge.render(abcText, measuresPerLine: measuresPerLine)
            warnings = result.warnings
            if result.hasVisual {
                try await bridge.loadSynth(
                    midiTranspose: instrument.midiTranspose,
                    program: instrument.midiProgram
                )
            }
            defaults.set(abcText, forKey: abcKey)
        } catch {
            warnings = [error.localizedDescription]
        }
    }

    func generateCoker() async {
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
        if isCokerTune {
            await generateCoker()
        } else {
            await renderNow()
        }
    }

    func play() async {
        isPlaying = true
        do {
            try await bridge.play()
        } catch {
            warnings = [error.localizedDescription]
            isPlaying = false
        }
    }

    func stop() async {
        try? await bridge.stop()
        isPlaying = false
    }

    func openABC() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText]
        if let abc = UTType(filenameExtension: "abc") { types.append(abc) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                isCokerTune = false
                abcText = text
                Task { await renderNow() }
            }
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