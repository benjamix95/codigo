import Foundation

enum RuntimeResourceLocator {
    static func appLogoURL() -> URL? {
        Bundle.main.url(forResource: "AppLogo", withExtension: "png")
    }

    static func appIconURL() -> URL? {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "Codigo", withExtension: "icns")
    }

    static func fontsDirectoryURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent("Fonts", isDirectory: true)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return candidate
    }
}
