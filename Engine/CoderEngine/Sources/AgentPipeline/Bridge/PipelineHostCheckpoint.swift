import Foundation

/// Valori di `TaskNode.metadata` per task completati lato host senza turno LLM.
public enum PipelineHostCheckpoint: String, Sendable, Equatable {
    /// Preflight UI: l’utente ha già confermato reproduce (`continueInvestigation`).
    case hostReproduceAck = "host_reproduce_ack"

    public static let metadataKey = "pipeline_checkpoint"
}
