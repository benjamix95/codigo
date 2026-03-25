import SwiftUI

enum WindowControlKind: CaseIterable {
    case close
    case minimize
    case zoom

    var symbolName: String {
        switch self {
        case .close: return "xmark"
        case .minimize: return "minus"
        case .zoom: return "plus"
        }
    }

    var helpText: String {
        switch self {
        case .close: return "Close Window"
        case .minimize: return "Minimize Window"
        case .zoom: return "Zoom Window"
        }
    }

    func fillColor(active: Bool) -> Color {
        switch self {
        case .close:
            return Color(red: 1.0, green: 0.37, blue: 0.33).opacity(active ? 1 : 0.6)
        case .minimize:
            return Color(red: 0.98, green: 0.79, blue: 0.26).opacity(active ? 1 : 0.6)
        case .zoom:
            return Color(red: 0.16, green: 0.84, blue: 0.31).opacity(active ? 1 : 0.6)
        }
    }
}
