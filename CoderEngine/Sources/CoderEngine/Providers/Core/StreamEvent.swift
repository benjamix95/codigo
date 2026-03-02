import Foundation

/// Events emitted during LLM response streaming
public enum StreamEvent: Sendable {
    /// Message start
    case started
    
    /// Text delta (token)
    case textDelta(String)

    /// Replace visible text entirely (resets accumulated content).
    /// Used by providers that run multi-turn loops (e.g. Codex) to move
    /// intermediate text into reasoning while keeping only the final
    /// turn's text visible.
    case textReplace(String)
    
    /// Message end
    case completed
    
    /// Error during streaming
    case error(String)
    
    /// Generic event from CLI provider (e.g. Codex JSONL)
    case raw(type: String, payload: [String: String])
}
