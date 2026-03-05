import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @State private var showRemoveConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection
                    settingsSection("CONNECTION") {
                        VStack(spacing: 14) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.success.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.body)
                                        .foregroundStyle(Color.success)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Connected")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("ollama.com")
                                        .font(.caption)
                                        .foregroundStyle(Color.textTertiary)
                                }
                                Spacer()
                            }

                            Button {
                                showRemoveConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "key.slash")
                                        .font(.subheadline)
                                    Text("Remove API Key")
                                        .font(.subheadline)
                                }
                                .foregroundStyle(Color.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.danger.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.danger.opacity(0.15), lineWidth: 0.5)
                                        )
                                )
                            }
                        }
                        .padding(14)
                    }

                    // About
                    settingsSection("ABOUT") {
                        VStack(spacing: 0) {
                            settingsRow(label: "Version", value: "1.0.0")
                            Rectangle().fill(Color.border).frame(height: 0.5).padding(.leading, 14)
                            settingsRow(label: "API", value: "ollama.com")
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .confirmationDialog(
                "Remove API Key?",
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    KeychainHelper.delete(key: "api_key")
                    hasAPIKey = false
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to re-enter your API key to use the app.")
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)

            content()
                .chromeCard(cornerRadius: 14)
        }
    }

    private func settingsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(14)
    }
}
