import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var network: NetworkMonitor
    #if os(macOS)
    @EnvironmentObject private var mcpManager: MCPClientManager
    @AppStorage("mcpEnabled") private var mcpEnabled = false
    @State private var installedMCPServers: Set<String> = []
    @State private var installingMCPServerID: String?
    @State private var mcpLibraryMessage: String?
    @State private var mcpLibraryError: String?
    #endif
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @AppStorage("hasOpenAIKey") private var hasOpenAIKey = false
    @AppStorage("visualizations_enabled") private var visualizationsEnabled = true
    @State private var showRemoveConfirmation = false
    @State private var showRemoveOpenAIConfirmation = false
    @State private var openAIKeyInput = ""
    @State private var isValidatingOpenAIKey = false
    @State private var openAIKeyError: String?
    @State private var showDataSharingSheet = false
    @State private var showDeleteAllConfirmation = false
    @State private var dataActionError: String?

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

                    // OpenAI
                    section("OPENAI") {
                        VStack(spacing: 16) {
                            if hasOpenAIKey, KeychainHelper.load(key: "openai_api_key") != nil {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.success.opacity(0.12))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .ultraLight))
                                            .foregroundStyle(Color.success)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Connected")
                                            .font(.app(15, weight: .medium))
                                            .foregroundStyle(Color.textPrimary)
                                        Text("api.openai.com")
                                            .font(.app(12))
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    Spacer()
                                }

                                Button {
                                    showRemoveOpenAIConfirmation = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "key.slash")
                                            .font(.system(size: 13, weight: .ultraLight))
                                        Text("REMOVE OPENAI KEY")
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
                            } else {
                                VStack(spacing: 12) {
                                    SecureField("OpenAI API Key", text: $openAIKeyInput)
                                        .font(.app(14))
                                        .textFieldStyle(.plain)
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.bgSecondary)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.border, lineWidth: 0.5)
                                        )
                                        #if os(iOS)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        #endif

                                    if let openAIKeyError {
                                        Text(openAIKeyError)
                                            .font(.app(11))
                                            .foregroundStyle(Color.danger)
                                    }

                                    Button {
                                        connectOpenAI()
                                    } label: {
                                        HStack(spacing: 8) {
                                            if isValidatingOpenAIKey {
                                                ProgressView()
                                                    .controlSize(.small)
                                                    .tint(Color.textPrimary)
                                            }
                                            Text("CONNECT")
                                                .font(.appLabel(11))
                                                .tracking(2)
                                        }
                                        .foregroundStyle(Color.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.accent.opacity(0.22))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(Color.accent.opacity(0.2), lineWidth: 0.5)
                                                )
                                        )
                                    }
                                    .disabled(openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingOpenAIKey)
                                }
                            }
                        }
                        .padding(16)
                    }

                    // Privacy / data sharing
                    section("PRIVACY") {
                        VStack(spacing: 0) {
                            Button {
                                showDataSharingSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.accent.opacity(0.12))
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "hand.raised")
                                            .font(.system(size: 14, weight: .ultraLight))
                                            .foregroundStyle(Color.accent)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Data Sharing")
                                            .font(.app(15, weight: .medium))
                                            .foregroundStyle(Color.textPrimary)
                                        Text("What's sent to \(AppConfig.apiHostDisplayName)")
                                            .font(.app(12))
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .ultraLight))
                                        .foregroundStyle(Color.textTertiary)
                                }
                                .padding(16)
                            }
                            .buttonStyle(.plain)
                            #if os(macOS)
                            .macPointingCursor()
                            #endif

                            Rectangle().fill(Color.border).frame(height: 0.5).padding(.leading, 16)

                            if let url = URL(string: AppConfig.privacyPolicyURL) {
                                Link(destination: url) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.accent.opacity(0.12))
                                                .frame(width: 38, height: 38)
                                            Image(systemName: "doc.text")
                                                .font(.system(size: 14, weight: .ultraLight))
                                                .foregroundStyle(Color.accent)
                                        }
                                        Text("Privacy Policy")
                                            .font(.app(15, weight: .medium))
                                            .foregroundStyle(Color.textPrimary)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 12, weight: .ultraLight))
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    .padding(16)
                                }
                                .buttonStyle(.plain)
                                #if os(macOS)
                                .macPointingCursor()
                                #endif
                            }
                        }
                    }

                    // Data
                    section("DATA") {
                        VStack(spacing: 14) {
                            Text("Delete all conversations and projects stored on this device. This cannot be undone and does not affect your API keys.")
                                .font(.app(12, weight: .light))
                                .foregroundStyle(Color.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                showDeleteAllConfirmation = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13, weight: .ultraLight))
                                    Text("DELETE ALL DATA")
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
                            #if os(macOS)
                            .buttonStyle(.plain)
                            .macPointingCursor()
                            #endif
                        }
                        .padding(16)
                    }

                    // Chat behavior
                    section("CHAT") {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.accent.opacity(0.12))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "chart.bar.xaxis")
                                        .font(.system(size: 14, weight: .ultraLight))
                                        .foregroundStyle(Color.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Visualizations")
                                        .font(.app(15, weight: .medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("Let the model render charts, tables, and dashboards")
                                        .font(.app(12))
                                        .foregroundStyle(Color.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: $visualizationsEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            .padding(16)
                        }
                    }

                    // MCP Servers (macOS only)
                    #if os(macOS)
                    section("MCP SERVERS") {
                        mcpSettingsContent
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
            .confirmationDialog(
                "Remove OpenAI Key?",
                isPresented: $showRemoveOpenAIConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    KeychainHelper.delete(key: "openai_api_key")
                    hasOpenAIKey = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("OpenAI models will no longer appear in the model picker.")
            }
            .sheet(isPresented: $showDataSharingSheet) {
                DataSharingDisclosureSheet()
            }
            .confirmationDialog(
                "Delete all data?",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes all conversations and projects from this device. Your API keys are not affected.")
            }
            .alert("Couldn't Delete Data", isPresented: Binding(
                get: { dataActionError != nil },
                set: { _ in dataActionError = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dataActionError ?? "An unknown error occurred.")
            }
        }
    }

    private func deleteAllData() {
        do {
            try modelContext.delete(model: Conversation.self)
            try modelContext.delete(model: Project.self)
            try modelContext.save()
            AppCommand.post(AppCommand.dataReset)
            Haptic.notification(.success)
            dismiss()
        } catch {
            dataActionError = error.localizedDescription
            Haptic.notification(.error)
        }
    }

    private func connectOpenAI() {
        let key = openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        isValidatingOpenAIKey = true
        openAIKeyError = nil

        Task {
            do {
                let valid = try await OpenAIAPIClient.shared.validateKey(key)
                await MainActor.run {
                    isValidatingOpenAIKey = false
                    if valid {
                        KeychainHelper.save(key: "openai_api_key", value: key)
                        hasOpenAIKey = true
                        openAIKeyInput = ""
                    } else {
                        openAIKeyError = "Invalid API key."
                    }
                }
            } catch {
                await MainActor.run {
                    isValidatingOpenAIKey = false
                    openAIKeyError = error.localizedDescription
                }
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

    #if os(macOS)
    private var mcpSettingsContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCP ENABLED")
                        .font(.appLabel(10))
                        .foregroundStyle(Color.textTertiary)
                        .labelTracking()
                    Text(mcpEnabled ? "On" : "Off")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(mcpEnabled ? Color.success : Color.textSecondary)
                }
                Spacer()
                Toggle("", isOn: $mcpEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(16)

            Rectangle()
                .fill(Color.border)
                .frame(height: 0.5)
                .padding(.leading, 16)

            if mcpEnabled {
                MCPServerStatusView()
            } else {
                VStack(spacing: 6) {
                    Text("MCP is disabled")
                        .font(.app(13, weight: .light))
                        .foregroundStyle(Color.textSecondary)
                    Text("Turn on to load servers from ~/.seer/mcp.json")
                        .font(.appMono(11, weight: .regular))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }

            Rectangle()
                .fill(Color.border)
                .frame(height: 0.5)
                .padding(.leading, 16)

            mcpLibraryContent
        }
        .onAppear {
            refreshInstalledMCPServers()
        }
        .onChange(of: mcpEnabled) { _, enabled in
            Task {
                if enabled {
                    await mcpManager.loadAndConnect()
                } else {
                    await mcpManager.shutdown()
                }
            }
        }
    }

    private var mcpLibraryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MCP LIBRARY")
                    .font(.appLabel(10))
                    .foregroundStyle(Color.textTertiary)
                    .labelTracking()
                Spacer()
                Text("\(MCPLibraryRegistry.servers.count) options")
                    .font(.app(11))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(Array(MCPLibraryRegistry.servers.enumerated()), id: \.element.id) { index, server in
                mcpLibraryRow(server: server)
                if index < MCPLibraryRegistry.servers.count - 1 {
                    Rectangle().fill(Color.border).frame(height: 0.5).padding(.leading, 16)
                }
            }

            if let message = mcpLibraryMessage {
                Text(message)
                    .font(.app(11))
                    .foregroundStyle(Color.success)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            if let error = mcpLibraryError {
                Text(error)
                    .font(.app(11))
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            Text("Installs add entries to ~/.seer/mcp.json. Set keys/credentials in that file where required.")
                .font(.app(10))
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
    }

    private func mcpLibraryRow(server: MCPLibraryServer) -> some View {
        let isInstalled = installedMCPServers.contains(server.id)
        let isInstalling = installingMCPServerID == server.id

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: server.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.app(13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text(server.description)
                    .font(.app(11))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Button {
                installLibraryServer(server)
            } label: {
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.textPrimary)
                        .frame(width: 64)
                } else {
                    Text(isInstalled ? "INSTALLED" : "INSTALL")
                        .font(.appLabel(10))
                        .tracking(1.2)
                        .foregroundStyle(isInstalled ? Color.textTertiary : Color.textPrimary)
                        .frame(minWidth: 64)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isInstalled ? Color.bgSecondary : Color.accent.opacity(0.22))
                        )
                }
            }
            .buttonStyle(.plain)
            .macPointingCursor()
            .disabled(isInstalled || isInstalling || installingMCPServerID != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func refreshInstalledMCPServers() {
        installedMCPServers = MCPConfigStore.installedServerNames()
    }

    private func installLibraryServer(_ server: MCPLibraryServer) {
        guard installingMCPServerID == nil else { return }

        installingMCPServerID = server.id
        defer { installingMCPServerID = nil }

        do {
            try MCPConfigStore.installLibraryServer(server)
            mcpLibraryError = nil
            mcpLibraryMessage = "Added '\(server.id)' to ~/.seer/mcp.json."
            refreshInstalledMCPServers()

            if mcpEnabled {
                Task {
                    await mcpManager.shutdown()
                    await mcpManager.loadAndConnect()
                }
            }
        } catch {
            mcpLibraryMessage = nil
            mcpLibraryError = error.localizedDescription
        }
    }
    #endif

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
