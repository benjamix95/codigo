import SwiftUI

extension MarkdownContentView {
    // MARK: - Headings

    func headingView(level: Int, text: String) -> some View {
        let size: CGFloat
        let weight: Font.Weight
        let color: Color
        let letterSpacing: CGFloat

        switch level {
        case 1:
            size = 21
            weight = .bold
            color = h1Color
            letterSpacing = -0.3
        case 2:
            size = 17.5
            weight = .bold
            color = h2Color
            letterSpacing = -0.2
        case 3:
            size = 15
            weight = .semibold
            color = h3Color
            letterSpacing = -0.1
        default:
            size = 13.5
            weight = .semibold
            color = h3Color
            letterSpacing = 0
        }

        return VStack(alignment: .leading, spacing: level <= 2 ? 10 : 4) {
            inlineMarkdown(text, fontSize: size, fontWeight: weight, color: color)
                .tracking(letterSpacing)
            if level == 1 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.40),
                                accentColor.opacity(0.15),
                                dividerColor,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1.5)
                    .frame(maxWidth: 320)
            } else if level == 2 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.20),
                                dividerColor,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .frame(maxWidth: 240)
            }
        }
    }

    // MARK: - Bullet Item

    func bulletItemView(text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if indent == 0 {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(accentColor.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .offset(y: 1)
            } else {
                Circle()
                    .strokeBorder(accentColor.opacity(0.5), lineWidth: 1)
                    .frame(width: 4.5, height: 4.5)
                    .offset(y: 1)
            }
            inlineMarkdown(text)
        }
        .padding(.leading, 4 + CGFloat(indent) * 22)
        .padding(.vertical, 4)
    }

    // MARK: - Numbered Item

    func numberedItemView(number: String, text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(
                    FontPreferences.resolveSansFont(
                        size: bodyFont,
                        family: uiSansFontFamily,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(accentColor.opacity(0.8))
                .frame(minWidth: 22, alignment: .trailing)
            inlineMarkdown(text)
        }
        .padding(.leading, CGFloat(indent) * 22)
        .padding(.vertical, 4)
    }

    // MARK: - Horizontal Rule

    var horizontalRuleView: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            dividerColor.opacity(0),
                            accentColor.opacity(0.15),
                            dividerColor.opacity(0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Blockquote

    func blockquoteView(text: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(quoteBarColor)
                .frame(width: 3)
            inlineMarkdown(text, color: textSecondary)
                .padding(.leading, 16)
                .padding(.vertical, 10)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(quoteBg)
        )
    }

    // MARK: - Inline Markdown Text

    @ViewBuilder
    func inlineMarkdown(
        _ text: String,
        fontSize: CGFloat = 0,
        fontWeight: Font.Weight = .regular,
        color: Color? = nil
    ) -> some View {
        let sz = fontSize == 0 ? bodyFont : fontSize
        let attributed = buildInlineAttributed(
            text,
            fontSize: sz,
            fontWeight: fontWeight,
            color: color
        )
        Text(attributed)
            .environment(\.openURL, OpenURLAction { url in
                MessageLinkRouter.open(url, onFileClicked: onFileClicked)
            })
            .font(
                FontPreferences.resolveSansFont(
                    size: sz,
                    family: uiSansFontFamily,
                    weight: fontWeight
                )
            )
            .foregroundStyle(color ?? textPrimary)
            .lineSpacing(bodyLineSpacing)
            .textSelection(.enabled)
    }

}
