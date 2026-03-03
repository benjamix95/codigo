import XCTest
@testable import CoderIDE

extension EventNormalizerLiveStateTests {
        })
    }

    func testDebugInstrumentEmitsTypedPayload() {
        let events = EventNormalizer.normalize(
            type: "debug_instrument",
            payload: [
                "path": "Sources/App.swift",
                "line": "73",
                "type": "timing",
                "expression": "compute()",
                "hypothesis_id": "abc123",
                "label": "hot path",
                "status": "completed"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugInstrument(let payload) = $0 {
                return payload.filePath == "Sources/App.swift"
                    && payload.lineNumber == 73
                    && payload.type == "timing"
                    && payload.label == "hot path"
            }
            return false
        })
    }

    func testFakeMCPLikeEventDoesNotNormalizeAsMCP() {
        let events = EventNormalizer.normalize(
            type: "mcp_tool_call",
            payload: [
                "tool": "check_mcp_status",
                "detail": "Probe local status"
            ]
        )
        guard case .taskActivity(let activity)? = events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "command_execution")
        XCTAssertEqual(activity.title, "command_execution")
    }

    func testApplyPatchEnvelopeKindIsFileUpdate() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "apply_patch",
            payload: ["path": "file.swift", "patch": "diff"]
        )
        XCTAssertEqual(envelope.kind, .fileUpdate)
    }

    func testWriteFileEnvelopeKindIsFileUpdate() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "write_file",
            payload: ["path": "out.txt", "content": "data"]
        )
        XCTAssertEqual(envelope.kind, .fileUpdate)
    }

    func testNotebookEditEnvelopeKindIsFileUpdate() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "notebook_edit",
            payload: ["path": "notebook.ipynb"]
        )
        XCTAssertEqual(envelope.kind, .fileUpdate)
    }

    func testNotebookWriteEnvelopeKindIsFileUpdate() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "notebook_write",
            payload: ["path": "notebook.ipynb"]
        )
        XCTAssertEqual(envelope.kind, .fileUpdate)
    }
}
