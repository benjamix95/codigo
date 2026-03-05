import Foundation

/// System prompt for each role
private func systemPrompt(for role: AgentRole) -> String {
    switch role {
    case .planner:
        return "You are the Planner. Analyze the request and produce a structured plan with clear steps. Do not write code."
    case .explorer:
        return "You are the Explorer. Analyze the codebase, search for relevant context, navigate symbols and dependencies. Report findings without modifying files."
    case .coder:
        return "You are the Coder. Execute code changes according to the plan. Use the available tools (edit file, run command, etc)."
    case .debugger:
        return "You are the Debugger. Identify bugs, analyze stack traces and resolve issues. Modify code to fix them."
    case .reviewer:
        return "You are the Reviewer. Review for bugs, regressions, logic errors and risks. Do NOT auto-fix. Report concrete findings with file paths and line numbers."
    case .docWriter:
        return "You are the DocWriter. Write clear documentation: README, comments, docstrings. Keep consistency with the code."
    case .securityAuditor:
        return "You are the SecurityAuditor. Analyze the code for vulnerabilities, insecure dependencies, and sensitive data exposure."
    case .testWriter:
        return """
        You are the TestWriter. Write tests for the modified code.
        - Swift: use XCTest, create files in Tests/<Target>Tests/ with naming *Tests.swift
        - Node: use Jest or Vitest, file *.test.ts or __tests__/*.ts
        - Python: use pytest, file test_*.py
        Include: unit tests (isolated functions), smoke tests (startup/base components work), integration tests (components together) where appropriate.
        Cover main cases and edge cases.
        """
    }
}

/// Runs the workers for each task in the plan, using any LLMProvider
public struct SwarmWorkerRunner: Sendable {
    private let provider: any LLMProvider
    private let isCancelled: (@Sendable () -> Bool)?

    public init(provider: any LLMProvider, isCancelled: (@Sendable () -> Bool)? = nil) {
        self.provider = provider
        self.isCancelled = isCancelled
    }

