import SwiftUI

/// The main new tab page view, powered by the pipeline widget system.
struct PipelineNewTabPageView: View {
    @State private var widgetStore = WidgetStore()
    @State private var showingPromptSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                greeting
                widgetGrid
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            addWidgetButton
        }
        .sheet(isPresented: $showingPromptSheet) {
            WidgetPromptSheet(store: widgetStore) {
                showingPromptSheet = false
            }
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(spacing: 4) {
            Text(greetingText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if widgetStore.widgets.isEmpty {
                Text("Add widgets to customize your new tab page")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
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

    // MARK: - Widget Grid

    private var widgetGrid: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 16)
        ], spacing: 16) {
            ForEach(widgetStore.widgets) { widget in
                PipelineWidgetContainerView(
                    widget: widget,
                    isEditMode: widgetStore.isEditMode,
                    onRemove: { widgetStore.removeWidget(id: widget.id) }
                )
            }
        }
    }

    // MARK: - Add Widget Button

    private var addWidgetButton: some View {
        Button(action: { showingPromptSheet = true }) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add Widget")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .padding(24)
    }
}
