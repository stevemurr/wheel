import SwiftUI
import WebKit

struct WidgetDashboardPageView: View {
    private let layoutMaxWidth: CGFloat = 920
    private let textMaxWidth: CGFloat = 640

    @State private var store = WidgetDashboardStore()
    @State private var bridge = WidgetRuntimeBridge()
    @State private var schemeHandler = WidgetFetchSchemeHandler()
    @State private var showingPromptSheet = false
    @State private var runtimeHeight: CGFloat = 260
    let openLink: (URL) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 58)

                    VStack(spacing: 30) {
                        headerPanel
                        widgetStage
                    }
                    .frame(maxWidth: layoutMaxWidth)

                    Spacer(minLength: 220)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                .padding(.horizontal, 24)
            }
            .background {
                DashboardInteractionSurface()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack(alignment: .top) {
                Color(nsColor: .windowBackgroundColor)

                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(0.08),
                        Color.accentColor.opacity(0.025),
                        .clear,
                    ],
                    center: .top,
                    startRadius: 12,
                    endRadius: 500
                )
                .frame(height: 360)
                .offset(y: -110)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingPromptSheet) {
            WidgetPromptSheet(onCreate: addWidget) {
                showingPromptSheet = false
            }
        }
        .onAppear(perform: configureBridge)
        .onChange(of: store.pendingRefreshIDs) { _, ids in
            guard !ids.isEmpty else { return }
            flushPendingRefreshes(ids)
        }
    }

    private var headerPanel: some View {
        VStack(spacing: 22) {
            controls
            greeting
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    private var greeting: some View {
        VStack(spacing: 10) {
            Text(headerEyebrowText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Text(greetingText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("Live widgets run in a single sandboxed dashboard runtime and persist across launches.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
        }
        .frame(maxWidth: textMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var widgetStage: some View {
        WidgetDashboardWebView(
            records: store.records,
            isEditing: store.isEditing,
            bridge: bridge,
            schemeHandler: schemeHandler
        )
        .frame(maxWidth: layoutMaxWidth)
        .frame(height: max(runtimeHeight, 280))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 16, y: 8)
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if !store.records.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.isEditing.toggle()
                        syncDashboard()
                    }
                } label: {
                    Label(store.isEditing ? "Done" : "Edit", systemImage: store.isEditing ? "checkmark" : "slider.horizontal.3")
                }
                .buttonStyle(DashboardActionButtonStyle())
            }

            Button {
                showingPromptSheet = true
            } label: {
                Label("Add Widget", systemImage: "plus")
            }
            .buttonStyle(DashboardPrimaryActionButtonStyle())

            if !store.records.isEmpty {
                Button {
                    for record in store.records {
                        store.refresh(id: record.id)
                    }
                    flushPendingRefreshes(store.pendingRefreshIDs)
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .buttonStyle(DashboardActionButtonStyle())
            }
        }
        .padding(6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 10, y: 4)
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private var headerEyebrowText: String {
        Date.now.formatted(
            .dateTime
            .weekday(.wide)
            .month(.abbreviated)
            .day()
        )
        .uppercased()
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
            bridge.bootstrapDashboard(records: store.records, isEditing: store.isEditing)
            store.refreshStale()
            syncDashboard()
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
            syncDashboard()
        case .moveUp(let id):
            if let index = store.index(of: id), index > 0 {
                store.move(from: index, to: index - 1)
                syncDashboard()
            }
        case .moveDown(let id):
            if let index = store.index(of: id), index < store.records.count - 1 {
                store.move(from: index, to: index + 1)
                syncDashboard()
            }
        case .toggleLayout(let id):
            store.toggleLayoutPreference(id: id)
            syncDashboard()
        case .refresh(let id):
            store.refresh(id: id)
            flushPendingRefreshes(store.pendingRefreshIDs)
        case .openLink(_, let url):
            openLink(url)
        }
    }

    @MainActor
    private func addWidget(_ manifest: WidgetManifest) throws {
        try store.add(manifest: manifest)
        syncDashboard()
    }

    @MainActor
    private func syncDashboard() {
        schemeHandler.updateAllowedHosts(for: store.manifests)
        bridge.setDashboardState(records: store.records, isEditing: store.isEditing)
        flushPendingRefreshes(store.pendingRefreshIDs)
    }

    @MainActor
    private func flushPendingRefreshes(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let requested = ids
        for id in requested {
            bridge.refreshWidget(id: id)
        }
        store.consumePendingRefreshes(requested)
    }
}

private struct DashboardInteractionSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> DashboardInteractionNSView {
        DashboardInteractionNSView()
    }

    func updateNSView(_ nsView: DashboardInteractionNSView, context: Context) {}
}

private final class DashboardInteractionNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

private struct DashboardActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.72 : 0.86))
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(configuration.isPressed ? 0.09 : 0.06), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct DashboardPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.92 : 1))
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.84 : 0.96))
            )
            .shadow(color: Color.accentColor.opacity(0.18), radius: 10, y: 4)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct WidgetDashboardWebView: View {
    let records: [WidgetRecord]
    let isEditing: Bool
    let bridge: WidgetRuntimeBridge
    let schemeHandler: WidgetFetchSchemeHandler

    var body: some View {
        HostedWKWebView(
            spec: spec,
            update: { _ in
                // Runtime state is synced explicitly from the parent view to avoid clobbering
                // in-webview interactions during unrelated SwiftUI updates like height changes.
                schemeHandler.updateAllowedHosts(for: records.map(\.manifest))
            }
        )
    }

    private var spec: HostedWKWebViewSpec {
        HostedWKWebViewSpec(
            dataStorePolicy: .nonPersistent,
            schemeHandlers: [
                .init(scheme: "widget-fetch", handler: schemeHandler),
            ],
            scriptMessageHandlers: [
                .init(name: bridge.messageHandlerName, handler: bridge),
            ],
            makeWebView: { configuration in
                BrowserWebView(frame: .zero, configuration: configuration)
            },
            configure: { webView in
                webView.setValue(false, forKey: "drawsBackground")
                bridge.attach(to: webView)
            },
            initialLoad: initialLoad,
            teardown: { _ in
                bridge.detach()
            }
        )
    }

    private var initialLoad: HostedWKWebViewLoad {
        if let baseURL = WidgetRuntimeResources.runtimeDirectoryURL(),
           let html = try? WidgetRuntimeResources.inlineRuntimeHTML() {
            return .htmlString(html, baseURL: baseURL)
        }

        return .htmlString("<html><body>Widget runtime not found.</body></html>", baseURL: nil)
    }
}
