import SwiftUI
import AppKit

// MARK: - Codigo Design System
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

        // Semantic
        static let success = Color(red: 0.2, green: 0.78, blue: 0.45)
        static let successLight = Color(red: 0.2, green: 0.78, blue: 0.45).opacity(0.8)
        static let warning = Color(red: 0.96, green: 0.68, blue: 0.22)
        static let warningLight = Color(red: 0.96, green: 0.68, blue: 0.22).opacity(0.8)
        static let error = Color(red: 0.94, green: 0.32, blue: 0.32)
        static let errorLight = Color(red: 0.94, green: 0.32, blue: 0.32).opacity(0.8)
        static let info = Color(red: 0.3, green: 0.56, blue: 0.98)

        // Mode colors — vivid but not garish
        static let agentColor = Color(red: 0.22, green: 0.78, blue: 0.46)
        static let agentColorLight = Color(red: 0.22, green: 0.78, blue: 0.46).opacity(0.8)
        static let ideColor = Color(red: 0.58, green: 0.42, blue: 0.92)
        static let ideColorLight = Color(red: 0.58, green: 0.42, blue: 0.92).opacity(0.8)
        static let mcpColor = Color(red: 0.96, green: 0.58, blue: 0.22)
        static let mcpColorLight = Color(red: 0.96, green: 0.58, blue: 0.22).opacity(0.8)
        static let swarmColor = Color(red: 0.22, green: 0.68, blue: 0.92)
        static let swarmColorLight = Color(red: 0.22, green: 0.68, blue: 0.92).opacity(0.8)
        static let reviewColor = Color(red: 0.18, green: 0.74, blue: 0.72)
        static let reviewColorLight = Color(red: 0.18, green: 0.74, blue: 0.72).opacity(0.8)
        static let planColor = Color(red: 0.32, green: 0.52, blue: 0.96)
        static let planColorLight = Color(red: 0.32, green: 0.52, blue: 0.96).opacity(0.8)

        // Backgrounds
        static let backgroundDeep = Color(nsColor: .windowBackgroundColor)
        static let backgroundPrimary = Color(nsColor: .windowBackgroundColor)
        static let backgroundSecondary = Color(nsColor: .controlBackgroundColor)
        static let backgroundTertiary = Color(nsColor: .textBackgroundColor)
        static let backgroundElevated = Color(nsColor: .controlBackgroundColor)

        // Surfaces — for cards and elevated areas
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let surfaceElevated = Color(nsColor: .controlBackgroundColor)
        static let surfaceGlass = Color(nsColor: .controlBackgroundColor)

        // Chat
        static let userBubble = Color.accentColor.opacity(0.08)
        static let assistantBubble = Color(nsColor: .controlBackgroundColor)

        // Dividers
        static let divider = Color(nsColor: .separatorColor)
        static let dividerStrong = Color(nsColor: .separatorColor)
        static let border = Color(nsColor: .separatorColor)
        static let borderSubtle = Color(nsColor: .separatorColor).opacity(0.5)

        // Backward-compat stubs
        static let glassTint = Color.clear
        static let glassTintLight = Color.clear
        static let glassTintDark = Color.clear
        static let glassBorder = Color(nsColor: .separatorColor)
        static let glassBorderLight = Color(nsColor: .separatorColor)
        static let glassHighlight = Color.clear

        // Gradients
        static let primaryGradient = LinearGradient(colors: [Color.accentColor], startPoint: .leading, endPoint: .trailing)
        static let glassGradient = LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
        static let agentGradient = LinearGradient(colors: [agentColor], startPoint: .leading, endPoint: .trailing)
        static let ideGradient = LinearGradient(colors: [ideColor], startPoint: .leading, endPoint: .trailing)
        static let mcpGradient = LinearGradient(colors: [mcpColor], startPoint: .leading, endPoint: .trailing)
        static let swarmGradient = LinearGradient(colors: [swarmColor], startPoint: .leading, endPoint: .trailing)
        static let reviewGradient = LinearGradient(colors: [reviewColor], startPoint: .leading, endPoint: .trailing)
        static let planGradient = LinearGradient(colors: [planColor], startPoint: .leading, endPoint: .trailing)
        static let shimmerGradient = LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Typography
    struct Typography {
        static let display = Font.system(size: 34, weight: .bold)
        static let displayMedium = Font.system(size: 28, weight: .semibold)
        static let largeTitle = Font.largeTitle
        static let title = Font.title
        static let title2 = Font.title2
        static let title3 = Font.title3
        static let headline = Font.headline
        static let body = Font.body
        static let bodyMedium = Font.body.weight(.medium)
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let subheadlineMedium = Font.subheadline.weight(.medium)
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let captionMedium = Font.caption.weight(.medium)
        static let caption2 = Font.caption2
        static let code = Font.system(size: 13, design: .monospaced)
        static let codeSmall = Font.system(size: 11, design: .monospaced)
        static let codeLarge = Font.system(size: 15, design: .monospaced)

        static func medium(_ font: Font) -> Font { font.weight(.medium) }
        static func semibold(_ font: Font) -> Font { font.weight(.semibold) }
        static func bold(_ font: Font) -> Font { font.weight(.bold) }
    }

    // MARK: - Spacing
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

    struct Blur {
        static let light: CGFloat = 8
        static let medium: CGFloat = 16
        static let heavy: CGFloat = 24
        static let ultra: CGFloat = 40
    }

    struct Shadows {
        static let small = Color.black.opacity(0.1)
        static let medium = Color.black.opacity(0.15)
        static let large = Color.black.opacity(0.2)
        static let glow = Color.clear
        static func primaryGlow(radius: CGFloat = 0) -> some View { Color.clear }
        static func coloredGlow(_ color: Color, radius: CGFloat = 0) -> some View { Color.clear }
    }
}

