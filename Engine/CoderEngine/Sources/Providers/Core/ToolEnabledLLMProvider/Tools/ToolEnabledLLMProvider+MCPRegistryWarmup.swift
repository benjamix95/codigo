import Foundation

private actor MCPNativeToolRegistryWarmupCoordinator {
    private var refreshInFlight = false

    func schedule(
        runtime: UnifiedToolRuntime,
        idleTTLSeconds: Int,
        timeoutMs: Int
    ) {
        guard !refreshInFlight else { return }
        refreshInFlight = true

        Task.detached(priority: .utility) {
            let discovered = await ToolEnabledLLMProvider.bestEffortMCPToolDiscovery(
                timeoutMs: timeoutMs
            ) {
                await runtime.mcpSessions.discoverAllTools(
                    idleTTLSeconds: idleTTLSeconds
                )
            }

            if !discovered.isEmpty {
                _ = MCPNativeToolRegistry.shared.mergeRegister(tools: discovered)
            }

            await self.finishRefresh()
        }
    }

    func finishRefresh() {
        refreshInFlight = false
    }

    func cancelAndReset() {
        refreshInFlight = false
    }
}

extension ToolEnabledLLMProvider {
    private static let mcpWarmupCoordinator = MCPNativeToolRegistryWarmupCoordinator()
    private static let primaryMCPWarmupTimeoutMs = 750
    private static let backgroundMCPWarmupTimeoutMs = 2_500
    private static let preferredMCPServerName = "coderide"

    func warmMCPNativeRegistryIfNeeded() async {
        guard policy.enableMCP else {
            MCPNativeToolRegistry.shared.clear()
            await Self.mcpWarmupCoordinator.cancelAndReset()
            return
        }

        let runtime = self.runtime
        let idleTTLSeconds = self.policy.mcpSessionIdleTTLSeconds

        if !MCPNativeToolRegistry.shared.hasTools() {
            let primaryTools = await Self.bestEffortMCPToolDiscovery(
                timeoutMs: Self.primaryMCPWarmupTimeoutMs
            ) {
                try await runtime.mcpSessions.listTools(
                    serverId: Self.preferredMCPServerName,
                    idleTTLSeconds: idleTTLSeconds
                )
            }

            if !primaryTools.isEmpty {
                _ = MCPNativeToolRegistry.shared.mergeRegister(tools: primaryTools)
            }
        }

        await Self.mcpWarmupCoordinator.schedule(
            runtime: runtime,
            idleTTLSeconds: idleTTLSeconds,
            timeoutMs: Self.backgroundMCPWarmupTimeoutMs
        )
    }

    static func bestEffortMCPToolDiscovery(
        timeoutMs: Int,
        discovery: @escaping @Sendable () async throws -> [MCPToolDescriptor]
    ) async -> [MCPToolDescriptor] {
        guard timeoutMs > 0 else {
            return (try? await discovery()) ?? []
        }

        let stream = AsyncStream<[MCPToolDescriptor]> { continuation in
            let discoveryTask = Task.detached(priority: .utility) {
                let discovered = (try? await discovery()) ?? []
                continuation.yield(discovered)
                continuation.finish()
            }

            let timeoutTask = Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                continuation.yield([])
                continuation.finish()
            }

            continuation.onTermination = { _ in
                discoveryTask.cancel()
                timeoutTask.cancel()
            }
        }

        for await discovered in stream {
            return discovered
        }
        return []
    }
}
