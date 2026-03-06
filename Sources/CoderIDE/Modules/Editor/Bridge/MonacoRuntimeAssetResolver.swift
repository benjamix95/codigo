import Foundation

enum MonacoRuntimeAssetResolver {
    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    static func editorHTMLURL() -> URL? {
        resourceBundle.url(forResource: "index", withExtension: "html", subdirectory: "monaco")
            ?? Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "monaco")
    }

    static func readAccessURL() -> URL? {
        resourceBundle.resourceURL ?? Bundle.main.resourceURL
    }
}
