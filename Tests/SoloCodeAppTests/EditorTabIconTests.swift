import XCTest
@testable import CoderIDE
import SwiftUI

final class EditorTabIconTests: XCTestCase {
    private let view = EditorPlaceholderView(folderPaths: ["/tmp"])

    func testSwiftFileExtensionMapsToSwiftIcon() {
        let icon = tabFileIcon("MyFile.swift")
        XCTAssertEqual(icon, "swift")
    }

    func testJavaScriptFileExtensionMapsToCurlybraces() {
        XCTAssertEqual(tabFileIcon("app.js"), "curlybraces")
        XCTAssertEqual(tabFileIcon("component.jsx"), "curlybraces")
    }

    func testTypeScriptFileExtensionMapsToCurlybraces() {
        XCTAssertEqual(tabFileIcon("service.ts"), "curlybraces")
        XCTAssertEqual(tabFileIcon("hook.tsx"), "curlybraces")
    }

    func testPythonFileExtension() {
        XCTAssertEqual(tabFileIcon("script.py"), "chevron.left.forwardslash.chevron.right")
    }

    func testJsonFileExtension() {
        XCTAssertEqual(tabFileIcon("package.json"), "curlybraces.square")
    }

    func testMarkdownFileExtension() {
        XCTAssertEqual(tabFileIcon("README.md"), "doc.text")
    }

    func testHtmlFileExtension() {
        XCTAssertEqual(tabFileIcon("index.html"), "globe")
        XCTAssertEqual(tabFileIcon("page.htm"), "globe")
    }

    func testCssFileExtension() {
        XCTAssertEqual(tabFileIcon("style.css"), "paintbrush")
        XCTAssertEqual(tabFileIcon("theme.scss"), "paintbrush")
    }

    func testShellFileExtension() {
        XCTAssertEqual(tabFileIcon("deploy.sh"), "terminal")
        XCTAssertEqual(tabFileIcon("init.zsh"), "terminal")
        XCTAssertEqual(tabFileIcon("setup.bash"), "terminal")
    }

    func testYamlFileExtension() {
        XCTAssertEqual(tabFileIcon("config.yml"), "list.bullet.indent")
        XCTAssertEqual(tabFileIcon("docker.yaml"), "list.bullet.indent")
    }

    func testImageFileExtension() {
        XCTAssertEqual(tabFileIcon("photo.png"), "photo")
        XCTAssertEqual(tabFileIcon("logo.svg"), "photo")
    }

    func testUnknownFileExtensionFallsBackToDoc() {
        XCTAssertEqual(tabFileIcon("data.xyz"), "doc")
        XCTAssertEqual(tabFileIcon("noext"), "doc")
    }

    private func tabFileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "curlybraces"
        case "ts", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces.square"
        case "md", "markdown": return "doc.text"
        case "html", "htm": return "globe"
        case "css", "scss": return "paintbrush"
        case "rs": return "gearshape.2"
        case "go": return "arrow.right.arrow.left"
        case "sh", "zsh", "bash": return "terminal"
        case "yml", "yaml": return "list.bullet.indent"
        case "png", "jpg", "jpeg", "svg", "gif": return "photo"
        default: return "doc"
        }
    }
}
