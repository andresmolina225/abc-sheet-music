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

struct PingResult: Codable {
    let ok: Bool
    let signature: String?
    let audioSupported: Bool?
}

/// Serializes all evaluateJavaScript calls — prevents overlapping render/transpose errors.
@MainActor
private final class WebViewJSQueue {
    private let webView: WKWebView
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(webView: WKWebView) { self.webView = webView }

    func eval(_ script: String) async throws -> Any? {
        await acquire()
        defer { release() }
        return try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(script) { value, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: value) }
            }
        }
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false; return }
        let next = waiters.removeFirst()
        next.resume()
    }
}

@MainActor
final class ABCBridge: NSObject, ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var signature = "abcjs…"
    @Published private(set) var audioSupported = false
    @Published private(set) var jsErrors: [String] = []

    let webView: WKWebView
    private let jsQueue: WebViewJSQueue
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var schemeHandler: LocalSchemeHandler?

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "javascriptEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let handler = BridgeScriptHandler()
        config.userContentController.add(handler, name: "bridge")

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        jsQueue = WebViewJSQueue(webView: webView)

        super.init()
        handler.owner = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        loadBridgePage()
    }

    private func loadBridgePage() {
        guard let resourceURL = Bundle.module.resourceURL else {
            markFailed(BridgeError.missingResources)
            return
        }
        let scheme = LocalSchemeHandler(rootURL: resourceURL)
        schemeHandler = scheme
        webView.configuration.setURLSchemeHandler(scheme, forURLScheme: "abcapp")

        guard let url = URL(string: "abcapp://Bridge/index.html") else {
            markFailed(BridgeError.missingBridgeHTML)
            return
        }
        webView.load(URLRequest(url: url))
    }

    fileprivate func handleBridgeMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            signature = body["signature"] as? String ?? "abcjs"
            audioSupported = body["audioSupported"] as? Bool ?? false
            isReady = true
            readyContinuation?.resume()
            readyContinuation = nil
        case "playbackFinished":
            NotificationCenter.default.post(name: .abcPlaybackFinished, object: nil)
        case "jsError", "error":
            let msg = body["message"] as? String ?? "JavaScript error"
            appendJSError(msg)
        case "log":
            if let msg = body["message"] as? String { appendJSError(msg) }
        default:
            break
        }
    }

    private func appendJSError(_ msg: String) {
        guard !jsErrors.contains(msg) else { return }
        jsErrors.append(msg)
        if jsErrors.count > 8 { jsErrors.removeFirst() }
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
                try? await Task.sleep(nanoseconds: 12_000_000_000)
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
        guard let value = try await jsQueue.eval("ABCBridge.transpose(\(arg), \(steps))") as? String else {
            throw BridgeError.badResponse
        }
        return value
    }

    func render(_ abc: String, measuresPerLine: Int) async throws -> RenderResult {
        try await waitUntilReady()
        let arg = abc.jsLiteral
        guard let json = try await jsQueue.eval(
            "JSON.stringify(ABCBridge.render(\(arg), \(measuresPerLine)))"
        ) as? String,
              let data = json.data(using: .utf8) else {
            throw BridgeError.badResponse
        }
        return try JSONDecoder().decode(RenderResult.self, from: data)
    }

    func loadSynth(midiTranspose: Int, program: Int) async throws {
        try await waitUntilReady()
        guard let json = try await jsQueue.eval(
            "JSON.stringify(ABCBridge.loadSynth(\(midiTranspose), \(program)))"
        ) as? String,
              let data = json.data(using: .utf8) else {
            throw BridgeError.badResponse
        }
        let result = try JSONDecoder().decode(SimpleResult.self, from: data)
        if !result.ok { throw BridgeError.synthFailed(result.error ?? "Synth load failed") }
    }

    func play() async throws {
        try await waitUntilReady()
        guard let json = try await jsQueue.eval("JSON.stringify(ABCBridge.play())") as? String,
              let data = json.data(using: .utf8) else {
            throw BridgeError.badResponse
        }
        let result = try JSONDecoder().decode(SimpleResult.self, from: data)
        if !result.ok { throw BridgeError.synthFailed(result.error ?? "Playback failed") }
    }

    func stop() async throws {
        try await waitUntilReady()
        _ = try await jsQueue.eval("ABCBridge.stop()")
    }
}

extension ABCBridge: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in appendJSError("Navigation failed: \(error.localizedDescription)") }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in appendJSError("Load failed: \(error.localizedDescription)") }
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
    var jsLiteral: String {
        if let data = try? JSONEncoder().encode(self),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\""
    }
}