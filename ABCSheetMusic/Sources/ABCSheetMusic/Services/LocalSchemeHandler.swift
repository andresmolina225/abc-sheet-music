import Foundation
import WebKit

/// Serves bundled resources at `abcapp:///…` (three-slash paths).
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    private let rootURL: URL
    private let lock = NSLock()
    private var stopped = Set<ObjectIdentifier>()

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // abcapp:///Bridge/index.html → Bridge/index.html
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty, let host = url.host, !host.isEmpty { path = host }

        let fileURL = rootURL.appendingPathComponent(path)
        guard fileURL.path.hasPrefix(rootURL.path),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard !self.isStopped(taskID) else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                guard !self.isStopped(taskID) else { return }
                let mime = Self.mimeType(for: fileURL.pathExtension)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": mime]
                )!
                DispatchQueue.main.async {
                    guard !self.isStopped(taskID) else { return }
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                }
            } catch {
                DispatchQueue.main.async {
                    guard !self.isStopped(taskID) else { return }
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        stopped.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }

    private func isStopped(_ id: ObjectIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped.contains(id)
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js":   return "application/javascript; charset=utf-8"
        case "css":  return "text/css; charset=utf-8"
        case "abc":  return "text/plain; charset=utf-8"
        default:     return "application/octet-stream"
        }
    }
}