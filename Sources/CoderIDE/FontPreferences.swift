import AppKit
import CoreText
import SwiftUI

enum FontKind {
    case sans
    case code
}

struct FontPreferences {
    static let systemSansToken = "__system_sans__"
    static let systemMonoToken = "__system_mono__"

    static let defaultSansFamily = systemSansToken
    static let defaultCodeFamily = systemMonoToken
    static let defaultSansSize: Double = 13
    static let defaultCodeSize: Double = 12

    static let sansSizeRange: ClosedRange<CGFloat> = 10...22
    static let codeSizeRange: ClosedRange<CGFloat> = 10...24

    private static let monoFamilyWhitelist = [
        "SF Mono", "Menlo", "Monaco", "JetBrains Mono", "Fira Code",
    ]

    private static var didRegisterBundledFonts = false

    static func registerBundledFonts() {
        guard !didRegisterBundledFonts else { return }
        didRegisterBundledFonts = true
        guard let fontDir = Bundle.module.resourceURL?.appendingPathComponent("Fonts", isDirectory: true) else {
            return
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: fontDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in urls where ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func sanitizeSize(_ rawValue: Double, kind: FontKind) -> CGFloat {
        let value = CGFloat(rawValue.isFinite ? rawValue : (kind == .sans ? defaultSansSize : defaultCodeSize))
        switch kind {
        case .sans: return min(max(value, sansSizeRange.lowerBound), sansSizeRange.upperBound)
        case .code: return min(max(value, codeSizeRange.lowerBound), codeSizeRange.upperBound)
        }
    }

    static func availableSansFamilies() -> [String] {
        let families = NSFontManager.shared.availableFontFamilies
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !isLikelyMonospaceFamily($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return families
    }

    static func availableMonoFamilies() -> [String] {
        let families = NSFontManager.shared.availableFontFamilies
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { isLikelyMonospaceFamily($0) || monoFamilyWhitelist.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return families
    }

    static func resolveSansFont(
        size: CGFloat,
        family: String,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        if family == systemSansToken {
            return .system(size: size, weight: weight, design: design)
        }
        if let postScript = postScriptName(forFamily: family) {
            return .custom(postScript, size: size).weight(weight)
        }
        if let fallback = firstAvailablePostScript(fromFamilies: ["Inter", "Helvetica Neue", "Helvetica", "Arial"]) {
            return .custom(fallback, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: design)
    }

    static func resolveCodeFont(size: CGFloat, family: String, weight: Font.Weight = .regular) -> Font {
        if family == systemMonoToken {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        if let postScript = postScriptName(forFamily: family) {
            return .custom(postScript, size: size).weight(weight)
        }
        if let fallback = firstAvailablePostScript(fromFamilies: ["SF Mono", "Menlo", "Monaco", "JetBrains Mono"]) {
            return .custom(fallback, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    static func resolveNSMonoFont(size: CGFloat, family: String) -> NSFont {
        if family == systemMonoToken {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        if let postScript = postScriptName(forFamily: family),
           let resolved = NSFont(name: postScript, size: size) {
            return resolved
        }
        if let fallback = firstAvailablePostScript(fromFamilies: ["SF Mono", "Menlo", "Monaco", "JetBrains Mono"]),
           let resolved = NSFont(name: fallback, size: size) {
            return resolved
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func isLikelyMonospaceFamily(_ family: String) -> Bool {
        if monoFamilyWhitelist.contains(family) { return true }
        guard let postScript = postScriptName(forFamily: family),
              let font = NSFont(name: postScript, size: 12) else {
            return false
        }
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.monoSpace) { return true }
        let lowered = family.lowercased()
        return lowered.contains("mono") || lowered.contains("code")
    }

    private static func firstAvailablePostScript(fromFamilies families: [String]) -> String? {
        for family in families {
            if let postScript = postScriptName(forFamily: family) {
                return postScript
            }
        }
        return nil
    }

    private static func postScriptName(forFamily family: String) -> String? {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family) else { return nil }
        for member in members {
            guard let postScript = member.first as? String, !postScript.isEmpty else { continue }
            let lower = postScript.lowercased()
            if lower.contains("regular") || lower.contains("roman") || lower.contains("book") {
                return postScript
            }
        }
        return members.first?.first as? String
    }
}

extension View {
    func codeFont(size: CGFloat, family: String, weight: Font.Weight = .regular) -> some View {
        font(FontPreferences.resolveCodeFont(size: size, family: family, weight: weight))
    }
}
