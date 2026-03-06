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
        XCTAssertTrue(
            visibleText.isEmpty,
            "Gli update intermedi non devono sporcare subito il body assistant"
        )

        let completionEvents = CodexCLIProvider.parseStreamJSONEvent(
            ["type": "turn.completed"],
            state: &state
        )
        let completionText = completionEvents.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }
        XCTAssertEqual(
            completionText.joined(),
            "Sto raccogliendo altri dettagli prima della risposta finale."
        )
    }
}
