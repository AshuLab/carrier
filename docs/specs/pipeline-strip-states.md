# The pipeline strip shows where an epic is, with no times

Status: spec

## Problem

The pipeline strip fixed on top of an epic's view in the macOS app mixes two things: where the epic is and how long each stage took. It shows `Queued 4s`, `Ship 5m`, `Review/Fix 2 rounds` and `Ready 7m ago`, and while an epic runs it shows `1st in queue`, a ticking time on Ship and `r2/5` on review. Diego does not want the times or the rounds there; the strip should answer one question, which step the epic is at. The Details tab and the sidebar already say when, and the Review tab already says which round.

Review and fix is also the one step that is not a straight line: the reviewer sends the epic back to the fixer and again to the reviewer until it approves. The strip draws it like any other step, a blue circle with its number, so nothing says that it goes back and forth.

## Solution

The strip carries no time and no count anywhere. Queued, Ship, Review / Fix and Ready are drawn by state alone: a step not started is grey, a step running is blue, a step finished is a green check. The name `Review/Fix` is written `Review / Fix`.

Review / Fix running is the one blue step that does not show its number: it shows the loop glyph (`arrow.triangle.2.circlepath`) and the glyph turns, to say the work goes back and forth until it is done. The turn follows the rule the spinning rings already follow: one Core Animation animation capped at 20 fps, not running while the window is hidden, and still with Reduce Motion on. When review and fix finish the step becomes a green check like the others. The other running steps (Queued for an epic waiting for a slot, Ship) stay a blue circle with their number, and do not turn.

A step the epic is stuck at follows the attention colours of the glossary: orange when a person's input is needed, red when something failed. Review limit reached and the agent asking for help are orange; retries exhausted, a timeout, failed authentication, a workspace problem and an invalid pull request are red. A kind the app does not know, or a stuck epic with no kind, is orange, because a person has to act either way. The step shows `!` in that colour and, after its name, the same words the sidebar already uses for that kind (`review limit reached`, `the agent needs you`, `timed out`, and so on), which are neither a time nor a count. The loop does not turn there. When the strip is too narrow for labels they give way to the bare names, as today, and the words stay in the step's tooltip.

A cancelled epic is neither of the two: nobody is being asked for anything and nothing failed. The step where it stopped is grey with `✕`, as the sidebar already draws a cancelled epic, and says `cancelled`.

The strip in each state (`✓` green, `2` blue circle, `⟳` blue turning loop, `3` grey, `!` orange or red, `✕` grey):

```
waiting for a slot   1 Queued ── 2 Ship ── 3 Review / Fix ── 4 Ready
shipping             ✓ Queued ── 2 Ship ── 3 Review / Fix ── 4 Ready
review or fix        ✓ Queued ── ✓ Ship ── ⟳ Review / Fix ── 4 Ready
needs input (limit)  ✓ Queued ── ✓ Ship ── ! Review / Fix  review limit reached ── 4 Ready   (orange)
error (timeout)      ✓ Queued ── ✓ Ship ── ! Review / Fix  timed out ── 4 Ready                (red)
finished or merged   ✓ Queued ── ✓ Ship ── ✓ Review / Fix ── ✓ Ready
cancelled in ship    ✓ Queued ── ✕ Ship  cancelled ── 3 Review / Fix ── 4 Ready
cancelled in review  ✓ Queued ── ✓ Ship ── ✕ Review / Fix  cancelled ── 4 Ready
```

What was cut. Showing the rounds in the strip (`2 rounds`, `r2/5`, `limit 5/5`, now `review limit reached`) lost because the Review tab has them with their blockers. Keeping `7m ago` on Ready and `2m ago` on cancelled lost because the strip stops carrying time at all; the Details tab and the sidebar have when it finished. Keeping the time on the running Ship step lost for the same reason. A loop that stays still lost because a still glyph reads as just another icon; the cost of the turn is bounded by the cap and by not drawing it while hidden, which the spinning rings already do. Drawing a cancelled epic in red lost to the attention colours: it is neither an error nor a request.

