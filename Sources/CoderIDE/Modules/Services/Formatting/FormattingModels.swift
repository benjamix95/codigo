import Foundation

// MARK: - Formatting Models

/// Risultato di un'operazione di formattazione.
struct FormattingResult: Sendable {
    let originalContent: String
    let formattedContent: String
    let filePath: String
    let didChange: Bool
    let error: String?

    var isSuccess: Bool { error == nil }

    static func success(original: String, formatted: String, filePath: String) -> FormattingResult {
        FormattingResult(
            originalContent: original,
            formattedContent: formatted,
            filePath: filePath,
            didChange: original != formatted,
            error: nil
        )
    }

    static func failure(filePath: String, error: String) -> FormattingResult {
        FormattingResult(
            originalContent: "",
            formattedContent: "",
            filePath: filePath,
            didChange: false,
            error: error
        )
    }
}

/// Opzioni per la formattazione.
struct FormattingOptions: Sendable {
    let indentWidth: Int
    let tabWidth: Int
    let useTabs: Bool
    let maxLineLength: Int

    init(
        indentWidth: Int = 4,
        tabWidth: Int = 4,
        useTabs: Bool = false,
        maxLineLength: Int = 120
    ) {
        self.indentWidth = indentWidth
        self.tabWidth = tabWidth
        self.useTabs = useTabs
        self.maxLineLength = maxLineLength
    }

    static let `default` = FormattingOptions()
}

/// Tipo di formatter supportato.
enum FormatterType: String, Sendable {
    case swiftFormat = "swift-format"
    case prettier = "prettier"
    case clangFormat = "clang-format"
}

/// Protocollo per adapter di formattazione.
protocol FormattingAdapter: Sendable {
    var formatterType: FormatterType { get }
    func format(content: String, filePath: String, options: FormattingOptions) async -> FormattingResult
    func formatFile(at path: String, options: FormattingOptions) async -> FormattingResult
    func isAvailable() async -> Bool
}
