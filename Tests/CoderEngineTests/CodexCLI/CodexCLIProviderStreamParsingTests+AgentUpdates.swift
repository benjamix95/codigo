import Foundation
import XCTest
@testable import CoderEngine

extension CodexCLIProviderStreamParsingTests {
    func testAgentMessageProducesOperationalUpdateBeforeFinalTurnText() {
        var state = CodexCLIProvider.CodexStreamParserState()

        _ = CodexCLIProvider.parseStreamJSONEvent(["type": "turn.started"], state: &state)
        let updateEvents = CodexCLIProvider.parseStreamJSONEvent(
            [
                "type": "item.completed",
                "item": [
                    "id": "message-1",
                    "type": "agent_message",
                    "text": "Sto raccogliendo altri dettagli prima della risposta finale."
                ],
            ],
            state: &state
        )

        let rawTypes = updateEvents.compactMap { event -> String? in
            if case .raw(let type, _) = event { return type }
            return nil
        }
        let visibleText = updateEvents.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }

        XCTAssertTrue(rawTypes.contains("assistant_update"))
        XCTAssertEqual(
            visibleText.joined(),
            "Sto raccogliendo altri dettagli prima della risposta finale."
        )

        let completionEvents = CodexCLIProvider.parseStreamJSONEvent(
            ["type": "turn.completed"],
            state: &state
        )
        let completionText = completionEvents.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }
        XCTAssertTrue(
            completionText.isEmpty,
            "Il completamento non deve duplicare testo gia' reso visibile durante il turno"
        )
    }

    func testAgentMessageFullSnapshotUpdateExtendsVisibleTextImmediately() {
        var state = CodexCLIProvider.CodexStreamParserState()

        _ = CodexCLIProvider.parseStreamJSONEvent(["type": "turn.started"], state: &state)
        let firstEvents = CodexCLIProvider.parseStreamJSONEvent(
            [
                "type": "item.updated",
                "item": [
                    "id": "message-2",
                    "type": "agent_message",
                    "text": "Sto analizzando"
                ],
            ],
            state: &state
        )
        let secondEvents = CodexCLIProvider.parseStreamJSONEvent(
            [
                "type": "item.completed",
                "item": [
                    "id": "message-2",
                    "type": "agent_message",
                    "text": "Sto analizzando il flusso completo"
                ],
            ],
            state: &state
        )

        let firstDeltas = firstEvents.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }
        let secondReplaces = secondEvents.compactMap { event -> String? in
            if case .textReplace(let text) = event { return text }
            return nil
        }

        XCTAssertEqual(firstDeltas, ["Sto analizzando"])
        XCTAssertEqual(secondReplaces, ["Sto analizzando il flusso completo"])
    }
}
