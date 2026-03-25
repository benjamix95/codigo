import SwiftUI
import AppKit

struct WindowChromeControls: View {
    let showTrafficLights: Bool
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var hoveredControl: WindowControlKind?

    var body: some View {
        HStack(spacing: 8) {
            if showTrafficLights {
                ForEach(WindowControlKind.allCases, id: \.self) { kind in
                    Button {
                        performWindowAction(kind)
                    } label: {
                        Circle()
                            .fill(kind.fillColor(active: controlActiveState != .inactive))
                            .frame(width: 13, height: 13)
                            .overlay {
                                if hoveredControl == kind {
                                    Image(systemName: kind.symbolName)
                                        .font(.system(size: 6.5, weight: .bold))
                                        .foregroundStyle(.black.opacity(0.72))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(kind.helpText)
                    .accessibilityLabel(kind.helpText)
                    .onHover { isHovering in
                        hoveredControl = isHovering ? kind : (hoveredControl == kind ? nil : hoveredControl)
                    }
                }
            }

            Button {
                NotificationCenter.default.post(name: .windowSidebarChromeToggleRequested, object: nil)
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        DesignSystem.Colors.textPrimary.opacity(controlActiveState == .inactive ? 0.6 : 0.96)
                    )
                    .frame(width: 30, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(controlActiveState == .inactive ? 0.05 : 0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.9), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle Sidebar")
            .accessibilityLabel("Toggle Sidebar")
        }
        .frame(height: 24)
    }

    private func performWindowAction(_ kind: WindowControlKind) {
        guard let window = NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first(where: { $0.canBecomeMain }) else { return }

        switch kind {
        case .close:
            window.performClose(nil)
        case .minimize:
            window.miniaturize(nil)
        case .zoom:
            window.performZoom(nil)
        }
    }
}
