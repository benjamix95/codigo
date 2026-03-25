import SwiftUI
import AppKit

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

    @ViewBuilder
    func chatPanelContainer(style: ChatBackgroundStyle, cornerRadius: CGFloat = 10) -> some View {
        switch style {
        case .solidNeutral:
            self
                .background(DesignSystem.Colors.chatPanelSolidBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                )
        case .transparentLegacy:
            self.sidebarPanel(cornerRadius: cornerRadius)
        }
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

// MARK: - Panel Resize Handle
/// A draggable divider that allows users to resize adjacent panels.
struct PanelResizeHandle: View {
    /// The current width of the panel being resized.
    @Binding var panelWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// Set to true when the handle is on the leading edge of the panel (drag right = wider).
    var leadingEdge: Bool = true

    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragStartWidth: CGFloat = 0

    @State private var cursorPushed = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill((isDragging || isHovering) ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.3))
                    .frame(width: isDragging || isHovering ? 3 : 1)
                    .animation(.easeOut(duration: 0.15), value: isDragging)
                    .animation(.easeOut(duration: 0.15), value: isHovering)
            )
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    if !cursorPushed {
                        NSCursor.resizeLeftRight.push()
                        cursorPushed = true
                    }
                } else {
                    if cursorPushed {
                        NSCursor.pop()
                        cursorPushed = false
                    }
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = panelWidth
                        }
                        let delta = leadingEdge ? -value.translation.width : value.translation.width
                        let newWidth = min(max(dragStartWidth + delta, minWidth), maxWidth)
                        // Only update binding when width changes by at least 2pt.
                        // During drag, onChanged fires at 60+ FPS. Each setter
                        // call writes to @AppStorage (UserDefaults) and triggers
                        // view invalidation. A 2pt threshold reduces updates
                        // to ~30 per second which is visually indistinguishable.
                        guard abs(newWidth - panelWidth) >= 2 else { return }
                        panelWidth = newWidth
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}

// MARK: - Window Auto-Resize Helper

enum WindowResizeHelper {
    /// Expands or shrinks the window width by `delta` points, keeping the left edge fixed.
    /// Positive delta = wider, negative = narrower. Respects screen bounds.
    @MainActor static func adjustWidth(by delta: CGFloat, animate: Bool? = nil) {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first(where: { $0.canBecomeMain }) else { return }
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        var frame = window.frame
        let newWidth = max(frame.width + delta, window.minSize.width)
        let maxRight = screen.visibleFrame.maxX
        let clampedWidth = min(newWidth, maxRight - frame.minX)
        frame.size.width = clampedWidth
        // Large jumps are typically panel open/close; disable animation to avoid visible jank.
        let shouldAnimate = animate ?? (abs(delta) < 220)
        window.setFrame(frame, display: true, animate: shouldAnimate)
    }
}
