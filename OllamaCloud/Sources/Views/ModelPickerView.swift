import SwiftUI

struct ModelPickerView: View {
    let onSelect: (OllamaModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var models: [OllamaModel] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""

    private var filteredModels: [OllamaModel] {
        if searchText.isEmpty { return models }
        return models.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                            .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.textTertiary)
                        Text(error)
                            .font(.app(13))
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Retry") { fetchModels() }
                            .font(.app(14, weight: .medium))
                            .foregroundStyle(Color.accent)
                            .padding(.top, 4)
                    }
                } else if models.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "cpu")
                            .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.textTertiary)
                        Text("No models found")
                            .font(.app(14))
                            .foregroundStyle(Color.textTertiary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredModels) { model in
                                Button { onSelect(model) } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.accentSoft)
                                                .frame(width: 38, height: 38)
                                            Image(systemName: "cube")
                                                .font(.system(size: 14, weight: .light, design: .rounded))
                                                .foregroundStyle(Color.accent)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.displayName)
                                                .font(.app(15, weight: .medium))
                                                .foregroundStyle(Color.textPrimary)
                                            Text(model.name)
                                                .font(.app(12))
                                                .foregroundStyle(Color.textTertiary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
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
                    Button("Cancel") { dismiss() }
                        .font(.app(15))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .onAppear { fetchModels() }
    }

    private func fetchModels() {
        isLoading = true
        error = nil
        Task {
            do { models = try await OllamaAPIClient.shared.fetchModels() }
            catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}
