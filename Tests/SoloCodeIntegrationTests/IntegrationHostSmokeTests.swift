import Foundation
import Testing
@testable import CoderIDE

struct IntegrationHostSmokeTests {
    @Test
    func hostApplicationBundleIsAvailable() {
        #expect(Bundle.main.bundleIdentifier == "com.solocode.app")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == "Solo Code")
        #expect(Bundle.main.bundleURL.pathExtension == "app")
        #expect(Bundle.main.executableURL != nil)
    }

    @Test
    func hostApplicationResolvesRuntimeResources() {
        #expect(RuntimeResourceLocator.appLogoURL() != nil)
        #expect(MonacoRuntimeAssetResolver.readAccessURL() != nil)
    }
}
