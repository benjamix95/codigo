import Foundation

public struct ValidationSelectedTestGroup: Sendable, Equatable {
    public let id: String
    public let bundle: String
    public let onlyTesting: [String]
}

public enum TargetedTestsSelector {
    public static func select(
        files: [String],
        descriptor: ProjectValidationDescriptor
    ) -> [ValidationSelectedTestGroup] {
        let normalized = ChangeScopeAnalyzer.normalize(files)
        let groups = descriptor.testGroups.filter { group in
            normalized.contains { path in
                group.pathPrefixes.contains { path.hasPrefix($0) }
            }
        }
        if !groups.isEmpty {
            return groups.map { ValidationSelectedTestGroup(id: $0.id, bundle: $0.bundle, onlyTesting: $0.onlyTesting) }
        }

        var fallbackBundles = Set<String>()
        for path in normalized {
            if path.hasPrefix("Engine/") || path.hasPrefix("Tools/") {
                fallbackBundles.insert("CoderEngineTests")
            }
            if path.hasPrefix("App/") {
                fallbackBundles.insert("SoloCodeAppTests")
            }
        }
        if fallbackBundles.isEmpty {
            fallbackBundles = ["CoderEngineTests"]
        }
        return fallbackBundles.sorted().map {
            ValidationSelectedTestGroup(id: "fallback-\($0)", bundle: $0, onlyTesting: [$0])
        }
    }
}
