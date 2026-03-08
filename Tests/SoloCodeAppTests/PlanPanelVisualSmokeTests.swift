import AppKit
import CoderEngine
import SwiftUI
import XCTest
@testable import CoderIDE

@MainActor
final class PlanPanelVisualSmokeTests: XCTestCase {
    private let outputDir = URL(fileURLWithPath: "/tmp/coderide-ui-smoke", isDirectory: true)

    override func setUpWithError() throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    func testCapturePlanPanelQuestionsWizardScreenshot() throws {
        let questions = """
        ## Questions
        1. Quale area vuoi prioritizzare?
        A) Todo sync
        B) Routing panel/chat
        C) Other (specify)
        """
        let imageURL = outputDir.appendingPathComponent("plan_questions_panel.png")
        let view = makePanelView(
            planningState: .awaitingClarification(questions: questions),
            flowPhase: .questioning,
            streamingContent: questions,
            seed: 1
        )
        try snapshot(view: view, size: CGSize(width: 500, height: 980), output: imageURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    }

    func testCapturePlanPanelClarificationsNeededWizardScreenshot() throws {
        let clarifications = """
        ## Clarifications Needed
        1. Quale vincolo e bloccante?
        A) Compatibilita backward
        B) UX custom risposte utente
        C) Other (specify)
        """
        let imageURL = outputDir.appendingPathComponent("plan_clarifications_needed_panel.png")
        let view = makePanelView(
            planningState: .awaitingClarification(questions: clarifications),
            flowPhase: .questioning,
            streamingContent: clarifications,
            seed: 2
        )
        try snapshot(view: view, size: CGSize(width: 500, height: 980), output: imageURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    }

    func testCapturePlanPanelAfterThreadSwitchScreenshot() throws {
        let questionsThreadB = """
        ## Questions
        1. Thread B: quale target?
        A) iOS
        B) macOS
        """
        let imageURL = outputDir.appendingPathComponent("plan_questions_panel_after_switch.png")
        let view = makePanelView(
            planningState: .awaitingClarification(questions: questionsThreadB),
            flowPhase: .questioning,
            streamingContent: questionsThreadB,
            seed: 5
        )
        try snapshot(view: view, size: CGSize(width: 500, height: 980), output: imageURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    }

    private func makePanelView(
        planningState: PlanningState,
        flowPhase: PlanFlowPhase,
        streamingContent: String,
        seed: Int
    ) -> some View {
        PlanPanelView(
            todoStore: TodoStore(),
            chatStore: ChatStore(),
            taskActivityStore: TaskActivityStore(),
            conversationId: UUID(),
            isCurrentConversationLoading: false,
            planningState: planningState,
            planFlowPhase: flowPhase,
            planStreamingContent: streamingContent,
            questionsWereVisited: true,
            clarificationIdentitySeed: seed,
            showHistorySection: false,
            workspaceSource: .manualDeepLink,
            onClose: {},
            onSelectOption: { _, _ in },
            onCustomResponse: { _ in },
            onSubmitClarificationAnswers: { _ in },
            onBuild: { _, _, _ in },
            onStop: {},
            onHistoryEntrySelectedForBuild: {}
        )
        .environmentObject(ProviderRegistry())
        .environmentObject(PlanHistoryStore())
    }

    private func snapshot<V: View>(view: V, size: CGSize, output: URL) throws {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Unable to allocate bitmap representation")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Unable to encode PNG screenshot")
            return
        }
        try pngData.write(to: output, options: .atomic)
    }
}
