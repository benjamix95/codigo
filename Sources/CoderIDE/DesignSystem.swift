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
        static let planColor = Color(red: 0.39, green: 0.40, blue: 0.95)
        static let planColorLight = planColor.opacity(0.8)

        // Background layers — rich blue-black in dark, system in light
        static let backgroundDeep = codigoAdaptive(
            .windowBackgroundColor,
            NSColor(red: 0.050, green: 0.050, blue: 0.075, alpha: 1)
        )
        static let backgroundPrimary = codigoAdaptive(
            .windowBackgroundColor,
            NSColor(red: 0.063, green: 0.063, blue: 0.098, alpha: 1)
        )
        static let backgroundSecondary = codigoAdaptive(
            .controlBackgroundColor,
            NSColor(red: 0.082, green: 0.082, blue: 0.133, alpha: 1)
        )
        static let backgroundTertiary = codigoAdaptive(
            .textBackgroundColor,
            NSColor(red: 0.098, green: 0.098, blue: 0.157, alpha: 1)
        )
        static let backgroundElevated = codigoAdaptive(
            .controlBackgroundColor,
            NSColor(red: 0.114, green: 0.114, blue: 0.188, alpha: 1)
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

        // Borders
        static let divider = codigoAdaptive(
            .separatorColor,
            NSColor(red: 0.150, green: 0.150, blue: 0.243, alpha: 1)
        )
        static let dividerStrong = codigoAdaptive(
            .separatorColor,
            NSColor(red: 0.196, green: 0.196, blue: 0.314, alpha: 1)
        )
        static let border = divider
        static let borderSubtle = codigoAdaptive(
            NSColor.separatorColor.withAlphaComponent(0.5),
            NSColor(red: 0.125, green: 0.125, blue: 0.204, alpha: 1)
        )
        static let borderAccent = codigoAdaptive(
            NSColor.separatorColor,
            NSColor(red: 0.220, green: 0.220, blue: 0.365, alpha: 1)
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
            colors: [planColor, Color(red: 0.51, green: 0.55, blue: 0.98)],
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
            colors: [planColor, Color(red: 0.53, green: 0.56, blue: 0.98)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let glassGradient = LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
        static let shimmerGradient = LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Typography
    struct Typography {
        static let display = Font.system(size: 34, weight: .bold, design: .rounded)
        static let displayMedium = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let largeTitle = Font.system(.largeTitle, design: .rounded)
        static let title = Font.system(.title, design: .rounded)
        static let title2 = Font.system(.title2, design: .rounded)
        static let title3 = Font.system(.title3, design: .rounded)
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

// MARK: - View Extensions

struct HoverHighlight: ViewModifier {
    @State private var isHovered = false
    var activeColor: Color

    func body(content: Content) -> some View {
        content
            .background(isHovered ? activeColor : Color.clear)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct SidebarMaterialBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    func hoverHighlight(_ color: Color = Color.primary.opacity(0.06)) -> some View {
        modifier(HoverHighlight(activeColor: color))
    }

    func sidebarPanel(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(SidebarMaterialBackground())
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
            )
    }

    func panelBackground(cornerRadius: CGFloat = 0) -> some View {
        self
            .background(DesignSystem.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    func panelBorder(cornerRadius: CGFloat = 0) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
            )
    }

    func liquidGlass(
        material: Material = .bar,
        cornerRadius: CGFloat = DesignSystem.CornerRadius.large,
        tint: Color = .clear,
        borderOpacity: CGFloat = 0
    ) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(DesignSystem.Colors.backgroundSecondary))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    func glassBackground(cornerRadius: CGFloat = DesignSystem.CornerRadius.large, tint: Color = .clear) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(DesignSystem.Colors.backgroundSecondary))
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
            .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5))
    }
}

// MARK: - Mode Badge
struct ModeBadge: View {
    let mode: CoderMode; let isActive: Bool
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
        case .agent: return "brain.head.profile"; case .ide: return "sparkles"; case .mcpServer: return "server.rack"
        case .agentSwarm: return "ant.fill"; case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"; case .plan: return "list.bullet.rectangle"
        }
    }
    private var modeColor: Color {
        switch mode {
        case .agent: return DesignSystem.Colors.agentColor; case .ide: return DesignSystem.Colors.ideColor
        case .mcpServer: return DesignSystem.Colors.mcpColor; case .agentSwarm: return DesignSystem.Colors.swarmColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor; case .plan: return DesignSystem.Colors.planColor
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
        var color: Color {
            switch self {
            case .online: return DesignSystem.Colors.success; case .offline: return .secondary
            case .loading: return DesignSystem.Colors.warning; case .error: return DesignSystem.Colors.error
            }
        }
        var icon: String {
            switch self {
            case .online: return "checkmark.circle.fill"; case .offline: return "circle"
            case .loading: return "arrow.triangle.2.circlepath"; case .error: return "exclamationmark.circle.fill"
            }
        }
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
            .foregroundStyle(isDestructive ? DesignSystem.Colors.error : tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill((isDestructive ? DesignSystem.Colors.error : tint).opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder((isDestructive ? DesignSystem.Colors.error : tint).opacity(0.15), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: DesignSystem.Colors.planColor.opacity(0.25), radius: 6, y: 2)
            .opacity(configuration.isPressed ? 0.85 : 1).scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(DesignSystem.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5))
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

// MARK: - Backward compat stubs
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
