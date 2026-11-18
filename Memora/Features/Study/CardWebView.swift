//
//  CardWebView.swift
//  Memora
//
//  Renders card HTML in a WKWebView whose baseURL is the media directory, so
//  `<img src="x.png">` and `[sound:x]`→<audio> resolve to local files. A
//  content rule blocks any http/https load, so remote references in imported
//  decks never cause a network request — Memora stays fully offline.
//

import SwiftUI
import WebKit

struct CardWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsVerticalScrollIndicator = true

        // Block remote network loads (offline guarantee).
        let blockRules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "MemoraBlockRemote", encodedContentRuleList: blockRules) { list, _ in
            if let list { webView.configuration.userContentController.add(list) }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = "\u{0}"

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            // Allow the initial in-memory load and local files; block web links.
            if url.isFileURL || url.scheme == "about" || navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
