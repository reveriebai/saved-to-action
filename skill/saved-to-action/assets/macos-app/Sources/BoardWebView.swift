import AppKit
import SwiftUI
import WebKit

struct BoardWebView: NSViewRepresentable {
    @ObservedObject var model: ActionModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        Self.makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pushPayload()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    @MainActor
    static func makeStandalone(model: ActionModel) -> (webView: WKWebView, coordinator: Coordinator) {
        let coordinator = Coordinator(model: model)
        return (makeWebView(coordinator: coordinator), coordinator)
    }

    private static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(coordinator, name: "boardStateDidChange")
        controller.add(coordinator, name: "openSource")
        controller.add(coordinator, name: "convertRevisit")
        controller.add(coordinator, name: "openRevisit")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InteractiveWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        coordinator.webView = webView
        if let url = Bundle.main.url(forResource: "Board", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        let model: ActionModel

        init(model: ActionModel) { self.model = model }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { pushPayload() }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url, url.scheme != "file" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "boardStateDidChange", let json = message.body as? String {
                SharedActionStore.importState(from: json)
                model.reload()
                pushPayload()
            } else if message.name == "openSource", let id = message.body as? String {
                SharedActionStore.openSource(actionID: id)
            } else if message.name == "convertRevisit" {
                _ = SharedActionStore.convertRevisit()
                model.reload()
                pushPayload()
            } else if message.name == "openRevisit" {
                SharedActionStore.openRevisitSource()
            }
        }

        func pushPayload() {
            let payload = SharedActionStore.boardPayloadBase64()
            webView?.evaluateJavaScript("window.applyNativePayloadBase64?.('\(payload)');")
        }
    }
}

private final class InteractiveWKWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}
