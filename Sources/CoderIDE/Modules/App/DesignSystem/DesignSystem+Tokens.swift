import SwiftUI
import AppKit

// MARK: - Adaptive Color Helpers

func codigoAdaptiveNS(_ light: NSColor, _ dark: NSColor) -> NSColor {
    NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

func codigoAdaptive(_ light: NSColor, _ dark: NSColor) -> Color {
    Color(nsColor: codigoAdaptiveNS(light, dark))
}

// MARK: - Design System

struct DesignSystem {

    // MARK: - Colors
    struct Colors {
        static let primary = Color.accentColor
        static let primaryLight = Color.accentColor.opacity(0.8)
        static let primaryDark = Color.accentColor

        // Text hierarchy
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)
        static let textQuaternary = Color(nsColor: .quaternaryLabelColor)

        static let secondary = Color.secondary
        static let secondaryDark = Color(nsColor: .tertiaryLabelColor)
        static let secondaryLight = Color.secondary

        // Semantic — Tailwind-inspired
        static let success = Color(red: 0.13, green: 0.77, blue: 0.37)
        static let successLight = success.opacity(0.8)
        static let warning = Color(red: 0.98, green: 0.57, blue: 0.24)
        static let warningLight = warning.opacity(0.8)
        static let error = Color(red: 0.94, green: 0.27, blue: 0.27)
        static let errorLight = error.opacity(0.8)
        static let info = Color(red: 0.23, green: 0.51, blue: 0.96)

        // Mode colors — vibrant, curated
        static let agentColor = Color(red: 0.13, green: 0.77, blue: 0.37)
        static let agentColorLight = agentColor.opacity(0.8)
        static let ideColor = Color(red: 0.65, green: 0.55, blue: 0.98)
        static let ideColorLight = ideColor.opacity(0.8)
        static let mcpColor = Color(red: 0.98, green: 0.57, blue: 0.24)
        static let mcpColorLight = mcpColor.opacity(0.8)
        static let swarmColor = Color(red: 0.22, green: 0.74, blue: 0.97)
        static let swarmColorLight = swarmColor.opacity(0.8)
        static let reviewColor = Color(red: 0.18, green: 0.83, blue: 0.75)
        static let reviewColorLight = reviewColor.opacity(0.8)
        static let planColor = Color(red: 0.95, green: 0.55, blue: 0.18)
        static let planColorLight = planColor.opacity(0.8)
        static let debugColor = Color(red: 0.94, green: 0.22, blue: 0.22)
        static let debugColorLight = debugColor.opacity(0.8)
        static let browserColor = Color(red: 0.30, green: 0.68, blue: 0.95)
        static let browserColorLight = browserColor.opacity(0.8)
        static let browserGradient = LinearGradient(
            colors: [browserColor, Color(red: 0.22, green: 0.82, blue: 0.88)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        // Background layers — neutral dark greys (Cursor style)
        static let backgroundDeep = codigoAdaptive(
            .windowBackgroundColor,
            NSColor(red: 0.067, green: 0.067, blue: 0.075, alpha: 1)
        )
        static let backgroundPrimary = codigoAdaptive(
            .windowBackgroundColor,
            NSColor(red: 0.098, green: 0.098, blue: 0.106, alpha: 1)
        )
        static let backgroundSecondary = codigoAdaptive(
            .controlBackgroundColor,
            NSColor(red: 0.118, green: 0.118, blue: 0.128, alpha: 1)
        )
        static let backgroundTertiary = codigoAdaptive(
            .textBackgroundColor,
            NSColor(red: 0.137, green: 0.137, blue: 0.149, alpha: 1)
        )
        static let backgroundElevated = codigoAdaptive(
            .controlBackgroundColor,
            NSColor(red: 0.157, green: 0.157, blue: 0.169, alpha: 1)
        )

        // Surfaces
        static let surface = backgroundSecondary
        static let surfaceElevated = backgroundElevated
        static let surfaceGlass = backgroundSecondary

        // Chat
        static let userBubble = codigoAdaptive(
            NSColor.controlAccentColor.withAlphaComponent(0.06),
            NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 0.08)
        )
        static let assistantBubble = backgroundSecondary
        /// Neutral user bubble fill — ChatGPT-style (not mode-colored)
        static let chatUserBubbleFill = codigoAdaptive(
            NSColor(red: 0.945, green: 0.945, blue: 0.957, alpha: 0.92),
            NSColor(red: 0.173, green: 0.173, blue: 0.204, alpha: 0.85)
        )
        /// Default chat surface in minimal mode (opaque, neutral).
        static let chatPanelSolidBackground = codigoAdaptive(
            NSColor(red: 0.965, green: 0.965, blue: 0.972, alpha: 1.0),
            NSColor(red: 0.098, green: 0.098, blue: 0.106, alpha: 1.0)
        )

        // Borders — neutral greys (Cursor style)
        static let divider = codigoAdaptive(
            .separatorColor,
            NSColor(red: 0.196, green: 0.196, blue: 0.208, alpha: 1)
        )
        static let dividerStrong = codigoAdaptive(
            .separatorColor,
            NSColor(red: 0.235, green: 0.235, blue: 0.247, alpha: 1)
        )
        static let border = divider
        static let borderSubtle = codigoAdaptive(
            NSColor.separatorColor.withAlphaComponent(0.5),
            NSColor(red: 0.157, green: 0.157, blue: 0.169, alpha: 1)
        )
        static let borderAccent = codigoAdaptive(
            NSColor.separatorColor,
            NSColor(red: 0.255, green: 0.255, blue: 0.267, alpha: 1)
        )

        // Glass stubs
        static let glassTint = Color.clear
        static let glassTintLight = Color.clear
        static let glassTintDark = Color.clear
        static let glassBorder = border
        static let glassBorderLight = borderSubtle
        static let glassHighlight = Color.clear

        // Mode gradients — 2-stop subtle shifts
        static let primaryGradient = LinearGradient(
            colors: [planColor, Color(red: 0.98, green: 0.68, blue: 0.32)],
            startPoint: .leading, endPoint: .trailing
        )
        static let agentGradient = LinearGradient(
            colors: [agentColor, Color(red: 0.20, green: 0.85, blue: 0.52)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let ideGradient = LinearGradient(
            colors: [ideColor, Color(red: 0.75, green: 0.62, blue: 0.99)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let mcpGradient = LinearGradient(
            colors: [mcpColor, Color(red: 0.99, green: 0.70, blue: 0.38)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let swarmGradient = LinearGradient(
            colors: [swarmColor, Color(red: 0.38, green: 0.82, blue: 0.99)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let reviewGradient = LinearGradient(
            colors: [reviewColor, Color(red: 0.30, green: 0.90, blue: 0.84)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let planGradient = LinearGradient(
            colors: [planColor, Color(red: 0.98, green: 0.68, blue: 0.32)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let debugGradient = LinearGradient(
            colors: [debugColor, Color(red: 0.98, green: 0.35, blue: 0.28)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let glassGradient = LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
        static let shimmerGradient = LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Typography
    struct Typography {
        static let display = FontPreferences.resolveSansFont(size: 34, family: FontPreferences.defaultSansFamily, weight: .bold)
        static let displayMedium = FontPreferences.resolveSansFont(size: 28, family: FontPreferences.defaultSansFamily, weight: .semibold)
        static let largeTitle = FontPreferences.resolveSansFont(size: 26, family: FontPreferences.defaultSansFamily, weight: .bold)
        static let title = FontPreferences.resolveSansFont(size: 22, family: FontPreferences.defaultSansFamily, weight: .semibold)
        static let title2 = FontPreferences.resolveSansFont(size: 19, family: FontPreferences.defaultSansFamily, weight: .semibold)
        static let title3 = FontPreferences.resolveSansFont(size: 17, family: FontPreferences.defaultSansFamily, weight: .semibold)
        static let headline = FontPreferences.resolveSansFont(size: 15, family: FontPreferences.defaultSansFamily, weight: .semibold)
        static let body = FontPreferences.resolveSansFont(size: 13.5, family: FontPreferences.defaultSansFamily)
        static let bodyMedium = FontPreferences.resolveSansFont(size: 13.5, family: FontPreferences.defaultSansFamily, weight: .medium)
        static let callout = FontPreferences.resolveSansFont(size: 13, family: FontPreferences.defaultSansFamily)
        static let subheadline = FontPreferences.resolveSansFont(size: 12, family: FontPreferences.defaultSansFamily)
        static let subheadlineMedium = FontPreferences.resolveSansFont(size: 12, family: FontPreferences.defaultSansFamily, weight: .medium)
        static let footnote = FontPreferences.resolveSansFont(size: 11, family: FontPreferences.defaultSansFamily)
        static let caption = FontPreferences.resolveSansFont(size: 10.5, family: FontPreferences.defaultSansFamily)
        static let captionMedium = FontPreferences.resolveSansFont(size: 10.5, family: FontPreferences.defaultSansFamily, weight: .medium)
        static let caption2 = FontPreferences.resolveSansFont(size: 10, family: FontPreferences.defaultSansFamily)
        static let code = FontPreferences.resolveCodeFont(size: 13, family: FontPreferences.defaultCodeFamily)
        static let codeSmall = FontPreferences.resolveCodeFont(size: 11, family: FontPreferences.defaultCodeFamily)
        static let codeLarge = FontPreferences.resolveCodeFont(size: 15, family: FontPreferences.defaultCodeFamily)

        static func medium(_ font: Font) -> Font { font.weight(.medium) }
        static func semibold(_ font: Font) -> Font { font.weight(.semibold) }
        static func bold(_ font: Font) -> Font { font.weight(.bold) }
    }

    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let xxxxl: CGFloat = 48
    }

    struct CornerRadius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let round: CGFloat = 9999
    }

    struct Sidebar {
        static let cardRadius: CGFloat = 12
        static let rowRadius: CGFloat = 8
        static let sectionSpacing: CGFloat = 10
        static let insetXS: CGFloat = 6
        static let insetSM: CGFloat = 8
        static let insetMD: CGFloat = 10
        static let insetLG: CGFloat = 12
    }

    struct Blur {
        static let light: CGFloat = 8
        static let medium: CGFloat = 16
        static let heavy: CGFloat = 24
        static let ultra: CGFloat = 40
    }

    struct Shadows {
        static let small = Color.black.opacity(0.15)
        static let medium = Color.black.opacity(0.22)
        static let large = Color.black.opacity(0.30)
        static let glow = Color.clear
        static func primaryGlow(radius: CGFloat = 0) -> some View { Color.clear }
        static func coloredGlow(_ color: Color, radius: CGFloat = 0) -> some View { Color.clear }
    }

    // MARK: - AppKit Helpers
    struct AppKit {
        static let windowBackground = codigoAdaptiveNS(
            .windowBackgroundColor,
            NSColor(red: 0.050, green: 0.050, blue: 0.075, alpha: 1)
        )
    }
}
