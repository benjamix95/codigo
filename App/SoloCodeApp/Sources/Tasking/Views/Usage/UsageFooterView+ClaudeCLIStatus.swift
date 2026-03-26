import CoderEngine
import SwiftUI

extension ClaudeStatus {
    /// Badge compatto per il footer (installazione + `claude auth status` / env API key).
    var usageFooterAuthBadge: (symbol: String, tint: Color, label: String) {
        if !isInstalled {
            return ("xmark.octagon.fill", DesignSystem.Colors.error, "CLI")
        }
        if isLoggedIn {
            let label: String
            switch authMethod {
            case "env": label = "API"
            case "oauth": label = "OAuth"
            case "file": label = "Saved"
            default: label = "OK"
            }
            return ("checkmark.circle.fill", .green, label)
        }
        return ("person.crop.circle.badge.xmark", .orange, "Auth")
    }
}
