import XCTest
@testable import CoderEngine

final class AnthropicSSEModelsTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - Content Block Start

    func testDecodesContentBlockStartToolUse() throws {
        let json = """
        {
            "type": "content_block_start",
            "index": 0,
            "content_block": {
                "type": "tool_use",
                "id": "toolu_01",
                "name": "read_file",
                "input": {}
            }
        }
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.type, "content_block_start")
        XCTAssertEqual(event.index, 0)
        XCTAssertEqual(event.contentBlock?.type, "tool_use")
        XCTAssertEqual(event.contentBlock?.id, "toolu_01")
        XCTAssertEqual(event.contentBlock?.name, "read_file")
    }

    func testDecodesContentBlockStartThinking() throws {
        let json = """
        {"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.contentBlock?.type, "thinking")
    }

    // MARK: - Content Block Delta

    func testDecodesTextDelta() throws {
        let json = """
        {
            "type": "content_block_delta",
            "index": 0,
            "delta": {"type": "text_delta", "text": "Hello world"}
        }
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.type, "content_block_delta")
        XCTAssertEqual(event.delta?.type, "text_delta")
        XCTAssertEqual(event.delta?.text, "Hello world")
    }

    func testDecodesThinkingDelta() throws {
        let json = """
        {
            "type": "content_block_delta",
            "index": 0,
            "delta": {"type": "thinking_delta", "thinking": "Let me think..."}
        }
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.delta?.type, "thinking_delta")
        XCTAssertEqual(event.delta?.thinking, "Let me think...")
    }

    func testDecodesInputJsonDelta() throws {
        let json = """
        {
            "type": "content_block_delta",
            "index": 1,
            "delta": {"type": "input_json_delta", "partial_json": "{\\"path\\":"}
        }
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.delta?.type, "input_json_delta")
        XCTAssertEqual(event.delta?.partialJson, "{\"path\":")
    }

    // MARK: - Message Delta (Usage)

    func testDecodesMessageDeltaWithUsage() throws {
        let json = """
        {
            "type": "message_delta",
            "usage": {"input_tokens": 100, "output_tokens": 50}
        }
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.type, "message_delta")
        XCTAssertEqual(event.usage?.inputTokens, 100)
        XCTAssertEqual(event.usage?.outputTokens, 50)
    }

    // MARK: - Error

    func testDecodesErrorEvent() throws {
        let json = """
        {
            "type": "error",
            "error": {"type": "overloaded_error", "message": "Overloaded"}
        }
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.type, "error")
        XCTAssertEqual(event.error?.type, "overloaded_error")
        XCTAssertEqual(event.error?.message, "Overloaded")
    }

    // MARK: - AnyCodableValue

    func testAnyCodableValueDictionaryToJSON() throws {
        let json = """
        {
            "type": "content_block_start",
            "index": 0,
            "content_block": {
                "type": "tool_use",
                "id": "t1",
                "name": "edit",
                "input": {"file": "test.swift", "line": 42}
            }
        }
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        let inputStr = event.contentBlock?.input?.toJSONString()
        XCTAssertNotNil(inputStr)
        XCTAssertTrue(inputStr!.contains("test.swift"))
    }

    func testAnyCodableValueNullReturnsNil() throws {
        let json = """
        {"type": "content_block_start","index":0,"content_block":{"type":"text"}}
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertNil(event.contentBlock?.input)
    }

    // MARK: - Robustness

    func testDecodesUnknownFieldsGracefully() throws {
        let json = """
        {"type":"ping","unknown_field":"value"}
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.type, "ping")
    }

    func testDecodesMinimalEvent() throws {
        let json = """
        {"type":"message_stop"}
        """
        let event = try decoder.decode(AnthropicSSEEvent.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(event.type, "message_stop")
        XCTAssertNil(event.index)
        XCTAssertNil(event.contentBlock)
        XCTAssertNil(event.delta)
    }
}
