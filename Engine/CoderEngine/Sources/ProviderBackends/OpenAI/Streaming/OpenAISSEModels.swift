import Foundation

// MARK: - Chat Completion Chunk (SSE)

/// Modello Codable per gli eventi SSE della OpenAI Chat Completions API.
struct OpenAIChatChunk: Decodable {
    let id: String?
    let choices: [OpenAIChunkChoice]?
    let usage: OpenAIChunkUsage?
    let error: OpenAIChunkError?
}

// MARK: - Choice

struct OpenAIChunkChoice: Decodable {
    let index: Int?
    let delta: OpenAIChunkDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

// MARK: - Delta

struct OpenAIChunkDelta: Decodable {
    let role: String?
    let content: String?
    let reasoningContent: String?
    let toolCalls: [OpenAIChunkToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}

// MARK: - Tool Call

struct OpenAIChunkToolCall: Decodable {
    let index: Int?
    let id: String?
    let function: OpenAIChunkFunction?
}

struct OpenAIChunkFunction: Decodable {
    let name: String?
    let arguments: String?
}

// MARK: - Usage

struct OpenAIChunkUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    var resolvedInput: Int? {
        promptTokens ?? inputTokens
    }

    var resolvedOutput: Int? {
        completionTokens ?? outputTokens
    }
}

// MARK: - Error

struct OpenAIChunkError: Decodable {
    let message: String?
    let type: String?
    let code: String?
}
