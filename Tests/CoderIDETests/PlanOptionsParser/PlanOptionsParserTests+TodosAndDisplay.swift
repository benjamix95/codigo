import XCTest
@testable import CoderIDE

extension PlanOptionsParserTests {
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos, ["First task", "Second task"])
    }

    func testExtractTodosFromOptionTextFallsBackToChecklistWithoutHeader() {
        let input = """
        Option details:
        - [ ] First task
        - [ ] Second task
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos, ["First task", "Second task"])
    }

    func testExtractTodosFromOptionTextReturnsEmptyWhenNoSection() {
        let input = """
        ## Option 1: Refactor
        - Pro: robustness
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertTrue(todos.isEmpty)
    }

    func testExtractFinalPlanBodyExcludingQuestionsOptionsTodos() {
        let input = """
        ## Questions
        1. Do you prefer A or B?
        A) A
        B) B

        ## Option 1: Quick patch
        Option text.

        ## Todo
        - [ ] Step one

        ## Cause
        - overflow in composer on narrow width
        - markdown parsing too dense

        ## Approach
        Apply ViewThatFits + display-only layout normalization.
        """

        let output = PlanOptionsParser.extractFinalPlanBodyExcludingQuestionsOptionsTodos(input)

        XCTAssertFalse(output.localizedCaseInsensitiveContains("## Questions"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("## Option"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("## Todo"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("## Cause"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("## Approach"))
    }

    func testExtractMermaidBlocksForDisplay() {
        let input = """
        ## Diagram
        ```mermaid
        graph TD
            A[Start] --> B[Build]
        ```
        """

        let blocks = PlanOptionsParser.extractMermaidBlocksForDisplay(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks[0].contains("graph TD"))
    }

    func testExtractMermaidBlocksForDisplaySupportsInlineMermaidFence() {
        let input = """
        ## Diagram
        ```mermaid graph TD; A-->B```
        """

        let blocks = PlanOptionsParser.extractMermaidBlocksForDisplay(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks[0].contains("graph TD"))
    }

    func testExtractTodosSkipsCodeFences() {
        let input = """
        ## Todo
        - [ ] Real step

        ```bash
        # Tasks
        - [ ] Fake step inside code fence
        ```
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos[0], "Real step")
    }

    func testExtractTodosSkipsCodeFencesInFallbackPasses() {
        let input = """
        Some text

        ```markdown
        - [ ] Fake checklist in fence
        ```

        - [ ] Real checklist outside
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos[0], "Real checklist outside")
    }

    func testChecklistPatternRequiresClosingBracket() {
        let input = """
        - [see documentation](https://example.com)
        - [important note] about something
        """
        let hasTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(input)
        XCTAssertFalse(hasTodoHeader, "Markdown links should not be detected as todo headers")
    }

    func testExtractDisplaySummaryStripsMermaid() {
        let input = """
        # My Plan
        ## Architecture
        ```mermaid
        graph TD
            A --> B
        ```
        Some approach text.
        """
        let (_, body) = PlanOptionsParser.extractDisplaySummary(from: input)
        XCTAssertFalse(body.contains("mermaid"), "Summary body should strip mermaid blocks")
        XCTAssertFalse(body.contains("graph TD"), "Summary body should strip mermaid content")
    }
}
