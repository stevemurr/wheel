import SwiftUI

/// Main view for the new tab page
struct NewTabPageView: View {
    @StateObject private var manager = NewTabPageManager.shared
    @State private var showAddWidgetSheet = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 40) {
                    // Greeting
                    if manager.config.showGreeting {
                        greetingView
                    }

                    // Widget grid
                    WidgetGridView(
                        manager: manager,
                        containerWidth: min(geometry.size.width, 800)
                    )

                    // Edit mode controls
                    if manager.isEditMode {
                        editModeControls
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: 800)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .background(backgroundView)
        }
        .onAppear {
            Task {
                await manager.refreshAll()
            }
        }
        .sheet(isPresented: $showAddWidgetSheet) {
            WidgetGallerySheet(manager: manager)
        }
    }

    private var greetingView: some View {
        VStack(spacing: 8) {
            Text(greeting)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        manager.isEditMode.toggle()
                    }
                } label: {
                    Label(
                        manager.isEditMode ? "Done" : "Customize",
                        systemImage: manager.isEditMode ? "checkmark" : "slider.horizontal.3"
                    )
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 20)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Good night"
        }
    }

    private var editModeControls: some View {
        HStack(spacing: 12) {
            Button {
                showAddWidgetSheet = true
            } label: {
                Label("Add Widget", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderedProminent)

            Button {
                manager.resetToDefaults()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch manager.config.backgroundStyle {
        case .system:
            Color(nsColor: .textBackgroundColor)
        case .dark:
            Color(white: 0.1)
        case .light:
            Color(white: 0.98)
        }
    }
}

/// Sheet for adding new widgets
struct WidgetGallerySheet: View {
    @ObservedObject var manager: NewTabPageManager
    @Environment(\.dismiss) private var dismiss

    private var availableWidgets: [WidgetRegistry.WidgetMetadata] {
        WidgetRegistry.shared.availableWidgets
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Widget")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Widget list
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    ForEach(availableWidgets, id: \.typeIdentifier) { widgetMeta in
                        WidgetGalleryItem(metadata: widgetMeta) {
                            manager.addWidget(typeIdentifier: widgetMeta.typeIdentifier)
                            dismiss()
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct WidgetGalleryItem: View {
    let metadata: WidgetRegistry.WidgetMetadata
    let onAdd: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 12) {
                Image(systemName: metadata.iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .frame(height: 48)

                Text(metadata.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: isHovered ? .controlBackgroundColor : .windowBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
