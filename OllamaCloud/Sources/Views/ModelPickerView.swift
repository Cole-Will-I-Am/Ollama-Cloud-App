import SwiftUI

struct ModelPickerView: View {
    let onSelect: (OllamaModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("favorite_model_names_json") private var favoriteModelNamesJSON = "[]"
    @AppStorage("hide_non_favorite_models") private var hideNonFavoriteModels = false
    @State private var models: [OllamaModel] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var fetchTask: Task<Void, Never>?
    @State private var favoriteModelNames: Set<String> = []

    private var searchedModels: [OllamaModel] {
        if searchText.isEmpty { return models }
        return models.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var favoriteModels: [OllamaModel] {
        searchedModels.filter { favoriteModelNames.contains($0.name) }
    }

    private var nonFavoriteModels: [OllamaModel] {
        searchedModels.filter { !favoriteModelNames.contains($0.name) }
    }

    private var hasVisibleModels: Bool {
        if hideNonFavoriteModels {
            return !favoriteModels.isEmpty
        }
        return !searchedModels.isEmpty
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
                } else if !hasVisibleModels {
                    VStack(spacing: 12) {
                        Image(systemName: hideNonFavoriteModels ? "star.slash" : "magnifyingglass")
                            .font(.system(size: 30, weight: .ultraLight))
                            .foregroundStyle(Color.textTertiary)
                        Text(hideNonFavoriteModels ? "No favorite models match your search" : "No models match your search")
                            .font(.app(14, weight: .light))
                            .foregroundStyle(Color.textTertiary)

                        if hideNonFavoriteModels {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    hideNonFavoriteModels = false
                                }
                            } label: {
                                Text("SHOW ALL MODELS")
                                    .font(.appLabel(10))
                                    .tracking(2)
                                    .foregroundStyle(Color.accent)
                            }
                            .padding(.top, 2)
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            HStack {
                                Text("\(favoriteModelNames.count) FAVORITES")
                                    .font(.appLabel(9))
                                    .tracking(1.8)
                                    .foregroundStyle(Color.textTertiary)
                                Spacer()
                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        hideNonFavoriteModels.toggle()
                                    }
                                    Haptic.selection()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: hideNonFavoriteModels ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                            .font(.system(size: 11, weight: .ultraLight))
                                        Text("FAVORITES ONLY")
                                            .font(.appLabel(9))
                                            .tracking(1.5)
                                    }
                                    .foregroundStyle(hideNonFavoriteModels ? Color.accent : Color.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(hideNonFavoriteModels ? Color.accentSoft : Color.surface)
                                    )
                                    .overlay(
                                        Capsule().stroke(Color.border, lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 8)

                            if !favoriteModels.isEmpty {
                                sectionHeader("FAVORITES")
                                ForEach(favoriteModels) { model in
                                    modelRow(model)
                                }
                            }

                            if !hideNonFavoriteModels && !nonFavoriteModels.isEmpty {
                                sectionHeader(favoriteModels.isEmpty ? "MODELS" : "ALL MODELS")
                                ForEach(nonFavoriteModels) { model in
                                    modelRow(model)
                                }
                            }
                        }
                        .padding(.bottom, 12)
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
        .onAppear {
            loadFavorites()
            fetchModels()
        }
        .onDisappear { fetchTask?.cancel() }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.appLabel(9))
                .tracking(1.8)
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func modelRow(_ model: OllamaModel) -> some View {
        HStack(spacing: 10) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                toggleFavorite(model)
            } label: {
                Image(systemName: favoriteModelNames.contains(model.name) ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(favoriteModelNames.contains(model.name) ? Color.accent : Color.textTertiary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favoriteModelNames.contains(model.name) ? "Remove favorite" : "Add favorite")
            .accessibilityHint("Pins this model for faster selection")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surface.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.border, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
    }

    private func loadFavorites() {
        guard let data = favoriteModelNamesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            favoriteModelNames = []
            return
        }
        favoriteModelNames = Set(decoded)
    }

    private func persistFavorites() {
        let encoded = Array(favoriteModelNames).sorted()
        guard let data = try? JSONEncoder().encode(encoded),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        favoriteModelNamesJSON = json
    }

    private func toggleFavorite(_ model: OllamaModel) {
        if favoriteModelNames.contains(model.name) {
            favoriteModelNames.remove(model.name)
        } else {
            favoriteModelNames.insert(model.name)
        }
        persistFavorites()
        Haptic.selection()
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
