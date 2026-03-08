import SwiftUI

extension MarkdownContentView {
    // MARK: - Premium Design Tokens

    var bodyFont: CGFloat { FontPreferences.sanitizeSize(uiSansFontSize + 0.5, kind: .sans) }
    var codeFontSize: CGFloat { FontPreferences.sanitizeSize(uiCodeFontSize, kind: .code) }
    var bodyLineSpacing: CGFloat { 7 }

    // Text
    var textPrimary: Color { .primary.opacity(0.93) }
    var textSecondary: Color { .primary.opacity(0.55) }

    // Accent — muted periwinkle/indigo for headings & bullets
    var accentColor: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.63, blue: 0.95)
            : Color(red: 0.30, green: 0.38, blue: 0.75)
    }

    // Code
    var codeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.082, blue: 0.110)
            : Color(red: 0.95, green: 0.955, blue: 0.97)
    }
    var codeBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }
    var inlineCodeColor: Color {
        colorScheme == .dark
            ? Color(red: 0.90, green: 0.64, blue: 0.44)
            : Color(red: 0.70, green: 0.33, blue: 0.12)
    }
    var inlineCodeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.90, green: 0.64, blue: 0.44).opacity(0.10)
            : Color(red: 0.70, green: 0.33, blue: 0.12).opacity(0.07)
    }

    // Headings
    var h1Color: Color {
        colorScheme == .dark
            ? Color(red: 0.94, green: 0.95, blue: 1.0)
            : Color(red: 0.08, green: 0.10, blue: 0.16)
    }
    var h2Color: Color {
        colorScheme == .dark
            ? Color(red: 0.88, green: 0.90, blue: 0.98)
            : Color(red: 0.12, green: 0.14, blue: 0.22)
    }
    var h3Color: Color {
        colorScheme == .dark
            ? Color(red: 0.82, green: 0.85, blue: 0.95)
            : Color(red: 0.15, green: 0.18, blue: 0.28)
    }

    // Dividers
    var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    // Blockquote
    var quoteBarColor: Color { accentColor.opacity(0.45) }
    var quoteBg: Color {
        colorScheme == .dark
            ? accentColor.opacity(0.04)
            : accentColor.opacity(0.03)
    }
}
