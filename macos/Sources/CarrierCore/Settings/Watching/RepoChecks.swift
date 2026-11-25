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
    /// "Use another identity": offered by a failed sign row, for that row's role. Ok, waiting, read and Solve rows offer none.
    public var anotherIdentity: AgentRole? { status == .fail ? role : nil }
}

public struct RepoChecks: Equatable {
    public var rows: [RepoCheckRow]
    /// said above the rows while the doctor runs or when it could not answer
    public var note: String?
}

public func repoChecks(repo: String, roles: [RepoRoleRow], doctor: DoctorState, bundle: Bundle? = nil, locale: Locale = .current) -> RepoChecks {
    var checks: [DoctorCheck] = []
    var note: String?
    switch doctor {
    case .checks(let all): checks = all.filter { $0.repo == repo }
    case .running: note = Copy.watchingDoctorRunning(bundle: bundle, locale: locale)
    case .unknown(let reason): note = Copy.watchingDoctorUnknown(reason: reason, bundle: bundle, locale: locale)
    case .refused(let reason): note = Copy.watchingDoctorRefused(reason: reason, bundle: bundle, locale: locale)
    case .idle: break
    }
    func row(_ title: String, role: AgentRole? = nil, _ found: DoctorCheck?) -> RepoCheckRow {
        guard let found else { return RepoCheckRow(title: title, status: .waiting, detail: Copy.watchingNotCheckedYet(bundle: bundle, locale: locale), role: role) }
        let status: RepoCheckRow.Status = switch found.status {
        case .ok: .ok
        case .warn: .warn
        case .fail: .fail
        }
        return RepoCheckRow(title: title, status: status, detail: found.shownDetail(bundle: bundle, locale: locale), fix: found.shownFix(bundle: bundle, locale: locale), role: role)
    }
    // a check that failed says what it is by the code of its detail; one that passed has none, and its name says it
    func matches(_ code: String, _ suffix: String, _ check: DoctorCheck) -> Bool { check.detailCode == code || (check.detailCode == nil && check.name.hasSuffix(suffix)) }
    func signRow(_ role: AgentRole) -> RepoCheckRow {
        let profile = roles.first { $0.role == role }?.value.profile
        let found = checks.first { check in
            matches("doctor.mintFailed", " can mint a token for \(repo)", check) && profile.map { check.profiles?.contains($0) == true } == true
        }
        return row(Copy.watchingCheckSign(role: role.title(bundle: bundle, locale: locale), bundle: bundle, locale: locale), role: role, found)
    }
    return RepoChecks(
        rows: [
            row(Copy.watchingCheckRead(bundle: bundle, locale: locale), checks.first { matches("doctor.readFailed", " can read \(repo)", $0) }),
            signRow(.author), signRow(.reviewer),
            row(Copy.watchingCheckSolve(bundle: bundle, locale: locale), checks.first { matches("doctor.labelsMissing", " has the Solve labels", $0) }),
        ],
        note: note
    )
}
