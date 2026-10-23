import Testing
@testable import CarrierCore

@Test(arguments: [
    ("gh issue view 635 --json title,body", "gh issue view 635 --json title,body", 0),
    ("git fetch -q && git branch -r | grep -i ship", "git fetch -q", 2),
    ("E=feat/x; ls -a | grep y; ls z", "ls -a", 2),
    ("D=$(mktemp -d); gh issue comment 635 --body-file $D/c.md", "gh issue comment 635 --body-file $D/c.md", 0),
    ("S=$(mktemp -d) && git archive origin/main | tar -x -C $S", "git archive origin/main", 1),
    ("pnpm test 2>&1 | grep -E \"Error|FAIL\" | head -5", "pnpm test 2>&1", 2),
    ("a || b", "a", 1),
    ("X=1", "X=1", 0),
    ("", "", 0),
    // a leading cd is skipped
    ("cd /a/b && pnpm test", "pnpm test", 0),
    ("cd /a/b; git status", "git status", 0),
    ("cd \"a b\" && git log", "git log", 0),
    ("cd /w && sed -n '1,5p; 9p' file.ts", "sed -n '1,5p; 9p' file.ts", 0),
    ("cd /a && git fetch && git pull", "git fetch", 1),
    // a cd alone, not first, or inside quotes / $( ) is the title
    ("cd /a/b", "cd /a/b", 0),
    ("cd", "cd", 0),
    ("git fetch && cd /a", "git fetch", 1),
    ("echo 'cd /a' && ls", "echo 'cd /a'", 1),
    ("echo $(cd /a && ls) && pwd", "echo $(cd /a && ls)", 1),
    ("cdr /a && ls", "cdr /a", 1),
    // an assignment before the cd keeps the piece as it is today
    ("VAR=1 cd x && cmd", "VAR=1 cd x", 1),
])
func aCommandIsTitledByWhatItStartsWith(command: String, title: String, more: Int) {
    let result = commandTitle(command)
    #expect(result.title == title)
    #expect(result.more == more)
}

@Test func aLongCommandEndsInAnEllipsis() {
    let title = commandTitle("cd /w && cat " + String(repeating: "a", count: 80)).title
    #expect(title.count == maxCommandTitle)
    #expect(title.hasSuffix("…"))
}

@Test func onlyACommandIsTitledAndAlwaysHasDetails() {
    let shell = TranscriptCard(tool: "Bash", kind: .shell, arg: "git fetch && git pull", summary: "", status: .ok, duration: nil)
    #expect(shell.title == "git fetch" && shell.moreCommands == 1)
    #expect(shell.hasDetails)
    let read = TranscriptCard(tool: "Read", kind: .read, arg: "src/app.ts", summary: "", status: .ok, duration: nil)
    #expect(read.title == "src/app.ts" && read.moreCommands == 0)
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
