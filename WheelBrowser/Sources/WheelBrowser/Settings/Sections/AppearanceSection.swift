import SwiftUI

struct AppearanceSection: View {
    @ObservedObject private var settings = AppSettings.shared
    private let runtimeCoordinator = SettingsRuntimeCoordinator.shared

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.appearanceMode) {
                Task { @MainActor in
                    await runtimeCoordinator.handleAppearanceSettingChanged()
                }
            }
        }
    }
}
