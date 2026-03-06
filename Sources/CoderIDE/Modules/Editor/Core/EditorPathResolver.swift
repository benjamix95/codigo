import Foundation

enum EditorPathResolver {
    static func relativePath(for absolutePath: String, roots: [String]) -> String? {
        let absoluteURL = URL(fileURLWithPath: absolutePath).standardizedFileURL
        for root in roots {
            let rootURL = URL(fileURLWithPath: root).standardizedFileURL
            let rootPath = rootURL.path
            let filePath = absoluteURL.path
            if filePath == rootPath {
                return absoluteURL.lastPathComponent
            }
            if filePath.hasPrefix(rootPath + "/") {
                return String(filePath.dropFirst(rootPath.count + 1))
            }
        }
        return nil
    }

    static func displayPath(_ path: String, roots: [String]) -> String {
        relativePath(for: path, roots: roots) ?? path
    }
}
