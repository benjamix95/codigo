import Foundation

/// Events emitted during LLM response streaming
public enum StreamEvent: Sendable {
    /// Message start
    case started
    
    /// Text delta (token)
    case textDelta(String)
    
    /// Message end
    case completed
    
    /// Error during streaming
    case error(String)
    
    /// Generic event from CLI provider (e.g. Codex JSONL)
    case raw(type: String, payload: [String: String])
}
