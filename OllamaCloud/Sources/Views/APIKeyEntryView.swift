import SwiftUI

struct APIKeyEntryView: View {
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.accent.opacity(0.15), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 80
                            )
                        )
                        .frame(width: 140, height: 140)

                    Image(systemName: "cloud.fill")
                        .font(.system(size: 52, weight: .thin))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accent, Color.accentHover],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 8) {
                    Text("Ollama Cloud")
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .foregroundStyle(Color.textPrimary)

                    Text("Chat with your cloud models.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }

                // Card
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API KEY")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textTertiary)
                            .tracking(1.2)

                        SecureField("Paste your key", text: $apiKey)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Color.textPrimary)
                            .glassField()
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    if let error {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundStyle(Color.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Group {
                                if apiKey.isEmpty {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.bgTertiary)
                                } else {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(LinearGradient.accentGradient)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                        )
                                }
                            }
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                }
                .padding(24)
                .chromeCard(cornerRadius: 20)
                .padding(.horizontal, 28)

                Spacer()
                Spacer()
            }
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
                    error = "Invalid API key."
                }
            } catch {
                self.error = error.localizedDescription
            }
            isValidating = false
        }
    }
}
