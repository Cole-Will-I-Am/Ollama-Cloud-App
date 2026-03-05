import SwiftUI

struct ModelPickerView: View {
    let onSelect: (OllamaModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var models: [OllamaModel] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var fetchTask: Task<Void, Never>?

    private var filteredModels: [OllamaModel] {
        if searchText.isEmpty { return models }
        return models.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Infer capability tags from model name.
    private func capabilityTags(for name: String) -> [(String, String, Color)] {
        let lower = name.lowercased()
        var tags: [(String, String, Color)] = []

        // Speed / size
        if lower.contains("tiny") || lower.contains("mini") || lower.contains("small") || lower.contains("1b") || lower.contains("3b") || lower.contains("0.5b") {
            tags.append(("bolt", "FAST", Color.success))
        }

        // Reasoning
        if lower.contains("deepseek") || lower.contains("think") || lower.contains("reason") || lower.contains("r1") || lower.contains("qwq") {
            tags.append(("brain", "REASON", Color(red: 0.55, green: 0.38, blue: 0.95)))
        }

        // Creative / large
        if lower.contains("70b") || lower.contains("72b") || lower.contains("405b") || lower.contains("llama3.1") || lower.contains("command-r") {
            tags.append(("paintbrush", "CREATIVE", Color(red: 1.0, green: 0.6, blue: 0.2)))
        }

        // Code
        if lower.contains("code") || lower.contains("starcoder") || lower.contains("deepseek-coder") || lower.contains("qwen2.5-coder") {
            tags.append(("chevron.left.forwardslash.chevron.right", "CODE", Color.accent))
        }

        // Vision
        if lower.contains("vision") || lower.contains("llava") || lower.contains("moondream") {
            tags.append(("eye", "VISION", Color(red: 0.3, green: 0.8, blue: 0.9)))
        }

        return tags
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(Color.accent)
                } else if let error {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(Color.textTertiary)
                        Text(error)
                            .font(.app(13))
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button { fetchModels() } label: {
                            Text("RETRY")
                                .font(.appLabel(11))
                                .tracking(2)
                                .foregroundStyle(Color.accent)
                        }
                        .padding(.top, 4)
                    }
                } else if models.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "cpu")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(Color.textTertiary)
                        Text("No models found")
                            .font(.app(14, weight: .light))
                            .foregroundStyle(Color.textTertiary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredModels) { model in
                                Button {
                                    Haptic.impact()
                                    onSelect(model)
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.accentSoft)
                                                .frame(width: 38, height: 38)
                                            Image(systemName: "cube")
                                                .font(.system(size: 14, weight: .ultraLight))
                                                .foregroundStyle(Color.accent)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(model.displayName)
                                                .font(.app(15, weight: .regular))
                                                .foregroundStyle(Color.textPrimary)

                                            HStack(spacing: 6) {
                                                Text(model.name)
                                                    .font(.app(11, weight: .light))
                                                    .foregroundStyle(Color.textTertiary)

                                                let tags = capabilityTags(for: model.name)
                                                ForEach(tags, id: \.1) { icon, label, color in
                                                    HStack(spacing: 3) {
                                                        Image(systemName: icon)
                                                            .font(.system(size: 7, weight: .medium))
                                                        Text(label)
                                                            .font(.appLabel(7))
                                                            .tracking(1.5)
                                                    }
                                                    .foregroundStyle(color)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        Capsule().fill(color.opacity(0.1))
                                                    )
                                                }
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .ultraLight))
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .searchable(text: $searchText, prompt: "Search")
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("CANCEL")
                            .font(.appLabel(11))
                            .tracking(2)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .onAppear { fetchModels() }
        .onDisappear { fetchTask?.cancel() }
    }

    private func fetchModels() {
        fetchTask?.cancel()
        isLoading = true
        error = nil
        fetchTask = Task {
            do {
                models = try await OllamaAPIClient.shared.fetchModels()
            } catch is CancellationError {
                return
            } catch let apiError as OllamaAPIError {
                error = apiError.userMessage
            } catch let caughtError {
                error = caughtError.localizedDescription
            }
            isLoading = false
        }
    }
}
