import Foundation

/// Logica di esecuzione streaming per Kilo CLI
enum KiloCLIExecution {
    static func runStreamingRequest(
        path: String,
        workspacePath: URL,
        fullPrompt: String,
        model: String?,
        imageURLs: [URL]?,
        environmentOverride: [String: String]?,
        executionController: ExecutionController?,
        executionScope: ExecutionScope,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            continuation.yield(.error("Kilo CLI not found at \(path). Install with: npm i -g kilo-code"))
            throw CoderEngineError.cliNotFound("kilo")
        }

        let args = buildArguments(
            fullPrompt: fullPrompt,
            model: model,
            imageURLs: imageURLs,
            workspacePath: workspacePath.path
        )
        let env = KiloCLIProvider.mergedEnvironment(with: environmentOverride)

        let stream = try await ProcessRunner.run(
            executable: path,
            arguments: args,
            workingDirectory: workspacePath,
            environment: env,
            executionController: executionController,
            scope: executionScope
        )

        continuation.yield(.started)
        var fullContent = ""

        for try await line in stream {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let events = KiloEventParser.parse(json: json, fullContent: &fullContent, defaultModel: model)
            for event in events {
                continuation.yield(event)
            }
        }

        continuation.yield(.completed)
        continuation.finish()
    }

    static func buildArguments(
        fullPrompt: String,
        model: String?,
        imageURLs: [URL]?,
        workspacePath: String
    ) -> [String] {
        var args = ["run", "--format", "json", "--auto"]
        if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            args += ["-m", model]
        }
        args += ["--dir", workspacePath]
        if let urls = imageURLs, !urls.isEmpty {
            for url in urls {
                args += ["-f", url.path]
            }
        }
        args.append(fullPrompt)
        return args
    }
}
