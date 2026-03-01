import XCTest
@testable import CoderIDE

final class BreadcrumbComponentTests: XCTestCase {
    func testBreadcrumbWithMatchingRoot() {
        let path = "/Users/dev/project/src/main.swift"
        let roots = ["/Users/dev/project"]
        let components = breadcrumbComponents(path: path, rootPaths: roots)
        XCTAssertEqual(components, ["project", "src", "main.swift"])
    }

    func testBreadcrumbWithNoMatchingRoot() {
        let path = "/opt/lib/utils/helper.py"
        let roots = ["/Users/dev/project"]
        let components = breadcrumbComponents(path: path, rootPaths: roots)
        XCTAssertEqual(components, ["lib", "utils", "helper.py"])
    }

    func testBreadcrumbWithMultipleRoots() {
        let path = "/workspace/frontend/src/App.tsx"
        let roots = ["/workspace/backend", "/workspace/frontend"]
        let components = breadcrumbComponents(path: path, rootPaths: roots)
        XCTAssertEqual(components, ["frontend", "src", "App.tsx"])
    }

    func testBreadcrumbWithShortPath() {
        let path = "/file.txt"
        let roots: [String] = []
        let components = breadcrumbComponents(path: path, rootPaths: roots)
        XCTAssertEqual(components, ["", "file.txt"])
    }

    func testBreadcrumbWithDeeplyNestedPath() {
        let path = "/a/b/c/d/e/f.swift"
        let roots: [String] = []
        let components = breadcrumbComponents(path: path, rootPaths: roots)
        XCTAssertEqual(components, ["d", "e", "f.swift"])
    }

    private func breadcrumbComponents(path: String, rootPaths: [String]) -> [String] {
        for root in rootPaths {
            if path.hasPrefix(root + "/") {
                let relative = String(path.dropFirst(root.count + 1))
                let rootName = (root as NSString).lastPathComponent
                return [rootName] + relative.components(separatedBy: "/")
            }
        }
        return path.components(separatedBy: "/").suffix(3).map { String($0) }
    }
}
