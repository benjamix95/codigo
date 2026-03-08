import Foundation
import SwiftUI

enum MarkdownInlineAttributedCache {
    private static let cache: NSCache<NSString, NSAttributedString> = {
        let c = NSCache<NSString, NSAttributedString>()
        c.countLimit = 768
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    static func key(
        text: String,
        contextID: UUID?,
        activeFolderPath: String?,
        fontSize: CGFloat,
        fontWeight: Font.Weight,
        codeFontFamily: String,
        codeFontSize: CGFloat,
        colorSignature: String,
        accentSignature: String,
        inlineCodeBackgroundSignature: String,
        inlineCodeColorSignature: String
    ) -> NSString {
        var hasher = Hasher()
        hasher.combine(text)
        hasher.combine(contextID)
        hasher.combine(activeFolderPath)
        hasher.combine(fontSize)
        hasher.combine(String(describing: fontWeight))
        hasher.combine(codeFontFamily)
        hasher.combine(codeFontSize)
        hasher.combine(colorSignature)
        hasher.combine(accentSignature)
        hasher.combine(inlineCodeBackgroundSignature)
        hasher.combine(inlineCodeColorSignature)
        let digest = hasher.finalize()
        return "\(text.count)|\(digest)" as NSString
    }

    static func get(_ key: NSString) -> AttributedString? {
        guard let cached = cache.object(forKey: key) else { return nil }
        return AttributedString(cached)
    }

    static func set(_ value: AttributedString, for key: NSString) {
        let nsValue = NSAttributedString(value)
        let cost = min(65_536, nsValue.length * 2)
        cache.setObject(nsValue, forKey: key, cost: cost)
    }
}
