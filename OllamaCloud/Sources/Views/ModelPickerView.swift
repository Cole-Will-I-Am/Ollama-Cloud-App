import SwiftUI

struct ModelPickerView: View {
    let onSelect: (OllamaModel) -> Void
    let onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("favorite_model_names_by_account_json") private var favoriteModelNamesByAccountJSON = "{}"
    @AppStorage("hide_non_favorite_models_by_account_json") private var hideNonFavoriteModelsByAccountJSON = "{}"
    @AppStorage("seer_favorite_seeded_scopes_json") private var seerFavoriteSeededScopesJSON = "{}"
    @State private var models: [OllamaModel] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var openAIError: String?
    @State private var searchText = ""
    @State private var fetchTask: Task<Void, Never>?
    @State private var favoriteModelNames: Set<String> = []
    @State private var hideNonFavoriteModels = false
    #if os(macOS)
    @State private var hoveredModelName: String?
    #endif

    init(
        onSelect: @escaping (OllamaModel) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

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

    // Provider-grouped computed properties for non-favorite models
    private var ollamaModels: [OllamaModel] {
        nonFavoriteModels.filter { $0.provider == .ollama }
    }

    private var openaiModels: [OllamaModel] {
        nonFavoriteModels.filter { $0.provider == .openai }
    }

    private var hasVisibleModels: Bool {
        if hideNonFavoriteModels {
            return !favoriteModels.isEmpty
        }
        return !searchedModels.isEmpty
    }

    private func isSeerModel(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == AppConfig.seerModelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                                persistHideNonFavoritePreference()
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
                                    persistHideNonFavoritePreference()
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
                                #if os(macOS)
                                .macPointingCursor()
                                #endif
                            }
                            .padding(.horizontal, 18)
                            .padding(.top, 8)

                            if !favoriteModels.isEmpty {
                                sectionHeader("FAVORITES")
                                ForEach(favoriteModels) { model in
                                    modelRow(model, isFavorite: true)
                                        .id("favorite-\(model.id)")
                                }
                            }

                            if !hideNonFavoriteModels {
                                if !ollamaModels.isEmpty {
                                    sectionHeader("OLLAMA")
                                    ForEach(ollamaModels) { model in
                                        modelRow(model, isFavorite: false)
                                            .id("other-\(model.id)")
                                    }
                                }

                                if !openaiModels.isEmpty {
                                    sectionHeader("OPENAI")
                                    ForEach(openaiModels) { model in
                                        modelRow(model, isFavorite: false)
                                            .id("other-\(model.id)")
                                    }
                                } else if let openAIError {
                                    sectionHeader("OPENAI")
                                    Text(openAIError)
                                        .font(.app(12, weight: .light))
                                        .foregroundStyle(Color.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 6)
                                }
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .searchable(text: $searchText, prompt: "Search")
                }
            }
            .navigationTitle("Models")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .background(Color.bgPrimary.ignoresSafeArea())
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel?()
                        dismiss()
                    } label: {
                        Text("CANCEL")
                            .font(.appLabel(11))
                            .tracking(2)
                            .foregroundStyle(Color.textSecondary)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    .macPointingCursor()
                    #endif
                }
            }
        }
        .onAppear {
            loadPreferences()
            fetchModels()
        }
        .onDisappear { fetchTask?.cancel() }
        .macSheetFixedSize(SeerSheetSize.modelPicker)
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
    private func modelRow(_ model: OllamaModel, isFavorite: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptic.impact()
                onSelect(model)
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.displayName)
                            .font(.app(15, weight: .regular))
                            .foregroundStyle(Color.textPrimary)

                        Text(model.name)
                            .font(.app(11, weight: .light))
                            .foregroundStyle(Color.textTertiary)
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
            #if os(macOS)
            .macPointingCursor()
            #endif

            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    toggleFavorite(model)
                }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isFavorite ? Color.accent : Color.textTertiary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .macPointingCursor()
            #endif
            .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
            .accessibilityHint("Pins this model for faster selection")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(modelRowFill(for: model))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.border, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        #if os(macOS)
        .onHover { hovering in
            if hovering {
                hoveredModelName = model.name
            } else if hoveredModelName == model.name {
                hoveredModelName = nil
            }
        }
        #endif
    }

    private func modelRowFill(for model: OllamaModel) -> Color {
        #if os(macOS)
        if hoveredModelName == model.name {
            return Color.surface.opacity(0.65)
        }
        #endif
        return Color.surface.opacity(0.35)
    }

    private func accountScopeKey() -> String {
        AccountScope.currentKey()
    }

    private func loadPreferences() {
        let scope = accountScopeKey()
        let favoriteMap = decodeFavoritesByAccount()
        if let existingFavorites = favoriteMap[scope] {
            favoriteModelNames = Set(existingFavorites)
        } else if AppConfig.seerModelEnabled {
            favoriteModelNames = [AppConfig.seerModelName]
            persistFavorites(favoriteModelNames)
        } else {
            favoriteModelNames = []
        }

        seedSeerFavoriteIfNeeded(scope: scope)

        let hideMap = decodeHidePreferenceByAccount()
        hideNonFavoriteModels = hideMap[scope] ?? false
    }

    private func decodeFavoritesByAccount() -> [String: [String]] {
        guard let data = favoriteModelNamesByAccountJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func decodeHidePreferenceByAccount() -> [String: Bool] {
        guard let data = hideNonFavoriteModelsByAccountJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func decodeSeerFavoriteSeededScopes() -> [String: Bool] {
        guard let data = seerFavoriteSeededScopesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persistSeerFavoriteSeededScopes(_ map: [String: Bool]) {
        guard let data = try? JSONEncoder().encode(map),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        seerFavoriteSeededScopesJSON = json
    }

    private func persistFavorites(_ favorites: Set<String>? = nil) {
        let effectiveFavorites = favorites ?? favoriteModelNames
        let encoded = Array(effectiveFavorites).sorted()
        var map = decodeFavoritesByAccount()
        map[accountScopeKey()] = encoded

        guard let data = try? JSONEncoder().encode(map),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        favoriteModelNamesByAccountJSON = json
    }

    private func persistHideNonFavoritePreference() {
        var map = decodeHidePreferenceByAccount()
        map[accountScopeKey()] = hideNonFavoriteModels

        guard let data = try? JSONEncoder().encode(map),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        hideNonFavoriteModelsByAccountJSON = json
    }

    private func seedSeerFavoriteIfNeeded(scope: String) {
        guard AppConfig.seerModelEnabled else { return }

        var seededMap = decodeSeerFavoriteSeededScopes()
        if seededMap[scope] == true { return }

        var updatedFavorites = favoriteModelNames
        updatedFavorites.insert(AppConfig.seerModelName)
        favoriteModelNames = updatedFavorites
        persistFavorites(updatedFavorites)
        seededMap[scope] = true
        persistSeerFavoriteSeededScopes(seededMap)
    }

    private func toggleFavorite(_ model: OllamaModel) {
        var updatedFavorites = favoriteModelNames
        if updatedFavorites.contains(model.name) {
            updatedFavorites.remove(model.name)
        } else {
            updatedFavorites.insert(model.name)
        }
        favoriteModelNames = updatedFavorites
        persistFavorites(updatedFavorites)
        Haptic.selection()
    }

    private func fetchModels() {
        fetchTask?.cancel()
        isLoading = true
        error = nil
        fetchTask = Task {
            do {
                async let ollamaFetch = OllamaAPIClient.shared.fetchModels()

                let hasOpenAIKey = KeychainHelper.load(key: "openai_api_key") != nil
                async let openAIFetch: [OllamaModel] = hasOpenAIKey
                    ? OpenAIAPIClient.shared.fetchModels()
                    : []

                let ollamaResults = try await ollamaFetch
                let openAIResults: [OllamaModel]
                do {
                    openAIResults = try await openAIFetch
                    openAIError = nil
                } catch {
                    // Don't block the Ollama list — but say why OpenAI models
                    // are missing instead of silently dropping them.
                    openAIResults = []
                    openAIError = hasOpenAIKey ? "OpenAI models unavailable. Check your key in Settings." : nil
                }

                let allModels = ollamaResults + openAIResults
                models = allModels.sorted { lhs, rhs in
                    let leftIsSeer = isSeerModel(lhs.name)
                    let rightIsSeer = isSeerModel(rhs.name)
                    if leftIsSeer != rightIsSeer {
                        return leftIsSeer && !rightIsSeer
                    }
                    // Group by provider
                    if lhs.provider != rhs.provider {
                        return lhs.provider == .ollama
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
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
