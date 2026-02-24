import XCTest
@testable import CoderIDE

final class MarkdownContentFormattingTests: XCTestCase {
    func testNormalizeAssistantDisplayLayoutSeparatesInlineNumberedList() {
        let input = """
        Esito verifica completata con due incongruenze rilevate. 1. Alta severità: task panel non si apre fuori swarm. 2. Media severità: mismatch stato TODO.
        """

        let output = MarkdownContentView.normalizeAssistantDisplayLayout(input)

        XCTAssertTrue(output.contains("rilevate.\n\n1. Alta severità"))
        XCTAssertTrue(output.contains("\n2. Media severità"))
    }

    func testNormalizeAssistantDisplayLayoutKeepsCodeFenceUnchanged() {
        let input = """
        Prima descrizione. ```swift
        let text = "1. non è una lista"
        ``` Dopo spiegazione.
        """

        let output = MarkdownContentView.normalizeAssistantDisplayLayout(input)

        XCTAssertTrue(output.contains("```swift\nlet text = \"1. non è una lista\"\n```"))
    }

    func testNormalizeAssistantDisplayLayoutSplitsDenseSingleLineParagraph() {
        let input = """
        Questo è un paragrafo molto lungo pensato per simulare una risposta troppo compatta e difficile da leggere in chat. Contiene diverse frasi consecutive che normalmente dovrebbero avere più respiro visivo. L'obiettivo è verificare che la normalizzazione produca separazioni naturali senza alterare il significato del contenuto. Questo migliora la leggibilità generale quando il modello restituisce tutto su una sola riga. Infine controlliamo che il testo mantenga ordine e tono professionale.
        """

        let output = MarkdownContentView.normalizeAssistantDisplayLayout(input)

        XCTAssertTrue(output.contains("\n\n"), "Expected at least one auto paragraph break")
    }
}
