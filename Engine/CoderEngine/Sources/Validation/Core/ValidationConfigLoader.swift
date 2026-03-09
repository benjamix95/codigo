import Foundation

public enum ValidationConfigLoader {
    public static let relativePath = "Config/validation/solocode-validation.json"

    public static func load(workspaceRoot: URL) throws -> ProjectValidationDescriptor {
        let url = workspaceRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProjectValidationDescriptor.self, from: data)
    }
}
