import SwiftUI

struct WidgetSettingsSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section("Widgets") {
            TextField("BFF Proxy Endpoint", text: $settings.bffEndpoint)
                .textFieldStyle(.roundedBorder)

            Text("Optional proxy server for widget data fetching. Leave empty to fetch data directly.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
