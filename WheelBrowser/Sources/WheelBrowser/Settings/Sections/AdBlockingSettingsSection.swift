import SwiftUI

struct AdBlockingSettingsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    private var registry = ExtensionRegistry.shared
    private var blockerManager = ContentBlockerManager.shared
    private let runtimeCoordinator = SettingsRuntimeCoordinator.shared

    @State private var customListURL: String = ""
    @State private var allowlistDraft: String = AppSettings.shared.adBlockDomainAllowlistRaw
    @State private var localError: String?

    var body: some View {
        Section("Ad Blocking") {
            Toggle("Enable Ad Blocker", isOn: $settings.adBlockerEnabled)
                .onChange(of: settings.adBlockerEnabled) {
                    reloadRuntime()
                }

            Toggle("EasyList", isOn: $settings.adBlockEasyListEnabled)
                .onChange(of: settings.adBlockEasyListEnabled) {
                    reloadRuntime()
                }

            Toggle("EasyPrivacy", isOn: $settings.adBlockEasyPrivacyEnabled)
                .onChange(of: settings.adBlockEasyPrivacyEnabled) {
                    reloadRuntime()
                }

            Toggle("Fanboy Annoyances", isOn: $settings.adBlockFanboyAnnoyancesEnabled)
                .onChange(of: settings.adBlockFanboyAnnoyancesEnabled) {
                    reloadRuntime()
                }

            if let status = refreshStatusText {
                Text(status)
                    .font(.caption)
                    .foregroundColor(blockerManager.lastRefreshError == nil ? .secondary : .red)
            }

            Button("Update Filter Lists Now") {
                Task { @MainActor in
                    await runtimeCoordinator.refreshAdBlockingLists()
                }
            }

            if !customSubscriptions.isEmpty {
                ForEach(customSubscriptions) { subscription in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle(subscription.name, isOn: Binding(
                            get: { subscription.isEnabled },
                            set: { newValue in
                                blockerManager.setSubscriptionEnabled(newValue, id: subscription.id)
                                Task { @MainActor in
                                    await runtimeCoordinator.handleAdBlockingSettingChanged()
                                }
                            }
                        ))

                        Spacer()

                        Button(role: .destructive) {
                            blockerManager.removeCustomList(id: subscription.id)
                            Task { @MainActor in
                                await runtimeCoordinator.handleAdBlockingSettingChanged()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                    if let error = subscription.lastError, !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Add Custom HTTPS Filter List")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("https://example.com/filterlist.txt", text: $customListURL)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        do {
                            try blockerManager.addCustomList(urlString: customListURL)
                            customListURL = ""
                            localError = nil
                            Task { @MainActor in
                                await runtimeCoordinator.refreshAdBlockingLists()
                            }
                        } catch {
                            localError = error.localizedDescription
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Domain Allowlist")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $allowlistDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Button("Apply Domain Allowlist") {
                    settings.adBlockDomainAllowlistRaw = allowlistDraft
                    reloadRuntime()
                }
                .buttonStyle(.bordered)
            }

            if let localError {
                Text(localError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            allowlistDraft = settings.adBlockDomainAllowlistRaw
        }
    }

    private var customSubscriptions: [FilterListSubscriptionState] {
        blockerManager
            .subscriptions(for: "com.wheel.adblock")
            .filter(\.isCustom)
    }

    private var refreshStatusText: String? {
        if let lastRefreshError = blockerManager.lastRefreshError {
            return lastRefreshError
        }
        if let lastRefreshAt = blockerManager.lastRefreshAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Last updated \(formatter.localizedString(for: lastRefreshAt, relativeTo: Date()))"
        }
        return nil
    }

    private func reloadRuntime() {
        localError = nil
        Task { @MainActor in
            await runtimeCoordinator.handleAdBlockingSettingChanged()
        }
    }
}
