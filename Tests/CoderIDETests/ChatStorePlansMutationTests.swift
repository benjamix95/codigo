import Foundation
import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ChatStorePlansMutationTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String = ""
    private var backupPlanStateData: Data?
    private var planStateURL: URL {
        MCPSharedState.planStateFilePath
    }

    override func setUpWithError() throws {
        suiteName = "ChatStorePlansMutationTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)

        backupPlanStateData = try? Data(contentsOf: planStateURL)
        try? FileManager.default.removeItem(at: planStateURL)
    }

    override func tearDownWithError() throws {
        userDefaults?.removePersistentDomain(forName: suiteName)
        if let backupPlanStateData {
            try? backupPlanStateData.write(to: planStateURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: planStateURL)
        }
        userDefaults = nil
        suiteName = ""
    }

    func testPlanCreateAndUpsertMutationsUpdateBoardMetadata() throws {
        let store = ChatStore(userDefaults: userDefaults)
        let conversationId = store.createConversation(contextId: nil, contextFolderPath: nil, mode: .agent)

        store.applyPlanCreate(
            goal: "Goal v2",
            chosenPath: "Option A",
            steps: [
                PlanStepUpsertPayload(
                    stepId: "1",
                    status: .pending,
                    title: "Analisi",
                    description: "Studiare mapper",
                    targetFile: "Sources/A.swift",
                    linkedFiles: ["Sources/A.swift"],
                    dependsOn: [],
                    notes: "note",
                    conversationId: nil
                )
            ],
            conversationId: conversationId.uuidString.lowercased()
        )

        store.applyPlanStepUpsert(
            PlanStepUpsertPayload(
                stepId: "1",
                status: .running,
                title: "Analisi estesa",
                description: "Aggiornare parser",
                targetFile: "Sources/B.swift",
                linkedFiles: ["Sources/B.swift", "Sources/C.swift"],
                dependsOn: ["0"],
                notes: "in corso",
                conversationId: conversationId.uuidString.lowercased()
            ),
            fallbackConversationId: conversationId
        )

        let board = try XCTUnwrap(store.planBoard(for: conversationId))
        XCTAssertEqual(board.goal, "Goal v2")
        XCTAssertEqual(board.chosenPath, "Option A")
        XCTAssertEqual(board.steps.count, 1)
        XCTAssertEqual(board.steps[0].status, .running)
        XCTAssertEqual(board.steps[0].title, "Analisi estesa")
        XCTAssertEqual(board.steps[0].targetFile, "Sources/B.swift")
        XCTAssertEqual(board.steps[0].linkedFiles.sorted(), ["Sources/B.swift", "Sources/C.swift"])
        XCTAssertEqual(board.steps[0].dependsOn, ["0"])
        XCTAssertEqual(board.steps[0].notes, "in corso")
    }

    func testBatchReorderDependencyAndWalkthroughMutations() throws {
        let store = ChatStore(userDefaults: userDefaults)
        let conversationId = store.createConversation(contextId: nil, contextFolderPath: nil, mode: .agent)

        store.applyPlanCreate(
            goal: "Goal",
            chosenPath: nil,
            steps: [
                PlanStepUpsertPayload(stepId: "1", status: .pending, title: "Uno", description: nil, targetFile: nil, linkedFiles: [], dependsOn: [], notes: nil, conversationId: nil),
                PlanStepUpsertPayload(stepId: "2", status: .pending, title: "Due", description: nil, targetFile: nil, linkedFiles: [], dependsOn: [], notes: nil, conversationId: nil),
            ],
            conversationId: conversationId.uuidString.lowercased()
        )

        store.applyPlanStepBatchUpdate(
            items: [
                PlanStepBatchUpdateItemPayload(stepId: "1", status: .done, title: "Uno", description: nil, targetFile: nil, linkedFiles: [], dependsOn: [], notes: nil),
                PlanStepBatchUpdateItemPayload(stepId: "2", status: .running, title: "Due", description: nil, targetFile: nil, linkedFiles: [], dependsOn: [], notes: nil),
            ],
            conversationId: conversationId.uuidString.lowercased(),
            fallbackConversationId: conversationId
        )
        store.applyPlanStepReorder(
            orderedStepIds: ["2", "1"],
            conversationId: conversationId.uuidString.lowercased(),
            fallbackConversationId: conversationId
        )
        store.applyPlanStepDependencySet(
            stepId: "2",
            dependsOn: ["1"],
            conversationId: conversationId.uuidString.lowercased(),
            fallbackConversationId: conversationId
        )
        store.applyPlanSetWalkthrough(
            markdown: "## Walkthrough\nDone",
            summary: "Completato",
            outcome: "done",
            conversationId: conversationId.uuidString.lowercased(),
            fallbackConversationId: conversationId
        )

        let board = try XCTUnwrap(store.planBoard(for: conversationId))
        XCTAssertEqual(board.steps.map(\.id), ["2", "1"])
        XCTAssertEqual(board.steps[0].dependsOn, ["1"])
        XCTAssertEqual(board.walkthroughMarkdown, "## Walkthrough\nDone")
        XCTAssertEqual(board.walkthroughSummary, "Completato")
        XCTAssertEqual(board.walkthroughOutcome, "done")
    }

    func testPlanStepDecodeBackwardCompatibilityDefaults() throws {
        let json = """
        {
          "id":"1",
          "title":"Legacy",
          "description":"Legacy step",
          "targetFile":"Sources/X.swift",
          "status":"pending"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PlanStep.self, from: json)
        XCTAssertEqual(decoded.linkedFiles, [])
        XCTAssertEqual(decoded.dependsOn, [])
        XCTAssertEqual(decoded.notes, "")
        XCTAssertNotNil(decoded.updatedAt)
    }

    func testPlanMutationsSyncToSharedStateWithDedup() throws {
        let store = ChatStore(userDefaults: userDefaults)
        let conversationId = store.createConversation(contextId: nil, contextFolderPath: nil, mode: .agent)
        let conversationRaw = conversationId.uuidString.lowercased()

        store.applyPlanCreate(
            goal: "Goal dedup",
            chosenPath: nil,
            steps: [
                PlanStepUpsertPayload(stepId: "1", status: .pending, title: "Uno", description: nil, targetFile: nil, linkedFiles: [], dependsOn: [], notes: nil, conversationId: nil)
            ],
            conversationId: conversationRaw
        )
        store.applyPlanCreate(
            goal: "Goal dedup",
            chosenPath: nil,
            steps: [
                PlanStepUpsertPayload(stepId: "1", status: .pending, title: "Uno", description: nil, targetFile: nil, linkedFiles: [], dependsOn: [], notes: nil, conversationId: nil)
            ],
            conversationId: conversationRaw
        )

        var history = MCPSharedState.readPlanHistoryJSONObject(conversationId: conversationId, limit: 50)
        XCTAssertEqual(history.count, 1)

        store.applyPlanStepUpsert(
            PlanStepUpsertPayload(
                stepId: "1",
                status: .done,
                title: "Uno",
                description: nil,
                targetFile: nil,
                linkedFiles: [],
                dependsOn: [],
                notes: nil,
                conversationId: conversationRaw
            ),
            fallbackConversationId: conversationId
        )

        history = MCPSharedState.readPlanHistoryJSONObject(conversationId: conversationId, limit: 50)
        XCTAssertEqual(history.count, 2)
    }
}
