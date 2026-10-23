# A stopped epic can be resumed from the app

Status: spec

## Problem

When an epic stops in needs-human, the only way to get it going again is to put the `solve:epic:ready` label back on its issue by hand on GitHub, and `docs/troubleshooting.md` says so: "There is no command or key for it". The macOS app shows why the epic stopped and has nothing to say or do about what comes next. It happened for real: the account Carrier runs on ran out of Claude credits, the epic retried several times, failed and stopped, and once the credits were back the person who fixed it had to leave the app and edit labels on GitHub to continue.

The engine already knows how to continue: a poll that finds `ready` on a stopped epic starts it again from ship, reusing the worktree and the pull request. What is missing is a way to ask for it from the app, and a place in the epic's view that tells the person it is possible and what will happen.

## Solution

The engine gets one new command on the control socket, `resumeEpic`, for one epic by repository and number. It does what the person does by hand today, no more: it puts `solve:epic:ready` on the epic's issue and runs a check, and the poll that finds `ready` on a stopped epic starts it again from ship, with its worktree and pull request, the review rounds starting over. The `needs-human` mirror comes off when the epic starts, through the reconciliation the engine already does. SQLite stays the authority and the labels stay its mirror, so ADR 0002 does not change and nothing is requeued behind GitHub's back. The command is named `resumeEpic` because the socket already has a `resume` that takes the engine out of pause.

The command answers when the epic has started again, not when the label is on, so the app never waits on something that may not happen. It refuses with a reason the app can show when the epic is unknown or is not stopped, when GitHub cannot be reached, and when the epic did not start within thirty seconds of the label going on (the label stays, and the next check takes it). An engine that does not list `resumeEpic` among its capabilities cannot be asked.

The app shows the epic's stuck state in a card between the title and the tabs, only while the epic is in needs-human, whatever the kind. The card says the reason in words, says in one line what resuming does for that kind, and has the button, **Resume**. The card's colour follows the attention colours: orange when a person's input is needed, red when something failed. The words by kind: for the failures (retries exhausted, timed out, authentication failed, workspace problem, invalid pull request) it asks to fix the cause and then resume; for the review limit it says resuming gives the epic five new rounds; for the agent asking for help it says to do what the agent asked on the pull request first. Against an engine that cannot be asked, the card shows the reason and the words with no button. The exploration with the three placements and the words is in `docs/research/macos-app-design/explorations/resume-button-options.html` (option C).

Resume always asks first. A sheet says what will happen: `solve:epic:ready` goes back on the issue, the epic starts again from ship reusing its worktree and its pull request, the review rounds start over, and if the cause is not fixed it will stop here again. After confirming, the button reads "Resuming…" until the engine answers. On success the epic is running again and the card is gone with the stuck state; on a refusal the card stays, shows the reason in words, and the button comes back.

Nothing checks that the cause is fixed. If the credits are still empty the epic retries, fails and stops again with the new error and the card comes back. The engine cannot know in advance whether credits will be enough, and a check that guesses wrong would block a resume that would have worked.

What was cut. A button in the toolbar next to "Open issue" lost because it is far from the reason and has no room for the words by kind; a button beside the status pill lost for the same reason, the pill being too small to say what resuming does. The app putting the label on GitHub itself lost because it has no GitHub credentials and talks to the engine only through the control socket (ADR 0005). The engine requeuing from SQLite without touching the label lost because GitHub would disagree with the app until the next reconciliation, and because the label is the contract with Solve. A preflight that tries the cause (credits, login) before resuming lost as above. Resuming with no confirmation lost because the action restarts the review rounds and publishes a label change on GitHub, so the person should read what happens first. An answer sent as soon as the label is on lost because the button could then say "Resuming…" for as long as the next check takes, or forever when the epic never starts. The button is called Resume and not Retry: an execution retry is the automatic one after a technical failure (glossary).

## Scope

