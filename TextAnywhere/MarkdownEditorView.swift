//
// Created by ktiays on 2026/10/23.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import SwiftUI
import WebKit

/// Hosts the bundled Markdown editor and keeps its document in sync with the draft.
/// The web view is created lazily and reused, so switching modes doesn't reload the page.
@MainActor
final class MarkdownEditorController: NSObject, WKNavigationDelegate {

    private static let messageHandlerName = "markdownEditor"

    var onChange: ((String) -> Void)?

    private var isReady = false
    private var syncedMarkdown: String?
    private var pendingScripts: [(source: String, arguments: [String: Any])] = []

    private(set) lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(
            MessageHandler(controller: self),
            name: Self.messageHandlerName
        )
        let webView = MarkdownEditorWebView(frame: .zero, configuration: configuration)
        webView.onUndo = { [weak self] in
            self?.evaluate("markdownEditor.undo()")
        }
        webView.onRedo = { [weak self] in
            self?.evaluate("markdownEditor.redo()")
        }
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")
        loadEditor(in: webView)
        return webView
    }()

    /// Starts a fresh editing session with `markdown`, discarding the editor's undo history.
    func load(_ markdown: String) {
        syncedMarkdown = markdown
        evaluate("markdownEditor.setMarkdown(markdown)", arguments: ["markdown": markdown])
    }

    /// Applies a draft change made outside the editor, keeping it undoable in the editor.
    func update(_ markdown: String) {
        guard markdown != syncedMarkdown else { return }
        syncedMarkdown = markdown
        evaluate(
            "markdownEditor.setMarkdown(markdown, { preservingHistory: true })",
            arguments: ["markdown": markdown]
        )
    }

    func setEditable(_ isEditable: Bool) {
        evaluate("markdownEditor.setEditable(editable)", arguments: ["editable": isEditable])
    }

    func setPlaceholder(_ placeholder: String) {
        evaluate("markdownEditor.setPlaceholder(placeholder)", arguments: ["placeholder": placeholder])
    }

    func focus() {
        webView.window?.makeFirstResponder(webView)
        evaluate("markdownEditor.focus()")
    }

    private func evaluate(_ source: String, arguments: [String: Any] = [:]) {
        guard isReady else {
            pendingScripts.append((source, arguments))
            return
        }
        webView.callAsyncJavaScript(source, arguments: arguments, in: nil, in: .page)
    }

    private func loadEditor(in webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: "MarkdownEditor", withExtension: "html") else {
            assertionFailure("MarkdownEditor.html is missing from the app bundle.")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            let scripts = pendingScripts
            pendingScripts = []
            for script in scripts {
                webView.callAsyncJavaScript(script.source, arguments: script.arguments, in: nil, in: .page)
            }
        case "change":
            guard let markdown = message["markdown"] as? String else { return }
            syncedMarkdown = markdown
            onChange?(markdown)
        case "openLink":
            guard let value = message["url"] as? String,
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else {
                return
            }
            NSWorkspace.shared.open(url)
        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        if let syncedMarkdown {
            pendingScripts = [("markdownEditor.setMarkdown(markdown)", ["markdown": syncedMarkdown])]
        }
        loadEditor(in: webView)
    }
}

/// The editor keeps its own history, so WebKit's undo stack stays empty and the Edit menu's
/// Undo and Redo would do nothing. Route those actions to the editor instead.
private final class MarkdownEditorWebView: WKWebView {

    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?

    @objc func undo(_ sender: Any?) {
        onUndo?()
    }

    @objc func redo(_ sender: Any?) {
        onRedo?()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)), #selector(redo(_:)):
            true
        default:
            super.validateUserInterfaceItem(item)
        }
    }
}

/// Forwards script messages without retaining the controller, which owns the web view.
private final class MessageHandler: NSObject, WKScriptMessageHandler {

    private weak var controller: MarkdownEditorController?

    init(controller: MarkdownEditorController) {
        self.controller = controller
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            controller?.receive(message.body)
        }
    }
}

struct MarkdownEditorView: NSViewRepresentable {

    let controller: MarkdownEditorController
    let markdown: String
    let placeholder: String
    let isEditable: Bool
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        controller.onChange = onChange
        controller.load(markdown)
        controller.setEditable(isEditable)
        controller.setPlaceholder(placeholder)
        context.coordinator.isEditable = isEditable
        context.coordinator.placeholder = placeholder
        DispatchQueue.main.async {
            controller.focus()
        }
        return controller.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        controller.onChange = onChange
        controller.update(markdown)
        if context.coordinator.isEditable != isEditable {
            context.coordinator.isEditable = isEditable
            controller.setEditable(isEditable)
        }
        if context.coordinator.placeholder != placeholder {
            context.coordinator.placeholder = placeholder
            controller.setPlaceholder(placeholder)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var isEditable = true
        var placeholder = ""
    }
}
