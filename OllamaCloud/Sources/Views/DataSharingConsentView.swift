import SwiftUI

/// Full-screen consent gate shown before SEER sends any chat content to a
/// third-party AI provider. Required by App Store Guidelines 5.1.1(i)/5.1.2(i):
/// the user must be told what data is sent and to whom, and must explicitly
/// agree, before personal data is shared.
struct DataSharingConsentView: View {
    @AppStorage(ConsentStore.storageKey) private var consentSignature = ""
    @State private var showDeclineInfo = false

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // Ambient glow, matching the API-key screen.
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
                .offset(y: -120)
                .blur(radius: 40)
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 0) {
                    Image("SeerEmblem")
                        .resizable()
                        #if os(macOS)
                        .interpolation(.high)
                        #endif
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 56)
                        .padding(.top, 48)
                        .padding(.bottom, 18)

                    Text("DATA & PRIVACY")
                        .font(.appLabel(11))
                        .labelTracking()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)

                    Text("Before you start chatting")
                        .font(.app(20, weight: .light))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)

                    DataSharingDisclosure()
                        .padding(20)
                        .chromeCard()
                        .padding(.horizontal, 24)

                    agreeButton
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    Button {
                        showDeclineInfo = true
                    } label: {
                        Text("Not now")
                            .font(.app(13))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .macPointingCursor()
                    #endif
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert("Consent is required", isPresented: $showDeclineInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("SEER sends your messages to an AI provider to generate replies. Without your agreement it can't produce responses. You can review the privacy policy before deciding.")
        }
    }

    private var agreeButton: some View {
        Button {
            Haptic.notification(.success)
            ConsentStore.recordConsent()
            // Keep the @AppStorage-backed value in sync so the gate dismisses.
            consentSignature = ConsentStore.requiredSignature()
        } label: {
            Text("I AGREE & CONTINUE")
                .font(.appLabel(14))
                .labelTracking()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(LinearGradient.accentGradient))
                .foregroundStyle(.white)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        .macPointingCursor()
        #endif
    }
}

/// The disclosure body: what data is sent, to whom, and a link to the policy.
/// Reused by the consent gate and the Settings review sheet so the two never
/// drift apart.
struct DataSharingDisclosure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("When you send a message, SEER transmits the following to your configured AI provider so it can generate a response:")
                .font(.app(13, weight: .light))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                point(icon: "text.bubble", title: "Your messages & chat history",
                      detail: "The text you type and the earlier messages in the current conversation.")
                point(icon: "photo", title: "Attachments",
                      detail: "Any images or files you add to a message.")
                point(icon: "gearshape.2", title: "System instructions",
                      detail: "The system prompt and tool definitions used for the request.")
            }

            Divider().overlay(Color.borderLight)

            VStack(alignment: .leading, spacing: 8) {
                Text("WHO RECEIVES IT")
                    .font(.appLabel(10))
                    .labelTracking()
                    .foregroundStyle(Color.textTertiary)
                Text(recipientDescription)
                    .font(.app(13, weight: .light))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Your data is handled under that provider's privacy policy. SEER does not sell your data or use it for advertising. Chats and credentials stay on your device otherwise.")
                .font(.app(12, weight: .light))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = URL(string: AppConfig.privacyPolicyURL) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .ultraLight))
                        Text("READ THE PRIVACY POLICY")
                            .font(.appLabel(11))
                            .tracking(2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Color.accent)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                .macPointingCursor()
                #endif
            }
        }
    }

    /// Names the active destination(s). Defaults to Ollama Cloud; mentions OpenAI
    /// and custom servers so the disclosure stays accurate after the user changes
    /// providers.
    private var recipientDescription: String {
        let host = AppConfig.apiHostDisplayName
        return "By default, Ollama Cloud (\(host)). If you add an OpenAI key, requests to OpenAI models go to OpenAI (api.openai.com) instead. If you configure a custom server address, your data is sent to that server."
    }

    private func point(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .ultraLight))
                    .foregroundStyle(Color.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.app(12, weight: .light))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Read-only review of the data-sharing disclosure, presented from Settings.
struct DataSharingDisclosureSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DataSharingDisclosure()
                    .padding(20)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Data & Privacy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .background(Color.bgPrimary.ignoresSafeArea())
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Text("DONE")
                            .font(.appLabel(12))
                            .tracking(2)
                            #if os(iOS)
                            .foregroundStyle(Color.accent)
                            #else
                            .foregroundStyle(Color.textPrimary)
                            #endif
                    }
                    #if os(macOS)
                    .buttonStyle(.bordered)
                    #endif
                }
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        #else
        .presentationBackground(Color.bgPrimary)
        #endif
    }
}