1. As Diego, I see a card with the reason in words whenever an epic is stopped in needs-human, whatever the kind, between the title and the tabs.
2. As Diego, I read in the card what resuming does for that kind: fix the cause first for the failures, five new review rounds for the review limit, do what the agent asked first when it asked for help.
3. As Diego, I see the card orange when my input is needed and red when something failed, the same as the strip.
4. As Diego, I press Resume and a sheet tells me what will happen before anything is sent; Cancel sends nothing.
5. As Diego, I confirm and the button reads "Resuming…" until the engine answers.
6. As Diego, when the epic starts again I see it running, the card gone, and `solve:epic:ready` was put back by Carrier, not by me.
7. As Diego, when the engine refuses (unknown epic, not stopped, GitHub unreachable, did not start in time) I see the reason in the card and the button comes back.
8. As Diego, when the cause was not fixed I see the epic stop again with its new reason and the card back, with nothing else to do.
9. As Diego, with an engine too old to be asked I see the card without the button.
10. As someone reading `docs/troubleshooting.md`, I find Resume as the way to continue an epic in needs-human, and putting the label back by hand as what it still does.

## Decisions

The command, in `src/control/server.ts`, follows the allowlist the other per-epic requests use and is a capability so the app knows whether it can ask:

```ts
z.strictObject({ id, cmd: z.literal('resumeEpic'), repo, issue }),
export type Capability = 'sessions' | 'events' | 'epic' | 'files' | 'availableRepos' | 'resumeEpic';
// Controls gains: resumeEpic(repo: string, issue: number): Promise<void>; it rejects with one of the refusals below
type ResumeRefusal = 'unknown epic' | 'not stopped' | 'github unavailable' | 'did not restart';
// reply: { id, ok: true } on success, { id, ok: false, error: ResumeRefusal } otherwise; anything else is 'internal error'
```

In the engine, the command refuses `unknown epic` when SQLite has no such epic and `not stopped` when its status is not `needs_human`, puts the ready label with the GitHub client the engine already uses, runs a poll through the same single-flight guard a person's check uses, and answers once the epic's status is no longer `needs_human`, or `did not restart` after thirty seconds. It must not change what a restart keeps or drops. The wait on a poll that was already running is that poll.

In the app, the request goes through `ControlRequests` and `ControlClient` like the other commands; the card's content (title, words, attention, sheet lines) is a plain value in `CarrierCore` built from the epic's stuck kind, reusing `Attention` and the sidebar's `interventionLine`, so the view only draws it. The words of a refusal are the app's own, one per `ResumeRefusal`.

`docs/troubleshooting.md` is updated: the sentence "There is no command or key for it" goes, Resume is the way, and the label by hand stays as what it does underneath. The glossary term **Resume (an epic)** is already written.

Testing seams. The engine behaviour (stories 6 to 8) goes through `src/orchestration/engine.test.ts` with its fake GitHub: an epic in needs-human is started again and ends `running` with the label calls recorded; an unknown epic and a running one are refused; GitHub failing gives `github unavailable` and leaves the epic stopped; an epic that does not start gives `did not restart` with the label left on (a clock the test controls, not a real wait). The request's shape, its rejection of extra fields and of a bad repository, and the capability in the hello go through `src/control/server.test.ts`, the seam that already pins the allowlist. The app's side goes through `macos/Tests/CarrierCoreTests`: the card per stuck kind (words, attention, with and without the button for an engine that cannot be asked), the request `ControlRequests` builds, and the refusal words, next to the existing tests of those files. The sheet, the "Resuming…" state and the layout have no automated test; Diego checks them against the exploration with the fixture and, with the real engine, on an epic he stops on purpose, in light and dark.

## Out of scope

What a requeue keeps or drops: the epic starts from ship with the rounds starting over, as it does today when the label goes back by hand; changing that is another decision. Resuming a cancelled or finished epic. Resuming from the menu bar, the sidebar or the Overview. A way to resume several epics at once. Telling the person what to fix (the words say what kind of failure it was, not how to repair it). Colouring the rest of the app by the attention colours, which is its own pending work.
