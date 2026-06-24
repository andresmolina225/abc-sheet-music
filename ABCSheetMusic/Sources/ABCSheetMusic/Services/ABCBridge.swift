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

@MainActor
private final class WebViewJSQueue {
    private let webView: WKWebView
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(webView: WKWebView) { self.webView = webView }

    func eval(_ script: String) async throws -> Any? {
        await acquire()
        defer { release() }
        BridgeDiagnostics.log("JS: \(script.prefix(120))…")
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                Task { @MainActor in
                    if let error {
                        BridgeDiagnostics.log("JS error: \(error.localizedDescription)")
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: value)
                    }
                }
            }
        }
    }

    /// WKWebView cannot return Promises from evaluateJavaScript (Code=5); callAsyncJavaScript awaits them.
    func evalAsync(_ functionBody: String) async throws -> Any? {
        await acquire()
        defer { release() }
        BridgeDiagnostics.log("JS async: \(functionBody.prefix(120))…")
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
            webView.callAsyncJavaScript(functionBody, arguments: [:], in: nil, in: .page) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let value):
                        cont.resume(returning: value)
                    case .failure(let error):
                        BridgeDiagnostics.log("JS async error: \(error.localizedDescription)")
                        cont.resume(throwing: error)
                    }
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
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private let schemeHandler: LocalSchemeHandler?

    override init() {
        BridgeDiagnostics.log("ABCBridge init")
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let handler = BridgeScriptHandler()
        config.userContentController.add(handler, name: "bridge")

        var scheme: LocalSchemeHandler?
        if let resourceURL = Bundle.module.resourceURL {
            scheme = LocalSchemeHandler(rootURL: resourceURL)
            config.setURLSchemeHandler(scheme, forURLScheme: "abcapp")
            BridgeDiagnostics.log("Resources at \(resourceURL.path)")
        } else {
            BridgeDiagnostics.log("ERROR: no Bundle.module.resourceURL")
        }
        schemeHandler = scheme

        let wv = NonFocusWebView(frame: .zero, configuration: config)
        webView = wv
        jsQueue = WebViewJSQueue(webView: wv)

        super.init()
        handler.owner = self
        wv.navigationDelegate = self
        wv.underPageBackgroundColor = .clear

        if let url = URL(string: "abcapp:///Bridge/index.html") {
            BridgeDiagnostics.log("Loading \(url.absoluteString)")
            wv.load(URLRequest(url: url))
        }
    }

    fileprivate func handleBridgeMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            signature = body["signature"] as? String ?? "abcjs"
            audioSupported = body["audioSupported"] as? Bool ?? false
            BridgeDiagnostics.log("Bridge ready · \(signature) · audio=\(audioSupported)")
            finishReady()
        case "playbackFinished":
            NotificationCenter.default.post(name: .abcPlaybackFinished, object: nil)
        case "jsError", "error":
            let msg = body["message"] as? String ?? "JavaScript error"
            BridgeDiagnostics.log("JS: \(msg)")
            appendJSError(msg)
        case "log":
            if let msg = body["message"] as? String {
                BridgeDiagnostics.log("JS log: \(msg)")
                appendJSError(msg)
            }
        default:
            break
        }
    }

    private func finishReady() {
        guard !isReady else { return }
        isReady = true
        let waiters = readyWaiters
        readyWaiters = []
        for w in waiters { w.resume() }
    }

    private func failAllWaiters(_ error: Error) {
        let waiters = readyWaiters
        readyWaiters = []
        for w in waiters { w.resume(throwing: error) }
    }

    private func appendJSError(_ msg: String) {
        guard !jsErrors.contains(msg) else { return }
        jsErrors.append(msg)
        if jsErrors.count > 8 { jsErrors.removeFirst() }
    }

    func waitUntilReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            readyWaiters.append(cont)
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
        let result = try await evalAsyncJSON("ABCBridge.loadSynth(\(midiTranspose), \(program))")
        try Self.requireOK(result, context: "loadSynth")
    }

    func play() async throws {
        try await waitUntilReady()
        let result = try await evalAsyncJSON("ABCBridge.play()")
        try Self.requireOK(result, context: "play")
        BridgeDiagnostics.log("play OK")
    }

    private func evalAsyncJSON(_ call: String) async throws -> [String: Any] {
        let body = "return JSON.stringify(await \(call));"
        let value = try await jsQueue.evalAsync(body)
        if let json = value as? String,
           let data = json.data(using: .utf8),
           let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        if let obj = value as? [String: Any] { return obj }
        BridgeDiagnostics.log("evalAsyncJSON unexpected: \(String(describing: value))")
        throw BridgeError.badResponse
    }

    func stop() async throws {
        try await waitUntilReady()
        _ = try await jsQueue.eval("ABCBridge.stop()")
    }

    private static func requireOK(_ dict: [String: Any], context: String) throws {
        let ok = dict["ok"] as? Bool ?? false
        if !ok {
            let err = dict["error"] as? String ?? "\(context) failed"
            BridgeDiagnostics.log("\(context): \(err)")
            throw BridgeError.synthFailed(err)
        }
    }
}

extension ABCBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        BridgeDiagnostics.log("WebView didFinish")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        BridgeDiagnostics.log("didFail: \(error.localizedDescription)")
        appendJSError("Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        BridgeDiagnostics.log("didFailProvisional: \(error.localizedDescription)")
        appendJSError("Load failed: \(error.localizedDescription)")
        failAllWaiters(BridgeError.missingBridgeHTML)
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