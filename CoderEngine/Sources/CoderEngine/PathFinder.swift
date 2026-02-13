import Foundation

public enum PathFinder {
    public static func find(executable: String) -> String? {
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let paths = pathEnv.split(separator: ":").map(String.init)
        for dir in paths {
            let fullPath = "\(dir)/\(executable)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        for defaultPath in ["/opt/homebrew/bin/\(executable)", "/usr/local/bin/\(executable)"] {
            if FileManager.default.isExecutableFile(atPath: defaultPath) {
                return defaultPath
            }
        }
        return nil
    }
}