## Scope

1. As Diego, I see no elapsed time and no round count anywhere in the strip, in any state, so it only says which step the epic is at.
2. As Diego, I read the third step as `Review / Fix`.
3. As Diego, I see a step not started in grey, a step running in blue and a step finished as a green check, and an epic waiting for a slot shows Queued as the running step with no text beside it.
4. As Diego, I see the loop glyph turning in the Review / Fix step while the epic is in review or fix, and a green check when it is done.
5. As Diego, I see the loop stop turning when the window is hidden or Reduce Motion is on, and when the epic is stuck.
6. As Diego, I see an epic stuck on a review limit or on the agent asking for help marked with an orange `!` and the words the sidebar uses for it, on the step where it is stuck, in ship or in review.
7. As Diego, I see an epic stuck on retries exhausted, a timeout, failed authentication, a workspace problem or an invalid pull request marked with a red `!` and those words.
8. As Diego, I see a cancelled epic marked with a grey `✕` and `cancelled` on the step where it stopped, and the steps it never reached in grey.
9. As Diego, I see a finished or merged epic with every step a green check and no text.

## Decisions

The model decides everything the view draws, so the view stays a mapping. `StepState` gains the stuck and cancelled cases and the step says whether it loops; the classification of a stuck kind is one function in `CarrierCore`, written so the sidebar's brief can reuse it:

```swift
public enum Attention: Equatable {
    case input, error
    /// nil kind and kinds the app does not know are `.input`: a person has to act either way.
    public init(kind: String?) {
        switch kind {
        case "retries_exhausted", "timeout", "auth", "workspace", "pr_invalid": self = .error
        default: self = .input
        }
    }
}

public enum StepState: Equatable { case done, current, waiting, input, error, cancelled }

public struct PipelineStep: Equatable {
    public var name: String
    public var state: StepState
    /// Only the words of a stuck or cancelled step; never a time or a count.
    public var label: String?
    /// True only for Review / Fix while the epic is in review or fix and not stuck.
    public var loops: Bool
}
```

The words of a stuck step are the sidebar's `interventionLine`, reused and not copied. `pipelineSteps` keeps reading the same snapshot and reply; it stops turning durations and rounds into labels, so the `took`, `reviewLabel`, `formatDuration` and `agoLine` uses in it go away with the parameters they needed. The engine's stage is still how the stuck step is found (ship, or review and fix).

Any other part of the app that classifies a stuck kind should use `Attention`, not a second list. The sidebar's rows do in their own epic, and that epic is built after this one so the type exists.

The turn of the glyph reuses the ring's way of running (the capped animation and the window-visibility and Reduce Motion gating of `RingHostView`) and does not add a SwiftUI repeating animation, which the app's research measured at 9% to 12% of a core.

Testing seams. Stories 1 to 3 and 6 to 9 go through `pipelineSteps` in `macos/Tests/CarrierCoreTests/EpicViewTests.swift`, the seam that already pins the strip: one case per row of the table above, the old expectations replaced, plus the kinds in `Attention(kind:)` including `nil` and an unknown string, which must come out `.input`. Story 4 is the `loops` flag of the same function (true for review or fix, false for ship, queued, stuck, finished). Story 5 is the animation gating and has no automated test: it is Core Animation behaviour, checked by Diego with the window hidden, Reduce Motion on and the epic stuck; the checklist also covers light and dark, a narrow window and the colours.

## Out of scope

The sidebar's rows (their own brief), the Details tab, the Review tab and the toolbar pill, which keep their times and rounds. Applying the attention colours to the rest of the app (the pill, the menu bar, the Overview, the tab counts, the repositories chips), which still draw every stuck epic in orange. The pipeline's data (`pipelineSteps` still reads the same snapshot and reply; it only stops turning them into labels). Any new step, and a different glyph for Ship or Queued. A time or a round count in the tooltip.
