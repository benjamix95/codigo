import CoderEngine
import Foundation

extension EventNormalizer {
    static func parseDebugNativeSessionPayload(
        payload: [String: String]
    ) -> DebugNativeSessionToolPayload? {
        let action = payload["action"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let adapter = payload["adapter"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "native"
        let status = NativeDebugStatus(
            rawValue: payload["status"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ) ?? .idle

        let breakpointsSpecs: [DebugNativeBreakpointSpec] = decodeJSONArray(
            payload["native_breakpoints_json"]
        ) ?? []
        let breakpoints = breakpointsSpecs.map(DebugBreakpoint.init(spec:))
        let arguments: [String] = decodeJSONArray(payload["arguments_json"]) ?? []
        let watchExpressions: [String] = decodeJSONArray(payload["watch_expressions_json"]) ?? []
        let callStack: [NativeCallStackFrame] = decodeJSONArray(payload["call_stack_json"]) ?? []
        let watchVariables: [NativeWatchVariable] = decodeJSONArray(payload["watch_variables_json"]) ?? []

        if action.isEmpty,
           payload["target_path"] == nil,
           payload["last_command"] == nil,
           payload["last_error"] == nil,
           payload["detail"] == nil {
            return nil
        }

        let state = NativeDebugSessionState(
            status: status,
            adapter: adapter,
            targetPath: payload["target_path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            breakpointsCount: Int(payload["breakpoints_count"] ?? "")
                ?? breakpoints.filter(\.isActive).count,
            callStack: callStack,
            watchVariables: watchVariables,
            lastCommand: payload["last_command"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            lastError: payload["last_error"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: Date()
        )

        return DebugNativeSessionToolPayload(
            action: action,
            detail: payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            state: state,
            breakpoints: breakpoints,
            arguments: arguments,
            watchExpressions: watchExpressions
        )
    }

    private static func decodeJSONArray<T: Decodable>(_ raw: String?) -> T? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
