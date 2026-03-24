import XCTest
@testable import CoderEngine

final class OpenAISSEModelsTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - Basic Chunk

    func testDecodesTextDeltaChunk() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "choices": [{
                "index": 0,
                "delta": {"content": "Hello"},
                "finish_reason": null
            }]
        }
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.id, "chatcmpl-123")
        XCTAssertEqual(chunk.choices?.first?.delta?.content, "Hello")
        XCTAssertNil(chunk.choices?.first?.finishReason)
    }

    // MARK: - Tool Calls

    func testDecodesToolCallDelta() throws {
        let json = """
        {
            "choices": [{
                "index": 0,
                "delta": {
                    "tool_calls": [{
                        "index": 0,
                        "id": "call_abc123",
                        "function": {
                            "name": "get_weather",
                            "arguments": "{\\"city\\":"
                        }
                    }]
                },
                "finish_reason": null
            }]
        }
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        let tc = chunk.choices?.first?.delta?.toolCalls?.first
        XCTAssertEqual(tc?.id, "call_abc123")
        XCTAssertEqual(tc?.index, 0)
        XCTAssertEqual(tc?.function?.name, "get_weather")
        XCTAssertEqual(tc?.function?.arguments, "{\"city\":")
    }

    func testDecodesToolCallFinishReason() throws {
        let json = """
        {
            "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]
        }
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.choices?.first?.finishReason, "tool_calls")
    }

    // MARK: - Usage

    func testDecodesUsageWithPromptTokens() throws {
        let json = """
        {
            "choices": [],
            "usage": {"prompt_tokens": 100, "completion_tokens": 50}
        }
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.usage?.resolvedInput, 100)
        XCTAssertEqual(chunk.usage?.resolvedOutput, 50)
    }

    func testDecodesUsageWithInputTokensFallback() throws {
        let json = """
        {
            "choices": [],
            "usage": {"input_tokens": 200, "output_tokens": 75}
        }
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.usage?.resolvedInput, 200)
        XCTAssertEqual(chunk.usage?.resolvedOutput, 75)
    }

    // MARK: - Reasoning Content

    func testDecodesReasoningContent() throws {
        let json = """
        {
            "choices": [{
                "index": 0,
                "delta": {"reasoning_content": "Let me think step by step..."},
                "finish_reason": null
            }]
        }
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.choices?.first?.delta?.reasoningContent, "Let me think step by step...")
    }

    // MARK: - Error

    func testDecodesErrorChunk() throws {
        let json = """
        {
            "error": {
                "message": "Rate limit exceeded",
                "type": "rate_limit_error",
                "code": "rate_limit"
            }
        }
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.error?.message, "Rate limit exceeded")
        XCTAssertEqual(chunk.error?.type, "rate_limit_error")
        XCTAssertEqual(chunk.error?.code, "rate_limit")
    }

    // MARK: - Robustness

    func testDecodesEmptyChoicesArray() throws {
        let json = """
        {"choices": []}
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(chunk.choices?.isEmpty ?? true)
    }

    func testDecodesMinimalChunk() throws {
        let json = """
        {}
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        XCTAssertNil(chunk.id)
        XCTAssertNil(chunk.choices)
        XCTAssertNil(chunk.usage)
        XCTAssertNil(chunk.error)
    }

    func testIgnoresUnknownFields() throws {
        let json = """
        {
            "id": "test",
            "object": "chat.completion.chunk",
            "created": 1234567890,
            "model": "gpt-4",
            "choices": []
        }
        """
        let chunk = try decoder.decode(OpenAIChatChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.id, "test")
    }
}
