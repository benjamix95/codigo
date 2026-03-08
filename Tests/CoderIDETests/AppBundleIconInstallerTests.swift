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

        #expect(plist["CFBundleIconFile"] as? String == AppBundleIconInstaller.iconFilename)
    }

    private func makeSandbox() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let unique = "codigo-app-icon-tests-\(UUID().uuidString)"
        let sandbox = base.appendingPathComponent(unique, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        return sandbox
    }
}
