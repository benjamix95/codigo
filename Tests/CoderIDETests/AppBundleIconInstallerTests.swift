import Foundation
import Testing
@testable import CoderIDE

struct AppBundleIconInstallerTests {
    @Test
    func iconSourceURLPrefersRepositoryResource() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let iconURL = sandbox
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CoderIDE", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(AppBundleIconInstaller.iconFilename)
        try FileManager.default.createDirectory(
            at: iconURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("icon".utf8).write(to: iconURL)

        #expect(
            AppBundleIconInstaller.iconSourceURL(workingDirectoryURL: sandbox) == iconURL
        )
    }

    @Test
    func installIfAvailableCopiesBundleIconIntoResources() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let iconURL = sandbox
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CoderIDE", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(AppBundleIconInstaller.iconFilename)
        let resourcesURL = sandbox
            .appendingPathComponent("Codigo.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let expectedData = Data("bundle-icon".utf8)

        try FileManager.default.createDirectory(
            at: iconURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try expectedData.write(to: iconURL)

        let installed = try AppBundleIconInstaller.installIfAvailable(
            into: resourcesURL,
            workingDirectoryURL: sandbox
        )

        #expect(installed)
        let copiedURL = resourcesURL.appendingPathComponent(AppBundleIconInstaller.iconFilename)
        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
        #expect(try Data(contentsOf: copiedURL) == expectedData)
    }

    @Test
    func infoPlistDeclaresBundleIconFile() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CoderIDE", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )

        #expect(plist["CFBundleIconName"] as? String == "AppIcon")
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
        #expect(plist["CFBundleExecutable"] as? String == "Codigo")
    }

    @Test
    func appIconAssetMatchesPrimaryLogoSource() throws {
        let resourcesURL = try resourcesRootURL()
        let logoData = try Data(contentsOf: resourcesURL.appendingPathComponent("AppLogo.png"))
        let iconData = try Data(contentsOf: resourcesURL
            .appendingPathComponent("Assets.xcassets", isDirectory: true)
            .appendingPathComponent("AppIcon.appiconset", isDirectory: true)
            .appendingPathComponent("icon_1024x1024.png"))

        #expect(iconData == logoData)
    }

    @Test
    func bundleIconContainsStandardMacOSRepresentations() throws {
        let resourcesURL = try resourcesRootURL()
        let icnsURL = resourcesURL.appendingPathComponent(AppBundleIconInstaller.iconFilename)
        let tempRoot = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let iconsetURL = tempRoot.appendingPathComponent("Codigo.iconset", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "iconset", icnsURL.path, "-o", iconsetURL.path]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)

        let filenames = try Set(FileManager.default.contentsOfDirectory(atPath: iconsetURL.path))
        let expected: Set<String> = [
            "icon_16x16.png",
            "icon_16x16@2x.png",
            "icon_32x32.png",
            "icon_32x32@2x.png",
            "icon_128x128.png",
            "icon_128x128@2x.png",
            "icon_256x256.png",
            "icon_256x256@2x.png",
            "icon_512x512.png",
            "icon_512x512@2x.png",
        ]

        #expect(filenames == expected)
    }

    @Test
    func appBundleSignerUsesAdHocDeepCodesign() {
        #expect(
            AppBundleSigner.codesignArguments(appPath: "/tmp/Codigo.app")
                == ["--force", "--deep", "-s", "-", "/tmp/Codigo.app"]
        )
    }

    @Test
    func assetCatalogInstallerUsesMacOSAppIconArguments() {
        #expect(
            AppAssetCatalogInstaller.actoolArguments(
                sourcePath: "/tmp/Assets.xcassets",
                outputPath: "/tmp/out",
                partialPlistPath: "/tmp/partial.plist"
            ) == [
                "actool",
                "/tmp/Assets.xcassets",
                "--compile", "/tmp/out",
                "--platform", "macosx",
                "--minimum-deployment-target", "14.0",
                "--app-icon", "AppIcon",
                "--output-partial-info-plist", "/tmp/partial.plist",
            ]
        )
    }

    private func makeSandbox() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let unique = "codigo-app-icon-tests-\(UUID().uuidString)"
        let sandbox = base.appendingPathComponent(unique, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        return sandbox
    }

    private func resourcesRootURL() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("CoderIDE", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
    }
}
