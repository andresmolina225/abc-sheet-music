import AppKit
import SwiftUI
import WebKit

/// Hosts the abcjs WKWebView — created only when this view appears (avoids early WebKit init crash).
struct ScoreWebView: NSViewRepresentable {
    @ObservedObject var bridge: ABCBridge

    func makeNSView(context: Context) -> WKWebView {
        bridge.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}