import Testing

@testable import CarrierCore

@Test func aPathShapedCodeIsAFileOrAFolderAndAnythingElseStaysCode() {
    #expect(inlinePath("docs/specs/fal-tyc-pendings.md") == .file(extension: "md"))
    #expect(inlinePath("README.md") == .file(extension: "md"))
    #expect(inlinePath("Sources/Carrier/TranscriptView.swift") == .file(extension: "swift"))
    #expect(inlinePath("docs/glossary.MD") == .file(extension: "md"))
    #expect(inlinePath("src/app/config.local") == .file(extension: "local"))
    #expect(inlinePath("scripts/build") == .file(extension: nil))
    #expect(inlinePath("docs/") == .folder)
    #expect(inlinePath("~/.carrier/chat/") == .folder)

    for code in ["", "/", "v1.2", "e.g.", "foo.bar", "pnpm test", "git status -sb", "GET /pendings/section", "foo()", "https://a.com/b.md", "elegibles - firmaron", "ls"] {
        #expect(inlinePath(code) == nil, "\(code) is not a path")
    }
}
