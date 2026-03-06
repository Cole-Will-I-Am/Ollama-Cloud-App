#if os(macOS)
import SwiftUI

struct MCPServerStatusView: View {
    @EnvironmentObject private var mcpManager: MCPClientManager

    var body: some View {
        VStack(spacing: 0) {
            if mcpManager.servers.isEmpty {
                emptyState
            } else {
                ForEach(Array(mcpManager.servers.keys.sorted()), id: \.self) { name in
                    if let state = mcpManager.servers[name] {
                        serverRow(name: name, state: state)
                        if name != mcpManager.servers.keys.sorted().last {
                            Rectangle().fill(Color.border).frame(height: 0.5).padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No MCP servers configured")
                .font(.app(13, weight: .light))
                .foregroundStyle(Color.textSecondary)
            Text("Add servers to ~/.seer/mcp.json")
                .font(.appMono(11, weight: .regular))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private func serverRow(name: String, state: MCPServerState) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor(for: state))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.app(13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text(state.statusLabel)
                    .font(.app(11))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Button {
                Task { await mcpManager.restartServer(name: name) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .macPointingCursor()
        }
        .padding(16)
    }

    private func statusColor(for state: MCPServerState) -> Color {
        switch state {
        case .connected: return Color.success
        case .error: return Color.danger
        case .connecting: return Color.accent
        case .disconnected: return Color.textTertiary
        }
    }
}
#endif
