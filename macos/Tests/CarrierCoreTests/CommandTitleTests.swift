import Testing
@testable import CarrierCore

@Test(arguments: [
    ("gh issue view 635 --json title,body", "gh issue view 635 --json title,body"),
    ("git fetch -q && git branch -r | grep -i ship", "git fetch -q +2"),
    ("E=feat/x; ls -a | grep y; ls z", "ls -a +2"),
    ("D=$(mktemp -d); gh issue comment 635 --body-file $D/c.md", "gh issue comment 635 --body-file $D/c.md"),
    ("S=$(mktemp -d) && git archive origin/main | tar -x -C $S", "git archive origin/main +1"),
    ("pnpm test 2>&1 | grep -E \"Error|FAIL\" | head -5", "pnpm test 2>&1 +2"),
    ("cd /w && sed -n '1,5p; 9p' file.ts", "cd /w +1"),
    ("a || b", "a +1"),
    ("X=1", "X=1"),
    ("", ""),
])
func aCommandIsTitledByWhatItStartsWith(command: String, title: String) {
    #expect(commandTitle(command) == title)
}

@Test func aLongCommandEndsInAnEllipsis() {
    let title = commandTitle("cat " + String(repeating: "a", count: 80))
    #expect(title.count == maxCommandTitle)
    #expect(title.hasSuffix("…"))
}

@Test func onlyACommandIsTitledAndAlwaysHasDetails() {
    let shell = TranscriptCard(tool: "Bash", kind: .shell, arg: "git fetch && git pull", summary: "", status: .ok, duration: nil)
    #expect(shell.title == "git fetch +1")
    #expect(shell.hasDetails)
    let read = TranscriptCard(tool: "Read", kind: .read, arg: "src/app.ts", summary: "", status: .ok, duration: nil)
    #expect(read.title == "src/app.ts")
    #expect(read.hasDetails == false)
}

@Test func copyTakesTheCommandAndWhatItPrinted() {
    var shell = TranscriptCard(tool: "Bash", kind: .shell, arg: "ls /tmp", summary: "", status: .ok, duration: nil)
    shell.output = ["a", "b"]
    #expect(shell.copyText == "ls /tmp\na\nb")
    var read = TranscriptCard(tool: "Read", kind: .read, arg: "src/app.ts", summary: "", status: .ok, duration: nil)
    read.output = ["x"]
    #expect(read.copyText == "x")
}

@Test func anOutputIsCutAtTheCollapsedLinesAndShownWholeOnRequest() {
    var card = TranscriptCard(tool: "Bash", kind: .shell, arg: "pnpm test", summary: "", status: .ok, duration: nil)
    card.output = (1...14).map { "line \($0)" }
    let cut = card.visibleOutput(expanded: false)
    #expect(cut.lines.count == collapsedOutputLines && cut.hidden == 14 - collapsedOutputLines)
    #expect(card.visibleOutput(expanded: true).lines.count == 14 && card.visibleOutput(expanded: true).hidden == 0)
    card.output = Array(card.output.prefix(collapsedOutputLines))
    #expect(card.visibleOutput(expanded: false).hidden == 0)
}
