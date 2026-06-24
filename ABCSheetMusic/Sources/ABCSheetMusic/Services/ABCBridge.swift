import AppKit
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

/// Serializes evaluateJavaScript — all callbacks resume on MainActor.
@MainActor
private final class WebViewJSQueue {
    private let webView: WKWebView
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(webView: WKWebView) { self.webView = webView }

    func eval(_ script: String) async throws -> Any? {
        await acquire()
        defer { release() }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                Task { @MainActor in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: value) }
                }
            }
        }
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false; return }
        waiters.removeFirst().resume()
    }
}

@MainActor
final class ABCBridge: NSObject, ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var signature = "abcjs…"
    @Published private(set) var audioSupported = false
    @Published private(set) var jsErrors: [String] = []

    private(set) var webView: WKWebView!
    private var jsQueue: WebViewJSQueue!
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private let schemeHandler: LocalSchemeHandler?

    override init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let handler = BridgeScriptHandler()
        config.userContentController.add(handler, name: "bridge")

        var scheme: LocalSchemeHandler?
        if let resourceURL = Bundle.module.resourceURL {
            scheme = LocalSchemeHandler(rootURL: resourceURL)
            config.setURLSchemeHandler(scheme, forURLScheme: "abcapp")
        }
        schemeHandler = scheme

        let wv = WKWebView(frame: .zero, configuration: config)
        webView = wv
        jsQueue = WebViewJSQueue(webView: wv)

        super.init()
        handler.owner = self
        wv.navigationDelegate = self
        wv.underPageBackgroundColor = .clear

        if let url = URL(string: "abcapp:///Bridge/index.html") {
            wv.load(URLRequest(url: url))
        }
    }

    fileprivate func handleBridgeMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            signature = body["signature"] as? String ?? "abcjs"
            audioSupported = body["audioSupported"] as? Bool ?? false
            finishReady()
        case "playbackFinished":
            NotificationCenter.default.post(name: .abcPlaybackFinished, object: nil)
        case "jsError", "error":
            appendJSError(body["message"] as? String ?? "JavaScript error")
        case "log":
            if let msg = body["message"] as? String { appendJSError(msg) }
        default:
            break
        }
    }

    private func finishReady() {
        guard !isReady else { return }
        isReady = true
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume()
        }
    }

    private func appendJSError(_ msg: String) {
        guard !jsErrors.contains(msg) else { return }
        jsErrors.append(msg)
        if jsErrors.count > 8 { jsErrors.removeFirst() }
    }

    private func failReady(_ error: Error) {
        if let cont = readyContinuation {
            readyContinuation = nil
            cont.resume(throwing: error)
        }
    }

    func waitUntilReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            readyContinuation = cont
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if !self.isReady {
                    self.failReady(BridgeError.timeout)
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
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        appendJSError("Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        appendJSError("Load failed: \(error.localizedDescription)")
        failReady(BridgeError.missingBridgeHTML)
    }
}

enum BridgeError: LocalizedError {
    case missingBridgeHTML
    case timeout
    case badResponse
    case synthFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBridgeHTML: return "abcjs bridge page failed to load."
        case .timeout: return "abcjs bridge timed out."
        case .badResponse: return "Unexpected abcjs response."
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
        DispatchQueue.main.async { [weak self] in
            self?.owner?.handleBridgeMessage(body)
        }
    }
}

private extension String {
    var jsLiteral: String {
        guard let data = try? JSONEncoder().encode(self),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }
}