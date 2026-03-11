import SwiftUI

struct SettingsAssistantSection: View {
    var manager: SettingsAssistantManager = .shared

    private var latestAssistantSuggestions: [String] {
        manager.messages.last(where: { $0.role == .assistant })?.suggestedFollowUps ?? []
    }

    var body: some View {
        Section("Settings Assistant") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ask Wheel to explain or change supported app settings. Settings changes are always previewed first and require confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                transcript

                if let pendingPlan = manager.pendingPlan {
                    pendingPlanCard(pendingPlan)
                }

                composer

                if !latestAssistantSuggestions.isEmpty && manager.pendingPlan == nil {
                    FollowUpSuggestionsView(suggestions: latestAssistantSuggestions) { suggestion in
                        manager.composerText = suggestion
                        Task {
                            await manager.submitComposerPrompt()
                        }
                    }
                }

                if let error = manager.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if manager.messages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("“What model am I using?”")
                        Text("“Turn on EasyList and EasyPrivacy.”")
                        Text("“Set the theme to dark and increase shown tab size to 110%.”")
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(manager.messages) { message in
                        ChatPanelMessageBubble(
                            message: message,
                            compact: true,
                            onSelectArtifact: { _ in }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .frame(minHeight: 180, maxHeight: 320)
    }

    private func pendingPlanCard(_ pendingPlan: SettingsAssistantPendingPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pending Confirmation")
                .font(.system(size: 12, weight: .semibold))

            if !pendingPlan.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warnings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(pendingPlan.warnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.caption)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(pendingPlan.actions, id: \.settingID) { action in
                    Text("• \(action.preview)")
                        .font(.caption)
                }
            }

            HStack {
                Button("Confirm") {
                    Task {
                        await manager.confirmPendingPlan()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isSending)

                Button("Cancel") {
                    manager.cancelPendingPlan()
                }
                .buttonStyle(.bordered)
                .disabled(manager.isSending)

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(
                manager.pendingPlan == nil
                    ? "Ask about supported settings"
                    : "Confirm or cancel the pending changes first",
                text: Binding(
                    get: { manager.composerText },
                    set: { manager.composerText = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .disabled(!manager.canSendPrompt)
            .onSubmit {
                Task {
                    await manager.submitComposerPrompt()
                }
            }

            Button("Send") {
                Task {
                    await manager.submitComposerPrompt()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!manager.canSendPrompt || manager.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
