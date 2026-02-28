import SwiftUI

struct AppearanceSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
