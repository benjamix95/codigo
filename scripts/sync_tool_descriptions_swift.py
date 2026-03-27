#!/usr/bin/env python3
"""Rigenera gli artefatti tool derivati dal registro canonico."""

from __future__ import annotations

import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY_PATH = ROOT / "Config/tooling/canonical_tool_registry.json"
TOOL_NAMES_PATH = ROOT / "Native/CoderideMCPServerRust/src/tool_names.txt"
TOOL_DESCRIPTIONS_PATH = ROOT / "Native/CoderideMCPServerRust/src/tool_descriptions.json"
RUST_SYNCED_SWIFT_PATH = ROOT / "Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+RustSyncedDescriptions.swift"
CANONICAL_SWIFT_PATH = ROOT / "Engine/CoderEngine/Sources/Tools/Catalog/CoderIDECanonicalToolRegistry+Generated.swift"

RUST_SYNCED_SWIFT_HEADER = (
    "import Foundation\n\n"
    "// AUTO-GENERATED — non modificare manualmente. Sorgente: Config/tooling/canonical_tool_registry.json\n"
    "// Rigenerare: python3 scripts/sync_tool_descriptions_swift.py\n"
    "// (anche in build Xcode: fase «Sync tool_descriptions Swift» sul target CoderIDEMCPServer.)\n\n"
    "enum RustSyncedToolDescriptions {\n"
    "    /// `mcpName` coincide con `Tool.name` (es. `coderide_read`).\n"
    "    static func text(mcpName: String, fallback: String) -> String {\n"
    "        parsed[mcpName] ?? fallback\n"
    "    }\n\n"
    "    private static let parsed: [String: String] = {\n"
    "        guard let obj = try? JSONSerialization.jsonObject(with: Data(embedded.utf8)) as? [String: String] else {\n"
    '            assertionFailure("tool_descriptions embedded JSON non valido")\n'
    "            return [:]\n"
    "        }\n"
    "        return obj\n"
    "    }()\n\n"
    '    private static let embedded = """\n'
)
RUST_SYNCED_SWIFT_FOOTER = '\n    """\n}\n'

CANONICAL_SWIFT_HEADER = (
    "import Foundation\n\n"
    "// AUTO-GENERATED — non modificare manualmente. Sorgente: Config/tooling/canonical_tool_registry.json\n"
    "// Rigenerare: python3 scripts/sync_tool_descriptions_swift.py\n\n"
    "enum CoderIDECanonicalToolRegistryGenerated {\n"
    '    static let embedded = """\n'
)
CANONICAL_SWIFT_FOOTER = '\n    """\n}\n'


def indent_json(raw: str, spaces: int = 4) -> str:
    prefix = " " * spaces
    return "\n".join(prefix + line if line else "" for line in raw.splitlines())


def main() -> None:
    manifest = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    tools = manifest.get("tools", [])
    xcode_phase_mode = os.environ.get("SOLOCODE_XCODE_PHASE_SYNC") == "1"

    tool_names = [tool["mcp_name"] for tool in tools]
    descriptions = {
        tool["mcp_name"]: tool["description"]
        for tool in tools
    }

    descriptions_raw = json.dumps(descriptions, indent=2, ensure_ascii=False)
    RUST_SYNCED_SWIFT_PATH.write_text(
        RUST_SYNCED_SWIFT_HEADER
        + indent_json(descriptions_raw)
        + RUST_SYNCED_SWIFT_FOOTER,
        encoding="utf-8"
    )
    print(f"OK: {RUST_SYNCED_SWIFT_PATH.relative_to(ROOT)} ({len(descriptions)} voci)")

    if xcode_phase_mode:
        return

    TOOL_NAMES_PATH.write_text("\n".join(tool_names) + "\n", encoding="utf-8")
    TOOL_DESCRIPTIONS_PATH.write_text(
        json.dumps(descriptions, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8"
    )

    manifest_raw = json.dumps(manifest, indent=2, ensure_ascii=False)
    CANONICAL_SWIFT_PATH.write_text(
        CANONICAL_SWIFT_HEADER
        + indent_json(manifest_raw)
        + CANONICAL_SWIFT_FOOTER,
        encoding="utf-8"
    )

    print(f"OK: {TOOL_NAMES_PATH.relative_to(ROOT)} ({len(tool_names)} tool)")
    print(f"OK: {TOOL_DESCRIPTIONS_PATH.relative_to(ROOT)} ({len(descriptions)} descriptions)")
    print(f"OK: {CANONICAL_SWIFT_PATH.relative_to(ROOT)} ({len(tools)} tool registry records)")


if __name__ == "__main__":
    main()
