import SwiftUI
import WebKit

enum HostedWKWebViewLoad {
    case request(URLRequest)
    case htmlString(String, baseURL: URL?)
    case fileURL(URL, allowingReadAccessTo: URL)
}

struct HostedWKWebViewSpec {
    enum DataStorePolicy {
        case persistent
        case nonPersistent
    }

    struct URLSchemeHandlerRegistration {
        let scheme: String
        let handler: WKURLSchemeHandler
    }

    struct ScriptMessageHandlerRegistration {
        let name: String
        let handler: WKScriptMessageHandler
    }

    var dataStorePolicy: DataStorePolicy = .persistent
    var schemeHandlers: [URLSchemeHandlerRegistration] = []
    var scriptMessageHandlers: [ScriptMessageHandlerRegistration] = []
    var makeConfiguration: (() -> WKWebViewConfiguration)?
    var makeWebView: ((WKWebViewConfiguration) -> WKWebView)?
    var configure: ((WKWebView) -> Void)?
    var initialLoad: HostedWKWebViewLoad?
    var teardown: ((WKWebView) -> Void)?

    init(
        dataStorePolicy: DataStorePolicy = .persistent,
        schemeHandlers: [URLSchemeHandlerRegistration] = [],
        scriptMessageHandlers: [ScriptMessageHandlerRegistration] = [],
        makeConfiguration: (() -> WKWebViewConfiguration)? = nil,
        makeWebView: ((WKWebViewConfiguration) -> WKWebView)? = nil,
        configure: ((WKWebView) -> Void)? = nil,
        initialLoad: HostedWKWebViewLoad? = nil,
        teardown: ((WKWebView) -> Void)? = nil
    ) {
        self.dataStorePolicy = dataStorePolicy
        self.schemeHandlers = schemeHandlers
        self.scriptMessageHandlers = scriptMessageHandlers
        self.makeConfiguration = makeConfiguration
        self.makeWebView = makeWebView
        self.configure = configure
        self.initialLoad = initialLoad
        self.teardown = teardown
    }
}

enum WKWebViewHost {
    static func build(spec: HostedWKWebViewSpec) -> WKWebView {
        let configuration = makeConfiguration(for: spec)
        let webView = spec.makeWebView?(configuration) ?? WKWebView(frame: .zero, configuration: configuration)
        attach(webView, spec: spec)
        return webView
    }

    static func attach(_ webView: WKWebView, spec: HostedWKWebViewSpec) {
        registerScriptMessageHandlers(for: spec, on: webView)
        spec.configure?(webView)

        if let initialLoad = spec.initialLoad {
            load(initialLoad, into: webView)
        }
    }

    static func dismantle(_ webView: WKWebView, spec: HostedWKWebViewSpec) {
        for registration in spec.scriptMessageHandlers {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: registration.name)
        }
        spec.teardown?(webView)
    }

    private static func makeConfiguration(for spec: HostedWKWebViewSpec) -> WKWebViewConfiguration {
        let configuration = spec.makeConfiguration?() ?? WKWebViewConfiguration()

        if spec.makeConfiguration == nil {
            configuration.websiteDataStore = {
                switch spec.dataStorePolicy {
                case .persistent:
                    return .default()
                case .nonPersistent:
                    return .nonPersistent()
                }
            }()
        }

        for registration in spec.schemeHandlers {
            configuration.setURLSchemeHandler(registration.handler, forURLScheme: registration.scheme)
        }

        return configuration
    }

    private static func registerScriptMessageHandlers(for spec: HostedWKWebViewSpec, on webView: WKWebView) {
        for registration in spec.scriptMessageHandlers {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: registration.name)
            webView.configuration.userContentController.add(registration.handler, name: registration.name)
        }
    }

    private static func load(_ load: HostedWKWebViewLoad, into webView: WKWebView) {
        switch load {
        case .request(let request):
            webView.load(request)
        case .htmlString(let html, let baseURL):
            webView.loadHTMLString(html, baseURL: baseURL)
        case .fileURL(let fileURL, let readAccessURL):
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
        }
    }
}

struct HostedWKWebView: NSViewRepresentable {
    final class Coordinator {
        let spec: HostedWKWebViewSpec

        init(spec: HostedWKWebViewSpec) {
            self.spec = spec
        }
    }

    let spec: HostedWKWebViewSpec
    var update: ((WKWebView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(spec: spec)
    }

    func makeNSView(context: Context) -> WKWebView {
        WKWebViewHost.build(spec: spec)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        update?(nsView)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        WKWebViewHost.dismantle(nsView, spec: coordinator.spec)
    }
}
