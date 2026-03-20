import CoderEngine
import Foundation

extension PipelineIntegrationService {
    func handleCircuitBreaker(_ p: CircuitBreakerPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.circuitBreakerActive = (p.phase == .open)
        persistSnapshot(for: conversationId)
        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: runtime.assistantMessageId,
                    turnId: runtime.chatTurnState.turnId,
                    sequence: 0,
                    source: "pipeline",
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "circuit-breaker",
                        "title": "Circuit breaker",
                        "detail": "\(p.phase.rawValue) - \(p.reason)",
                    ]
                ),
            ],
            for: conversationId
        )
    }

    func handleBackpressure(_ p: BackpressurePayload, for conversationId: UUID) {
        let status = p.active ? "active" : "cleared"
        chatStore?.setTaskStatus(
            "Backpressure \(status) (\(p.activeWorkers)/\(p.maxWorkers) workers)",
            for: conversationId
        )
    }

    func handleProviderHealth(_ p: ProviderHealthPayload, for conversationId: UUID) {
        if p.status == .unhealthy {
            let healthRuntime = runtime(for: conversationId)
            consumePipelineEvents(
                [
                    ChatPipelineEvent(
                        conversationId: conversationId,
                        assistantMessageId: healthRuntime?.assistantMessageId ?? UUID(),
                        turnId: healthRuntime?.chatTurnState.turnId ?? UUID().uuidString,
                        sequence: 0,
                        source: "pipeline",
                        kind: .statusBadge,
                        payload: [
                            "artifact_id": "provider-health-\(p.providerId)",
                            "title": "Provider unhealthy",
                            "detail": p.providerId,
                        ]
                    ),
                ],
                for: conversationId
            )
        }
    }

    func handleErrorBudget(_ p: ErrorBudgetPayload, for conversationId: UUID) {
        let budgetRuntime = runtime(for: conversationId)
        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: budgetRuntime?.assistantMessageId ?? UUID(),
                    turnId: budgetRuntime?.chatTurnState.turnId ?? UUID().uuidString,
                    sequence: 0,
                    source: "pipeline",
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "error-budget",
                        "title": "Error budget low",
                        "detail": "\(p.failedPercent)%/\(p.maxPercent)%, \(p.consecutiveFailures) consecutive failures",
                    ]
                ),
            ],
            for: conversationId
        )
    }
}
