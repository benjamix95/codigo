import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.large
    var padding: CGFloat = DesignSystem.Spacing.lg
    var tint: Color = .clear
    init(cornerRadius: CGFloat = DesignSystem.CornerRadius.large, padding: CGFloat = DesignSystem.Spacing.lg, tint: Color = .clear, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.content = content()
    }
    var body: some View {
        content.padding(padding)
            .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5))
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
        case .agent: return "brain.head.profile"; case .ide: return "sparkles"; case .mcpServer: return "server.rack"
        case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"; case .debug: return "ladybug.fill"; case .plan: return "list.bullet.rectangle"
        case .browser: return "globe"
        }
    }
    private var modeColor: Color {
        switch mode {
        case .agent: return DesignSystem.Colors.agentColor; case .ide: return DesignSystem.Colors.ideColor
        case .mcpServer: return DesignSystem.Colors.mcpColor; case .browser: return DesignSystem.Colors.browserColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor; case .debug: return DesignSystem.Colors.debugColor; case .plan: return DesignSystem.Colors.planColor
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    let icon: String?
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
    let status: Status
    let text: String
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

struct ToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.accentColor : .secondary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension Animation {
    static let smooth = Animation.easeInOut(duration: 0.2)
    static let smoothSlow = Animation.easeInOut(duration: 0.35)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let springBouncy = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let quick = Animation.easeOut(duration: 0.15)
    static let gentle = Animation.spring(response: 0.4, dampingFraction: 0.85)
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
