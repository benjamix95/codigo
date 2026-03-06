import XCTest
@testable import CoderEngine

final class PipelineJobFactoryChatMessageTests: XCTestCase {
    func testFromChatMessageStoresFullPromptInTaskMetadata() {
        let prompt = """
        [DEBUG MODE ACTIVE]
        Preferisci analisi approfondita e poi rispondi al bug dell'utente senza perdere contesto.
        """

        let (job, tasks) = PipelineJobFactory.fromChatMessage(
            prompt: prompt,
            workspace: "/tmp/workspace",
            providerId: "codex-cli"
        )

        XCTAssertEqual(job.request, String(prompt.prefix(200)))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].metadata["pipeline_full_prompt"], prompt)
        XCTAssertEqual(tasks[0].title, String(prompt.prefix(80)))
    }
}
