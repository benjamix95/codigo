import SwiftUI
import AppKit

extension SoloCodeApp {
    var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var resolvedSansFont: Font {
        FontPreferences.resolveSansFont(
            size: FontPreferences.sanitizeSize(uiSansFontSize, kind: .sans),
            family: uiSansFontFamily
        )
    }

    /// Menu bar image loaded and resized once, reused on every render.
    static let cachedMenuBarImage: NSImage? = {
        guard let url = RuntimeResourceLocator.appLogoURL(),
              let img = NSImage(contentsOf: url) else { return nil }
        let resized = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            img.draw(in: rect)
            return true
        }
        return resized
    }()
}
