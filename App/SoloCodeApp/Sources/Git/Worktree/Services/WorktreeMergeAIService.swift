import CoderEngine
import Foundation

struct WorktreeQualityGateReport: Equatable {
    let attempts: Int
    let testCommandDescription: String
    let lastOutput: String
}

struct WorktreeConflictResolutionReport: Equatable {
    let resolved: Bool
    let notes: String
    let qualityGate: WorktreeQualityGateReport
}

enum WorktreeMergeAIServiceError: LocalizedError {
    case providerUnavailable
    case testCommandUnavailable(String)
    case automaticTestExecutionBlocked
    case qualityGateFailed(String)
    case conflictResolutionFailed(String)
    case runtimeFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "Nessun provider agent compatibile autenticato disponibile per il merge assistito."
        case .testCommandUnavailable(let path):
            return "Impossibile rilevare un comando test standard in \(path)."
        case .automaticTestExecutionBlocked:
            return "Esecuzione automatica dei test bloccata per sicurezza: esegui i test manualmente prima del merge."
        case .qualityGateFailed(let output):
            return "Quality gate fallito: \(output)"
        case .conflictResolutionFailed(let details):
            return "Conflitti non risolti automaticamente: \(details)"
        case .runtimeFailed(let details):
            return "Esecuzione provider fallita: \(details)"
        }
    }
}

@MainActor
class WorktreeMergeAIService {
    typealias ProcessRunner = (
        _ executable: String,
        _ arguments: [String],
        _ cwd: String
    ) async -> (status: Int32, stdout: String, stderr: String)

    typealias PromptRunner = (
        _ provider: any LLMProvider,
        _ gitRoot: String,
        _ prompt: String
    ) async throws -> String

    private let gitService = GitService()
    private let processRunner: ProcessRunner?
    private let promptRunner: PromptRunner?

    init(
        processRunner: ProcessRunner? = nil,
        promptRunner: PromptRunner? = nil
    ) {
        self.processRunner = processRunner
        self.promptRunner = promptRunner
    }

    func resolveConflictsAndFixTests(
        gitRoot: String,
        sourceBranch: String,
        targetBranch: String,
        conflictedFiles: [String],
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry,
        maxFixRounds: Int = 3
    ) async throws -> WorktreeConflictResolutionReport {
        let provider = try resolveProvider(
            preferredProviderId: preferredProviderId,
            providerRegistry: providerRegistry
        )
        let prompt = conflictResolutionPrompt(
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            conflictedFiles: conflictedFiles
        )
        _ = try await runHeadlessPrompt(
            provider: provider,
            gitRoot: gitRoot,
            prompt: prompt
        )

        let remaining = try gitService.listConflictedFiles(gitRoot: gitRoot)
        guard remaining.isEmpty else {
            throw WorktreeMergeAIServiceError.conflictResolutionFailed(
                remaining.joined(separator: ", ")
            )
        }

        let quality = try await enforceQualityGate(
            gitRoot: gitRoot,
            stage: "post-merge",
            preferredProviderId: preferredProviderId,
            providerRegistry: providerRegistry,
            maxAttempts: maxFixRounds
        )
        return WorktreeConflictResolutionReport(
            resolved: true,
            notes: "Conflitti risolti con analisi semantica e test verdi.",
            qualityGate: quality
        )
    }

