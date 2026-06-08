import Foundation

/// Tracks the user's explicit consent to send chat content to a third-party AI
/// provider, as required by App Store Review Guidelines 5.1.1(i) / 5.1.2(i).
///
/// Consent is bound to a "signature" that encodes the policy version and the
/// active data destination (the API host). If the destination changes — for
/// example the user points the app at a different server — or the disclosure is
/// updated, the stored signature no longer matches and the user is asked to
/// consent again before any data is sent.
enum ConsentStore {
    static let storageKey = "data_sharing_consent_signature"

    /// Bump when the disclosure text materially changes, to re-prompt users.
    static let policyVersion = 1

    /// The signature the user must currently match to be considered consented.
    static func requiredSignature() -> String {
        "v\(policyVersion)|\(AppConfig.apiHostDisplayName)"
    }

    /// Whether the given stored signature still satisfies the current requirement.
    /// Pass the value read from `@AppStorage(ConsentStore.storageKey)` so the
    /// check re-evaluates reactively when consent is recorded or the host changes.
    static func hasConsented(signature: String) -> Bool {
        !signature.isEmpty && signature == requiredSignature()
    }

    /// Convenience for non-reactive call sites.
    static var hasConsented: Bool {
        let stored = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return hasConsented(signature: stored)
    }

    static func recordConsent() {
        UserDefaults.standard.set(requiredSignature(), forKey: storageKey)
    }

    static func revokeConsent() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
