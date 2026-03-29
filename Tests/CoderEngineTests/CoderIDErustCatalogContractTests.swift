import XCTest
@testable import CoderEngine

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

    private static func canonicalRegistryTools() throws -> [[String: Any]] {
        let root = repoRoot(from: #filePath)
        let url = root
            .appendingPathComponent("Config/tooling/canonical_tool_registry.json")
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any],
              let tools = dict["tools"] as? [[String: Any]] else {
            throw NSError(
                domain: "CoderIDErustCatalogContractTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "canonical_tool_registry.json senza array 'tools'"]
            )
        }
        return tools
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

    func testEverySwiftCoderideToolIsPublishedInRustCatalog() throws {
        let rust = try Self.rustToolNames()
        let swift = Set(CoderIDETools.all.map(\.name)).filter { $0.hasPrefix("coderide_") }
        for name in swift.sorted() {
            XCTAssertTrue(
                rust.contains(name),
                "CoderIDETools espone '\(name)' ma il catalogo Rust non lo pubblica in tools/list (drift Swift→Rust)"
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

    func testCanonicalRegistryDrivesRustNamesAndDescriptions() throws {
        let rustNames = try Self.rustToolNames()
        let registryTools = try Self.canonicalRegistryTools()
        let registryNames = Set(
            registryTools.compactMap { $0["mcp_name"] as? String }
        )
        XCTAssertEqual(rustNames, registryNames)

        let root = Self.repoRoot(from: #filePath)
        let url = root.appendingPathComponent("Native/CoderideMCPServerRust/src/tool_descriptions.json")
        let data = try Data(contentsOf: url)
        let desc = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])

        for tool in registryTools {
            let mcpName = try XCTUnwrap(tool["mcp_name"] as? String)
            let description = try XCTUnwrap(tool["description"] as? String)
            XCTAssertEqual(desc[mcpName], description, "\(mcpName): description should be derived from canonical registry")
        }
    }

    /// Anti-drift: ogni tool non-audit nel JSON Rust ha un omologo in `CoderIDETools` e il JSON contiene `Usage:` (fonte MCP `tools/list`).
    /// Per allineare testualmente intro Swift vs JSON si può estendere in seguito (stessa clausola d'uso).
    func testToolDescriptionsJsonKeysAndUsageConvention() throws {
        let root = Self.repoRoot(from: #filePath)
        let url = root.appendingPathComponent("Native/CoderideMCPServerRust/src/tool_descriptions.json")
        let data = try Data(contentsOf: url)
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            XCTFail("tool_descriptions.json deve essere un oggetto { nome: stringa }")
            return
        }
        var byName: [String: String] = [:]
        for tool in CoderIDETools.all {
            if let existing = byName[tool.name], existing != tool.description {
                XCTFail(
                    "CoderIDETools.all ha due Tool con nome '\(tool.name)' ma description diversa (unifica le definizioni)"
                )
                return
            }
            byName[tool.name] = tool.description
        }
        for (name, jsonDesc) in jsonObject.sorted(by: { $0.key < $1.key }) {
            guard let swiftDesc = byName[name] else {
                XCTFail("tool_descriptions.json chiave '\(name)' non trovata in CoderIDETools.all")
                continue
            }
            XCTAssertTrue(jsonDesc.contains("Usage:"), "\(name): manca 'Usage:' in tool_descriptions.json")
            XCTAssertFalse(swiftDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(name): description Swift vuota")
            XCTAssertEqual(
                swiftDesc,
                jsonDesc,
                "\(name): la description in CoderIDETools deve coincidere con tool_descriptions.json (vedi RustSyncedToolDescriptions)"
            )
        }
    }

    func testEveryRustCatalogToolHasSchemaCoverage() throws {
        let rust = try Self.rustToolNames()
        let root = Self.repoRoot(from: #filePath)
        let schemaURL = root.appendingPathComponent("Native/CoderideMCPServerRust/src/tool_schema.rs")
        let workflowURL = root.appendingPathComponent("Native/CoderideMCPServerRust/src/tool_schema_verified_workflows.rs")
        let schemaText = try String(contentsOf: schemaURL, encoding: .utf8)
        let workflowText = try String(contentsOf: workflowURL, encoding: .utf8)

        let prefixCoveredFamilies = [
            "coderide_audit_",
            "coderide_review_",
            "coderide_security_",
            "coderide_bughunter_",
        ]

        for name in rust.sorted() {
            let coveredByPrefix = prefixCoveredFamilies.contains { name.hasPrefix($0) }
                || workflowText.contains(#"if name.starts_with("coderide_review_")"#) && name.hasPrefix("coderide_review_")
                || workflowText.contains(#"if name.starts_with("coderide_security_")"#) && name.hasPrefix("coderide_security_")
                || workflowText.contains(#"if name.starts_with("coderide_bughunter_")"#) && name.hasPrefix("coderide_bughunter_")

            let coveredByExplicitSchema = schemaText.contains("\"\(name)\"")
            XCTAssertTrue(
                coveredByPrefix || coveredByExplicitSchema,
                "\(name): missing schema coverage in Rust tool_schema files"
            )
        }
    }

    func testProviderAvailableCanonicalToolsAreRecognizedAsWorkspaceTools() throws {
        let records = CoderIDECanonicalToolRegistry.shared.allRecords.filter {
            CoderIDECanonicalToolRegistry.shared.isUsable(
                CoderIDECanonicalToolRegistry.shared.availability(for: $0, on: .providers)
            )
        }
        for record in records {
            XCTAssertTrue(
                WorkspaceToolCatalog.isWorkspaceTool(record.mcpName),
                "\(record.mcpName): provider-available MCP tool should be recognized as workspace tool"
            )
            XCTAssertTrue(
                WorkspaceToolCatalog.isWorkspaceTool(record.runtimeName),
                "\(record.runtimeName): provider-available runtime tool should be recognized as workspace tool"
            )
        }
    }

    func testRustClaudeFallbackPromptEnforcesCoderideFirstSearchAndRead() throws {
        let root = Self.repoRoot(from: #filePath)
        let url = root.appendingPathComponent("Native/RustCore/src/main_chat/providers/cli/claude.rs")
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(text.contains("ABSOLUTE TOOL PRECEDENCE"))
        XCTAssertTrue(text.contains("Do NOT use Claude native search/read/edit tools as first choice"))
        XCTAssertTrue(text.contains("Do NOT use shell workspace discovery with `grep`, `rg`, `find`, `fd`, `cat`, `ls`, or `tree`."))
        XCTAssertTrue(text.contains("For natural-language code discovery, use `coderide_semantic_search`."))
        XCTAssertTrue(text.contains("For exact text or regex search, use `coderide_grep`."))
    }
}
#endif
