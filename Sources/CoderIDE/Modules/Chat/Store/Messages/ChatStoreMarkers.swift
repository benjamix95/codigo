import Foundation
import CoderEngine

extension ChatStore {
// MARK: - Cached regex patterns (compiled once, reused on every call)

private enum MarkerRegex {
    static let coderideMarker = try! NSRegularExpression(
        pattern: "\\[\\s*CODERIDE\\s*:[^\\]\\n]*\\]", options: .caseInsensitive)
    static let ideFilesLine = try! NSRegularExpression(
        pattern: #"^[^\n]*IDE\s*:\s*files\s*=[^\]\n]*\]?\s*"#,
        options: [.caseInsensitive, .anchorsMatchLines])
    static let opLineIDE = try! NSRegularExpression(
        pattern: #"^(?:Creating|Generating|Processing|Analyzing|Reading|Writing|Updating)\s+[^\n]*?(?:IDE|CODERIDE|planIDE)[^\n]*$"#,
        options: [.caseInsensitive, .anchorsMatchLines])
    static let bugReview = try! NSRegularExpression(
        pattern: #"(?im)^Planning\s+(?:bug\s+review|code\s+review)\s+workflow\s*$"#,
        options: [.caseInsensitive, .anchorsMatchLines])
    static let inlineOpPrefix = try! NSRegularExpression(
        pattern: #"(?im)^(\s*(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing|Inspecting)\s+(?:initial\s+)?(?:task\s+panel(?:\s+and\s+todo\s+update)?|todo(?:\s+update)?|workflow(?:\s+steps?)?|project\s+analysis|analysis|plan|execution(?:\s+flow)?)(?:\s+and\s+todo\s+update)?\s+)"#,
        options: [.caseInsensitive, .anchorsMatchLines])
    static let initBoilerplate = try! NSRegularExpression(
        pattern: #"(?im)^(?:(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+(?:initial\s+)?(?:task\s+panel|todo|workflow|workflow\s+steps?|project\s+analysis|analysis|plan|execution|execution\s+flow|operations?)\b[^\n]*|(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+[^\n]*(?:task\s+panel|todo|workflow|analysis|plan|execution)\b[^\n]*)$"#,
        options: [.caseInsensitive, .anchorsMatchLines])
    static let progressHeading = try! NSRegularExpression(
        pattern: #"(?im)^(?:\*{1,2}\s*)?(?:Updating|Planning|Reading|Analyzing|Implementing)\b[^\n]{0,140}(?:\*{1,2})?\s*$"#,
        options: [.caseInsensitive, .anchorsMatchLines])
    static let cliTrace = try! NSRegularExpression(
        pattern: #"(?im)^(?:Explored\s+\d+\s+files?(?:,\s*\d+\s+search(?:es)?)?(?:,\s*\d+\s+list)?|Ran\s+[^\n]+|Inspecting\s+[^\n]+)\s*$"#,
        options: [.caseInsensitive, .anchorsMatchLines])
    static let inlineMarkerPrefix = try! NSRegularExpression(
        pattern: #"(?i)\bmarkers\s*:\s*[a-z_][a-z0-9_]*\|"#, options: [])
    static let inlineMarkerTypes = try! NSRegularExpression(
        pattern: #"(?i)\b(?:todo_write|todo_read|plan_step(?:_update)?|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|web_fetch(?:_started|_completed|_failed)?|instant_grep)\|"#, options: [])
    static let inlineMarkerBroken = try! NSRegularExpression(
        pattern: #"(?i)\b(?:markers)?[a-z_]*(?:todo_write|todo_read|do_write|do_read|plan_step(?:_update)?|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|web_fetch(?:_started|_completed|_failed)?|instant_grep)\|"#, options: [])
    static let technicalEvents = try! NSRegularExpression(
        pattern: #"(?i)\b(?:coderide_show_task_panel|coderide_show_swarm_panel|read_batch_started|read_batch_completed|web_search_started|web_search_completed|web_search_failed|web_fetch_started|web_fetch_completed|web_fetch_failed|plan_step(?:_update)?|todo_write|todo_read|instant_grep)\b"#, options: [])
    static let stickyKeyValue = try! NSRegularExpression(
        pattern: #"([A-Za-zÀ-ÖØ-öø-ÿ])((?i:files|count|group_id|queryid|query|step_id|pathscope|matchescount|previewlines|status|priority|notes|title|id|task)=)"#, options: [])
    static let singleKeyValue = try! NSRegularExpression(
        pattern: #"(?i)\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task)=[^|\n\r]+(?:\||$)"#, options: [])
    static let keyValueBracket = try! NSRegularExpression(
        pattern: #"(?i)\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task|pathscope|matchescount|previewlines)=[^\]\n\r]+\]"#, options: [])
    static let trailingSpaceNewline = try! NSRegularExpression(pattern: #"\s+\n"#, options: [])
    static let excessiveNewlines = try! NSRegularExpression(pattern: #"\n{3,}"#, options: [])
    static let excessiveSpaces = try! NSRegularExpression(pattern: #"[ \t]{2,}"#, options: [])
    static let missingSpaceAfterPunct = try! NSRegularExpression(
        pattern: #"([.!?])([A-Za-zÀ-ÖØ-öø-ÿ])"#, options: [])
    static let tripleNewlines = try! NSRegularExpression(pattern: #"\n\n\n+"#, options: [])
    static let structuredPayload = try! NSRegularExpression(
        pattern: #"(?i)(?:\b[a-z_][a-z0-9_]*=[^|\n\r]+(?:\|\s*|\s*$)){2,}"#, options: [])
}

private enum MarkerStripCache {
    static let aggressive: NSCache<NSString, NSString> = makeCache()
    static let conservative: NSCache<NSString, NSString> = makeCache()

    static func cache(for aggressive: Bool) -> NSCache<NSString, NSString> {
        aggressive ? self.aggressive : self.conservative
    }

    static func key(for content: String, aggressive: Bool) -> NSString {
        var hasher = Hasher()
        hasher.combine(content)
        let digest = hasher.finalize()
        let prefix = content.prefix(56)
        let suffix = content.suffix(28)
        return "\(aggressive ? 1 : 0)|\(content.count)|\(digest)|\(prefix)|\(suffix)" as NSString
    }

    private static func makeCache() -> NSCache<NSString, NSString> {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 512
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }
}

private static func shouldRunMarkerCleanup(_ content: String, aggressive: Bool) -> Bool {
    guard !content.isEmpty else { return false }

    let commonNeedles = [
        "[CODERIDE",
        "markers:",
        "todo_write|",
        "todo_read|",
        "plan_step",
        "read_batch",
        "web_search",
        "web_fetch",
        "instant_grep",
        "coderide_show_task_panel",
        "coderide_show_swarm_panel",
    ]

    for needle in commonNeedles where content.range(of: needle, options: .caseInsensitive) != nil {
        return true
    }

    if aggressive {
        if content.contains("=") && content.contains("|") {
            return true
        }
        let aggressiveNeedles = [
            "IDE: files=",
            "Planning bug review workflow",
            "Planning code review workflow",
            "Explored ",
            "Inspecting ",
            "Ran ",
            "Bootstrapping ",
            "Initializing ",
            "Preparing ",
            "Setting ",
            "Starting ",
        ]
        for needle in aggressiveNeedles where content.range(of: needle, options: .caseInsensitive) != nil {
            return true
        }
    }

    return false
}

/// Helper: apply pre-compiled NSRegularExpression as a replacement on the full string.
private static func applyRegex(_ regex: NSRegularExpression, on string: inout String, template: String) {
    let ns = string as NSString
    string = regex.stringByReplacingMatches(
        in: string, range: NSRange(location: 0, length: ns.length), withTemplate: template)
}

/// Removes CODERIDE markers from source to avoid flashes during streaming.
/// Protects code fences (```...```) from being corrupted by cleanup regexes.
static func stripCoderideMarkers(_ content: String, aggressive: Bool = true) -> String {
    let cache = MarkerStripCache.cache(for: aggressive)
    let cacheKey = MarkerStripCache.key(for: content, aggressive: aggressive)
    if let cached = cache.object(forKey: cacheKey) {
        return cached as String
    }

    if !shouldRunMarkerCleanup(content, aggressive: aggressive) {
        var fastPathResult = aggressive
            ? content.trimmingCharacters(in: .whitespacesAndNewlines)
            : content
        while fastPathResult.contains("\n\n\n") {
            fastPathResult = fastPathResult.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        cache.setObject(
            fastPathResult as NSString,
            forKey: cacheKey,
            cost: min(16_384, fastPathResult.utf16.count)
        )
        return fastPathResult
    }

    // Split into code-fence vs prose segments so regexes only touch prose
    let segments = splitByCodeFences(content)
    var result = segments.map { seg -> String in
        guard !seg.isCodeFence else { return seg.text }
        return stripProseSegment(seg.text, aggressive: aggressive)
    }.joined()
    // Final whitespace cleanup across the whole result (safe — doesn't alter code blocks)
    applyRegex(MarkerRegex.excessiveNewlines, on: &result, template: "\n\n")
    applyRegex(MarkerRegex.tripleNewlines, on: &result, template: "\n\n")
    let finalResult = aggressive ? result.trimmingCharacters(in: .whitespacesAndNewlines) : result
    cache.setObject(
        finalResult as NSString,
        forKey: cacheKey,
        cost: min(16_384, finalResult.utf16.count)
    )
    return finalResult
}

/// Strip markers from a prose (non-code-fence) segment.
private static func stripProseSegment(_ text: String, aggressive: Bool) -> String {
    var out = text
    // 1. Standard [CODERIDE:...] markers
    while true {
        let ns = out as NSString
        guard let match = MarkerRegex.coderideMarker.firstMatch(
            in: out, range: NSRange(location: 0, length: ns.length)) else { break }
        let start = out.index(out.startIndex, offsetBy: match.range.location)
        let end = out.index(start, offsetBy: match.range.length)
        out.removeSubrange(start..<end)
    }
    // 2. Fallback for incomplete [CODERIDE markers
    while let start = out.range(of: "[CODERIDE", options: .caseInsensitive) {
        if let end = out[start.upperBound...].firstIndex(of: "]") {
            out.removeSubrange(start.lowerBound..<out.index(after: end))
        } else {
            if let newline = out[start.lowerBound...].firstIndex(of: "\n") {
                out.removeSubrange(start.lowerBound..<newline)
            } else {
                out.removeSubrange(start.lowerBound..<out.endIndex)
            }
            break
        }
    }
    if aggressive {
        applyRegex(MarkerRegex.ideFilesLine, on: &out, template: "")
        applyRegex(MarkerRegex.opLineIDE, on: &out, template: "")
        applyRegex(MarkerRegex.bugReview, on: &out, template: "")
        applyRegex(MarkerRegex.inlineOpPrefix, on: &out, template: "")
        applyRegex(MarkerRegex.initBoilerplate, on: &out, template: "")
        applyRegex(MarkerRegex.progressHeading, on: &out, template: "")
        applyRegex(MarkerRegex.cliTrace, on: &out, template: "")
    }
    // Inline markers
    applyRegex(MarkerRegex.inlineMarkerPrefix, on: &out, template: "")
    applyRegex(MarkerRegex.inlineMarkerTypes, on: &out, template: "")
    applyRegex(MarkerRegex.inlineMarkerBroken, on: &out, template: "")
    applyRegex(MarkerRegex.technicalEvents, on: &out, template: "")
    if aggressive {
        applyRegex(MarkerRegex.stickyKeyValue, on: &out, template: "$1 $2")
        applyRegex(MarkerRegex.singleKeyValue, on: &out, template: "")
        applyRegex(MarkerRegex.keyValueBracket, on: &out, template: "")
        out = stripStructuredMarkerPayloads(out)
    }
    // Cleanup formatting (safe on prose only)
    applyRegex(MarkerRegex.trailingSpaceNewline, on: &out, template: "\n")
    applyRegex(MarkerRegex.excessiveSpaces, on: &out, template: " ")
    applyRegex(MarkerRegex.missingSpaceAfterPunct, on: &out, template: "$1 $2")
    return out
}

/// Splits content into alternating prose / code-fence segments.
private static func splitByCodeFences(_ input: String) -> [(text: String, isCodeFence: Bool)] {
    var segments: [(String, Bool)] = []
    var cursor = input.startIndex
    while cursor < input.endIndex {
        guard let fenceRange = input[cursor...].range(of: "```") else {
            let rest = String(input[cursor...])
            if !rest.isEmpty { segments.append((rest, false)) }
            break
        }
        let before = String(input[cursor..<fenceRange.lowerBound])
        if !before.isEmpty { segments.append((before, false)) }
        if let closingFence = input[fenceRange.upperBound...].range(of: "```") {
            let fenceChunk = String(input[fenceRange.lowerBound..<closingFence.upperBound])
            segments.append((fenceChunk, true))
            cursor = closingFence.upperBound
        } else {
            // Unclosed fence — treat as code fence to protect it
            let remainder = String(input[fenceRange.lowerBound...])
            segments.append((remainder, true))
            break
        }
    }
    return segments
}

private static let structuredPayloadMarkerKeys: Set<String> = [
    "id", "title", "status", "priority", "notes", "files", "step_id",
    "queryid", "query", "group_id", "count", "task",
]

private static func stripStructuredMarkerPayloads(_ input: String) -> String {
    let regex = MarkerRegex.structuredPayload
    var out = input
    while true {
        let ns = out as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: out, options: [], range: range)
        guard !matches.isEmpty else { break }
        var removed = false
        for match in matches.reversed() {
            guard let strRange = Range(match.range, in: out) else { continue }
            let chunk = String(out[strRange])
            let keys = chunk
                .split(separator: "|")
                .compactMap { segment -> String? in
                    guard let eq = segment.firstIndex(of: "=") else { return nil }
                    return String(segment[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                }
            guard !keys.isEmpty else { continue }
            let markerKeyCount = keys.filter { structuredPayloadMarkerKeys.contains($0) }.count
            if markerKeyCount >= 3 {
                out.removeSubrange(strRange)
                removed = true
            }
        }
        if !removed { break }
    }
    return out
}

/// Extracts the last "operational" line from content during streaming (e.g. "Planning next moves", "Explored lints").
/// Used to show LLM thinking like Cursor does.
static func extractLastOperationalThinkingLine(from content: String) -> String? {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lines = trimmed.components(separatedBy: .newlines)
    let operationalPrefixes = [
        "Planning", "Explored", "Inspecting", "Ran ", "Reading", "Analyzing",
        "Implementing", "Updating", "Creating", "Generating", "Processing",
        "Setting", "Preparing", "Starting", "Initializing", "Bootstrapping",
        "Writing", "Searching"
    ]
    for line in lines.reversed() {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count > 3, t.count < 150 else { continue }
        let lower = t.lowercased()
        for prefix in operationalPrefixes {
            if lower.hasPrefix(prefix.lowercased()) {
                return t
            }
        }
    }
    return nil
}
}
