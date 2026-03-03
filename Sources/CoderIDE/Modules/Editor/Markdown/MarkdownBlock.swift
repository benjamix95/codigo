import Foundation

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletItem(text: String, indent: Int)
    case numberedItem(number: String, text: String, indent: Int)
    case codeBlock(language: String, code: String)
    case mermaid(code: String)
    case horizontalRule
    case blockquote(text: String)
    case table(headers: [String], rows: [[String]])
    case spacer
}
