import SwiftUI

// MARK: - Colors

extension Color {
    // Backgrounds — near-black with blue undertone
    static let bgPrimary = Color(red: 0.035, green: 0.035, blue: 0.055)
    static let bgSecondary = Color(red: 0.065, green: 0.065, blue: 0.085)
    static let bgTertiary = Color(red: 0.095, green: 0.095, blue: 0.115)

    // Surfaces — chrome dark
    static let surface = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let surfaceElevated = Color(red: 0.11, green: 0.11, blue: 0.14)

    // Text
    static let textPrimary = Color(red: 0.93, green: 0.93, blue: 0.96)
    static let textSecondary = Color(red: 0.50, green: 0.50, blue: 0.56)
    static let textTertiary = Color(red: 0.35, green: 0.35, blue: 0.40)

    // Chrome accent — cool silver-blue
    static let accent = Color(red: 0.40, green: 0.52, blue: 0.98)
    static let accentHover = Color(red: 0.50, green: 0.60, blue: 1.0)

    // Borders — ultra-subtle metallic edge
    static let border = Color.white.opacity(0.06)
    static let borderLight = Color.white.opacity(0.10)

    // Semantic
    static let danger = Color(red: 1.0, green: 0.30, blue: 0.35)
    static let success = Color(red: 0.20, green: 0.84, blue: 0.55)

    // Bubbles
    static let userBubble = Color(red: 0.30, green: 0.42, blue: 0.95)
    static let assistantBubble = Color(red: 0.09, green: 0.09, blue: 0.12)
}

// MARK: - Gradients

extension LinearGradient {
    /// Accent button gradient
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.35, green: 0.45, blue: 0.95),
            Color(red: 0.50, green: 0.35, blue: 0.90)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Chrome edge highlight
    static let chromeEdge = LinearGradient(
        colors: [
            Color.white.opacity(0.12),
            Color.white.opacity(0.03),
            Color.white.opacity(0.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Subtle surface gradient for cards
    static let surfaceGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.04),
            Color.white.opacity(0.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View Modifiers

struct ChromeCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(LinearGradient.surfaceGradient)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.border, lineWidth: 0.5)
                    )
            )
    }
}

struct GlassField: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.borderLight, lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    func chromeCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(ChromeCard(cornerRadius: cornerRadius))
    }

    func glassField(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassField(cornerRadius: cornerRadius))
    }
}
