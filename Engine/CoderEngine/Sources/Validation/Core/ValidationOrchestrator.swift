import Foundation

public actor ValidationOrchestrator {
    private let configLoader: (URL) throws -> ProjectValidationDescriptor
    private let stageFactory: (ValidationProfile) -> [any ValidationStage]

    public init() {
        self.configLoader = ValidationConfigLoader.load
        self.stageFactory = ValidationOrchestrator.stages
    }

    init(
        configLoader: @escaping (URL) throws -> ProjectValidationDescriptor,
        stageFactory: @escaping (ValidationProfile) -> [any ValidationStage]
    ) {
        self.configLoader = configLoader
        self.stageFactory = stageFactory
    }

    public func run(context: ValidationContext) async throws -> ValidationRunResult {
        let startedAt = Date()
        let descriptor = try configLoader(context.workspaceRoot)
        let resolvedFiles = try await ChangeScopeAnalyzer.resolveFiles(context: context, descriptor: descriptor)
        let effective = ValidationContext(
            trigger: context.trigger,
            workspaceRoot: context.workspaceRoot,
            touchedFiles: resolvedFiles,
            patchText: context.patchText,
            patchFileURL: context.patchFileURL,
            workspaceContainsPatch: context.workspaceContainsPatch,
            stagedOnly: context.stagedOnly
        )
        let profile = ValidationProfileResolver.resolve(trigger: context.trigger)
        let stages = stageFactory(profile)
        var results: [ValidationStageResult] = []
        var failure: ValidationFailure?

        for stage in stages {
            let result = await stage.run(context: effective, profile: profile, descriptor: descriptor)
            results.append(result)
            if result.status == .failed {
                failure = ValidationFailure(stage: stage.id, message: result.summary)
                break
            }
        }

        let final = ValidationRunResult(
            runId: "validation-\(UUID().uuidString.prefix(8))",
            profile: profile,
            status: failure == nil ? .passed : .failed,
            touchedFiles: effective.touchedFiles,
            stageResults: results,
            durationMs: max(1, Int(Date().timeIntervalSince(startedAt) * 1000)),
            failure: failure
        )
        await ValidationMetricsStore.shared.record(final)
        return final
    }

    private static func stages(for profile: ValidationProfile) -> [any ValidationStage] {
        var stages: [any ValidationStage] = [
            PatchSafetyStage(),
            CodeSizeStage(),
            BuildStage(),
            TargetedTestsStage(),
            SecurityStage(),
        ]
        if profile == .gitCommit || profile == .ciFull {
            stages.append(RegressionStage())
        }
        if profile == .ciFull {
            stages.append(PerformanceStage())
            stages.append(E2EStage())
        }
        return stages
    }
}
