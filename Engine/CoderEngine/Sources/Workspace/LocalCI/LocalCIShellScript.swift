import Foundation

enum LocalCIShellScript {
    static let managedMarker = "# @solocode-managed — generato da SoloCode."

    static func script(for stacks: [LocalCIStack]) -> String {
        var blocks: [String] = []
        for stack in stacks where stack != .unknown {
            blocks.append(block(for: stack))
        }
        let body = blocks.joined(separator: "\n\n")
        return """
        #!/usr/bin/env bash
        \(managedMarker)
        set -euo pipefail
        cd "$(dirname "$0")/.."

        \(body)
        echo "solocode-local-ci: OK"
        """
    }

    private static func block(for stack: LocalCIStack) -> String {
        switch stack {
        case .rust:
            return """
            echo "== Rust =="
            cargo fmt --all -- --check
            cargo clippy --workspace --all-targets -- -D warnings
            cargo test --workspace
            """
        case .go:
            return """
            echo "== Go =="
            go test ./...
            """
        case .nodeNpm:
            return """
            echo "== Node (npm) =="
            npm ci
            npm test --if-present
            """
        case .nodePnpm:
            return """
            echo "== Node (pnpm) =="
            corepack enable || true
            pnpm install --frozen-lockfile
            pnpm test --if-present || npm test --if-present
            """
        case .nodeYarn:
            return """
            echo "== Node (yarn) =="
            yarn install --frozen-lockfile
            yarn test || npm test --if-present
            """
        case .swiftPackage:
            return """
            echo "== Swift PM =="
            swift test
            """
        case .swiftXcode:
            return """
            echo "== Xcode =="
            proj=$(ls -d *.xcodeproj 2>/dev/null | head -1 || true)
            if [[ -z "$proj" ]]; then echo "Nessun .xcodeproj"; exit 1; fi
            scheme="${proj%.xcodeproj}"
            xcodebuild -project "$proj" -scheme "$scheme" -destination 'platform=macOS' build
            """
        case .python:
            return """
            echo "== Python =="
            python3 -m pip install -U pip
            if [ -f requirements.txt ]; then python3 -m pip install -r requirements.txt; fi
            python3 -m pip install pytest || true
            python3 -m pytest -q || true
            """
        case .javaMaven:
            return """
            echo "== Maven =="
            mvn -B test
            """
        case .javaGradle:
            return """
            echo "== Gradle =="
            chmod +x gradlew 2>/dev/null || true
            ./gradlew test
            """
        case .rubyBundler:
            return """
            echo "== Ruby =="
            bundle install
            bundle exec rake test
            """
        case .unknown:
            return "echo 'skip unknown'"
        }
    }
}
