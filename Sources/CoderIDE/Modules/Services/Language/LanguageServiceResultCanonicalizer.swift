import Foundation

enum LanguageServiceResultCanonicalizer {
    static func canonicalize(
        locations: [LanguageLocation],
        symbolName: String? = nil,
        source: LanguageServiceSource? = nil,
        limit: Int? = nil
    ) -> [LanguageLocation] {
        var unique: [LocationKey: LanguageLocation] = [:]
        for location in locations {
            let normalized = LanguageLocation(
                filePath: location.filePath,
                line: max(1, location.line),
                column: location.column.map { max(1, $0) },
                symbolName: normalizeSymbolName(symbolName ?? location.symbolName),
                source: source ?? location.source
            )
            unique[LocationKey(from: normalized)] = normalized
        }

        let sorted = unique.values.sorted(by: locationSort)
        guard let limit else { return sorted }
        return Array(sorted.prefix(max(0, limit)))
    }

    static func canonicalize(hover: LanguageHoverResult?, source: LanguageServiceSource? = nil) -> LanguageHoverResult? {
        guard let hover else { return nil }
        let contents = hover.contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contents.isEmpty else { return nil }
        return LanguageHoverResult(contents: contents, source: source ?? hover.source)
    }

    static func canonicalize(
        renamePlan: LanguageRenamePlan,
        requestedOldName: String,
        requestedNewName: String,
        source: LanguageServiceSource? = nil
    ) -> LanguageRenamePlan {
        let effectiveSource = source ?? renamePlan.source
        let oldName = normalizeSymbolName(requestedOldName)
        let newName = normalizeSymbolName(requestedNewName)
        return LanguageRenamePlan(
            oldName: oldName,
            newName: newName,
            references: canonicalize(
                locations: renamePlan.references,
                symbolName: oldName,
                source: effectiveSource
            ),
            source: effectiveSource
        )
    }

    private static func normalizeSymbolName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func locationSort(lhs: LanguageLocation, rhs: LanguageLocation) -> Bool {
        if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        let lhsColumn = lhs.column ?? Int.max
        let rhsColumn = rhs.column ?? Int.max
        if lhsColumn != rhsColumn { return lhsColumn < rhsColumn }
        if lhs.symbolName != rhs.symbolName { return lhs.symbolName < rhs.symbolName }
        return lhs.source.rawValue < rhs.source.rawValue
    }
}

private struct LocationKey: Hashable {
    let filePath: String
    let line: Int
    let column: Int
    let symbolName: String

    init(from location: LanguageLocation) {
        self.filePath = location.filePath
        self.line = location.line
        self.column = location.column ?? -1
        self.symbolName = location.symbolName
    }
}
