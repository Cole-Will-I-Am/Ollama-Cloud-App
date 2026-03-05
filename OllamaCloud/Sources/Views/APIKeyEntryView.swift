import SwiftUI

struct APIKeyEntryView: View {
    @EnvironmentObject private var network: NetworkMonitor
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var isTakingLong = false
    @State private var errorMessage: String?
    @State private var slowTimerTask: Task<Void, Never>?

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
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                // Logo
                Image("SeerLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 36)
                    .padding(.bottom, 24)

                Text("ENTER YOUR API KEY TO CONNECT")
                    .font(.appLabel(11))
                    .labelTracking()
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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.app(12, weight: .medium))
                            .foregroundStyle(Color.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    // Slow validation hint
                    if isTakingLong {
                        Text("Taking longer than expected...")
                            .font(.app(12, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                    }

                    Button {
                        validate()
                    } label: {
                        Group {
                            if isValidating {
                                ProgressView()
                                    .tint(.white)
                            } else if !network.isConnected {
                                HStack(spacing: 6) {
                                    Image(systemName: "wifi.slash")
                                        .font(.system(size: 13, weight: .ultraLight))
                                    Text("NO CONNECTION")
                                        .font(.appLabel(13))
                                        .labelTracking()
                                }
                            } else {
                                Text("CONNECT")
                                    .font(.appLabel(14))
                                    .labelTracking()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(connectButtonDisabled
                                      ? AnyShapeStyle(Color.bgTertiary)
                                      : AnyShapeStyle(LinearGradient.accentGradient))
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(connectButtonDisabled)
                }
                .padding(24)
                .chromeCard()
                .padding(.horizontal, 32)

                Spacer()
                Spacer()
            }
        }
    }

    private var connectButtonDisabled: Bool {
        apiKey.isEmpty || isValidating || !network.isConnected
    }

    private func validate() {
        guard network.isConnected else {
            errorMessage = "No internet connection"
            return
        }

        isValidating = true
        isTakingLong = false
        errorMessage = nil

        // Start slow-timer: show hint after 15s
        slowTimerTask?.cancel()
        slowTimerTask = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeIn(duration: 0.2)) {
                    isTakingLong = true
                }
            }
        }

        Task {
            do {
                let valid = try await OllamaAPIClient.shared.validateKey(apiKey)
                if valid {
                    Haptic.notification(.success)
                    KeychainHelper.save(key: "api_key", value: apiKey)
                    hasAPIKey = true
                } else {
                    errorMessage = "Invalid API key"
                }
            } catch let apiError as OllamaAPIError {
                errorMessage = apiError.userMessage
            } catch {
                errorMessage = error.localizedDescription
            }

            slowTimerTask?.cancel()
            isValidating = false
            isTakingLong = false
        }
    }
}
