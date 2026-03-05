import SwiftUI

struct APIKeyEntryView: View {
    @EnvironmentObject private var network: NetworkMonitor
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var isTakingLong = false
    @State private var errorMessage: String?
    @State private var slowTimerTask: Task<Void, Never>?
    @State private var showKeyHelp = false

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

                // Emblem
                Image("SeerEmblem")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 64)
                    .padding(.bottom, 16)

                // Logo
                Image("SeerLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 32)
                    .padding(.bottom, 12)

                Text("ENTER YOUR API KEY TO CONNECT")
                    .font(.appLabel(11))
                    .labelTracking()
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 40)

                // Input card
                VStack(spacing: 18) {
                    SecureField("", text: $apiKey, prompt: Text("Paste Ollama API Key").foregroundStyle(Color.textTertiary))
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
                        showKeyHelp = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 12, weight: .ultraLight))
                            Text("How to get an API key")
                                .font(.app(12))
                        }
                        .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

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

                Spacer(minLength: 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("POWERED BY")
                        .font(.appLabel(10))
                        .tracking(2)
                    Text("OLLAMA")
                        .font(.appLabel(10, weight: .medium))
                        .tracking(2)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 8)

                Link(destination: URL(string: "mailto:licensing@manticthink.com")!) {
                    HStack(spacing: 5) {
                        Image(systemName: "envelope")
                            .font(.system(size: 10, weight: .ultraLight))
                        Text("CONTACT")
                            .font(.appLabel(10))
                            .tracking(2)
                    }
                    .foregroundStyle(Color.accent.opacity(0.95))
                }
            }
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showKeyHelp) {
            keyHelpSheet
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

    private var keyHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Get your Ollama Cloud API key in a few steps:")
                        .font(.app(15, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                    Text("1. Sign in to your Ollama account.")
                        .font(.app(14))
                        .foregroundStyle(Color.textSecondary)
                    Text("2. Open account settings and create a new API key.")
                        .font(.app(14))
                        .foregroundStyle(Color.textSecondary)
                    Text("3. Copy the key and paste it into this app.")
                        .font(.app(14))
                        .foregroundStyle(Color.textSecondary)

                    Link(destination: URL(string: "https://ollama.com")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .ultraLight))
                            Text("Open Ollama")
                                .font(.appLabel(11))
                                .tracking(2)
                        }
                        .foregroundStyle(Color.accent)
                        .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Color.bgPrimary)
            .navigationTitle("API Key Help")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }
}
