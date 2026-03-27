import Foundation

public struct InstructionPolicySessionDescriptor: Sendable, Equatable {
    public let policyRef: String?
    public let policyHash: String?
    public let shouldReinjectPolicyText: Bool

    public init(
        policyRef: String?,
        policyHash: String?,
        shouldReinjectPolicyText: Bool
    ) {
        self.policyRef = policyRef
        self.policyHash = policyHash
        self.shouldReinjectPolicyText = shouldReinjectPolicyText
    }
}

public extension WorkspaceContext {
    var requiredInstructionPolicyHash: String? {
        let hash = instructionPolicyBundle.policyHash.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }

    var instructionPolicyRef: String? {
        let ref = instructionPolicyBundle.policyRef.trimmingCharacters(in: .whitespacesAndNewlines)
        return ref.isEmpty ? nil : ref
    }

    var instructionPolicySessionDescriptor: InstructionPolicySessionDescriptor {
        InstructionPolicySessionDescriptor(
            policyRef: instructionPolicyRef,
            policyHash: requiredInstructionPolicyHash,
            // Main chat transports are still stateless across sends, so the
            // safe default remains full policy reinjection even when the ref
            // is unchanged. The descriptor exists to make this explicit.
            shouldReinjectPolicyText: true
        )
    }
}
