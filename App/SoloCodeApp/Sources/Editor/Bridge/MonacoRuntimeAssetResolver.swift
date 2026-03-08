import Foundation

enum MonacoRuntimeAssetResolver {
    static func editorHTMLURL() -> URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "monaco")
    }

    static func readAccessURL() -> URL? {
        Bundle.main.resourceURL
    }
}