// MARK: - Hover Effect (real but subtle)
struct HoverHighlight: ViewModifier {
    @State private var isHovered = false
    var activeColor: Color = Color.primary.opacity(0.06)

    func body(content: Content) -> some View {
        content
            .background(isHovered ? activeColor : Color.clear)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    func hoverHighlight(_ color: Color = Color.primary.opacity(0.06)) -> some View {
        modifier(HoverHighlight(activeColor: color))
    }

    func liquidGlass(
        material: Material = .bar,
        cornerRadius: CGFloat = DesignSystem.CornerRadius.large,
        tint: Color = .clear,
        borderOpacity: CGFloat = 0
    ) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color(nsColor: .controlBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    func glassBackground(cornerRadius: CGFloat = DesignSystem.CornerRadius.large, tint: Color = .clear) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color(nsColor: .controlBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    func hoverEffect(scale: CGFloat = 1.0) -> some View { self }
    func glow(color: Color, radius: CGFloat = 0) -> some View { self }
}

// MARK: - Glass Card
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.large
    var padding: CGFloat = DesignSystem.Spacing.lg
    var tint: Color = .clear
    init(cornerRadius: CGFloat = DesignSystem.CornerRadius.large, padding: CGFloat = DesignSystem.Spacing.lg, tint: Color = .clear, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius; self.padding = padding; self.tint = tint; self.content = content()
    }
    var body: some View {
        content.padding(padding)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color(nsColor: .controlBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Mode Badge
struct ModeBadge: View {
    let mode: CoderMode
    let isActive: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName).font(.caption2)
            Text(mode.rawValue).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(modeColor)
        .background(modeColor.opacity(0.12), in: Capsule())
    }
    private var iconName: String {
        switch mode {
        case .agent: return "brain.head.profile"
        case .ide: return "sparkles"
        case .mcpServer: return "server.rack"
        case .agentSwarm: return "ant.fill"
        case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"
        case .plan: return "list.bullet.rectangle"
        }
    }
    private var modeColor: Color {
        switch mode {
        case .agent: return DesignSystem.Colors.agentColor
        case .ide: return DesignSystem.Colors.ideColor
        case .mcpServer: return DesignSystem.Colors.mcpColor
        case .agentSwarm: return DesignSystem.Colors.swarmColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor
        case .plan: return DesignSystem.Colors.planColor
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String; let icon: String?
    init(_ title: String, icon: String? = nil) { self.title = title; self.icon = icon }
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.caption).foregroundStyle(.secondary) }
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).textCase(.uppercase).tracking(0.8)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg).padding(.top, DesignSystem.Spacing.lg)
    }
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    enum Status {
        case online, offline, loading, error
        var color: Color { switch self { case .online: return .green; case .offline: return .secondary; case .loading: return .orange; case .error: return .red } }
        var icon: String { switch self { case .online: return "checkmark.circle.fill"; case .offline: return "circle"; case .loading: return "arrow.triangle.2.circlepath"; case .error: return "exclamationmark.circle.fill" } }
    }
    let status: Status; let text: String
    var body: some View {
        HStack(spacing: 4) { Image(systemName: status.icon).font(.caption2); Text(text).font(.caption) }.foregroundStyle(status.color)
    }
}

// MARK: - Button Styles
struct GlassButtonStyle: ButtonStyle {
    var tint: Color = .accentColor; var isDestructive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium))
            .foregroundStyle(isDestructive ? .red : tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill((isDestructive ? Color.red : tint).opacity(0.1)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct GlassInputStyle: TextFieldStyle {
    var tintColor: Color = .accentColor
    func _body(configuration: TextField<Self._Label>) -> some View { configuration.textFieldStyle(.roundedBorder) }
}

extension Animation {
    static let smooth = Animation.easeInOut(duration: 0.2)
    static let smoothSlow = Animation.easeInOut(duration: 0.35)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let springBouncy = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let quick = Animation.easeOut(duration: 0.15)
    static let gentle = Animation.spring(response: 0.4, dampingFraction: 0.85)
}

struct ToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.accentColor : .secondary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct AnimatedGradientBackground: View { var body: some View { Color.clear } }
struct FloatingOrb: View {
    let color: Color; let size: CGFloat
    init(color: Color, size: CGFloat = 200) { self.color = color; self.size = size }
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}
struct ParticleView: View {
    let color: Color; init(color: Color = .accentColor) { self.color = color }
    var body: some View { Color.clear }
}
