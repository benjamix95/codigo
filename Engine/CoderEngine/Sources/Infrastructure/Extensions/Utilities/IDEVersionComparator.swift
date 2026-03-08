import Foundation

public enum IDEVersionComparator {
    public static func satisfies(minimum requiredVersion: String, current currentVersion: String) -> Bool? {
        guard
            let required = parse(requiredVersion),
            let current = parse(currentVersion)
        else {
            return nil
        }
        return compare(current, required) != .orderedAscending
    }

    public static func compare(_ lhsVersion: String, _ rhsVersion: String) -> ComparisonResult? {
        guard
            let lhs = parse(lhsVersion),
            let rhs = parse(rhsVersion)
        else {
            return nil
        }
        return compare(lhs, rhs)
    }

    private static func parse(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else {
            return nil
        }

        var parsed: [Int] = []
        parsed.reserveCapacity(components.count)
        for component in components {
            guard !component.isEmpty else {
                return nil
            }
            guard let value = Int(component), value >= 0 else {
                return nil
            }
            parsed.append(value)
        }
        return parsed
    }

    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let maxCount = max(lhs.count, rhs.count)
        for index in 0..<maxCount {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }
}
