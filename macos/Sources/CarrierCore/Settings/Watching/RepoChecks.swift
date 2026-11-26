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

/// What is said above the checks while the doctor runs or when it could not answer; nil otherwise.
func doctorNote(_ doctor: DoctorState, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    switch doctor {
    case .running: Copy.watchingDoctorRunning(bundle: bundle, locale: locale)
    case .unknown(let reason): Copy.watchingDoctorUnknown(reason: reason, bundle: bundle, locale: locale)
    case .refused(let reason): Copy.watchingDoctorRefused(reason: reason, bundle: bundle, locale: locale)
    case .checks, .idle: nil
    }
}

/// A check of the doctor as a row; one the doctor did not report (`found` is nil) reads as waiting, with `missing` as its words.
func checkRow(_ title: String, role: AgentRole? = nil, _ found: DoctorCheck?, missing: String, bundle: Bundle? = nil, locale: Locale = .current) -> RepoCheckRow {
    guard let found else { return RepoCheckRow(title: title, status: .waiting, detail: missing, role: role) }
    let status: RepoCheckRow.Status = switch found.status {
    case .ok: .ok
    case .warn: .warn
    case .fail: .fail
    }
    return RepoCheckRow(title: title, status: status, detail: found.shownDetail(bundle: bundle, locale: locale), fix: found.shownFix(bundle: bundle, locale: locale), role: role)
}

/// A failed check says what it is by the code of its detail; one that passed has none, and its name says it.
func isCheck(_ code: String, suffix: String, _ check: DoctorCheck) -> Bool { check.detailCode == code || (check.detailCode == nil && check.name.hasSuffix(suffix)) }

/// The check of the doctor that says whether an identity can mint a token in `repo`.
func isMintCheck(_ check: DoctorCheck, repo: String) -> Bool { check.repo == repo && isCheck("doctor.mintFailed", suffix: " can mint a token for \(repo)", check) }

public func repoChecks(repo: String, roles: [RepoRoleRow], doctor: DoctorState, bundle: Bundle? = nil, locale: Locale = .current) -> RepoChecks {
    var checks: [DoctorCheck] = []
    if case .checks(let all) = doctor { checks = all.filter { $0.repo == repo } }
    func row(_ title: String, role: AgentRole? = nil, _ found: DoctorCheck?) -> RepoCheckRow {
        checkRow(title, role: role, found, missing: Copy.watchingNotCheckedYet(bundle: bundle, locale: locale), bundle: bundle, locale: locale)
    }
    func signRow(_ role: AgentRole) -> RepoCheckRow {
        let profile = roles.first { $0.role == role }?.value.profile
        let found = checks.first { check in isMintCheck(check, repo: repo) && profile.map { check.profiles?.contains($0) == true } == true }
        return row(Copy.watchingCheckSign(role: role.title(bundle: bundle, locale: locale), bundle: bundle, locale: locale), role: role, found)
    }
    return RepoChecks(
        rows: [
            row(Copy.watchingCheckRead(bundle: bundle, locale: locale), checks.first { isCheck("doctor.readFailed", suffix: " can read \(repo)", $0) }),
            signRow(.author), signRow(.reviewer),
            row(Copy.watchingCheckSolve(bundle: bundle, locale: locale), checks.first { isCheck("doctor.labelsMissing", suffix: " has the Solve labels", $0) }),
        ],
        note: doctorNote(doctor, bundle: bundle, locale: locale)
    )
}
