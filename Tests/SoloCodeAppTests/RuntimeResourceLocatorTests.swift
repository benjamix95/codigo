import Foundation
import Testing
@testable import CoderIDE

struct RuntimeResourceLocatorTests {
    @Test
    func appLogoLookupReturnsExistingFileWhenFound() {
        let logoURL = RuntimeResourceLocator.appLogoURL()
        guard let logoURL else { return }

        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: logoURL.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(!isDirectory.boolValue)
    }

    @Test
    func fontsDirectoryLookupReturnsDirectoryWhenFound() {
        let fontsURL = RuntimeResourceLocator.fontsDirectoryURL()
        guard let fontsURL else { return }

        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: fontsURL.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(isDirectory.boolValue)
    }
}
