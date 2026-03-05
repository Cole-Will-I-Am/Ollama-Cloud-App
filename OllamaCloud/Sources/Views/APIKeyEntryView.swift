import SwiftUI

struct APIKeyEntryView: View {
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "cloud.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accent)

                Text("Ollama Cloud")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.textPrimary)

                Text("Chat with your cloud models from your phone.\nEnter your Ollama API key to get started.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 32)

                VStack(spacing: 16) {
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.border, lineWidth: 1)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.danger)
                    }

                    Button {
                        validate()
                    } label: {
                        Group {
                            if isValidating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Connect")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(apiKey.isEmpty ? Color.border : Color.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                }
                .padding(.horizontal, 32)

                Spacer()
                Spacer()
            }
            .background(Color.bgPrimary)
        }
    }

    private func validate() {
        isValidating = true
        error = nil

        Task {
            do {
                let valid = try await OllamaAPIClient.shared.validateKey(apiKey)
                if valid {
                    KeychainHelper.save(key: "api_key", value: apiKey)
                    hasAPIKey = true
                } else {
                    error = "Invalid API key. Check your key and try again."
                }
            } catch {
                self.error = error.localizedDescription
            }
            isValidating = false
        }
    }
}
