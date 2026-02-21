import XCTest
@testable import CoderIDE

final class ChatPanelBuildBehaviorTests: XCTestCase {
    func testBuildPromptContainsNoEchoInstruction() {
        let instructions = """
        6. Non ripetere integralmente il piano in chat: esegui, aggiorna TODO/step, e fornisci feedback operativo.
        """
        XCTAssertTrue(instructions.localizedCaseInsensitiveContains("Non ripetere integralmente il piano in chat"))
    }

    func testBuildDoesNotAppendPlanTextToUserMessage() {
        let kickoff = "Build piano avviata: esegui il piano selezionato."
        XCTAssertFalse(kickoff.localizedCaseInsensitiveContains("## Opzione"))
        XCTAssertFalse(kickoff.localizedCaseInsensitiveContains("## Todo"))
    }

    func testNormalizeBuildFinalResponseRemovesPlanEchoBlocks() {
        let raw = """
        ## Opzione 1: Refactor
        Dettagli...
        ## Todo
        - [ ] A
        - [ ] B

        ## Stato esecuzione
        Completato con successo.
        """
        let normalized = normalizeBuildFinalResponse(raw)
        XCTAssertFalse(normalized.localizedCaseInsensitiveContains("## Opzione"))
        XCTAssertFalse(normalized.localizedCaseInsensitiveContains("## Todo"))
        XCTAssertTrue(normalized.localizedCaseInsensitiveContains("Stato esecuzione"))
    }
}

