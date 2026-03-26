import XCTest

#if canImport(CoderIDEMCPServer)
@testable import CoderIDEMCPServer

/// Contract: ogni tool nel catalogo Rust (`tool_names.txt`) deve essere esposto anche da `CoderIDETools` (allowlist Codex).
final class CoderIDErustCatalogContractTests: XCTestCase {
    private static func repoRoot(from file: StaticString) -> URL {
        var url = URL(fileURLWithPath: "\(file)", isDirectory: false).deletingLastPathComponent()
        while url.path != "/" {
            let marker = url.appendingPathComponent("Native/CoderideMCPServerRust/src/tool_names.txt")
            if FileManager.default.fileExists(atPath: marker.path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        XCTFail("Impossibile trovare la root del repo (tool_names.txt).")
        return URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private static func rustToolNames() throws -> Set<String> {
        let root = repoRoot(from: #filePath)
        let url = root
            .appendingPathComponent("Native/CoderideMCPServerRust/src/tool_names.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let names = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(names)
    }

    private static func catalogToolCount() throws -> Int {
        let root = repoRoot(from: #filePath)
        let url = root
            .appendingPathComponent("Native/CoderideMCPServerRust/src/catalog.rs")
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = #/CATALOG_TOOL_COUNT:\s*usize\s*=\s*(\d+)/#
        guard let match = text.firstMatch(of: pattern),
              let n = Int(match.1)
        else {
            throw NSError(
                domain: "CoderIDErustCatalogContractTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "CATALOG_TOOL_COUNT non trovato in catalog.rs"]
            )
        }
        return n
    }

    func testEveryRustCatalogToolIsAdvertisedInCoderIDETools() throws {
        let rust = try Self.rustToolNames()
        let swift = Set(CoderIDETools.all.map(\.name))
        for name in rust.sorted() {
            XCTAssertTrue(
                swift.contains(name),
                "tool_names.txt elenca '\(name)' che non è presente in CoderIDETools (drift Rust→Swift)"
            )
        }
    }

    func testRustCatalogLineCountMatchesDeclaredConstant() throws {
        let rust = try Self.rustToolNames()
        let declared = try Self.catalogToolCount()
        XCTAssertEqual(
            rust.count,
            declared,
            "Righe tool_names.txt (\(rust.count)) ≠ CATALOG_TOOL_COUNT (\(declared))"
        )
    }
}
#endif
