import Foundation

extension ProviderToolEventMapper {
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
            if let value = input[key] {
                if let intValue = intValue(from: value) {
                    return intValue
                }
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

    static func fileChangeTitle(path: String, changeType: String) -> String {
        let base = (path as NSString).lastPathComponent
        let normalized = normalizeToolIdentifier(changeType)
        if normalized.contains("create") || normalized.contains("add") || normalized == "write_new" {
            return "Created \(base)"
        }
        if normalized.contains("delete") || normalized.contains("remove") {
            return "Deleted \(base)"
        }
        return "Edited \(base)"
    }

    static func buildDiffPreview(old: String, new: String) -> String {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)
        var out: [String] = []
        out.append("--- old")
        out.append("+++ new")
        let commonPrefixCount = zip(oldLines, newLines).prefix { $0 == $1 }.count
        let oldTail = Array(oldLines.dropFirst(commonPrefixCount))
        let newTail = Array(newLines.dropFirst(commonPrefixCount))
        for line in oldTail.prefix(80) {
            out.append("-\(line)")
        }
        for line in newTail.prefix(80) {
            out.append("+\(line)")
        }
        return out.joined(separator: "\n")
    }

    static func payloadTitle(_ payload: [String: Any], fallback: String) -> String {
        let title = firstString(in: payload, keys: ["title"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? fallback : title
    }
}
