#!/usr/bin/env python3
"""Rigenera CoderIDETools+RustSyncedDescriptions.swift da tool_descriptions.json (fonte unica)."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JSON_PATH = ROOT / "Native/CoderideMCPServerRust/src/tool_descriptions.json"
OUT_PATH = ROOT / "Tools/CoderIDEMCPServer/Sources/Tools/Catalog/CoderIDETools+RustSyncedDescriptions.swift"

SWIFT_HEADER = (
    "import Foundation\n\n"
    "// AUTO-GENERATED — non modificare manualmente. Sorgente: Native/CoderideMCPServerRust/src/tool_descriptions.json\n"
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

SWIFT_FOOTER = '\n    """\n}\n'


def main() -> None:
    data = json.loads(json.dumps(json.loads(JSON_PATH.read_text(encoding="utf-8")), sort_keys=True))
    raw = json.dumps(data, indent=2, ensure_ascii=False)
    embedded_body = "\n".join("    " + line if line else "" for line in raw.splitlines())
    OUT_PATH.write_text(SWIFT_HEADER + embedded_body + SWIFT_FOOTER, encoding="utf-8")
    print(f"OK: {OUT_PATH.relative_to(ROOT)} ({len(data)} voci)")


if __name__ == "__main__":
    main()
