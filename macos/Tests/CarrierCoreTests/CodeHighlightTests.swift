import Foundation
import Testing

@testable import CarrierCore

private func kinds(_ code: String, _ language: String) -> [(String, CodeTokenKind)] {
    codeTokens(code, language: language).filter { $0.kind != .plain }.map { ($0.text, $0.kind) }
}

@Test func theTokensPutTogetherAreTheCodeWhateverTheLanguage() {
    let code = "const a = \"x\" + 1 // note\n/* block\nacross */ f(`t`)\n"
    for language in ["javascript", "python", "shell", "yaml", "sql", "unknown"] {
        #expect(codeTokens(code, language: language).map(\.text).joined() == code)
    }
}

@Test func aScriptIsColouredByKeywordsStringsNumbersCommentsCallsAndTypes() {
    let tokens = kinds("const total = sum(2, \"a\") // done\nlet x: Foo", "typescript")
    #expect(tokens.map(\.0) == ["const", "sum", "2", "\"a\"", "// done", "let", "Foo"])
    #expect(tokens.map(\.1) == [.keyword, .function, .number, .string, .comment, .keyword, .type])
}

@Test func aShellColoursTheCommandsAndGreysThePrompt() {
    let tokens = codeTokens("$ pnpm test --filter chat # the suite\necho \"$((2 + 3))\"", language: "shell").filter { $0.kind != .plain }
    #expect(tokens.map(\.text) == ["$ ", "pnpm", "# the suite", "echo", "\"$((2 + 3))\""])
    #expect(tokens.map(\.kind) == [.prompt, .function, .comment, .function, .string])
}

@Test func aHashInsideAWordIsNotAComment() {
    #expect(kinds("echo $#", "shell").map(\.0) == ["echo"])
}

@Test func jsonKeysAreNotStrings() {
    #expect(kinds("{\"a\": \"b\", \"n\": 1, \"ok\": true}", "json").map(\.1) == [.type, .string, .type, .number, .type, .keyword])
}

@Test func aBlockCommentAndATripleQuoteRunOverLines() {
    #expect(kinds("/* a\nb */ x", "swift").map(\.0) == ["/* a\nb */"])
    #expect(kinds("\"\"\"a\nb\"\"\"", "python").map(\.0) == ["\"\"\"a\nb\"\"\""])
}

@Test func theLanguageComesFromTheNameTheExtensionOrWhatTheBlockLooksLike() {
    #expect(codeLanguage("JS") == "javascript" && codeLanguage("tsx") == "typescript" && codeLanguage("text") == nil)
    #expect(resolvedCodeLanguage(nil, code: "diff --git a/x b/x\n+a") == "diff")
    #expect(resolvedCodeLanguage(nil, code: "$ ls\nfile") == "shell")
    #expect(resolvedCodeLanguage(nil, code: "{\"a\": [1, 2]}") == "json")
    #expect(resolvedCodeLanguage(nil, code: "{ not json") == nil)
    #expect(resolvedCodeLanguage("text", code: "$ ls") == nil)
    #expect(codeLanguageName("js", resolved: "javascript") == "JavaScript" && codeLanguageName("toml", resolved: nil) == "toml" && codeLanguageName(nil, resolved: nil) == "Code")
}

@Test func theFenceGivesTheLanguageAndTheFile() {
    #expect(fenceInfo("") == (nil, nil) && fenceInfo("swift") == ("swift", nil))
    #expect(fenceInfo("ts src/a.ts") == ("ts", "src/a.ts") && fenceInfo("ts:src/a.ts") == ("ts", "src/a.ts"))
    #expect(fenceInfo("ts title=\"src/a.ts\"") == ("ts", "src/a.ts") && fenceInfo("src/a.ts") == ("ts", "src/a.ts"))
    #expect(fenceInfo("diff") == ("diff", nil))
    let blocks = markdownBlocks("```ts src/a.ts\nx\n```")
    #expect(blocks == [.code(language: "ts", file: "src/a.ts", "x")])
}

@Test func theLinesOfADiffAreTintedByWhatTheyDo() {
    #expect(diffLines("diff --git a b\n--- a\n+++ b\n@@ -1 +1 @@\n ctx\n-old\n+new") == [.meta, .meta, .meta, .hunk, .context, .removed, .added])
}

@Test func copyingAShellSessionTakesTheCommandsAlone() {
    #expect(codeCopyText("$ pnpm install\nDone.\n$ pnpm test", language: "shell") == "pnpm install\npnpm test")
    #expect(codeCopyText("pnpm test", language: "shell") == "pnpm test")
    #expect(codeCopyText("$ not a shell", language: "python") == "$ not a shell")
}
