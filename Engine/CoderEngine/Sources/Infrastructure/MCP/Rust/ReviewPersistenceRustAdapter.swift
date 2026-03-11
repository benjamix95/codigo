import Foundation

enum ReviewPersistenceRustAdapter {
    static func encodeReviewSnapshot(_ snapshot: CodeReviewSessionSnapshot) -> Data? {
        encode(
            functionName: "review_core_persistence_encode_review_snapshot",
            value: snapshot
        )
    }

    static func decodeReviewSnapshot(from data: Data) -> CodeReviewSessionSnapshot? {
        decode(
            functionName: "review_core_persistence_decode_review_snapshot",
            payload: data,
            as: CodeReviewSessionSnapshot.self
        )
    }

    static func encodeBugHunterSnapshot(_ snapshot: MCPSharedBugHunterSnapshot) -> Data? {
        encode(
            functionName: "review_core_persistence_encode_bughunter_snapshot",
            value: snapshot
        )
    }

    static func decodeBugHunterSnapshot(from data: Data) -> MCPSharedBugHunterSnapshot? {
        decode(
            functionName: "review_core_persistence_decode_bughunter_snapshot",
            payload: data,
            as: MCPSharedBugHunterSnapshot.self
        )
    }

    static func encodeReviewCommands(_ commands: [MCPSharedCodeReviewCommand]) -> Data? {
        encode(
            functionName: "review_core_persistence_encode_review_commands",
            value: commands
        )
    }

    static func decodeReviewCommands(from data: Data) -> [MCPSharedCodeReviewCommand]? {
        decode(
            functionName: "review_core_persistence_decode_review_commands",
            payload: data,
            as: [MCPSharedCodeReviewCommand].self
        )
    }

    static func encodeBugHunterCommands(_ commands: [MCPSharedBugHunterCommand]) -> Data? {
        encode(
            functionName: "review_core_persistence_encode_bughunter_commands",
            value: commands
        )
    }

    static func decodeBugHunterCommands(from data: Data) -> [MCPSharedBugHunterCommand]? {
        decode(
            functionName: "review_core_persistence_decode_bughunter_commands",
            payload: data,
            as: [MCPSharedBugHunterCommand].self
        )
    }

    static func sqlJSONLiteral<T: Encodable>(
        functionName: String,
        value: T
    ) throws -> String {
        guard let data = encode(functionName: functionName, value: value),
              let string = String(data: data, encoding: .utf8) else {
            throw PersistenceBootstrapError.migrationFailed("Unable to encode JSON payload.")
        }
        return PersistenceSupport.sqlLiteral(string)
    }

    private static func encode<T: Encodable>(
        functionName: String,
        value: T
    ) -> Data? {
        guard let rawData = try? JSONEncoder.persistence.encode(value),
              let rawPayload = String(data: rawData, encoding: .utf8) else {
            return nil
        }
        let request = ReviewPersistencePayloadRequest(
            schemaVersion: 1,
            payload: rawPayload
        )
        guard let response: ReviewPersistencePayloadResponse = ReviewCoreBridge.call(
            functionName: functionName,
            request: request
        ),
        !response.isError,
        let payload = response.payload else {
            return rawData
        }
        return Data(payload.utf8)
    }

    private static func decode<T: Decodable>(
        functionName: String,
        payload: Data,
        as _: T.Type
    ) -> T? {
        let fallback = try? JSONDecoder.persistence.decode(T.self, from: payload)
        let request = ReviewPersistencePayloadRequest(
            schemaVersion: 1,
            payload: String(data: payload, encoding: .utf8) ?? ""
        )
        guard let response: ReviewPersistencePayloadResponse = ReviewCoreBridge.call(
            functionName: functionName,
            request: request
        ),
        !response.isError,
        let payload = response.payload else {
            return fallback
        }
        return try? JSONDecoder.persistence.decode(T.self, from: Data(payload.utf8))
    }
}

private struct ReviewPersistencePayloadRequest: Encodable {
    let schemaVersion: Int
    let payload: String
}

private struct ReviewPersistencePayloadResponse: Decodable {
    let isError: Bool
    let errorMessage: String?
    let payload: String?
}

extension JSONEncoder {
    static var persistence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var persistence: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
