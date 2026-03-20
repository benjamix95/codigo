import Foundation

public extension GeminiCLIProvider {
    static func firstString(in input: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = input[key], let stringValue = stringify(value), !stringValue.isEmpty {
                return stringValue
            }
        }
        for (_, value) in input {
            if let nested = value as? [String: Any], let found = firstString(in: nested, keys: keys) {
                return found
            }
            if let list = value as? [Any] {
                for item in list {
                    if let nested = item as? [String: Any], let found = firstString(in: nested, keys: keys) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    static func firstInt(in input: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = input[key] else { continue }
            if let intValue = intValue(from: value) {
                return intValue
            }
        }
        for (_, value) in input {
            if let nested = value as? [String: Any], let found = firstInt(in: nested, keys: keys) {
                return found
            }
            if let list = value as? [Any] {
                for item in list {
                    if let nested = item as? [String: Any], let found = firstInt(in: nested, keys: keys) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    static func stringify(_ value: Any) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let arr = value as? [String] { return arr.joined(separator: "\n") }
        if let arr = value as? [[String: Any]] {
            let chunks = arr.compactMap { dict -> String? in
                if let t = dict["text"] as? String { return t }
                if let o = dict["output"] as? String { return o }
                if let c = dict["content"] as? String { return c }
                return nil
            }
            if !chunks.isEmpty { return chunks.joined(separator: "\n") }
        }
        if let dict = value as? [String: Any] {
            if let t = dict["text"] as? String { return t }
            if let o = dict["output"] as? String { return o }
            if let c = dict["content"] as? String { return c }
            if let e = dict["error"] as? String { return e }
        }
        return nil
    }

    static func intValue(from value: Any) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func fileChangeTitle(path: String, changeType: String) -> String {
        let basename = (path as NSString).lastPathComponent.isEmpty
            ? "file"
            : (path as NSString).lastPathComponent
        let normalized = changeType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("create")
            || normalized == "a"
            || normalized == "add"
            || normalized == "added"
            || normalized == "create_file"
        {
            return "Created \(basename)"
        }
        if normalized.contains("delete")
            || normalized.contains("remove")
            || normalized == "d"
            || normalized == "deleted"
        {
            return "Deleted \(basename)"
        }
        return "Edited \(basename)"
    }

    static func nonEmptyString(_ value: Any?) -> String? {
        guard let value, let text = stringify(value) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
