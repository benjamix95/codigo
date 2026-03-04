import AppKit
import Testing
@testable import CoderIDE

struct FontPreferencesTests {
    @Test
    func sanitizeSizeClampsRanges() {
        #expect(FontPreferences.sanitizeSize(2, kind: .sans) == FontPreferences.sansSizeRange.lowerBound)
        #expect(FontPreferences.sanitizeSize(99, kind: .sans) == FontPreferences.sansSizeRange.upperBound)
        #expect(FontPreferences.sanitizeSize(2, kind: .code) == FontPreferences.codeSizeRange.lowerBound)
        #expect(FontPreferences.sanitizeSize(99, kind: .code) == FontPreferences.codeSizeRange.upperBound)
    }

    @Test
    func resolveNSMonoFontAlwaysReturnsAFont() {
        let system = FontPreferences.resolveNSMonoFont(size: 12, family: FontPreferences.systemMonoToken)
        #expect(system.pointSize == 12)

        let fallback = FontPreferences.resolveNSMonoFont(size: 13, family: "Missing Font Family XYZ")
        #expect(fallback.pointSize == 13)
    }

    @Test
    func fontListsAreNotEmpty() {
        #expect(!FontPreferences.availableSansFamilies().isEmpty)
        #expect(!FontPreferences.availableMonoFamilies().isEmpty)
    }

    @Test
    func registerBundledFontsIsIdempotent() {
        let completedWithoutCrash = {
            FontPreferences.registerBundledFonts()
            FontPreferences.registerBundledFonts()
            return true
        }()
        #expect(completedWithoutCrash)
    }
}
