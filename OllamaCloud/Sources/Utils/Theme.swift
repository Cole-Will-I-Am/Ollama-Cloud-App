import SwiftUI

// MARK: - Colors

extension Color {
    // Backgrounds
    static let bgPrimary = Color(red: 0.03, green: 0.03, blue: 0.04)
    static let bgSecondary = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let bgTertiary = Color(red: 0.10, green: 0.10, blue: 0.13)

    // Surfaces
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.10)
    static let surfaceElevated = Color(red: 0.10, green: 0.10, blue: 0.13)

    // Text
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.45)
    static let textTertiary = Color.white.opacity(0.25)

    // Accent
    static let accent = Color(red: 0.38, green: 0.50, blue: 1.0)
    static let accentSoft = Color(red: 0.38, green: 0.50, blue: 1.0).opacity(0.12)

    // Borders
    static let border = Color.white.opacity(0.05)
    static let borderLight = Color.white.opacity(0.08)

    // Semantic
    static let danger = Color(red: 1.0, green: 0.32, blue: 0.32)
    static let success = Color(red: 0.24, green: 0.86, blue: 0.56)

    // Bubbles
    static let userBubble = Color(red: 0.32, green: 0.44, blue: 1.0)
    static let assistantBubble = Color.white.opacity(0.04)
}

// MARK: - Gradients

extension LinearGradient {
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.48, blue: 1.0),
            Color(red: 0.55, green: 0.38, blue: 0.95)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [Color.white.opacity(0.03), Color.white.opacity(0.0)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Font

extension Font {
    /// Primary app font — clean sans-serif (SF Pro)
    static func app(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Wide-tracked label font — for buttons, badges, small UI labels.
    /// Expanded width with light weight for that "CONTACT" / "BETA" aesthetic.
    static func appLabel(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .default).width(.expanded)
    }

    /// Display font — for large titles / hero text. Thin, slightly tracked.
    static func appDisplay(_ size: CGFloat, weight: Font.Weight = .thin) -> Font {
        .system(size: size, weight: weight, design: .default).width(.expanded)
    }
}

// MARK: - Tracking Modifier

extension View {
    /// Apply wide letter-spacing for the tracked uppercase label look.
    func labelTracking() -> some View {
        self.tracking(3)
    }

    /// Subtle tracking for titles and headings.
    func titleTracking() -> some View {
        self.tracking(1.2)
    }
}

// MARK: - View Modifiers

struct ChromeCard: ViewModifier {
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient.surfaceGradient)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.border, lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    func chromeCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(ChromeCard(radius: cornerRadius))
    }
}
