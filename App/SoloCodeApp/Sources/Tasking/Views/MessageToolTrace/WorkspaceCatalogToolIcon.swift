import CoderEngine
import SwiftUI

enum ToolTraceEventWorkspaceCatalog {
    static func isWorkspaceTool(_ event: ToolTraceEvent) -> Bool {
        for key in ["mcp_tool", "mcpTool", "tool", "name"] {
            if let v = event.payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !v.isEmpty,
               WorkspaceToolCatalog.isWorkspaceTool(v) {
                return true
            }
        }
        let normalized = MessageToolTraceToolIdentity.normalizedToolName(for: event)
        if !normalized.isEmpty, WorkspaceToolCatalog.isWorkspaceTool(normalized) {
            return true
        }
        let typeTag = event.type.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceToolCatalog.isWorkspaceTool(typeTag)
    }
}

/// Icona funzionale del tool con un piccolo accento “SoloCode” solo per i tool del catalogo workspace.
struct WorkspaceCatalogToolIcon: View {
    let event: ToolTraceEvent

    private var identity: MessageToolTraceToolIdentity {
        MessageToolTraceToolIdentity.resolve(for: event)
    }

    private var showsWorkspaceBadge: Bool {
        ToolTraceEventWorkspaceCatalog.isWorkspaceTool(event)
    }

    private var badgeSystemName: String {
        if identity.symbolName == "sparkles" {
            return "star.circle.fill"
        }
        return "sparkle"
    }

    private var badgeGradient: LinearGradient {
        LinearGradient(
            colors: [
                DesignSystem.Colors.ideColor,
                DesignSystem.Colors.reviewColor,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: identity.symbolName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(identity.tint)

            if showsWorkspaceBadge {
                Image(systemName: badgeSystemName)
                    .font(.system(size: 5.5, weight: .semibold))
                    .foregroundStyle(badgeGradient)
                    .offset(x: 3.5, y: -2.5)
                    .shadow(color: DesignSystem.Colors.ideColor.opacity(0.45), radius: 1.2, x: 0, y: 0.5)
            }
        }
    }
}
