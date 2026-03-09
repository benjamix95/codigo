import Foundation

protocol ValidationStage: Sendable {
    var id: ValidationStageID { get }
    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult
}
