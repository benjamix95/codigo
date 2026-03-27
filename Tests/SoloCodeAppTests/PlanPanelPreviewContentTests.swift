import XCTest
@testable import CoderIDE

final class PlanPanelPreviewContentTests: XCTestCase {
    func testChosenPathTakesPrecedenceOverStoredMarkdown() {
        let content = preferredPlanPanelHistoryContent(
            markdown: "# Plan\n\nLegacy body",
            chosenPath: "## Plan\n\nChosen option body",
            fallbackTitle: "Plan A"
        )

        XCTAssertEqual(content, "## Plan\n\nChosen option body")

        let buildContent = fallbackPlanBuildContent(
            goal: "Refactor chat",
            chosenPath: "## Plan\n\nChosen option body",
            steps: []
        )
        XCTAssertEqual(buildContent, "## Plan\n\nChosen option body")
    }

    func testMarkdownIsUsedWhenChosenPathIsEmpty() {
        let content = preferredPlanPanelHistoryContent(
            markdown: "# Plan\n\nStored body",
            chosenPath: "   ",
            fallbackTitle: "Plan B"
        )

        XCTAssertEqual(content, "# Plan\n\nStored body")
    }

    func testFallbackPlaceholderUsesTitleWhenBothContentsAreEmpty() {
        let content = preferredPlanPanelHistoryContent(
            markdown: "  ",
            chosenPath: nil,
            fallbackTitle: "Deploy flow"
        )

        XCTAssertEqual(content, "# Deploy flow\n\n(No plan content available.)")
    }

    func testOptionContentPrefersMatchingChosenPath() {
        let options = [
            PlanOption(id: 2, title: "B", fullText: "## Plan\n\nOption B"),
            PlanOption(id: 1, title: "A", fullText: "## Plan\n\nOption A"),
        ]

        let content = preferredPlanPanelOptionContent(
            chosenPath: "## Plan\n\nOption B",
            options: options
        )

        XCTAssertEqual(content, "## Plan\n\nOption B")
    }

    func testOptionContentFallsBackToFirstSortedOptionWhenChosenPathDoesNotMatch() {
        let options = [
            PlanOption(id: 3, title: "C", fullText: "## Plan\n\nOption C"),
            PlanOption(id: 1, title: "A", fullText: "## Plan\n\nOption A"),
        ]

        let content = preferredPlanPanelOptionContent(
            chosenPath: "## Plan\n\nStale option",
            options: options
        )

        XCTAssertEqual(content, "## Plan\n\nOption A")

        let buildContent = fallbackPlanBuildContent(
            goal: "Verifica tool Codex",
            chosenPath: nil,
            steps: [
                PlanStep(id: "1", title: "Create todo", description: "Create todo", targetFile: nil, status: .pending),
                PlanStep(id: "2", title: "Read README", description: "Read README", targetFile: nil, status: .pending),
            ]
        )

        XCTAssertEqual(
            buildContent,
            """
            # Verifica tool Codex

            ## Todo
            - [ ] Create todo
            - [ ] Read README
            """
        )
    }

    func testDisplayContentPrefersScopedHistoryWhenLiveBoardIsNotPreferred() {
        let liveBoard = PlanBoard(
            goal: "Live goal",
            options: [PlanOption(id: 1, title: "A", fullText: "## Plan\n\nLive option")],
            chosenPath: "## Plan\n\nLive chosen",
            steps: [],
            updatedAt: .now
        )

        let content = preferredPlanPanelDisplayContent(
            preferLiveBoard: false,
            liveBoard: liveBoard,
            planningState: .idle,
            selectedHistoryContent: "## Plan\n\nHistory snapshot"
        )

        XCTAssertEqual(content, "## Plan\n\nHistory snapshot")
    }

    func testDisplayContentPrefersLiveBoardWhenPlanStateRequiresIt() {
        let liveBoard = PlanBoard(
            goal: "Live goal",
            options: [PlanOption(id: 2, title: "B", fullText: "## Plan\n\nLive option")],
            chosenPath: "## Plan\n\nLive chosen",
            steps: [],
            updatedAt: .now
        )

        let content = preferredPlanPanelDisplayContent(
            preferLiveBoard: true,
            liveBoard: liveBoard,
            planningState: .idle,
            selectedHistoryContent: "## Plan\n\nHistory snapshot"
        )

        XCTAssertEqual(content, "## Plan\n\nLive chosen")
    }

    func testBuildChoicePrefersSelectedHistoryWhenLiveBoardIsNotPreferred() {
        let liveBoard = PlanBoard(
            goal: "Live goal",
            options: [PlanOption(id: 1, title: "A", fullText: "## Plan\n\nLive option")],
            chosenPath: "## Plan\n\nLive chosen",
            steps: [],
            updatedAt: .now
        )

        let choice = preferredPlanPanelBuildChoice(
            preferLiveBoard: false,
            liveBoard: liveBoard,
            selectedHistoryBuildContent: "## Todo\n- [ ] Use history"
        )

        XCTAssertEqual(choice?.text, "## Todo\n- [ ] Use history")
        XCTAssertEqual(choice?.isFallback, false)
    }

    func testBuildChoiceDoesNotFallBackToLiveBoardWhenSelectedHistoryIsUnbuildable() {
        let liveBoard = PlanBoard(
            goal: "Live goal",
            options: [PlanOption(id: 1, title: "A", fullText: "## Plan\n\nLive option")],
            chosenPath: "## Plan\n\nLive chosen",
            steps: [],
            updatedAt: .now
        )

        let choice = preferredPlanPanelBuildChoice(
            preferLiveBoard: false,
            liveBoard: liveBoard,
            selectedHistoryBuildContent: nil
        )

        XCTAssertNil(choice)
    }
}
