import XCTest
@testable import CoderIDE

final class PlanOptionsParserTests: XCTestCase {
    func testParseItalianOptionsWithMarkdownHeader() {
        let input = """
        ## Opzione 1: Refactor parser
        - Pro: robustezza

        ## Opzione 2: Patch minima
        - Pro: veloce
        """

        let options = PlanOptionsParser.parse(from: input)
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].id, 1)
        XCTAssertTrue(options[0].title.localizedCaseInsensitiveContains("Refactor"))
        XCTAssertEqual(options[1].id, 2)
    }

    func testParseEnglishOptionsCaseInsensitive() {
        let input = """
        ## OPTION 1: Use strategy pattern
        details...

        ## option 2 - Keep current architecture
        details...
        """

        let options = PlanOptionsParser.parse(from: input)
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options.map(\.id), [1, 2])
        XCTAssertTrue(options[0].title.localizedCaseInsensitiveContains("strategy"))
    }

    func testParseClarificationQuestionsReturnsQuestions() {
        let input = """
        Ho bisogno di dettagli.
        ## Domande di chiarimento
        1. Quale parte del sistema deve essere modificata?
        2. Esistono vincoli di retrocompatibilità?
        3. Preferisci refactor o patch?
        """
        let questions = PlanOptionsParser.parseClarificationQuestions(from: input)
        XCTAssertNotNil(questions)
        XCTAssertEqual(questions?.count ?? 0, 3)
        XCTAssertEqual(questions?[0], "Quale parte del sistema deve essere modificata?")
        XCTAssertEqual(questions?[1], "Esistono vincoli di retrocompatibilità?")
    }

    func testParseClarificationQuestionsReturnsNilWhenNoBlock() {
        let input = """
        ## Opzione 1: Refactor
        - Pro: robustezza
        """
        let questions = PlanOptionsParser.parseClarificationQuestions(from: input)
        XCTAssertNil(questions)
    }

    func testParseClarificationQuestionsReturnsNilWithOnlyOneQuestion() {
        let input = """
        ## Domande di chiarimento
        1. Una sola domanda?
        """
        let questions = PlanOptionsParser.parseClarificationQuestions(from: input)
        XCTAssertNil(questions)
    }

    func testExtractTodosFromOptionText() {
        let input = """
        ## Opzione 1: Refactor
        - Pro: robustezza
        ## Todo
        - [ ] Step 1: Creare interfaccia
        - [ ] Step 2: Implementare classe concreta
        - [ ] Step 3: Aggiornare test
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos.count, 3)
        XCTAssertEqual(todos[0], "Step 1: Creare interfaccia")
        XCTAssertEqual(todos[1], "Step 2: Implementare classe concreta")
        XCTAssertEqual(todos[2], "Step 3: Aggiornare test")
    }

    func testExtractTodosFromOptionTextWithBullets() {
        let input = """
        ## Todo
        - First task
        - Second task
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos.count, 2)
    }

    func testExtractTodosFromOptionTextReturnsEmptyWhenNoSection() {
        let input = """
        ## Opzione 1: Refactor
        - Pro: robustezza
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertTrue(todos.isEmpty)
    }
}

