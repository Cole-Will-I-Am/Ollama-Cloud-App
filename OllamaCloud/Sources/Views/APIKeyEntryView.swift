import SwiftUI

struct APIKeyEntryView: View {
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accent.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 40,
                        endRadius: 260
                    )
                )
                .frame(width: 500, height: 500)
                .offset(y: -80)
                .blur(radius: 40)

            VStack(spacing: 0) {
                Spacer()

                // Logo
                Image(systemName: "cloud.fill")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(Color.accent.opacity(0.7))
                    .padding(.bottom, 20)

                Text("Ollama Cloud")
                    .font(.app(30, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.bottom, 6)

                Text("Enter your API key to connect")
                    .font(.app(15, weight: .regular))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 40)

                // Input card
                VStack(spacing: 18) {
                    SecureField("", text: $apiKey, prompt: Text("Paste API key").foregroundStyle(Color.textTertiary))
                        .font(.app(15))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.bgSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.borderLight, lineWidth: 0.5)
                                )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let error {
                        Text(error)
                            .font(.app(12, weight: .medium))
                            .foregroundStyle(Color.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
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
                                    .font(.app(16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(apiKey.isEmpty
                                      ? AnyShapeStyle(Color.bgTertiary)
                                      : AnyShapeStyle(LinearGradient.accentGradient))
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                }
                .padding(24)
                .chromeCard()
                .padding(.horizontal, 32)

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
                    error = "Invalid API key"
                }
            } catch {
                self.error = error.localizedDescription
            }
            isValidating = false
        }
    }
}
