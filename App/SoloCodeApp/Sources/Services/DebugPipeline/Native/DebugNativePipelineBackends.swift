import CoderEngine
import Foundation

protocol DebugNativePipelineBackend: Sendable {
    func canRun(
        context: DebugNativePipelineTaskContext,
        provider: any LLMProvider
    ) async -> Bool

    func perform(
        context: DebugNativePipelineTaskContext,
        provider: any LLMProvider
    ) async -> DebugNativeBackendOutcome
}

struct DebugNativePipelineAdapter {
    let backends: [any DebugNativePipelineBackend]

    func execute(
        context: DebugNativePipelineTaskContext,
        provider: any LLMProvider
    ) async -> DebugNativeBackendOutcome {
        struct Indexed: Sendable {
            let index: Int
            let outcome: DebugNativeBackendOutcome
        }

        let indexedOutcomes: [Indexed] = await withTaskGroup(of: Indexed.self) { group in
            for (idx, backend) in backends.enumerated() {
                group.addTask {
                    let can = await backend.canRun(context: context, provider: provider)
                    guard can else {
                        return Indexed(index: idx, outcome: DebugNativeBackendOutcome())
                    }
                    let outcome = await backend.perform(context: context, provider: provider)
                    return Indexed(index: idx, outcome: outcome)
                }
            }
            var collected: [Indexed] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        var merged = DebugNativeBackendOutcome()
        for item in indexedOutcomes.sorted(by: { $0.index < $1.index }) {
            if let state = item.outcome.state {
                merged.state = state
            }
            merged.logs.append(contentsOf: item.outcome.logs)
        }

        if merged.state == nil {
            merged.state = makeErrorState(
                context: context,
                message: "Nessun backend native disponibile per lo stage \(context.stage.rawValue)."
            )
        }

        return merged
    }

    private func makeErrorState(
        context: DebugNativePipelineTaskContext,
        message: String
    ) -> NativeDebugSessionState {
        NativeDebugSessionState(
            status: .error,
            adapter: "debug-native-adapter",
            targetPath: context.targetPath,
            breakpointsCount: context.breakpoints.filter(\.isActive).count,
            callStack: [],
            watchVariables: [],
            lastCommand: context.stage.rawValue,
            lastError: message,
            updatedAt: Date()
        )
    }
}

struct DebugNativeLLDBBackend: DebugNativePipelineBackend {
    let debugService: DebugService

    func canRun(
        context: DebugNativePipelineTaskContext,
        provider _: any LLMProvider
    ) async -> Bool {
        context.backendPolicy != .mcpOnly
    }

    func perform(
        context: DebugNativePipelineTaskContext,
        provider _: any LLMProvider
    ) async -> DebugNativeBackendOutcome {
        let state: NativeDebugSessionState
        switch context.stage {
        case .nativeStart:
            guard let targetPath = context.targetPath, !targetPath.isEmpty else {
                state = NativeDebugSessionState(
                    status: .error,
                    adapter: "lldb-dap",
                    targetPath: nil,
                    breakpointsCount: context.breakpoints.filter(\.isActive).count,
                    callStack: [],
                    watchVariables: [],
                    lastCommand: context.stage.rawValue,
                    lastError: "Target debug non disponibile.",
                    updatedAt: Date()
                )
                return DebugNativeBackendOutcome(state: state)
            }
            state = await debugService.startSession(
                targetPath: targetPath,
                arguments: context.arguments,
                breakpoints: context.debugBreakpoints,
                watchExpressions: context.watchExpressions
            )
        case .nativeRefresh:
            state = await debugService.refresh()
        case .nativeSyncBreakpoints:
            let breakpointState = await debugService.syncBreakpoints(context.debugBreakpoints)
            if context.watchExpressions.isEmpty {
                state = breakpointState
            } else {
                state = await debugService.syncWatches(context.watchExpressions)
            }
        case .nativeSyncWatches:
            state = await debugService.syncWatches(context.watchExpressions)
        case .nativeStepIn:
            state = await debugService.stepIn()
        case .nativeStepOver:
            state = await debugService.stepOver()
        case .nativeStepOut:
            state = await debugService.stepOut()
        case .nativeStop:
            state = await debugService.stopSession()
        default:
            state = await debugService.snapshot()
        }

        return DebugNativeBackendOutcome(state: state)
    }
}

struct DebugNativeXcodeBuildMCPBackend: DebugNativePipelineBackend {
    private let serverId = "user-XcodeBuildMCP"

    func canRun(
        context: DebugNativePipelineTaskContext,
        provider: any LLMProvider
    ) async -> Bool {
        guard context.backendPolicy == .appleHybrid else {
            return false
        }
        guard provider is ToolEnabledLLMProvider else {
            return false
        }
        switch context.stage {
        case .nativeStart, .nativeStop:
            return true
        default:
            return false
        }
    }

    func perform(
        context: DebugNativePipelineTaskContext,
        provider: any LLMProvider
    ) async -> DebugNativeBackendOutcome {
        guard let provider = provider as? ToolEnabledLLMProvider else {
            return DebugNativeBackendOutcome()
        }

        var logs: [DebugNativeBackendLog] = []
        logs.append(contentsOf: await sessionDefaultsLogs(using: provider))

        switch context.stage {
        case .nativeStart:
            logs.append(contentsOf: await callLogs(
                provider: provider,
                toolName: "start_sim_log_cap",
                arguments: [
                    "captureConsole": true,
                    "subsystemFilter": "app",
                ],
                successMessage: "XcodeBuildMCP log capture avviato.",
                failureMessage: "Impossibile avviare la cattura log simulator."
            ))
        case .nativeStop:
            logs.append(contentsOf: await callLogs(
                provider: provider,
                toolName: "stop_sim_log_cap",
                arguments: [:],
                successMessage: "XcodeBuildMCP log capture fermato.",
                failureMessage: "Impossibile fermare la cattura log simulator."
            ))
        default:
            break
        }

        return DebugNativeBackendOutcome(logs: logs)
    }

    private func sessionDefaultsLogs(
        using provider: ToolEnabledLLMProvider
    ) async -> [DebugNativeBackendLog] {
        await callLogs(
            provider: provider,
            toolName: "session_show_defaults",
            arguments: [:],
            successMessage: "Session defaults XcodeBuildMCP caricati.",
            failureMessage: "Impossibile leggere i defaults di XcodeBuildMCP."
        )
    }

    private func callLogs(
        provider: ToolEnabledLLMProvider,
        toolName: String,
        arguments: [String: Any],
        successMessage: String,
        failureMessage: String
    ) async -> [DebugNativeBackendLog] {
        do {
            let result = try await provider.callMCPTool(
                serverId: serverId,
                toolName: toolName,
                arguments: arguments,
                timeoutMs: 30_000
            )
            let message = result.isError ? failureMessage : successMessage
            let severity: DebugEntrySeverity = result.isError ? .warning : .info
            let detail = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return [DebugNativeBackendLog(
                severity: severity,
                source: "xcodebuildmcp/\(toolName)",
                message: message,
                detail: detail.isEmpty ? nil : detail,
                category: "native"
            )]
        } catch {
            return [DebugNativeBackendLog(
                severity: .warning,
                source: "xcodebuildmcp/\(toolName)",
                message: failureMessage,
                detail: error.localizedDescription,
                category: "native"
            )]
        }
    }
}
