import XCTest
@testable import CoderEngine

final class CodexDetectorStablePathTests: XCTestCase {
    func testPreferredCodexPathPrefersStableReleaseOverAlphaBuild() {
        let selected = CodexDetector.preferredCodexPath(
            candidates: [
                "/opt/homebrew/bin/codex",
                "/Applications/Codex.app/Contents/Resources/codex",
            ],
            versionLoader: { path in
                switch path {
                case "/opt/homebrew/bin/codex":
                    return "codex-cli 0.117.0"
                case "/Applications/Codex.app/Contents/Resources/codex":
                    return "codex-cli 0.117.0-alpha.24"
                default:
                    return nil
                }
            },
            isExecutable: { _ in true }
        )

        XCTAssertEqual(selected, "/opt/homebrew/bin/codex")
    }

    func testPreferredCodexPathFallsBackToHighestKnownVersionWhenOnlyPrereleasesExist() {
        let selected = CodexDetector.preferredCodexPath(
            candidates: [
                "/tmp/codex-a",
                "/tmp/codex-b",
            ],
            versionLoader: { path in
                switch path {
                case "/tmp/codex-a":
                    return "codex-cli 0.117.0-alpha.24"
                case "/tmp/codex-b":
                    return "codex-cli 0.117.0-alpha.25"
                default:
                    return nil
                }
            },
            isExecutable: { _ in true }
        )

        XCTAssertEqual(selected, "/tmp/codex-b")
    }

    func testPreferredCodexPathSkipsVersionProbeWhenBlockingProbeIsDisabled() {
        var probedPaths: [String] = []
        let selected = CodexDetector.preferredCodexPath(
            candidates: [
                "/opt/homebrew/bin/codex",
                "/Applications/Codex.app/Contents/Resources/codex",
            ],
            versionLoader: { path in
                probedPaths.append(path)
                return "codex-cli 999.0.0"
            },
            isExecutable: { _ in true },
            allowsBlockingVersionProbe: false
        )

        XCTAssertEqual(selected, "/opt/homebrew/bin/codex")
        XCTAssertTrue(probedPaths.isEmpty)
    }
}
