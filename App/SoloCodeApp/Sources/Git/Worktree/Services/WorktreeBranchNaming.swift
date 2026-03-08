import Foundation

func sanitizeWorktreeBranchComponent(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.isEmpty { return "task" }

    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
    let mapped = trimmed.map { char -> Character in
        guard let scalar = char.unicodeScalars.first else { return "-" }
        return allowed.contains(scalar) ? char : "-"
    }

    var collapsed = String(mapped)
    while collapsed.contains("--") {
        collapsed = collapsed.replacingOccurrences(of: "--", with: "-")
    }
    return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func makeDefaultWorktreeBranchName(baseBranch: String) -> String {
    let base = sanitizeWorktreeBranchComponent(baseBranch.isEmpty ? "task" : baseBranch)
    let suffix = String(UUID().uuidString.lowercased().prefix(6))
    return "solocode/\(base)-\(suffix)"
}
