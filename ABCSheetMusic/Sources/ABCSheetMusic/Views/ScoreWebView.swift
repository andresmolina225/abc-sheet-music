import AppKit
import SwiftUI
import WebKit

/// Hosts the abcjs WKWebView for score display.
struct ScoreWebView: NSViewRepresentable {
    @ObservedObject var bridge: ABCBridge

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        guard let wv = bridge.webView else { return container }
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let wv = bridge.webView, wv.superview !== container else { return }
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}