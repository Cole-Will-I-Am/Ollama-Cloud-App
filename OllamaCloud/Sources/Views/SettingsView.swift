import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var network: NetworkMonitor
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @State private var showRemoveConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Connection
                    section("CONNECTION") {
                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(connectionColor.opacity(0.12))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: connectionIcon)
                                        .font(.system(size: 14, weight: .ultraLight))
                                        .foregroundStyle(connectionColor)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(connectionTitle)
                                        .font(.app(15, weight: .medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(AppConfig.apiHostDisplayName)
                                        .font(.app(12))
                                        .foregroundStyle(Color.textTertiary)
                                }
                                Spacer()
                            }

                            Button {
                                showRemoveConfirmation = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "key.slash")
                                        .font(.system(size: 13, weight: .ultraLight))
                                    Text("REMOVE API KEY")
                                        .font(.appLabel(11))
                                        .tracking(2)
                                }
                                .foregroundStyle(Color.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.danger.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.danger.opacity(0.1), lineWidth: 0.5)
                                        )
                                )
                            }
                        }
                        .padding(16)
                    }

                    // MCP Servers (macOS only)
                    #if os(macOS)
                    section("MCP SERVERS") {
                        MCPServerStatusView()
                    }
                    #endif

                    // About
                    section("ABOUT") {
                        VStack(spacing: 0) {
                            row("Version", appVersionDisplay)
                            Rectangle().fill(Color.border).frame(height: 0.5).padding(.leading, 16)
                            row("API", AppConfig.apiHostDisplayName)
                        }
                    }

                    // Contact
                    Link(destination: URL(string: "mailto:licensing@manticthink.com")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope")
                                .font(.system(size: 11, weight: .ultraLight))
                            Text("CONTACT")
                                .font(.appLabel(10))
                                .tracking(2)
                        }
                        .foregroundStyle(Color.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .background(Color.bgPrimary.ignoresSafeArea())
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Text("DONE")
                            .font(.appLabel(12))
                            .tracking(2)
                            #if os(iOS)
                            .foregroundStyle(Color.accent)
                            #else
                            .foregroundStyle(Color.textPrimary)
                            #endif
                    }
                    #if os(macOS)
                    .buttonStyle(.bordered)
                    #endif
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
                Text("You'll need to re-enter your key to continue.")
            }
        }
    }

    private var connectionTitle: String {
        network.isConnected ? "Connected" : "Offline"
    }

    private var connectionIcon: String {
        network.isConnected ? "checkmark" : "wifi.slash"
    }

    private var connectionColor: Color {
        network.isConnected ? Color.success : Color.danger
    }

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "Unknown"
        let build = (info?["CFBundleVersion"] as? String) ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appLabel(10))
                .foregroundStyle(Color.textTertiary)
                .labelTracking()
                .padding(.leading, 4)
            content()
                .chromeCard()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.app(14, weight: .light))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(value)
                .font(.app(14, weight: .light))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(16)
    }
}
