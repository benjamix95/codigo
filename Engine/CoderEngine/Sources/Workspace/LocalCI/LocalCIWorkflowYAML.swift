import Foundation

/// Genera un workflow GitHub Actions minimale e corretto per i linguaggi rilevati.
enum LocalCIWorkflowYAML {
    static let managedMarker = "# @solocode-managed — generato da SoloCode; modifica liberamente il contenuto operativo."

    static func document(for stacks: [LocalCIStack], projectLabel: String) -> String {
        var jobs: [String] = []
        var idx = 0
        for stack in stacks where stack != .unknown {
            idx += 1
            let (name, steps) = jobBody(for: stack)
            let key = "job-\(idx)-\(stack.rawValue.replacingOccurrences(of: ".", with: "-"))"
            jobs.append(
                """
                  \(key):
                    name: \(name)
                    runs-on: \(runsOn(for: stack))
                    steps:
                \(steps)
                """
            )
        }

        let jobsBlock = jobs.joined(separator: "\n")
        let onBlock = """
        on:
          push:
            branches: [ main, master, develop ]
          pull_request:
          workflow_dispatch:
        """

        return """
        \(managedMarker)
        # CI automatica suggerita per: \(projectLabel)
        # Esegui in locale: scripts/solocode-run-local-ci.sh
        name: SoloCode auto CI

        \(onBlock)
        permissions:
          contents: read

        concurrency:
          group: auto-ci-${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
          cancel-in-progress: true

        jobs:
        \(jobsBlock)
        """
    }

    private static func runsOn(for stack: LocalCIStack) -> String {
        switch stack {
        case .swiftPackage, .swiftXcode:
            return "macos-latest"
        default:
            return "ubuntu-latest"
        }
    }

    private static func jobBody(for stack: LocalCIStack) -> (String, String) {
        switch stack {
        case .rust:
            return ("Rust", rustSteps)
        case .go:
            return ("Go", goSteps)
        case .nodeNpm, .nodePnpm, .nodeYarn:
            return ("Node.js", nodeSteps(stack))
        case .swiftPackage:
            return ("Swift PM", swiftPMSteps)
        case .swiftXcode:
            return ("Xcode", swiftXcodeSteps)
        case .python:
            return ("Python", pythonSteps)
        case .javaMaven:
            return ("Maven", mavenSteps)
        case .javaGradle:
            return ("Gradle", gradleSteps)
        case .rubyBundler:
            return ("Ruby", rubySteps)
        case .unknown:
            return ("Unknown", "      - run: echo 'unknown'\n")
        }
    }

    private static var rustSteps: String {
        """
              - uses: actions/checkout@v4
              - uses: dtolnay/rust-toolchain@stable
              - name: fmt
                run: cargo fmt --all -- --check
              - name: clippy
                run: cargo clippy --workspace --all-targets -- -D warnings
              - name: test
                run: cargo test --workspace
        """
    }

    private static var goSteps: String {
        """
              - uses: actions/checkout@v4
              - uses: actions/setup-go@v5
                with:
                  go-version: 'stable'
              - name: test
                run: go test ./...
        """
    }

    private static func nodeSteps(_ stack: LocalCIStack) -> String {
        let install: String
        switch stack {
        case .nodePnpm:
            install = """
                  - uses: pnpm/action-setup@v4
                    with:
                      version: 9
                  - uses: actions/setup-node@v4
                    with:
                      node-version: '20'
                      cache: 'pnpm'
                  - name: install
                    run: pnpm install --frozen-lockfile
            """
        case .nodeYarn:
            install = """
                  - uses: actions/setup-node@v4
                    with:
                      node-version: '20'
                      cache: 'yarn'
                  - name: install
                    run: yarn install --frozen-lockfile
            """
        default:
            install = """
                  - uses: actions/setup-node@v4
                    with:
                      node-version: '20'
                      cache: 'npm'
                  - name: install
                    run: npm ci
            """
        }
        let testRun: String
        switch stack {
        case .nodePnpm:
            testRun = "pnpm test --if-present"
        case .nodeYarn:
            testRun = "yarn test --if-present"
        default:
            testRun = "npm test --if-present"
        }
        return """
              - uses: actions/checkout@v4
        \(install)
              - name: test
                run: \(testRun)
        """
    }

    private static var swiftPMSteps: String {
        """
              - uses: actions/checkout@v4
              - name: Swift PM
                run: swift test
        """
    }

    private static var swiftXcodeSteps: String {
        """
              - uses: actions/checkout@v4
              - uses: maxim-lobanov/setup-xcode@v1
                with:
                  xcode-version: latest-stable
              - name: Build (schema = nome .xcodeproj)
                run: |
                  set -euo pipefail
                  proj=$(ls -d *.xcodeproj 2>/dev/null | head -1 || true)
                  if [[ -z "$proj" ]]; then echo "Nessun .xcodeproj in root"; exit 1; fi
                  scheme="${proj%.xcodeproj}"
                  xcodebuild -project "$proj" -scheme "$scheme" -destination 'platform=macOS' build
        """
    }

    private static var pythonSteps: String {
        """
              - uses: actions/checkout@v4
              - uses: actions/setup-python@v5
                with:
                  python-version: '3.x'
              - name: pip
                run: |
                  python -m pip install -U pip
                  if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
              - name: pytest
                run: |
                  pip install pytest || true
                  pytest -q || python -m pytest -q
        """
    }

    private static var mavenSteps: String {
        """
              - uses: actions/checkout@v4
              - uses: actions/setup-java@v4
                with:
                  distribution: 'temurin'
                  java-version: '17'
              - name: test
                run: mvn -B test
        """
    }

    private static var gradleSteps: String {
        """
              - uses: actions/checkout@v4
              - uses: actions/setup-java@v4
                with:
                  distribution: 'temurin'
                  java-version: '17'
              - name: test
                run: chmod +x gradlew 2>/dev/null || true; ./gradlew test
        """
    }

    private static var rubySteps: String {
        """
              - uses: actions/checkout@v4
              - uses: ruby/setup-ruby@v1
                with:
                  ruby-version: '3.3'
                  bundler-cache: true
              - name: test
                run: bundle install && bundle exec rake test
        """
    }
}
