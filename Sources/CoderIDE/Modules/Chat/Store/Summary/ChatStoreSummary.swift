import Foundation
import CoderEngine

extension ChatStore {
/// Update real token usage from API response for a conversation.
func updateLastInputTokens(_ tokens: Int, for conversationId: UUID?) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    conversations[idx].lastInputTokens = tokens
}

func summarizeConversation(
    id: UUID?,
    keepLast: Int,
    provider: any CoderEngine.LLMProvider,
    context: CoderEngine.WorkspaceContext
) async throws -> Bool {
    guard let cid = id, let idx = conversations.firstIndex(where: { $0.id == cid }) else { return false }
    let msgs = conversations[idx].messages
    let safeKeepLast = max(2, keepLast)
    guard msgs.count > safeKeepLast + 2 else { return false }

    let toSummarize = Array(msgs.prefix(msgs.count - safeKeepLast))
    let previousSummary = conversations[idx].contextMemorySummaryMarkdown
        ?? msgs.first(where: {
            $0.role == .assistant
                && ($0.content.contains("[Conversation summary]")
                    || $0.content.contains("[Previous summary]"))
        })?.content

    let textToSummarize = toSummarize.map { message in
        let roleLabel = message.role == .user ? "User" : "Assistant"
        let cleaned = ChatStore.stripCoderideMarkers(message.content)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(roleLabel): \(cleaned)"
    }.joined(separator: "\n\n")

    let previousSummaryBlock: String = {
        guard let previousSummary else { return "" }
        let cleaned = ChatStore.stripCoderideMarkers(previousSummary)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        return """
        Existing summary (update and preserve stable facts):
        \(cleaned)

        """
    }()

    let prompt = """
    Create an updated compact conversation memory for a coding assistant.

    Rules:
    - Preserve objectives, constraints, decisions, current status, unresolved issues.
    - Preserve user preferences (language/style/tooling), and important environment assumptions.
    - Preserve modified files and verification outcomes (tests/build).
    - Remove noise, repetition, and transient tool chatter.
    - Keep it concise but complete enough for high-quality follow-ups.
    - Output in English.
    - Output ONLY markdown with these sections in this exact order:
      1) ## Objectives
      2) ## Decisions
      3) ## Progress
      4) ## Open items
      5) ## User preferences

    \(previousSummaryBlock)Conversation to summarize:
    \(textToSummarize)
    """
    let ctx = CoderEngine.WorkspaceContext(
        workspacePaths: context.workspacePaths,
        isNamedWorkspace: false,
        workspaceName: nil,
        excludedPaths: [],
        openFiles: [],
        activeSelection: nil,
        activeFilePath: nil,
        activeRootPath: context.activeRootPath
    )
    let stream = try await provider.send(prompt: prompt, context: ctx, imageURLs: nil)
    var summary = ""
    var sawProviderError = false
    for try await ev in stream {
        if case .textDelta(let d) = ev { summary += d }
        if case .error = ev { sawProviderError = true }
    }
    let cleanedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedSummary.isEmpty else { return false }
    if sawProviderError, cleanedSummary.isEmpty {
        return false
    }
    conversations[idx].contextMemorySummaryMarkdown = cleanedSummary
    conversations[idx].contextMemoryGeneratedAt = .now
    conversations[idx].contextMemorySourceMessageCount = toSummarize.count
    saveConversations()
    return true
}

/// Builds compact conversation context for prompts without mutating visible chat history.
/// Combines optional persistent memory summary with recent cleaned turns.
/// When a memory summary exists, only the messages *after* the summarized range
/// are included — the summary replaces the older messages, compressing the context
/// sent to the LLM (similar to Cursor's context compression).
func buildPromptContext(
    conversationId: UUID?,
    maxMessages: Int = 20,
    maxCharsPerMessage: Int = 2000,
    includeMemorySummary: Bool = true,
    maxSummaryChars: Int = 6_000
) -> String {
    guard let conv = conversation(for: conversationId) else { return "" }
    var sections: [String] = []

    var hasMemorySummary = false
    var summarizedMessageCount = 0

    if includeMemorySummary,
       let memory = conv.contextMemorySummaryMarkdown?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !memory.isEmpty {
        let cleanedMemory = ChatStore.stripCoderideMarkers(memory)
        if !cleanedMemory.isEmpty {
            let clippedMemory = cleanedMemory.count > maxSummaryChars
                ? String(cleanedMemory.prefix(maxSummaryChars)) + "…"
                : cleanedMemory
            sections.append("### Conversation memory\n\(clippedMemory)")
            hasMemorySummary = true
            summarizedMessageCount = conv.contextMemorySourceMessageCount ?? 0
        }
    }

    let messagesToInclude: ArraySlice<ChatMessage>
    if hasMemorySummary && summarizedMessageCount > 0 {
        let unsummarizedMessages = Array(conv.messages.suffix(
            max(0, conv.messages.count - summarizedMessageCount)
        ))
        messagesToInclude = unsummarizedMessages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(maxMessages)[...]
    } else {
        messagesToInclude = conv.messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(maxMessages)[...]
    }

    var lines: [String] = []
    for msg in messagesToInclude {
        let roleLabel = msg.role == .user ? "User" : "Assistant"
        let normalized = ChatStore.stripCoderideMarkers(msg.content)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { continue }
        let excerpt = normalized.count > maxCharsPerMessage
            ? String(normalized.prefix(maxCharsPerMessage)) + "…"
            : normalized
        lines.append("- \(roleLabel): \(excerpt)")
    }

    if !lines.isEmpty {
        sections.append(lines.joined(separator: "\n"))
    }

    return sections.joined(separator: "\n\n")
}
}
