import SwiftUI
import AppKit

// MARK: - Liquid Glass Design System
/// Apple-inspired "Liquid Glass" design with glassmorphism, blur effects, and elegant transparency
struct DesignSystem {
    
    // MARK: - Colors
    struct Colors {
        // Primary accent - elegant blue-violet gradient
        static let primary = Color(
            red: 0.35,
            green: 0.47,
            blue: 0.95
        )
        static let primaryLight = Color(
            red: 0.45,
            green: 0.57,
            blue: 1.0
        )
        static let primaryDark = Color(
            red: 0.25,
            green: 0.37,
            blue: 0.85
        )
        
        // Glass tints
        static let glassTint = Color.white.opacity(0.03)
        static let glassTintLight = Color.white.opacity(0.05)
        static let glassTintDark = Color.black.opacity(0.1)
        static let glassBorder = Color.white.opacity(0.08)
        static let glassBorderLight = Color.white.opacity(0.12)
        static let glassHighlight = Color.white.opacity(0.15)
        
        // Background layers - deep space aesthetic
        static let backgroundDeep = Color(
            red: 0.02,
            green: 0.02,
            blue: 0.06
        )
        static let backgroundPrimary = Color(
            red: 0.04,
            green: 0.04,
            blue: 0.08
        )
        static let backgroundSecondary = Color(
            red: 0.06,
            green: 0.06,
            blue: 0.10
        )
        static let backgroundTertiary = Color(
            red: 0.08,
            green: 0.08,
            blue: 0.12
        )
        static let backgroundElevated = Color(
            red: 0.10,
            green: 0.10,
            blue: 0.14
        )
        
        // Surface colors
        static let surface = Color(
            red: 0.08,
            green: 0.08,
            blue: 0.12
        )
        static let surfaceElevated = Color(
            red: 0.12,
            green: 0.12,
            blue: 0.16
        )
        static let surfaceGlass = Color.white.opacity(0.04)
        
        // Text hierarchy
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.65)
        static let textTertiary = Color.white.opacity(0.45)
        static let textQuaternary = Color.white.opacity(0.3)
        
        // Legacy aliases for backward compatibility
        static let secondary = textSecondary
        static let secondaryDark = textTertiary
        static let secondaryLight = textSecondary
        
        // Semantic colors - vibrant and modern
        static let success = Color(
            red: 0.20,
            green: 0.92,
            blue: 0.58
        )
        static let successLight = Color(
            red: 0.30,
            green: 1.0,
            blue: 0.68
        )
        static let warning = Color(
            red: 1.0,
            green: 0.75,
            blue: 0.28
        )
        static let warningLight = Color(
            red: 1.0,
            green: 0.85,
            blue: 0.38
        )
        static let error = Color(
            red: 1.0,
            green: 0.35,
            blue: 0.45
        )
        static let errorLight = Color(
            red: 1.0,
            green: 0.45,
            blue: 0.55
        )
        static let info = Color(
            red: 0.40,
            green: 0.70,
            blue: 1.0
        )
        
        // Mode colors - elegant gradients
        static let agentColor = Color(
            red: 0.30,
            green: 0.90,
            blue: 0.60
        )
        static let agentColorLight = Color(
            red: 0.40,
            green: 1.0,
            blue: 0.70
        )
        static let ideColor = Color(
            red: 0.55,
            green: 0.45,
            blue: 0.95
        )
        static let ideColorLight = Color(
            red: 0.65,
            green: 0.55,
            blue: 1.0
        )
        static let mcpColor = Color(
            red: 1.0,
            green: 0.60,
            blue: 0.35
        )
        static let mcpColorLight = Color(
            red: 1.0,
            green: 0.70,
            blue: 0.45
        )
        static let swarmColor = Color(
            red: 0.35,
            green: 0.75,
            blue: 0.95
        )
        static let swarmColorLight = Color(
            red: 0.45,
            green: 0.85,
            blue: 1.0
        )
        static let reviewColor = Color(
            red: 0.25,
            green: 0.82,
            blue: 0.80
        )
        static let reviewColorLight = Color(
            red: 0.40,
            green: 0.92,
            blue: 0.90
        )
        static let planColor = Color(
            red: 0.35,
            green: 0.65,
            blue: 0.95
        )
        static let planColorLight = Color(
            red: 0.45,
            green: 0.75,
            blue: 1.0
        )
        
