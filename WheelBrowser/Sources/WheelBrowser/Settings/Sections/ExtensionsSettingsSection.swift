import AppKit
import SwiftUI

struct ExtensionsSettingsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    private var registry = ExtensionRegistry.shared
    private let runtimeCoordinator = SettingsRuntimeCoordinator.shared

    var body: some View {
        Section("Extensions") {
            Toggle("Enable Extensions", isOn: $settings.extensionsEnabled)
                .onChange(of: settings.extensionsEnabled) {
                    Task { @MainActor in
                        await runtimeCoordinator.handleExtensionsSettingChanged()
                    }
                }

            if registry.isReloading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Reloading extensions...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if registry.installedExtensions.isEmpty {
                Text("No bundled or sideloaded extensions found.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(registry.installedExtensions) { installedExtension in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(installedExtension.displayName)
                                .font(.system(size: 13, weight: .semibold))

                            Text("\(installedExtension.logicalID ?? installedExtension.id) • \(installedExtension.source.rawValue) • v\(installedExtension.version)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(installedExtension.healthSummary)
                                .font(.caption)
                                .foregroundColor(installedExtension.isValid && installedExtension.lastRuntimeError == nil ? .secondary : .red)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if let logicalID = installedExtension.logicalID {
                            Toggle("", isOn: Binding(
                                get: { installedExtension.isEnabled },
                                set: { newValue in
                                    Task { @MainActor in
                                        await registry.setEnabled(newValue, for: logicalID)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .disabled(!installedExtension.isValid)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Button("Reload Extensions") {
                    Task { @MainActor in
                        await runtimeCoordinator.handleExtensionsSettingChanged()
                    }
                }

                Button("Open Extensions Folder") {
                    let directoryURL = registry.extensionsDirectoryURL()
                    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(directoryURL)
                }
            }
        }
    }
}
