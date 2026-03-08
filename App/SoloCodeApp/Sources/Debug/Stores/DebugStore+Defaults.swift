extension DebugStore {
    // MARK: - Default Debug Flow Diagram

    static let defaultDebugFlowDiagram = """
    flowchart LR
        A[Describe] --> B[Reproduce]
        B --> C[Fix]
        C --> D[Verify]
        D --> E[Resolve]
        C -.-> C1[Hypothesize]
        C1 -.-> C2[Instrument]
        C2 -.-> C3[Observe]
    """
}

