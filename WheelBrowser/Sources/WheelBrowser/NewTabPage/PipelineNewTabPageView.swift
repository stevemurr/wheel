import SwiftUI

/// The main new tab page view, powered by the pipeline widget system.
struct PipelineNewTabPageView: View {
    @State private var widgetStore = WidgetStore()
    @State private var showingPromptSheet = false
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                greeting
                if widgetStore.widgets.isEmpty {
                    emptyState
                } else {
                    widgetGrid
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                if !widgetStore.widgets.isEmpty {
                    editButton
                }
                addWidgetButton
            }
            .padding(24)
        }
        .sheet(isPresented: $showingPromptSheet) {
            WidgetPromptSheet(store: widgetStore) {
                showingPromptSheet = false
            }
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        Text(greetingText)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Widgets Yet")
                .font(.headline)

            Text("Create custom widgets powered by AI to display live data")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Create Your First Widget") {
                showingPromptSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.top, 40)
    }

    // MARK: - Widget Grid

    private var widgetGrid: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 16)
        ], spacing: 16) {
            ForEach(Array(widgetStore.widgets.enumerated()), id: \.element.id) { index, widget in
                PipelineWidgetContainerView(
                    widget: widget,
                    isEditMode: isEditing,
                    onRemove: { widgetStore.removeWidget(id: widget.id) },
                    canMoveUp: index > 0,
                    canMoveDown: index < widgetStore.widgets.count - 1,
                    onMoveUp: {
                        widgetStore.moveWidget(from: IndexSet(integer: index), to: index - 1)
                    },
                    onMoveDown: {
                        widgetStore.moveWidget(from: IndexSet(integer: index), to: index + 2)
                    }
                )
            }
        }
    }

    // MARK: - Edit Button

    private var editButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditing.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.system(size: 13, weight: .semibold))
                Text(isEditing ? "Done" : "Edit")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
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
    }
}
