import XCTest
@testable import CoderEngine

final class PipelineJobFactoryChatMessageTests: XCTestCase {
    func testFromChatMessageStoresFullPromptInTaskMetadata() {
        let prompt = """
        [DEBUG MODE ACTIVE]
        Preferisci analisi approfondita e poi rispondi al bug dell'utente senza perdere contesto.
        """
        let displayRequest = "Correggi il timer bloccato nella chat"

        let (job, tasks) = PipelineJobFactory.fromChatMessage(
            prompt: prompt,
            displayRequest: displayRequest,
            workspace: "/tmp/workspace",
            providerId: "codex-cli"
        )

        XCTAssertEqual(job.request, displayRequest)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].metadata["pipeline_full_prompt"], prompt)
        XCTAssertEqual(tasks[0].title, displayRequest)
    }
}
