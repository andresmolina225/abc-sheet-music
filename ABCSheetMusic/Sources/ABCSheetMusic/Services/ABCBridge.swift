import Foundation
import WebKit

struct RenderResult: Codable {
    let ok: Bool
    let warnings: [String]
    let hasVisual: Bool
}

struct SimpleResult: Codable {
    let ok: Bool
    var error: String?
}

@MainActor
final class ABCBridge: NSObject, ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var signature = "abcjs…"

    let webView: WKWebView

    private var readyContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let handler = BridgeScriptHandler()
        config.userContentController.add(handler, name: "bridge")
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        handler.owner = self
        webView.setValue(false, forKey: "drawsBackground")
        loadBridgePage()
    }

    private func loadBridgePage() {
        guard let resourceURL = Bundle.module.resourceURL else {
            markFailed(BridgeError.missingResources)
            return
        }
        let bridgeURL = resourceURL
            .appendingPathComponent("Bridge", isDirectory: true)
            .appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: bridgeURL.path) else {
            markFailed(BridgeError.missingBridgeHTML)
            return
        }
        webView.loadFileURL(bridgeURL, allowingReadAccessTo: resourceURL)
    }

    fileprivate func handleBridgeMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        if type == "ready" {
            signature = body["signature"] as? String ?? "abcjs"
            isReady = true
            readyContinuation?.resume()
            readyContinuation = nil
        } else if type == "playbackFinished" {
            NotificationCenter.default.post(name: .abcPlaybackFinished, object: nil)
        }
    }

    private func markFailed(_ error: Error) {
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }

    func waitUntilReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            readyContinuation = cont
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if !self.isReady {
                    self.readyContinuation?.resume(throwing: BridgeError.timeout)
                    self.readyContinuation = nil
                }
            }
        }
    }

    func transpose(_ abc: String, steps: Int) async throws -> String {
        try await waitUntilReady()
        let arg = abc.jsLiteral
        guard let value = try await evaluateJavaScript("ABCBridge.transpose(\(arg), \(steps))") as? String else {
            throw BridgeError.badResponse
        }
        return value
    }

    func render(_ abc: String, measuresPerLine: Int) async throws -> RenderResult {
        try await waitUntilReady()
        let arg = abc.jsLiteral
        guard let json = try await evaluateJavaScript("JSON.stringify(ABCBridge.render(\(arg), \(measuresPerLine)))") as? String,
              let data = json.data(using: .utf8) else {
            throw BridgeError.badResponse
        }
        return try JSONDecoder().decode(RenderResult.self, from: data)
    }

    func loadSynth(midiTranspose: Int, program: Int) async throws {
        try await waitUntilReady()
        guard let json = try await evaluateJavaScript(
            "JSON.stringify(ABCBridge.loadSynth(\(midiTranspose), \(program)))"
        ) as? String,
              let data = json.data(using: .utf8) else {
            throw BridgeError.badResponse
        }
        let result = try JSONDecoder().decode(SimpleResult.self, from: data)
        if !result.ok { throw BridgeError.synthFailed(result.error ?? "unknown") }
    }

    func play() async throws {
        try await waitUntilReady()
        guard let json = try await evaluateJavaScript("JSON.stringify(ABCBridge.play())") as? String,
              let data = json.data(using: .utf8) else {
            throw BridgeError.badResponse
        }
        let result = try JSONDecoder().decode(SimpleResult.self, from: data)
        if !result.ok { throw BridgeError.synthFailed(result.error ?? "playback failed") }
    }

    func stop() async throws {
        try await waitUntilReady()
        _ = try await evaluateJavaScript("ABCBridge.stop()")
    }

    @discardableResult
    private func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(script) { value, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: value) }
            }
        }
    }
}

enum BridgeError: LocalizedError {
    case missingResources
    case missingBridgeHTML
    case timeout
    case badResponse
    case synthFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingResources: return "App resources not found."
        case .missingBridgeHTML: return "abcjs bridge page not found."
        case .timeout: return "abcjs bridge timed out loading."
        case .badResponse: return "Unexpected response from abcjs."
        case .synthFailed(let msg): return msg
        }
    }
}

extension Notification.Name {
    static let abcPlaybackFinished = Notification.Name("abcPlaybackFinished")
}

private final class BridgeScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: ABCBridge?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bridge", let body = message.body as? [String: Any] else { return }
        Task { @MainActor in owner?.handleBridgeMessage(body) }
    }
}

private extension String {
    /// Encode as a JS string literal for evaluateJavaScript.
    var jsLiteral: String {
        if let data = try? JSONEncoder().encode(self),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\""
    }
}