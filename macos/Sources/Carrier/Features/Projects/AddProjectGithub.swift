import AppKit
import CarrierCore
import SwiftUI

// What the shared sheet asks of GitHub: the person's repositories, a pasted address, and the clone.

extension AddProjectSheet {
    /// ponytail: five pages of thirty are read, the newest pushes; a person with more types the address or searches for it, which the check below handles.
    private static let listedPages = 5

    /// The person's repositories, page by page, and what the host can do; the host's own words when it cannot list them.
    func loadRepositories(_ host: SocketChatHost) async {
        let found = (try? await host.capabilities()) ?? []
        capabilities = found
        // a host that did not answer is not one that is older: the clone itself says so
        if found.isEmpty == false { github.canClone = found.contains(newSession == nil ? .projects : .repoBranches) }
        guard found.contains(.githubRepos) else { return }
        for page in 1...Self.listedPages {
            do {
                let loaded = try await host.githubRepos(page: page)
                github.repos += loaded.repos.filter { isRepoName($0.name) }
                if loaded.hasMore == false { return }
            } catch ControlError.remote(let refusal) {
                github.listingProblem = refusal.shown()
                return
            } catch {
                return
            }
        }
    }

    /// A pasted address that is not in the person's repositories is looked up on GitHub once typing pauses, so a repository the login cannot see says so
    /// before Clone is pressed.
    func checkPastedRepository() {
        checkTask?.cancel()
        guard let repo = repoReference(query), capabilities.contains(.repoBranches),
            github.repos.contains(where: { $0.name.lowercased() == repo.lowercased() }) == false
        else { return }
        let key = repo.lowercased()
        switch github.visibility[key] {
        case .visible, .notVisible, .problem: return
        case .checking, nil: break
        }
        github.visibility[key] = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard Task.isCancelled == false else { return }
            do {
                _ = try await SocketChatHost().repoBranches(repo)
                github.visibility[key] = .visible
            } catch ControlError.remote(let refusal) {
                github.visibility[key] = isRepoNotVisible(refusal) ? .notVisible : .problem(refusal.shown())
            } catch {
                github.visibility[key] = nil
            }
        }
    }

    func clone(_ repo: String, into parent: String?) {
        problem = nil
        Task {
            do {
                try await model.startClone(repo, into: parent)
                dismiss()
            } catch ControlError.remote(let refusal) {
                problem = refusal.shown()
            } catch {
                problem = hostNotRunningWords()
            }
        }
    }

    /// The system's folder panel for the folder this one clone goes in (the default is left as it is); refused for a folder inside Carrier's own.
    func chooseParent(for repo: String, current: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: current)
        panel.prompt = Copy.projectsChoose()
        panel.message = Copy.projectsCloneIntoMessage(repo: repo)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let refusal = projectsFolderRefusal(url.path, carrierFolder: currentCarrierFolder()) {
            problem = refusal.shown()
            return
        }
        problem = nil
        github.chosenParents[repo.lowercased()] = url.path
    }
}
