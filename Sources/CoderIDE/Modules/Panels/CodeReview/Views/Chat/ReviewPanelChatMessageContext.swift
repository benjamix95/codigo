import AppKit
import Foundation

struct ReviewPanelChatMessageFileTarget: Identifiable, Equatable {
    let path: String
    let line: Int?

    var id: String {
        if let line {
            return "\(path):\(line)"
        }
        return path
    }

    var displayLabel: String {
        let name = (path as NSString).lastPathComponent
        if let line {
            return "\(name):\(line)"
        }
        return name
    }
}

enum ReviewPanelChatMessageContext {
    private static let fileReferencePattern =
        #"([A-Za-z0-9_./-]+\.[A-Za-z0-9]+)(?::([0-9]+))?"#

    static func fileTargets(from content: String, limit: Int = 3) -> [ReviewPanelChatMessageFileTarget] {
        guard !content.isEmpty,
              let regex = try? NSRegularExpression(pattern: fileReferencePattern) else {
            return []
        }

        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, range: nsRange)
        var targets: [ReviewPanelChatMessageFileTarget] = []
        var seen = Set<String>()

        for match in matches {
            guard let pathRange = Range(match.range(at: 1), in: content) else { continue }
            let path = String(content[pathRange])
            guard isLikelyFilePath(path) else { continue }
            let line: Int? = {
                guard let lineRange = Range(match.range(at: 2), in: content) else { return nil }
                return Int(content[lineRange])
            }()
            let target = ReviewPanelChatMessageFileTarget(path: path, line: line)
            guard seen.insert(target.id).inserted else { continue }
            targets.append(target)
            if targets.count >= limit { break }
        }

        return targets
    }

    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func isLikelyFilePath(_ value: String) -> Bool {
        guard value.contains("/") || value.contains(".") else { return false }
        let ext = (value as NSString).pathExtension
        return !ext.isEmpty
    }
}
