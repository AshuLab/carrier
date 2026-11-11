import Foundation

// "Ready for Carrier" on a repo's page: four rows from the checks of `carrier doctor` that are about that repo (`repo` and `profiles`).
// A role's row is the repo's mint check whose `profiles` holds the profile the role resolves to there, so two roles of one identity show
// the same check. A check the doctor did not report (something before it failed, or it has not answered) reads as waiting, never failed.

public struct RepoCheckRow: Equatable, Identifiable {
    public enum Status: Equatable { case ok, warn, fail, waiting }

    public var title: String
    public var status: Status
    public var detail: String?
    public var fix: String?
    /// set on a sign row: the role whose identity could be changed
    public var role: AgentRole?
    public var id: String { title }
}

public struct RepoChecks: Equatable {
    public var rows: [RepoCheckRow]
    /// said above the rows while the doctor runs or when it could not answer
    public var note: String?
}

public func repoChecks(repo: String, roles: [RepoRoleRow], doctor: DoctorState) -> RepoChecks {
    var checks: [DoctorCheck] = []
    var note: String?
    switch doctor {
    case .checks(let all): checks = all.filter { $0.repo == repo }
    case .running: note = "Running carrier doctor…"
    case .unknown(let reason): note = "Could not check: \(reason)"
    case .idle: break
    }
    func row(_ title: String, role: AgentRole? = nil, _ found: DoctorCheck?) -> RepoCheckRow {
        guard let found else { return RepoCheckRow(title: title, status: .waiting, detail: "Not checked yet", role: role) }
        let status: RepoCheckRow.Status = switch found.status {
        case .ok: .ok
        case .warn: .warn
        case .fail: .fail
        }
        return RepoCheckRow(title: title, status: status, detail: found.detail, fix: found.fix, role: role)
    }
    func signRow(_ role: AgentRole) -> RepoCheckRow {
        let profile = roles.first { $0.role == role }?.value.profile
        let found = checks.first { check in
            check.name.hasSuffix(" can mint a token for \(repo)") && profile.map { check.profiles?.contains($0) == true } == true
        }
        return row("\(role.title) can sign here", role: role, found)
    }
    return RepoChecks(
        rows: [
            row("Carrier can read it", checks.first { $0.name.hasSuffix(" can read \(repo)") }),
            signRow(.author), signRow(.reviewer),
            row("Solve is set up", checks.first { $0.name == "\(repo) has the Solve labels" }),
        ],
        note: note
    )
}
