import AppKit
import CarrierCore
import SwiftUI

/// Live preview of the terminal surface inside Settings > Terminal reflecting theme, ANSI colors, padding, typography and cursor style.
struct TerminalSettingsPreview: View {
    let profile: TerminalAppearanceProfile
    let pinPromptToBottom: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var previewMonospace: MonospaceSettings {
        MonospaceSettings(
            family: profile.fontFamily ?? MonospaceSettings.systemFamily,
            size: CGFloat(profile.fontSize),
            ligatures: profile.ligatures
        )
    }

    private var previewFont: Font {
        Font(previewMonospace.font(MonospaceSettings.defaultSize, weight: .regular))
    }

    private var previewBoldFont: Font {
        Font(previewMonospace.font(MonospaceSettings.defaultSize, weight: .bold))
    }

    private func paletteColor(_ index: Int, fallback: RGBA) -> Color {
        guard profile.palette.indices.contains(index) else {
            return Color(profile.adjustedForMinimumContrast(fallback))
        }
        return Color(profile.adjustedForMinimumContrast(profile.palette[index]))
    }

    private func rawPaletteColor(_ index: Int, fallback: RGBA) -> Color {
        guard profile.palette.indices.contains(index) else { return Color(fallback) }
        return Color(profile.palette[index])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s5) {
            HStack(spacing: Tokens.Space.s6) {
                Text("~/carrier")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(6, fallback: profile.foreground))
                Text("feat/terminal-ui")
                    .font(previewFont)
                    .foregroundStyle(paletteColor(5, fallback: profile.foreground))
                Text("❯")
                    .font(previewBoldFont)
                    .foregroundStyle(Color(profile.cursorColor))
                Text("pnpm test && git status")
                    .font(previewFont)
                    .foregroundStyle(Color(profile.foreground))
                    .lineLimit(1)
            }

            HStack(spacing: Tokens.Space.s6) {
                Text("✓ PASS")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(2, fallback: profile.boldColor))
                Text("1609")
                    .font(previewBoldFont)
                    .foregroundStyle(Color(profile.boldColor))
                Text("tests")
                    .font(previewFont)
                    .foregroundStyle(Color(profile.foreground))
                Text("· dim contrast sample")
                    .font(previewFont)
                    .foregroundStyle(paletteColor(8, fallback: profile.foreground))
                    .lineLimit(1)
            }

            HStack(spacing: Tokens.Space.s6) {
                Text("WARN")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(3, fallback: profile.foreground))
                Text("ERR")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(1, fallback: profile.foreground))
                Text("a != b => c")
                    .font(previewFont)
                    .foregroundStyle(paletteColor(4, fallback: profile.foreground))
                Text("selected text")
                    .font(previewFont)
                    .foregroundStyle(Color(profile.selectionForeground))
                    .padding(.horizontal, Tokens.Space.s4)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(Color(profile.selectionBackground)))
            }

            HStack(spacing: Tokens.Space.s3) {
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: Tokens.Radius.hair)
                        .fill(rawPaletteColor(index, fallback: profile.foreground))
                        .frame(width: 12, height: 6)
                }
                Spacer(minLength: 6)
                Text("ANSI 0–15")
                    .font(previewFont)
                    .foregroundStyle(paletteColor(8, fallback: profile.foreground))
            }
            .padding(.top, Tokens.Space.s2)

            if pinPromptToBottom {
                Spacer(minLength: 6)
            }

            HStack(spacing: Tokens.Space.s6) {
                Text("~/carrier")
                    .font(previewBoldFont)
                    .foregroundStyle(paletteColor(6, fallback: profile.foreground))
                Text("❯")
                    .font(previewBoldFont)
                    .foregroundStyle(Color(profile.cursorColor))
                HStack(spacing: Tokens.Space.none) {
                    Text("cargo test --lib ")
                        .font(previewFont)
                        .foregroundStyle(Color(profile.foreground))
                    cursorGlyph
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 164, alignment: pinPromptToBottom ? .bottomLeading : .topLeading)
        .padding(.horizontal, CGFloat(profile.paddingX))
        .padding(.vertical, CGFloat(profile.paddingY))
        .background {
            if profile.isSurfaceTranslucent {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    Rectangle().fill(Color(profile.chromeBackground))
                }
            } else {
                Rectangle().fill(Color(profile.background))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var cursorGlyph: some View {
        if profile.cursorBlink && reduceMotion == false {
            TimelineView(.periodic(from: .now, by: 0.55)) { context in
                let visible = Int(context.date.timeIntervalSinceReferenceDate / 0.55).isMultiple(of: 2)
                cursorShape
                    .opacity(visible ? 1 : 0.12)
                    .animation(.easeInOut(duration: 0.12), value: visible)
            }
        } else {
            cursorShape
        }
    }

    @ViewBuilder
    private var cursorShape: some View {
        switch profile.cursorStyle {
        case .block:
            Text(" ")
                .font(previewFont)
                .foregroundStyle(Color(profile.cursorText))
                .background(Rectangle().fill(Color(profile.cursorColor)))
        case .bar:
            Text(" ")
                .font(previewFont)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(profile.cursorColor))
                        .frame(width: 2)
                }
        case .underline:
            Text(" ")
                .font(previewFont)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(profile.cursorColor))
                        .frame(height: 2)
                }
        }
    }
}
