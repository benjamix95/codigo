import Foundation
import XCTest
@testable import CoderEngine

extension CodexCLIProviderStreamParsingTests {
    func runParser(events input: [[String: Any]]) -> [StreamEvent] {
        var state = CodexCLIProvider.CodexStreamParserState()
        var out: [StreamEvent] = []
        for json in input {
            out.append(contentsOf: CodexCLIProvider.parseStreamJSONEvent(json, state: &state))
        }
        out.append(contentsOf: CodexCLIProvider.finalizeStreamJSONState(state: &state))
        return out
    }

    func runGit(_ args: [String], cwd: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            return
        }
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(
            domain: "CodexCLIProviderStreamParsingTests",
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed: \(out) \(err)"
            ]
        )
    }
}
