import SwiftUI

struct DarkModeSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section("Dark Mode (Web Content)") {
            Picker("Mode", selection: $settings.darkModeMode) {
                ForEach(DarkModeMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Inverts page colors while preserving images and videos. Similar to Dark Reader extension.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Brightness slider
            HStack {
                Image(systemName: "sun.min")
                    .foregroundColor(.secondary)
                Slider(value: $settings.darkModeBrightness, in: 50...150, step: 5)
                Image(systemName: "sun.max")
                    .foregroundColor(.secondary)
                Text("\(Int(settings.darkModeBrightness))%")
                    .frame(width: 45, alignment: .trailing)
                    .foregroundColor(.secondary)
            }

            // Contrast slider
            HStack {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundColor(.secondary)
                Slider(value: $settings.darkModeContrast, in: 50...150, step: 5)
                Image(systemName: "circle.righthalf.filled")
                    .foregroundColor(.secondary)
                Text("\(Int(settings.darkModeContrast))%")
                    .frame(width: 45, alignment: .trailing)
                    .foregroundColor(.secondary)
            }

            // Reset to defaults button
            if settings.darkModeBrightness != 100 || settings.darkModeContrast != 100 {
                Button("Reset to Defaults") {
                    settings.darkModeBrightness = 100
                    settings.darkModeContrast = 100
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