    func enforceQualityGate(
        gitRoot: String,
        stage: String,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry,
        maxAttempts: Int = 3
    ) async throws -> WorktreeQualityGateReport {
        guard processRunner != nil else {
            throw WorktreeMergeAIServiceError.automaticTestExecutionBlocked
        }

        guard let cmd = TestProjectDetector.testCommand(
            workspacePath: URL(fileURLWithPath: gitRoot)
        ) else {
            throw WorktreeMergeAIServiceError.testCommandUnavailable(gitRoot)
        }

        let provider = try resolveProvider(
            preferredProviderId: preferredProviderId,
            providerRegistry: providerRegistry
        )

        var lastOutput = ""
        for attempt in 1...max(1, maxAttempts) {
            let testResult = await runProcess(
                executable: cmd.executable,
                arguments: cmd.arguments,
                cwd: gitRoot
            )
            let output = mergedOutput(stdout: testResult.stdout, stderr: testResult.stderr)
            lastOutput = output
            if testResult.status == 0 {
                return WorktreeQualityGateReport(
                    attempts: attempt,
                    testCommandDescription: ([cmd.executable] + cmd.arguments).joined(separator: " "),
                    lastOutput: output
                )
            }

            if attempt == maxAttempts {
                break
            }

            let prompt = qualityFixPrompt(
                stage: stage,
                commandDescription: ([cmd.executable] + cmd.arguments).joined(separator: " "),
                failedOutput: output,
                attempt: attempt + 1,
                maxAttempts: maxAttempts
            )
            _ = try await runHeadlessPrompt(
                provider: provider,
                gitRoot: gitRoot,
                prompt: prompt
            )
        }

        throw WorktreeMergeAIServiceError.qualityGateFailed(lastOutput)
    }
}

extension WorktreeMergeAIService {
    func resolveProvider(
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry
    ) throws -> any LLMProvider {
        if let preferredProviderId,
           ProviderSupport.isAgentCompatibleProvider(id: preferredProviderId),
           let preferredProvider = providerRegistry.provider(for: preferredProviderId),
           preferredProvider.isAuthenticated()
        {
            return preferredProvider
        }

        if let bootstrapId = ProviderSupport.firstHealthyAgentProviderId(
            preferred: preferredProviderId,
            registry: providerRegistry
        ),
           let bootstrapProvider = providerRegistry.provider(for: bootstrapId),
           bootstrapProvider.isAuthenticated()
        {
            return bootstrapProvider
        }
        throw WorktreeMergeAIServiceError.providerUnavailable
    }

    func runHeadlessPrompt(
        provider: any LLMProvider,
        gitRoot: String,
        prompt: String
    ) async throws -> String {
        if let promptRunner {
            return try await promptRunner(provider, gitRoot, prompt)
        }
        var accumulatedText = ""
        do {
            let stream = try await provider.send(
                prompt: prompt,
                context: WorkspaceContext(
                    workspacePaths: [URL(fileURLWithPath: gitRoot)],
                    openFiles: []
                ),
                attachments: nil
            )
            for try await event in stream {
                switch event {
                case .started:
                    break
                case .textDelta(let text):
                    accumulatedText += text
                case .textReplace(let text):
                    accumulatedText = text
                case .raw:
                    break
                case .completed:
                    return accumulatedText
                case .error(let message):
                    let detail = mergedOutput(stdout: accumulatedText, stderr: message)
                    throw WorktreeMergeAIServiceError.runtimeFailed(detail)
                }
            }
            return accumulatedText
        } catch let error as WorktreeMergeAIServiceError {
            throw error
        } catch {
            let detail = mergedOutput(stdout: accumulatedText, stderr: error.localizedDescription)
            throw WorktreeMergeAIServiceError.runtimeFailed(detail)
        }
    }

    func runProcess(
        executable: String,
        arguments: [String],
        cwd: String
    ) async -> (status: Int32, stdout: String, stderr: String) {
        if let processRunner {
            return await processRunner(executable, arguments, cwd)
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                    process.waitUntilExit()
                    let stdout = String(
                        data: out.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    let stderr = String(
                        data: err.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    continuation.resume(
                        returning: (process.terminationStatus, stdout, stderr)
                    )
                } catch {
                    continuation.resume(
                        returning: (
                            1,
                            "",
                            "Errore esecuzione comando: \(error.localizedDescription)"
                        )
                    )
                }
            }
        }
    }

    func mergedOutput(stdout: String, stderr: String) -> String {
        let value = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return value.isEmpty ? "Nessun output disponibile." : value
    }
}
