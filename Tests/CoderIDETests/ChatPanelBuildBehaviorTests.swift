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

    func testNormalizeBuildFinalResponseKeepsOperationalTodoSectionWhenNoPlanEcho() {
        let raw = """
        ## Stato esecuzione
        Aggiornamenti:

        ## Todo
        - [x] Verifica build
        - [x] Esegui test
        """
        let normalized = normalizeBuildFinalResponse(raw)
        XCTAssertEqual(normalized, raw)
    }

    func testPlanBuildDisabledReasonCodes() {
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .analyzing,
                hasBuildChoice: true,
                providerExecutionCapable: true
            ),
            "Analisi codebase in corso: attendi il completamento."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .questioning,
                hasBuildChoice: true,
                providerExecutionCapable: true
            ),
            "Servono chiarimenti: rispondi alle domande prima del build."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .generating,
                hasBuildChoice: true,
                providerExecutionCapable: true
            ),
            "Generazione piano in corso: attendi il completamento."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .proposalReady,
                hasBuildChoice: false,
                providerExecutionCapable: true
            ),
            "Nessuna opzione disponibile da eseguire."
        )
        XCTAssertEqual(
            planBuildDisabledReason(
                phase: .proposalReady,
                hasBuildChoice: true,
                providerExecutionCapable: false
            ),
            "Provider non pronto: seleziona un provider execution-capable autenticato."
        )
        XCTAssertNil(
            planBuildDisabledReason(
                phase: .readyToBuild,
                hasBuildChoice: true,
                providerExecutionCapable: true
            )
        )
    }

    func testBuildPlanClarificationPromptIncludesCustomPrecedenceAndFinalMandatoryNote() {
        let submission = PlanClarificationSubmission(
            answers: [
                PlanClarificationAnswer(
                    questionId: 2,
                    question: "Quale priorità vuoi?",
                    optionId: "I",
                    optionText: "Other...",
                    customResponse: "Priorità: stabilità in produzione"
                ),
                PlanClarificationAnswer(
                    questionId: 1,
                    question: "Qual è l'obiettivo?",
                    optionId: "B",
                    optionText: "Correggere bug",
                    customResponse: nil
                ),
            ],
            finalMandatoryNote: "Non toccare API pubbliche e mantieni retrocompatibilità."
        )

        let prompt = buildPlanClarificationPrompt(submission)
        XCTAssertTrue(prompt.contains("1. Qual è l'obiettivo?"))
        XCTAssertTrue(prompt.contains("Risposta selezionata: B) Correggere bug"))
        XCTAssertTrue(prompt.contains("2. Quale priorità vuoi?"))
        XCTAssertTrue(prompt.contains("Risposta personalizzata (precedenza): Priorità: stabilità in produzione"))
        XCTAssertTrue(prompt.contains("Nota finale obbligatoria utente: Non toccare API pubbliche"))
    }

    func testBuildPlanClarificationPromptOmitsCustomLineWhenAbsent() {
        let submission = PlanClarificationSubmission(
            answers: [
                PlanClarificationAnswer(
                    questionId: 1,
                    question: "Quale area?",
                    optionId: "A",
                    optionText: "UI chat",
                    customResponse: nil
                )
            ],
            finalMandatoryNote: "Testare su macOS."
        )

        let prompt = buildPlanClarificationPrompt(submission)
        XCTAssertFalse(prompt.contains("Risposta personalizzata (precedenza):"))
        XCTAssertTrue(prompt.contains("Nota finale obbligatoria utente: Testare su macOS."))
    }
}