        // Chat bubbles - glass style
        static let userBubble = Color.white.opacity(0.06)
        static let assistantBubble = Color.white.opacity(0.03)
        
        // Dividers and borders
        static let divider = Color.white.opacity(0.06)
        static let dividerStrong = Color.white.opacity(0.1)
        static let border = Color.white.opacity(0.08)
        static let borderSubtle = Color.white.opacity(0.04)
        
        // Gradients
        static let primaryGradient = LinearGradient(
            colors: [primaryLight, primary, primaryDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let glassGradient = LinearGradient(
            colors: [
                Color.white.opacity(0.08),
                Color.white.opacity(0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let agentGradient = LinearGradient(
            colors: [
                agentColor.opacity(0.25),
                agentColorLight.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let ideGradient = LinearGradient(
            colors: [
                ideColor.opacity(0.25),
                ideColorLight.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let mcpGradient = LinearGradient(
            colors: [
                mcpColor.opacity(0.25),
                mcpColorLight.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let swarmGradient = LinearGradient(
            colors: [
                swarmColor.opacity(0.25),
                swarmColorLight.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let reviewGradient = LinearGradient(
            colors: [
                reviewColor.opacity(0.25),
                reviewColorLight.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let planGradient = LinearGradient(
            colors: [
                planColor.opacity(0.25),
                planColorLight.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Shimmer gradient for loading states
        static let shimmerGradient = LinearGradient(
            colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.08),
                Color.white.opacity(0.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Typography
    struct Typography {
        // Display
        static let display = Font.system(size: 34, weight: .bold, design: .rounded)
        static let displayMedium = Font.system(size: 28, weight: .semibold, design: .rounded)
        
        // Titles
        static let largeTitle = Font.system(size: 24, weight: .bold, design: .rounded)
        static let title = Font.system(size: 20, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 16, weight: .semibold, design: .rounded)
        
        // Body
        static let headline = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 15, weight: .regular, design: .rounded)
        static let bodyMedium = Font.system(size: 15, weight: .medium, design: .rounded)
        static let callout = Font.system(size: 14, weight: .regular, design: .rounded)
        
        // Captions
        static let subheadline = Font.system(size: 13, weight: .regular, design: .rounded)
        static let subheadlineMedium = Font.system(size: 13, weight: .medium, design: .rounded)
        static let footnote = Font.system(size: 12, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 11, weight: .regular, design: .rounded)
        static let captionMedium = Font.system(size: 11, weight: .medium, design: .rounded)
        static let caption2 = Font.system(size: 10, weight: .regular, design: .rounded)
        
        // Monospace for code
        static let code = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let codeSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let codeLarge = Font.system(size: 15, weight: .regular, design: .monospaced)
        
        // Modifiers
        static func medium(_ font: Font) -> Font {
            font.weight(.medium)
        }
        
        static func semibold(_ font: Font) -> Font {
            font.weight(.semibold)
        }
        
        static func bold(_ font: Font) -> Font {
            font.weight(.bold)
        }
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
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let xl: CGFloat = 18
        static let xxl: CGFloat = 22
        static let round: CGFloat = 9999
    }
    
    // MARK: - Blur Radius
    struct Blur {
        static let light: CGFloat = 8
        static let medium: CGFloat = 16
        static let heavy: CGFloat = 24
        static let ultra: CGFloat = 40
    }
    
    // MARK: - Shadows
    struct Shadows {
        static let small = Color.black.opacity(0.15)
        static let medium = Color.black.opacity(0.25)
        static let large = Color.black.opacity(0.35)
        static let glow = Color.white.opacity(0.1)
        
        static func primaryGlow(radius: CGFloat = 20) -> some View {
            Color.clear.shadow(
                color: Colors.primary.opacity(0.3),
                radius: radius,
                x: 0,
                y: 0
            )
        }
        
        static func coloredGlow(_ color: Color, radius: CGFloat = 15) -> some View {
            Color.clear.shadow(
                color: color.opacity(0.25),
                radius: radius,
                x: 0,
                y: 0
            )
        }
    }
}

// MARK: - Liquid Glass View Modifier
struct LiquidGlassModifier: ViewModifier {
    var material: Material = .ultraThin
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.large
    var tint: Color = .clear
    var borderOpacity: CGFloat = 0.08
    
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(0.7)
            }
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tint.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(borderOpacity + 0.05),
                                Color.white.opacity(borderOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func liquidGlass(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = DesignSystem.CornerRadius.large,
        tint: Color = .clear,
        borderOpacity: CGFloat = 0.08
    ) -> some View {
        modifier(LiquidGlassModifier(
            material: material,
            cornerRadius: cornerRadius,
            tint: tint,
            borderOpacity: borderOpacity
        ))
    }
    
    func glassBackground(
        cornerRadius: CGFloat = DesignSystem.CornerRadius.large,
        tint: Color = .clear
    ) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
                .opacity(0.6)
        }
        .background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(DesignSystem.Colors.glassGradient)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    Color.white.opacity(0.1),
                    lineWidth: 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Card View
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.large
    var padding: CGFloat = DesignSystem.Spacing.lg
    var tint: Color = .clear
    
    init(
        cornerRadius: CGFloat = DesignSystem.CornerRadius.large,
        padding: CGFloat = DesignSystem.Spacing.lg,
        tint: Color = .clear,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .liquidGlass(cornerRadius: cornerRadius, tint: tint)
    }
}

// MARK: - Mode Badge - Glass Style
struct ModeBadge: View {
    let mode: CoderMode
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: iconName)
                .font(DesignSystem.Typography.captionMedium)
            Text(mode.rawValue)
                .font(DesignSystem.Typography.captionMedium)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .foregroundColor(foregroundColor)
        .liquidGlass(
            cornerRadius: DesignSystem.CornerRadius.medium,
            tint: modeColor
        )
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
    
    private var foregroundColor: Color {
        modeColor
    }
}

// MARK: - Section Header - Glass Style
struct SectionHeader: View {
    let title: String
    let icon: String?
    
    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.primary)
            }
            Text(title)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(1.2)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.lg)
    }
}

// MARK: - Status Indicator - Glass Style
struct StatusIndicator: View {
    enum Status {
        case online
        case offline
        case loading
        case error
        
        var color: Color {
            switch self {
            case .online: return DesignSystem.Colors.success
            case .offline: return DesignSystem.Colors.textTertiary
            case .loading: return DesignSystem.Colors.warning
            case .error: return DesignSystem.Colors.error
            }
        }
        
        var icon: String {
            switch self {
            case .online: return "checkmark.circle.fill"
            case .offline: return "circle"
            case .loading: return "arrow.triangle.2.circlepath"
            case .error: return "exclamationmark.circle.fill"
            }
        }
    }
    
    let status: Status
    let text: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: status.icon)
                .font(DesignSystem.Typography.caption)
            Text(text)
                .font(DesignSystem.Typography.caption)
        }
        .foregroundStyle(status.color)
    }
}

// MARK: - Button Styles - Glass Style
struct GlassButtonStyle: ButtonStyle {
    var tint: Color = DesignSystem.Colors.primary
    var isDestructive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.subheadlineMedium)
            .foregroundStyle(isDestructive ? DesignSystem.Colors.error : tint)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .liquidGlass(
                cornerRadius: DesignSystem.CornerRadius.medium,
                tint: isDestructive ? DesignSystem.Colors.error : tint
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.subheadlineMedium)
            .foregroundStyle(.white)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(DesignSystem.Colors.primaryGradient)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            }
            .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.subheadlineMedium)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Input Field Style
struct GlassInputStyle: TextFieldStyle {
    var tintColor: Color = DesignSystem.Colors.primary
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DesignSystem.Typography.body)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .padding(DesignSystem.Spacing.md)
            .liquidGlass(
                cornerRadius: DesignSystem.CornerRadius.large,
                tint: tintColor.opacity(0.3)
            )
    }
}

// MARK: - Animations
extension Animation {
    static let smooth = Animation.easeInOut(duration: 0.25)
    static let smoothSlow = Animation.easeInOut(duration: 0.4)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.75)
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let quick = Animation.easeOut(duration: 0.15)
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.8)
}

// MARK: - Hover Effect
struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false
    var scaleAmount: CGFloat = 1.02
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scaleAmount : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverEffect(scale: CGFloat = 1.02) -> some View {
        modifier(HoverEffectModifier(scaleAmount: scale))
    }
}

// MARK: - Toolbar Icon Button Style
/// Stile raffinato per pulsanti icona nella toolbar: sfondo pill su hover, accento primary, animazioni fluide
struct ToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ToolbarIconButtonHoverModifier(isPressed: configuration.isPressed))
    }
}

