#if os(macOS)
import SwiftUI

struct MCPServerStatusView: View {
    @EnvironmentObject private var mcpManager: MCPClientManager

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(BuiltInMCPRegistry.servers.enumerated()), id: \.element.id) { index, server in
                builtInRow(server: server)
                if index < BuiltInMCPRegistry.servers.count - 1 || !customServerNames.isEmpty {
                    Rectangle().fill(Color.border).frame(height: 0.5).padding(.leading, 16)
                }
            }

            ForEach(Array(customServerNames.enumerated()), id: \.element) { index, name in
                if let state = mcpManager.servers[name] {
                    customRow(name: name, state: state)
                    if index < customServerNames.count - 1 {
                        Rectangle().fill(Color.border).frame(height: 0.5).padding(.leading, 16)
                    }
                }
            }
        }
    }

    private var customServerNames: [String] {
        let builtInIDs = Set(BuiltInMCPRegistry.servers.map(\.id))
        return mcpManager.servers.keys
            .filter { !builtInIDs.contains($0) }
            .sorted()
    }

    private func builtInRow(server: BuiltInMCPServer) -> some View {
        let state = mcpManager.servers[server.id]
        let isEnabled = BuiltInMCPRegistry.isEnabled(server)

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor(for: state, enabled: isEnabled).opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: server.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor(for: state, enabled: isEnabled))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(server.id)
                    .font(.app(13, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.textPrimary : Color.textTertiary)

                if isEnabled, isConnecting(state) {
                    ConnectingTimerLabel(startedAt: mcpManager.connectingStartedAt[server.id])
                } else {
                    Text(isEnabled ? (state?.statusLabel ?? "Off") : server.description)
                        .font(.app(11))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            if isEnabled {
                Button {
                    Task { await mcpManager.restartServer(name: server.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .macPointingCursor()
            }

            Toggle("", isOn: Binding(
                get: { BuiltInMCPRegistry.isEnabled(server) },
                set: { newValue in
                    Task { await mcpManager.toggleBuiltInServer(server, enabled: newValue) }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func customRow(name: String, state: MCPServerState) -> some View {
        let isEnabled = CustomMCPRegistry.isEnabled(serverName: name)

        return HStack(spacing: 12) {
            Circle()
                .fill(statusColor(for: state, enabled: isEnabled))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.app(13, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.textPrimary : Color.textTertiary)

                if isEnabled, isConnecting(state) {
                    ConnectingTimerLabel(startedAt: mcpManager.connectingStartedAt[name])
                } else {
                    Text(isEnabled ? state.statusLabel : "Off")
                        .font(.app(11))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            if isEnabled {
                Button {
                    Task { await mcpManager.restartServer(name: name) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .macPointingCursor()
            }

            Toggle("", isOn: Binding(
                get: { CustomMCPRegistry.isEnabled(serverName: name) },
                set: { newValue in
                    Task { await mcpManager.toggleCustomServer(name: name, enabled: newValue) }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(16)
    }

    private func isConnecting(_ state: MCPServerState?) -> Bool {
        guard let state else { return false }
        if case .connecting = state { return true }
        return false
    }

    private func statusColor(for state: MCPServerState?, enabled: Bool) -> Color {
        guard enabled else { return Color.textTertiary }
        guard let state else { return Color.textTertiary }
        switch state {
        case .connected: return Color.success
        case .error: return Color.danger
        case .connecting: return Color.accent
        case .disconnected: return Color.textTertiary
        }
    }
}

// MARK: - Live elapsed timer for connecting state

private struct ConnectingTimerLabel: View {
    let startedAt: Date?
    @State private var elapsed: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("Connecting... \(elapsed)s")
            .font(.app(11))
            .foregroundStyle(Color.accent)
            .onReceive(timer) { _ in
                guard let startedAt else { return }
                elapsed = Int(Date().timeIntervalSince(startedAt))
            }
            .onAppear {
                guard let startedAt else { return }
                elapsed = Int(Date().timeIntervalSince(startedAt))
            }
    }
}
#endif
