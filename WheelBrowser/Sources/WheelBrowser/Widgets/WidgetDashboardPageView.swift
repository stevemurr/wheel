import SwiftUI
import WebKit

struct WidgetDashboardPageView: View {
    @State private var store = WidgetDashboardStore()
    @State private var bridge = WidgetRuntimeBridge()
    @State private var schemeHandler = WidgetFetchSchemeHandler()
    @State private var showingPromptSheet = false
    @State private var runtimeHeight: CGFloat = 260
    let openLink: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                greeting

                WidgetDashboardWebView(
                    records: store.records,
                    isEditing: store.isEditing,
                    bridge: bridge,
                    schemeHandler: schemeHandler
                )
                .frame(maxWidth: .infinity)
                .frame(height: max(runtimeHeight, 260))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            controls
                .padding(24)
        }
        .sheet(isPresented: $showingPromptSheet) {
            WidgetPromptSheet(store: store) {
                showingPromptSheet = false
            }
        }
        .onAppear(perform: configureBridge)
        .onChange(of: store.pendingRefreshIDs) { _, ids in
            guard !ids.isEmpty else { return }
            let requested = ids
            for id in requested {
                bridge.refreshWidget(id: id)
            }
            store.consumePendingRefreshes(requested)
        }
    }

    private var greeting: some View {
        VStack(spacing: 8) {
            Text(greetingText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Live widgets run in a single sandboxed dashboard runtime and persist across launches.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if !store.records.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.isEditing.toggle()
                    }
                } label: {
                    Label(store.isEditing ? "Done" : "Edit", systemImage: store.isEditing ? "checkmark" : "slider.horizontal.3")
                }
                .buttonStyle(.bordered)

                Button {
                    for record in store.records {
                        store.refresh(id: record.id)
                    }
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            Button {
                showingPromptSheet = true
            } label: {
                Label("Add Widget", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    private func configureBridge() {
        bridge.onReady = {
            schemeHandler.updateAllowedHosts(for: store.manifests)
            bridge.bootstrapDashboard(records: store.records, isEditing: store.isEditing)
            store.refreshStale()
        }
        bridge.onWidgetLoaded = { id in
            store.markLoaded(id: id)
        }
        bridge.onWidgetError = { id, message in
            store.markError(id: id, message: message)
        }
        bridge.onHeightChanged = { height in
            runtimeHeight = height
        }
        bridge.onRuntimeError = { message in
            Log.Widgets.error("Widget runtime error: \(message)")
        }
        bridge.onWidgetAction = { action in
            handleAction(action)
        }
    }

    private func handleAction(_ action: WidgetRuntimeAction) {
        switch action {
        case .remove(let id):
            store.remove(id: id)
        case .moveUp(let id):
            if let index = store.index(of: id), index > 0 {
                store.move(from: index, to: index - 1)
            }
        case .moveDown(let id):
            if let index = store.index(of: id), index < store.records.count - 1 {
                store.move(from: index, to: index + 1)
            }
        case .refresh(let id):
            store.refresh(id: id)
        case .openLink(_, let url):
            openLink(url)
        }
    }
}

private struct WidgetDashboardWebView: NSViewRepresentable {
    let records: [WidgetRecord]
    let isEditing: Bool
    let bridge: WidgetRuntimeBridge
    let schemeHandler: WidgetFetchSchemeHandler

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "widget-fetch")
        configuration.userContentController.add(bridge, name: "widgetBridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        bridge.attach(to: webView)

        if let htmlURL = WidgetRuntimeResources.runtimeHTMLURL() {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<html><body>Widget runtime not found.</body></html>", baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        schemeHandler.updateAllowedHosts(for: records.map(\.manifest))
        bridge.setDashboardState(records: records, isEditing: isEditing)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "widgetBridge")
    }
}
