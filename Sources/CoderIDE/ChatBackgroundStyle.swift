import Foundation

enum ChatBackgroundStyle: String, CaseIterable, Identifiable {
    case solidNeutral = "solid_neutral"
    case transparentLegacy = "transparent_legacy"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solidNeutral: return "Solido neutro"
        case .transparentLegacy: return "Trasparente"
        }
    }

    static var defaultRawValue: String { ChatBackgroundStyle.solidNeutral.rawValue }

    static func normalizedRawValue(_ raw: String) -> String {
        ChatBackgroundStyle(rawValue: raw)?.rawValue ?? defaultRawValue
    }

    static func from(raw: String) -> ChatBackgroundStyle {
        ChatBackgroundStyle(rawValue: raw) ?? .solidNeutral
    }
}