private struct ToolbarIconButtonHoverModifier: ViewModifier {
    let isPressed: Bool
    @State private var isHovered = false
    
    private var isActive: Bool { isHovered || isPressed }
    
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.medium))
            .foregroundStyle(isActive ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .fill(.ultraThinMaterial)
                        .opacity(0.8)
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                                .stroke(
                                    DesignSystem.Colors.primary.opacity(0.25),
                                    lineWidth: 0.5
                                )
                        }
                        .background {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                                .fill(DesignSystem.Colors.primary.opacity(0.06))
                        }
                }
            }
            .scaleEffect(isPressed ? 0.96 : (isHovered ? 1.04 : 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Glow Effect
struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.4), radius: radius, x: 0, y: 0)
    }
}

extension View {
    func glow(color: Color, radius: CGFloat = 10) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
}

// MARK: - Animated Gradient Background
struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    
    var body: some View {
        LinearGradient(
            colors: [
                DesignSystem.Colors.backgroundDeep,
                DesignSystem.Colors.backgroundPrimary,
                DesignSystem.Colors.backgroundSecondary,
                DesignSystem.Colors.backgroundPrimary
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Floating Orb Background Effect
struct FloatingOrb: View {
    let color: Color
    let size: CGFloat
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 0.3
    
    init(color: Color, size: CGFloat = 200) {
        self.color = color
        self.size = size
    }
    
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.4), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .offset(offset)
            .opacity(opacity)
            .blur(radius: size / 4)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: Double.random(in: 4...8))
                    .repeatForever(autoreverses: true)
                ) {
                    offset = CGSize(
                        width: CGFloat.random(in: -100...100),
                        height: CGFloat.random(in: -100...100)
                    )
                    opacity = Double.random(in: 0.2...0.4)
                }
            }
    }
}

// MARK: - Particle Effect for Loading
struct ParticleView: View {
    let color: Color
    @State private var particles: [Particle] = []
    
    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var opacity: Double
        var scale: CGFloat
    }
    
    init(color: Color = DesignSystem.Colors.primary) {
        self.color = color
    }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let opacity = particle.opacity
                    let scale = particle.scale
                    
                    context.opacity = opacity
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: particle.x - 2,
                            y: particle.y - 2,
                            width: 4 * scale,
                            height: 4 * scale
                        )),
                        with: .color(color)
                    )
                }
            }
        }
        .onAppear {
            for _ in 0..<20 {
                particles.append(Particle(
                    x: CGFloat.random(in: 0...200),
                    y: CGFloat.random(in: 0...200),
                    opacity: Double.random(in: 0.3...0.8),
                    scale: CGFloat.random(in: 0.5...1.5)
                ))
            }
        }
    }
}