    /// Runs tasks; tasks with the same order are executed in parallel
    public func run(tasks: [AgentTask], context: WorkspaceContext, imageURLs: [URL]? = nil) -> AsyncThrowingStream<StreamEvent, Error> {
        let checkCancelled = isCancelled
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(.started)
                    let sortedTasks = tasks.sorted(by: { $0.order < $1.order })
                    let stepNames = sortedTasks.map { $0.role.displayName }.joined(separator: ",")
                    continuation.yield(.raw(type: "swarm_steps", payload: ["steps": stepNames]))
                    var accumulatedOutput = ""

                    let orderGroups = Dictionary(grouping: sortedTasks, by: { $0.order }).sorted(by: { $0.key < $1.key })
                    var isFirstTask = true

                    for (_, groupTasks) in orderGroups {
                        if checkCancelled?() == true {
                            continuation.yield(.textDelta("\n\n[Swarm interrupted by user.]\n"))
                            break
                        }
                        if groupTasks.count == 1 {
                            let task = groupTasks[0]
                            let header = "\n## \(task.role.displayName)\n\n"
                            continuation.yield(.textDelta(header))
                            continuation.yield(.raw(type: "agent", payload: swarmPayload(for: task, detail: "started")))
                            let taskImageURLs = isFirstTask && !(imageURLs?.isEmpty ?? true) ? imageURLs : nil
                            let output = try await runSingleTask(task, context: context, imageURLs: taskImageURLs, previousOutputs: accumulatedOutput, provider: provider, continuation: continuation)
                            continuation.yield(.raw(type: "agent", payload: swarmPayload(for: task, detail: "completed")))
                            accumulatedOutput += output + "\n"
                        } else {
                            continuation.yield(.textDelta("\n## Parallelo: \(groupTasks.map { $0.role.displayName }.joined(separator: ", "))\n\n"))
                            for t in groupTasks { continuation.yield(.raw(type: "agent", payload: swarmPayload(for: t, detail: "started"))) }
                            var groupOutputs: [(String, String)] = []
                            let maxParallelWorkers = 3
                            for chunkStart in stride(from: 0, to: groupTasks.count, by: maxParallelWorkers) {
                                let chunkEnd = min(chunkStart + maxParallelWorkers, groupTasks.count)
                                let chunkTasks = Array(groupTasks[chunkStart..<chunkEnd])
                                await withTaskGroup(of: (String, String).self) { g in
                                    for (chunkIdx, task) in chunkTasks.enumerated() {
                                        g.addTask {
                                            if checkCancelled?() == true {
                                                return (task.role.rawValue, "\n### \(task.role.displayName)\n\n[Interrupted by user]\n")
                                            }
                                            let header = "\n### \(task.role.displayName)\n\n"
                                            let prompt = self.buildPrompt(for: task, previousOutputs: accumulatedOutput)
                                            let globalIdx = chunkStart + chunkIdx
                                            let taskImageURLs = (isFirstTask && globalIdx == 0 && !(imageURLs?.isEmpty ?? true)) ? imageURLs : nil
                                            var out = header
                                            do {
                                                let stream = try await self.provider.send(prompt: prompt, context: context, imageURLs: taskImageURLs)
                                                for try await event in stream {
                                                    if case .textDelta(let d) = event { out += d }
                                                    if case .error(let e) = event {
                                                        out += "\n[Errore \(task.role.displayName): \(e)]\n"
                                                    }
                                                    if case .raw(let type, let payload) = event {
                                                        continuation.yield(.raw(type: type, payload: self.enrichSwarmPayload(payload, for: task)))
                                                    }
                                                }
                                            } catch {
                                                out += "\n[Errore \(task.role.displayName): \(error.localizedDescription)]\n"
                                            }
                                            return (task.role.rawValue, out)
                                        }
                                    }
                                    for await res in g { groupOutputs.append(res) }
                                }
                                if checkCancelled?() == true { break }
                            }
                            for t in groupTasks { continuation.yield(.raw(type: "agent", payload: swarmPayload(for: t, detail: "completed"))) }
                            let merged = groupOutputs.sorted(by: { $0.0 < $1.0 }).map(\.1).joined(separator: "\n")
                            continuation.yield(.textDelta(merged))
                            accumulatedOutput += merged + "\n"
                        }
                        if checkCancelled?() == true {
                            continuation.yield(.textDelta("\n\n[Swarm interrupted during parallel execution.]\n"))
                            break
                        }
                        isFirstTask = false
                    }

                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runSingleTask(_ task: AgentTask, context: WorkspaceContext, imageURLs: [URL]?, previousOutputs: String, provider: any LLMProvider, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws -> String {
        let header = "\n## \(task.role.displayName)\n\n"
        let prompt = buildPrompt(for: task, previousOutputs: previousOutputs)
        var taskOutput = header
        let stream = try await provider.send(prompt: prompt, context: context, imageURLs: imageURLs)
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                continuation.yield(.textDelta(delta))
                taskOutput += delta
            case .error(let err):
                let e = "\n[Errore \(task.role.displayName): \(err)]\n"
                continuation.yield(.textDelta(e))
                taskOutput += e
            case .raw(let type, let payload):
                continuation.yield(.raw(type: type, payload: enrichSwarmPayload(payload, for: task)))
            default: break
            }
        }
        return taskOutput
    }

    private func swarmPayload(for task: AgentTask, detail: String) -> [String: String] {
        [
            "title": task.role.displayName,
            "detail": detail,
            "swarm_id": task.role.rawValue,
            "group_id": "swarm-\(task.role.rawValue)"
        ]
    }

    private func enrichSwarmPayload(_ payload: [String: String], for task: AgentTask) -> [String: String] {
        var enriched = payload
        enriched["swarm_id"] = task.role.rawValue
        if enriched["group_id"] == nil {
            enriched["group_id"] = "swarm-\(task.role.rawValue)"
        }
        if (enriched["title"] ?? "").isEmpty {
            enriched["title"] = task.role.displayName
        }
        return enriched
    }

    private func buildPrompt(for task: AgentTask, previousOutputs: String) -> String {
        var parts: [String] = []
        parts.append(systemPrompt(for: task.role))
        parts.append("\n**Task:** \(task.taskDescription)")
        if !previousOutputs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("\n**Output from previous agents:**\n\(previousOutputs)")
        }
        parts.append("\nExecute the task. Respond and act in the workspace.")
        parts.append("\nIf you want to show the user the tasks panel, use the `show_task_panel` tool.")

        parts.append("""

        **Sub-agent policy:** use sub-agent/Task tool/parallel execution only when the task
        really requires independent workstreams or distinct specialist roles.
        Do not start sub-agents for linear or short operations you can complete directly.
        Follow instructions in AGENTS.md / CLAUDE.md if present in the workspace.
        """)
        return parts.joined()
    }
}
