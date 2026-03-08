import Foundation

func isValidGitRefFormat(_ ref: String) -> Bool {
    let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard !trimmed.hasPrefix("-") else { return false }
    guard !trimmed.hasSuffix(".lock") else { return false }
    guard !trimmed.hasSuffix(".") else { return false }

    let invalidChars = CharacterSet.whitespacesAndNewlines
        .union(.controlCharacters)
    guard trimmed.unicodeScalars.allSatisfy({ !invalidChars.contains($0) }) else {
        return false
    }

    let forbiddenSequences = [":", "?", "*", "[", "\\", "@{"]
    for sequence in forbiddenSequences where trimmed.contains(sequence) {
        return false
    }
    return true
}

func validatedGitRef(_ ref: String, label: String) throws -> String {
    let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidGitRefFormat(trimmed) else {
        throw GitServiceError.commandFailed("Il riferimento Git per \(label) non è valido.")
    }
    return trimmed
}
