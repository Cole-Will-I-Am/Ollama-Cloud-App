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
            Group {
                if isLoading {
                    ProgressView("Loading models...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("Failed to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { fetchModels() }
                    }
                } else if models.isEmpty {
                    ContentUnavailableView(
                        "No Models",
                        systemImage: "cpu",
                        description: Text("No models found in your Ollama Cloud account.")
                    )
                } else {
                    List(filteredModels) { model in
                        Button {
                            onSelect(model)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                    .font(.body)
                                    .foregroundStyle(Color.textPrimary)
                                Text(model.name)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search models")
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { fetchModels() }
    }

    private func fetchModels() {
        isLoading = true
        error = nil
        Task {
            do {
                models = try await OllamaAPIClient.shared.fetchModels()
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
