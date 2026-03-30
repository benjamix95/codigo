import Foundation
import XCTest

struct CodexAppServerWireHarness {
    static func repoRoot(filePath: String) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func writeCodexConfig(at codexHome: URL, command: String) throws {
        let content = """
        model = "gpt-5.4"
        model_provider = "openai"
        fast_mode = true

        [sandbox_workspace_write]
        network_access = true

        [mcp_servers.coderide]
        command = "\(command)"
        args = [ "--workspace", "." ]
        required = true
        """
        try content.write(
            to: codexHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
    }

    static func writeHealthyStubServer(in root: URL) throws -> URL {
        let script = root.appendingPathComponent("healthy-mcp.py")
        let contents = """
        #!/usr/bin/env python3
        import json, sys

        for raw in sys.stdin:
            line = raw.strip()
            if not line:
                continue
            msg = json.loads(line)
            method = msg.get("method")
            if method == "initialize":
                print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"protocolVersion":"2025-11-25","capabilities":{"tools":{"listChanged":False}},"serverInfo":{"name":"stub-coderide","version":"1.0.0","title":"Stub CoderIDE"}}}), flush=True)
            elif method == "tools/list":
                print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"tools":[{"name":"coderide_read","inputSchema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},{"name":"coderide_grep","inputSchema":{"type":"object","properties":{}}}]}}), flush=True)
            elif method == "resources/list":
                print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"resources":[],"nextCursor":None}}), flush=True)
            elif method == "resources/templates/list":
                print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"resourceTemplates":[],"nextCursor":None}}), flush=True)
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    static func writeFailingStubServer(in root: URL) throws -> URL {
        let script = root.appendingPathComponent("failing-mcp.py")
        let contents = """
        #!/usr/bin/env python3
        import sys
        sys.stdin.readline()
        sys.exit(0)
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    static func runHarness(
        codexPath: String,
        codexHome: URL,
        workspace: URL,
        root: URL
    ) throws -> HarnessSummary {
        let harness = try writeHarnessScript(in: root)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", harness.path, codexPath, codexHome.path, workspace.path]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            XCTFail("Harness codex app-server fallito: \(stderrText)")
            throw NSError(domain: "CodexAppServerMCPWireIntegrationTests", code: Int(process.terminationStatus))
        }

        return try JSONDecoder().decode(HarnessSummary.self, from: stdoutData)
    }

    private static func writeHarnessScript(in root: URL) throws -> URL {
        let script = root.appendingPathComponent("harness.py")
        let contents = """
        #!/usr/bin/env python3
        import json, os, select, subprocess, sys, time

        codex_path, codex_home, workspace = sys.argv[1:4]
        env = os.environ.copy()
        env["CODEX_HOME"] = codex_home
        proc = subprocess.Popen([codex_path, "app-server"], cwd=workspace, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, bufsize=1)

        def send(obj):
            proc.stdin.write(json.dumps(obj) + "\\n")
            proc.stdin.flush()

        def read_for(timeout):
            end = time.time() + timeout
            lines = []
            while time.time() < end:
                r, _, _ = select.select([proc.stdout, proc.stderr], [], [], 0.2)
                for stream in r:
                    line = stream.readline()
                    if not line:
                        continue
                    src = "stdout" if stream is proc.stdout else "stderr"
                    lines.append((src, line.rstrip()))
            return lines

        def read_until(predicate, timeout):
            end = time.time() + timeout
            lines = []
            while time.time() < end:
                r, _, _ = select.select([proc.stdout, proc.stderr], [], [], 0.2)
                for stream in r:
                    line = stream.readline()
                    if not line:
                        continue
                    src = "stdout" if stream is proc.stdout else "stderr"
                    line = line.rstrip()
                    lines.append((src, line))
                    if predicate(src, line):
                        return lines
            return lines

        def absorb(summary, lines):
            for src, line in lines:
                if '"id":3' in line and '"result"' in line:
                    summary["threadStarted"] = True
                if src == "stderr" and "required MCP servers failed to initialize" in line:
                    summary["startupStatus"] = "failed"
                    summary["startupError"] = line
                if '"method":"mcpServer/startupStatus/updated"' in line and '"name":"coderide"' in line:
                    obj = json.loads(line)
                    params = obj.get("params", {})
                    summary["startupStatus"] = params.get("status")
                    summary["startupError"] = params.get("error")
                if '"id":3' in line and '"error"' in line:
                    summary["startupStatus"] = "failed"
                    summary["startupError"] = line
                if '"id":4' in line:
                    obj = json.loads(line)
                    for server in obj.get("result", {}).get("data", []):
                        if server.get("name") == "coderide":
                            summary["toolNames"] = sorted(list((server.get("tools") or {}).keys()))

        summary = {"threadStarted": False, "startupStatus": None, "startupError": None, "toolNames": []}
        send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"wire-test","version":"1.0"},"capabilities":{"experimentalApi":True}}})
        read_until(lambda src, line: '"id":1' in line, 5)
        send({"jsonrpc":"2.0","method":"notifications/initialized","params":{}})
        send({"jsonrpc":"2.0","id":2,"method":"config/mcpServer/reload","params":{}})
        read_until(lambda src, line: '"id":2' in line, 5)
        send({"jsonrpc":"2.0","id":3,"method":"thread/start","params":{"cwd":workspace,"approvalPolicy":"never","sandbox":"workspace-write","ephemeral":True,"experimentalRawEvents":True}})
        absorb(summary, read_until(lambda src, line: '"id":3' in line, 15))
        send({"jsonrpc":"2.0","id":4,"method":"mcpServerStatus/list","params":{"limit":50}})
        lines = read_until(lambda src, line: '"id":4' in line, 10)
        lines.extend(read_for(2.0))
        absorb(summary, lines)
        proc.kill()
        try:
            proc.wait(timeout=2)
        except Exception:
            pass
        print(json.dumps(summary))
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}

struct HarnessSummary: Decodable {
    let threadStarted: Bool
    let startupStatus: String?
    let startupError: String?
    let toolNames: [String]
}
