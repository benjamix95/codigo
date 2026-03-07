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

    static let defaultSansFamily = "Geist"
    static let defaultCodeFamily = "Geist Mono"
    static let defaultSansSize: Double = 13
    static let defaultCodeSize: Double = 12

    static let sansSizeRange: ClosedRange<CGFloat> = 10...22
    static let codeSizeRange: ClosedRange<CGFloat> = 10...24

    private static let monoFamilyWhitelist = [
        "Geist Mono", "SF Mono", "Menlo", "Monaco", "JetBrains Mono", "Fira Code",
    ]

    private static let fontRegistrationLock = NSLock()
    private static var didRegisterBundledFonts = false
    private static let postScriptMissingSentinel = "__missing__"
    private static let postScriptCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 256
        return cache
    }()

    static func registerBundledFonts() {
        fontRegistrationLock.lock()
        defer { fontRegistrationLock.unlock() }
        guard !didRegisterBundledFonts else { return }
        didRegisterBundledFonts = true
        guard let fontDir = RuntimeResourceLocator.fontsDirectoryURL() else {
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
        if let fallback = firstAvailablePostScript(fromFamilies: ["Geist", "Inter", "Helvetica Neue", "Helvetica", "Arial"]) {
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
        if let fallback = firstAvailablePostScript(fromFamilies: ["Geist Mono", "SF Mono", "Menlo", "Monaco", "JetBrains Mono"]) {
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
        if let fallback = firstAvailablePostScript(fromFamilies: ["Geist Mono", "SF Mono", "Menlo", "Monaco", "JetBrains Mono"]),
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
        let key = family as NSString
        if let cached = postScriptCache.object(forKey: key) {
            let value = cached as String
            return value == postScriptMissingSentinel ? nil : value
        }

        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family) else {
            postScriptCache.setObject(postScriptMissingSentinel as NSString, forKey: key)
            return nil
        }

        for member in members {
            guard let postScript = member.first as? String, !postScript.isEmpty else { continue }
            let lower = postScript.lowercased()
            if lower.contains("regular") || lower.contains("roman") || lower.contains("book") {
                postScriptCache.setObject(postScript as NSString, forKey: key)
                return postScript
            }
        }
        if let fallback = members.first?.first as? String {
            postScriptCache.setObject(fallback as NSString, forKey: key)
            return fallback
        }
        postScriptCache.setObject(postScriptMissingSentinel as NSString, forKey: key)
        return nil
    }
}

extension View {
    func codeFont(size: CGFloat, family: String, weight: Font.Weight = .regular) -> some View {
        font(FontPreferences.resolveCodeFont(size: size, family: family, weight: weight))
    }
}
