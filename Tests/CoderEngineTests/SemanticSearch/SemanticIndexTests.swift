import Foundation
import XCTest
@testable import CoderEngine

final class SemanticIndexTests: XCTestCase {

    func makeTestIndexedFiles() -> ([IndexedFile], URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-index-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let content1 = """
        import Foundation

        class AuthenticationService {
            func login(username: String, password: String) -> Bool {
                return validateCredentials(username, password)
            }

            func logout() {
                clearSession()
            }

            private func validateCredentials(_ user: String, _ pass: String) -> Bool {
                return true
            }

            private func clearSession() { }
        }
        """

        let content2 = """
        import Foundation

        struct UserProfile {
            let id: String
            let name: String
            let email: String

            func save() {
                Database.shared.persist(self)
            }

            func delete() {
                Database.shared.remove(id)
            }
        }
        """

        let content3 = """
        import XCTest

        final class AuthTests: XCTestCase {
            func testLoginSuccess() {
                let service = AuthenticationService()
                XCTAssertTrue(service.login(username: "admin", password: "pass"))
            }

            func testLogoutClearsSession() {
                let service = AuthenticationService()
                service.logout()
            }
        }
        """

        let file1Path = tmpDir.appendingPathComponent("AuthenticationService.swift")
        let file2Path = tmpDir.appendingPathComponent("UserProfile.swift")
        let file3Path = tmpDir.appendingPathComponent("AuthTests.swift")

        try! content1.write(to: file1Path, atomically: true, encoding: .utf8)
        try! content2.write(to: file2Path, atomically: true, encoding: .utf8)
        try! content3.write(to: file3Path, atomically: true, encoding: .utf8)

        let sym1 = [
            IndexedSymbol(name: "AuthenticationService", kind: .class, filePath: "AuthenticationService.swift", line: 3, endLine: 17, language: .swift),
            IndexedSymbol(name: "login", kind: .method, filePath: "AuthenticationService.swift", line: 4, endLine: 6, containerName: "AuthenticationService", language: .swift),
            IndexedSymbol(name: "logout", kind: .method, filePath: "AuthenticationService.swift", line: 8, endLine: 10, containerName: "AuthenticationService", language: .swift),
        ]

        let sym2 = [
            IndexedSymbol(name: "UserProfile", kind: .struct, filePath: "UserProfile.swift", line: 3, endLine: 15, language: .swift),
            IndexedSymbol(name: "save", kind: .method, filePath: "UserProfile.swift", line: 8, endLine: 10, containerName: "UserProfile", language: .swift),
            IndexedSymbol(name: "delete", kind: .method, filePath: "UserProfile.swift", line: 12, endLine: 14, containerName: "UserProfile", language: .swift),
        ]

        let sym3 = [
            IndexedSymbol(name: "AuthTests", kind: .class, filePath: "AuthTests.swift", line: 3, endLine: 13, language: .swift),
            IndexedSymbol(name: "testLoginSuccess", kind: .test, filePath: "AuthTests.swift", line: 4, endLine: 7, containerName: "AuthTests", language: .swift),
            IndexedSymbol(name: "testLogoutClearsSession", kind: .test, filePath: "AuthTests.swift", line: 9, endLine: 12, containerName: "AuthTests", language: .swift),
        ]

        let files = [
            IndexedFile(relativePath: "AuthenticationService.swift", absolutePath: file1Path.path, language: .swift, symbols: sym1, imports: ["Foundation"], lineCount: 18, size: UInt64(content1.utf8.count)),
            IndexedFile(relativePath: "UserProfile.swift", absolutePath: file2Path.path, language: .swift, symbols: sym2, imports: ["Foundation"], lineCount: 16, size: UInt64(content2.utf8.count)),
            IndexedFile(relativePath: "AuthTests.swift", absolutePath: file3Path.path, language: .swift, symbols: sym3, imports: ["XCTest"], lineCount: 14, size: UInt64(content3.utf8.count)),
        ]

        return (files, tmpDir)
    }
}
