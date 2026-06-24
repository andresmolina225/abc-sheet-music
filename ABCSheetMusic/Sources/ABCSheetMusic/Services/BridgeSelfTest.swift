import AppKit
import Foundation

/// Run: swift run -- --self-test
/// Logs to ~/Library/Logs/ABCSheetMusic.log
@MainActor
enum BridgeSelfTest {
    static func run() async {
        BridgeDiagnostics.log("=== self-test start ===")
        let bridge = ABCBridge()

        // WKWebView must be in a window for reliable audio on macOS
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = bridge.webView
        window.orderBack(nil)

        do {
            try await bridge.waitUntilReady()
            BridgeDiagnostics.log("ready: \(bridge.signature) audio=\(bridge.audioSupported)")

            let abc = """
            X:1
            T:Self Test
            M:4/4
            L:1/8
            K:C
            (3 C E G (3 c G E C4 |
            """
            let render = try await bridge.render(abc, measuresPerLine: 1)
            BridgeDiagnostics.log("render ok=\(render.ok) warnings=\(render.warnings.count)")

            try await bridge.loadSynth(midiTranspose: 0, program: 0)
            BridgeDiagnostics.log("loadSynth OK")

            try await bridge.play()
            BridgeDiagnostics.log("play started")
            try await Task.sleep(nanoseconds: 3_000_000_000)
            try await bridge.stop()
            BridgeDiagnostics.log("=== self-test PASS ===")
        } catch {
            BridgeDiagnostics.log("=== self-test FAIL: \(error) ===")
        }
        window.close()
    }
}