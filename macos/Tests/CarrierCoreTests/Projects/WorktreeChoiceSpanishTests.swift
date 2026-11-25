import Foundation
import Testing

@testable import CarrierCore

// The worktree half of the new-session sentence in Spanish (design/copy/es.json): the sentence and its warning, the picker's badges and footer, the warnings under the
// "from" chip and the states of the worktree's name. The English words are asserted in WorktreeChoiceTests, with `english`.

private let b = spanish.bundle
private let l = spanish.locale

private func info(
    branch: String? = "main", dirty: Int = 0, git: Bool = true, bare: Bool = false, fetchedAt: Int? = nil,
    branches: [WorkspaceInfo.Branch] = [.init(name: "main", remote: false)]
) -> WorkspaceInfo {
    WorkspaceInfo(folder: "/w/api", git: git, bare: bare, branch: branch, defaultBranch: "main", dirty: dirty, branches: branches, fetchedAt: fetchedAt)
}

@Test func theSentenceSaysWhereTheSessionWorksInSpanish() {
    func sentence(_ workspace: WorkspaceInfo?, worktree: (name: String, from: String?)? = nil, gitMissing: Bool = false) -> String {
        workSentence(folder: "/w/api", workspace: workspace, worktree: worktree, gitMissing: gitMissing, bundle: b, locale: l)
    }
    #expect(workSentence(folder: nil, bundle: b, locale: l) == "Trabaja en Elige un espacio de trabajo… en la carpeta base")
    #expect(sentence(nil) == "Trabaja en api en la carpeta base")
    #expect(sentence(info()) == "Trabaja en api en la carpeta base (main)")
    #expect(sentence(info(branch: nil)) == "Trabaja en api en la carpeta base (HEAD desacoplado)")
    #expect(sentence(info(git: false, branches: [])) == "Trabaja en api en la carpeta (no es un repositorio git: sin worktree)")
    #expect(sentence(info(bare: true)) == "Trabaja en api en la carpeta (repositorio bare: sin worktree)")
    #expect(sentence(info(branch: nil, branches: [])) == "Trabaja en api en la carpeta (proyecto nuevo, aún sin commits: sin worktree)")
    #expect(sentence(info(), worktree: ("brave-marine", "origin/main")) == "Trabaja en api en un worktree nuevo carrier/brave-marine desde origin/main")
    #expect(sentence(info(), worktree: ("brave-marine", nil)) == "Trabaja en api en un worktree nuevo carrier/brave-marine desde …")
    #expect(sentence(info(), gitMissing: true) == "Trabaja en api en la carpeta (Falta git: sin worktree y sin rama. Mira Salud en Ajustes)")
    #expect(gitMissingReason(bundle: b, locale: l) == "Falta git: sin worktree y sin rama. Mira Salud en Ajustes")
}

@Test func theUncommittedFilesAreCountedInSpanishWithTheirPlural() {
    #expect(uncommittedWarning(info(dirty: 1), bundle: b, locale: l) == "1 archivo sin confirmar en la carpeta. Un worktree los mantiene fuera del camino del agente.")
    #expect(uncommittedWarning(info(dirty: 3), bundle: b, locale: l) == "3 archivos sin confirmar en la carpeta. Un worktree los mantiene fuera del camino del agente.")
    #expect(uncommittedWarning(info(dirty: 0), bundle: b, locale: l) == nil)
}

@Test func theBranchPickersBadgesAndFooterAreSpanish() {
    let workspace = info(
        fetchedAt: 1_792_000_000_000,
        branches: [.init(name: "main", remote: false, ahead: 1, behind: 2), .init(name: "feat", remote: false), .init(name: "origin/main", remote: true)]
    )
    let now = Date(timeIntervalSince1970: 1_792_000_000 + 120)
    let picker = branchPicker(workspace, now: now, unreachable: true, bundle: b, locale: l)
    #expect(picker.fetched == "Actualizado hace 2 minutos" && picker.unreachable == "No se pudo contactar con origin")
    #expect(picker.local[0].behindText(bundle: b, locale: l) == "2 por detrás de origin" && picker.local[0].notPushedText(bundle: b, locale: l) == "1 sin subir")
    #expect(picker.local[1].behindText(bundle: b, locale: l) == nil && picker.local[1].notPushedText(bundle: b, locale: l) == nil)
    #expect(branchPicker(workspace, now: now, bundle: b, locale: l).unreachable == nil)
}

@Test func whenTheBranchesWereFetchedIsSaidInSpanishWithItsPlural() {
    let now = Date(timeIntervalSince1970: 1_792_100_000)
    func line(_ ago: Int?) -> String { fetchedLine(ago.map { (1_792_100_000 - $0) * 1000 }, now: now, bundle: b, locale: l) }
    #expect(line(nil) == "Nunca actualizado")
    #expect(line(10) == "Actualizado ahora mismo")
    #expect(line(60) == "Actualizado hace 1 minuto" && line(5 * 60) == "Actualizado hace 5 minutos")
    #expect(line(3600) == "Actualizado hace 1 hora" && line(3 * 3600) == "Actualizado hace 3 horas")
    #expect(line(86_400) == "Actualizado hace 1 día" && line(4 * 86_400) == "Actualizado hace 4 días")
}

@Test func theWarningsUnderTheFromChipAreSpanishWithTheirPlural() {
    let behind = info(branches: [.init(name: "main", remote: false, ahead: 0, behind: 1), .init(name: "dev", remote: false, ahead: 0, behind: 3)])
    #expect(startWarning(StartPoint(branch: "main", side: .local), in: behind, bundle: b, locale: l) == "main va 1 commit por detrás de origin/main, así que el worktree empieza sin él.")
    #expect(startWarning(StartPoint(branch: "dev", side: .local), in: behind, bundle: b, locale: l) == "dev va 3 commits por detrás de origin/dev, así que el worktree empieza sin ellos.")
    let ahead = info(branches: [.init(name: "main", remote: false, ahead: 1, behind: 0), .init(name: "dev", remote: false, ahead: 2, behind: 0)])
    #expect(startWarning(StartPoint(branch: "main", side: .remote), in: ahead, bundle: b, locale: l) == "main tiene 1 commit sin subir a origin/main, así que el worktree no lo tendrá.")
    #expect(startWarning(StartPoint(branch: "dev", side: .remote), in: ahead, bundle: b, locale: l) == "dev tiene 2 commits sin subir a origin/dev, así que el worktree no los tendrá.")
    #expect(startWarning(StartPoint(branch: "main", side: .remote), in: behind, bundle: b, locale: l) == nil)
}

@Test func theNameOfTheWorktreeSaysWhyItCannotBeUsedInSpanish() {
    #expect(stateOfName(NameCheck(valid: true, free: true), bundle: b, locale: l) == .free)
    #expect(stateOfName(NameCheck(valid: false, free: false), bundle: b, locale: l) == .problem("Ese nombre no se puede usar"))
    #expect(stateOfName(NameCheck(valid: false, free: false, reason: "words of the host"), bundle: b, locale: l) == .problem("words of the host"))
}
