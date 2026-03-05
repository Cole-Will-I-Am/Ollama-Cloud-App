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
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundStyle(Color.danger)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { fetchModels() }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accent)
                    }
                    .padding()
                } else if models.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundStyle(Color.textTertiary)
                        Text("No models found")
                            .font(.subheadline)
                            .foregroundStyle(Color.textTertiary)
                    }
                } else {
                    List(filteredModels) { model in
                        Button {
                            onSelect(model)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.surfaceElevated)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.border, lineWidth: 0.5)
                                        )
                                    Image(systemName: "cube")
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundStyle(Color.accent)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(model.name)
                                        .font(.caption)
                                        .foregroundStyle(Color.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .searchable(text: $searchText, prompt: "Search models")
                }
            }
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
            do {
                models = try await OllamaAPIClient.shared.fetchModels()
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
