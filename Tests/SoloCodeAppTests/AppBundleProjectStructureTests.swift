import Foundation
import Testing
@testable import CoderIDE

struct AppBundleProjectStructureTests {
    @Test
    func infoPlistDeclaresSoloCodeBundleMetadata() throws {
        let plistURL = repoRootURL()
            .appendingPathComponent("Config", isDirectory: true)
            .appendingPathComponent("Plists", isDirectory: true)
            .appendingPathComponent("SoloCode-Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        #expect(plist["CFBundleIdentifier"] as? String == "com.solocode.app")
        #expect(plist["CFBundleDisplayName"] as? String == "Solo Code")
        #expect(plist["CFBundleName"] as? String == "Solo Code")
        #expect(plist["CFBundleIconName"] as? String == "AppIcon")
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
    }

    @Test
    func appIconAssetMatchesPrimaryLogoSource() throws {
        let resourcesURL = repoRootURL()
            .appendingPathComponent("App", isDirectory: true)
            .appendingPathComponent("SoloCodeApp", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let logoData = try Data(contentsOf: resourcesURL.appendingPathComponent("AppLogo.png"))
        let iconData = try Data(contentsOf: resourcesURL
            .appendingPathComponent("Assets.xcassets", isDirectory: true)
            .appendingPathComponent("AppIcon.appiconset", isDirectory: true)
            .appendingPathComponent("icon_1024x1024.png"))

        #expect(iconData == logoData)
    }

    @Test
    func generatedProjectArtifactsExist() {
        let root = repoRootURL()
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Solo Code.xcodeproj").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Solo Code.xcworkspace").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Config/TestPlans/Solo Code.xctestplan").path))
    }

    @Test
    func monacoAndFontResourcesUseMainBundleLayout() {
        #expect(MonacoRuntimeAssetResolver.readAccessURL() != nil)
        #expect(RuntimeResourceLocator.fontsDirectoryURL() != nil)
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
