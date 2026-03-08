// MARK: - Theme Palette

struct MermaidPalette {
    // Node colors
    let primaryColor: String
    let primaryTextColor: String
    let primaryBorderColor: String
    let lineColor: String
    let secondaryColor: String
    let tertiaryColor: String
    let nodeBg: String
    let nodeBorder: String
    let nodeTextColor: String
    let clusterBkg: String
    let clusterBorder: String
    let titleColor: String
    let edgeLabelBg: String
    let textColor: String
    let canvasBg: String
    let secondaryBorderColor: String

    // Sequence diagram
    let noteBg: String
    let noteTextColor: String
    let noteBorderColor: String
    let activationBg: String
    let sequenceNumberColor: String

    // Export
    let exportBg: String

    // Card UI
    let cardBg: String
    let cardBorder: String
    let headerBg: String
    let toolbarBg: String
    let toolbarBorder: String
    let toolbarIconColor: String
    let toolbarIconHover: String
    let labelColor: String
    let labelSecondary: String

    // Error
    let errorColor: String
    let errorBg: String
    let errorBorder: String

    // MARK: - Light

    static let light = MermaidPalette(
        primaryColor: "#4F8FF7",
        primaryTextColor: "#1a1a2e",
        primaryBorderColor: "#B8C9E0",
        lineColor: "#8B99AD",
        secondaryColor: "#F5F7FA",
        tertiaryColor: "#EDF0F5",
        nodeBg: "#FFFFFF",
        nodeBorder: "#D0D7E2",
        nodeTextColor: "#1a1a2e",
        clusterBkg: "#F7F9FC",
        clusterBorder: "#D0D7E2",
        titleColor: "#1a1a2e",
        edgeLabelBg: "#FFFFFF",
        textColor: "#374151",
        canvasBg: "#FFFFFF",
        secondaryBorderColor: "#D0D7E2",
        noteBg: "#FEF9E7",
        noteTextColor: "#5D4E37",
        noteBorderColor: "#E8DCC8",
        activationBg: "#E8F0FE",
        sequenceNumberColor: "#FFFFFF",
        exportBg: "#FFFFFF",
        cardBg: "transparent",
        cardBorder: "#E5E7EB",
        headerBg: "transparent",
        toolbarBg: "#F3F4F6",
        toolbarBorder: "#E5E7EB",
        toolbarIconColor: "#6B7280",
        toolbarIconHover: "#374151",
        labelColor: "#374151",
        labelSecondary: "#9CA3AF",
        errorColor: "#DC2626",
        errorBg: "#FEF2F2",
        errorBorder: "#FECACA"
    )

    // MARK: - Dark

    static let dark = MermaidPalette(
        primaryColor: "#2a2a2a",
        primaryTextColor: "#b0b0b0",
        primaryBorderColor: "#3a3a3a",
        lineColor: "#555555",
        secondaryColor: "#1e1e1e",
        tertiaryColor: "#242424",
        nodeBg: "#1e1e1e",
        nodeBorder: "#3a3a3a",
        nodeTextColor: "#b0b0b0",
        clusterBkg: "#161616",
        clusterBorder: "#333333",
        titleColor: "#cccccc",
        edgeLabelBg: "#1a1a1a",
        textColor: "#999999",
        canvasBg: "#0d0d0d",
        secondaryBorderColor: "#333333",
        noteBg: "#222222",
        noteTextColor: "#aaaaaa",
        noteBorderColor: "#3a3a3a",
        activationBg: "#252525",
        sequenceNumberColor: "#b0b0b0",
        exportBg: "#0d0d0d",
        cardBg: "transparent",
        cardBorder: "#1F2937",
        headerBg: "transparent",
        toolbarBg: "#1F2937",
        toolbarBorder: "#374151",
        toolbarIconColor: "#9CA3AF",
        toolbarIconHover: "#E5E7EB",
        labelColor: "#E5E7EB",
        labelSecondary: "#6B7280",
        errorColor: "#F87171",
        errorBg: "#1C1517",
        errorBorder: "#7F1D1D"
    )
}
