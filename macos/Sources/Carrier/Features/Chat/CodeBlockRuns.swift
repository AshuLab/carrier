import CarrierCore
import CarrierUI
import SwiftUI

extension CodeBlockView.Role {
    init(_ kind: CodeTokenKind) {
        switch kind {
        case .plain: self = .plain
        case .prompt: self = .prompt
        case .keyword: self = .keyword
        case .string: self = .string
        case .number: self = .number
        case .comment: self = .comment
        case .function: self = .function
        case .type: self = .type
        }
    }
}

extension CodeBlockView.DiffLine {
    init(_ kind: DiffLineKind) {
        switch kind {
        case .added: self = .added
        case .removed: self = .removed
        case .hunk: self = .hunk
        case .meta: self = .meta
        case .context: self = .context
        }
    }
}

extension CodeBlockView {
    /// A fenced block of `code` in `language` (named, or guessed from the code when it is nil): the chat's highlighting, the diff's lines and the words Copy takes
    /// are `CarrierCore`'s, and the monospace settings are the app's now.
    init(language: String?, file: String? = nil, code: String, foldAfter: Int = 25, spare: Int = 4) {
        let resolved = resolvedCodeLanguage(language, code: code)
        self.init(
            name: codeLanguageName(language, resolved: resolved), file: file, code: code, copyText: codeCopyText(code, language: resolved), isDiff: resolved == "diff",
            runs: { text in codeTokens(text, language: resolved).map { Run(text: $0.text, role: Role($0.kind)) } },
            diffLines: resolved == "diff" ? CarrierCore.diffLines(code).map(DiffLine.init) : [], monospace: MonospaceStyle.shared.settings, foldAfter: foldAfter, spare: spare
        )
    }
}
