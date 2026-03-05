import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @State private var showRemoveConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("API Key") {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(Color.accent)
                        Text("Connected to Ollama Cloud")
                            .foregroundStyle(Color.textPrimary)
                    }

                    Button(role: .destructive) {
                        showRemoveConfirmation = true
                    } label: {
                        Label("Remove API Key", systemImage: "trash")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("API", value: "ollama.com")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
                Text("You'll need to re-enter your API key to use the app.")
            }
        }
    }
}
