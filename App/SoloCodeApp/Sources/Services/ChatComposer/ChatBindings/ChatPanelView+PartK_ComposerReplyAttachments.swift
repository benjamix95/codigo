import CoderEngine
import Foundation

extension ChatPanelView {
    // MARK: - Send Message
    // MARK: - Send Message (orchestrator)

    internal func quotedReplyText(for message: ChatMessage) -> String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .components(separatedBy: .newlines)
            .map { line in
                let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.isEmpty ? ">" : "> \(normalized)"
            }
            .joined(separator: "\n")
    }

    internal func beginReply(to message: ChatMessage) {
        let quoted = quotedReplyText(for: message)
        inputText = quoted.isEmpty ? "" : "\(quoted)\n\n"
        isInputFocused = true
    }

    internal func mapAttachmentKindToLLM(_ kind: ChatAttachmentKind) -> LLMAttachmentKind {
        switch kind {
        case .image: return .image
        case .document: return .document
        case .file: return .file
        }
    }

    internal func prepareRuntimeAttachmentURL(
        sourceURL: URL,
        workspaceURL: URL,
        turnId: UUID
    ) -> URL {
        let standardizedSource = sourceURL.standardizedFileURL
        let standardizedWorkspace = workspaceURL.standardizedFileURL
        let resolvedSource = standardizedSource.resolvingSymlinksInPath()
        let resolvedWorkspace = standardizedWorkspace.resolvingSymlinksInPath()
        if isURL(resolvedSource, inside: resolvedWorkspace) {
            return resolvedSource
        }

        let runtimeRoot = standardizedWorkspace
            .appendingPathComponent(".solocode_attachments", isDirectory: true)
        if pathContainsSymlink(runtimeRoot) {
            return resolvedSource
        }

        let runtimeDir = runtimeRoot
            .appendingPathComponent(turnId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

        let resolvedRuntimeDir = runtimeDir.resolvingSymlinksInPath()
        if !isURL(resolvedRuntimeDir, inside: resolvedWorkspace) {
            return resolvedSource
        }

        let ext = standardizedSource.pathExtension
        let baseName = standardizedSource.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
            .prefix(40)
        let runtimeFileName = ext.isEmpty
            ? "\(UUID().uuidString)_\(baseName)"
            : "\(UUID().uuidString)_\(baseName).\(ext)"
        let runtimeURL = runtimeDir.appendingPathComponent(String(runtimeFileName))
        if !FileManager.default.fileExists(atPath: runtimeURL.path) {
            try? FileManager.default.copyItem(at: resolvedSource, to: runtimeURL)
        }
        return runtimeURL
    }

    private func isURL(_ candidate: URL, inside directory: URL) -> Bool {
        let candidatePath = candidate.path
        let directoryPath = directory.path
        if candidatePath == directoryPath {
            return true
        }
        let normalizedDirectory = directoryPath.hasSuffix("/") ? directoryPath : "\(directoryPath)/"
        return candidatePath.hasPrefix(normalizedDirectory)
    }

    private func pathContainsSymlink(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
    }

    internal func buildAttachmentBundle(
        attachments: [ComposerAttachment],
        workspaceURL: URL,
        turnId: UUID,
        capabilities: ProviderAttachmentCapabilities
    ) -> (chat: [ChatAttachment], llm: [LLMAttachment], fallbackPreamble: String) {
        guard !attachments.isEmpty else { return ([], [], "") }

        var chatAttachments: [ChatAttachment] = []
        var llmAttachments: [LLMAttachment] = []
        var fallbackLines: [String] = []

        for item in attachments {
            let runtimeURL = prepareRuntimeAttachmentURL(
                sourceURL: item.url,
                workspaceURL: workspaceURL,
                turnId: turnId
            )
            let chatAttachment = ChatAttachment(
                kind: item.kind,
                originalName: item.originalName,
                mimeType: item.mimeType,
                localPath: item.url.path,
                sizeBytes: item.sizeBytes
            )
            chatAttachments.append(chatAttachment)
            llmAttachments.append(
                LLMAttachment(
                    kind: mapAttachmentKindToLLM(item.kind),
                    url: runtimeURL,
                    mimeType: item.mimeType,
                    filename: item.originalName,
                    sizeBytes: item.sizeBytes
                )
            )

            let isNativeSupported: Bool
            switch item.kind {
            case .image:
                isNativeSupported = capabilities.nativeImage
            case .document:
                isNativeSupported = capabilities.nativeDocument
            case .file:
                isNativeSupported = capabilities.nativeFile
            }
            if !isNativeSupported {
                let sizeText = item.sizeBytes.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? "n/a"
                fallbackLines.append(
                    "- \(item.originalName) [\(item.kind.rawValue)] path=\(runtimeURL.path) size=\(sizeText)"
                )
            }
        }

        let preamble: String
        if fallbackLines.isEmpty {
            preamble = ""
        } else {
            preamble = """
            ## Attachments available for this request
            The following files are NOT natively supported by the provider and are available via local path:
            \(fallbackLines.joined(separator: "\n"))

            Use file reading tools to analyze them if needed.
            """
        }

        return (chatAttachments, llmAttachments, preamble)
    }
}
