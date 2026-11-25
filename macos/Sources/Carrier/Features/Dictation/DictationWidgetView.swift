import AppKit
import CarrierCore
import SwiftUI

struct DictationWidgetView: View {
    let dictation: GlobalDictation
    let style: DictationWidgetStyle
    let livePreview: Bool
    let theme: DictationWidgetTheme
    /// The keys line: what ends the dictation and Esc.
    let hint: () -> String
    let voice: () -> VoiceLevels
    /// Copy was pressed; it goes back when the widget has new text.
    @State private var copied = false
    /// The check or x of a dictation that ended has faded.
    @State private var faded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let look = dictationWidgetLook(dictation.shown, style: style, livePreview: livePreview)
        Group {
            if let box = look.box { boxed(look, box) } else if let icon = look.icon { PillIcon(icon: icon, cause: dictation.notCleaned) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // the message box's line, outside the box and only while it listens
        .background {
            if dictation.shown == .listening { DictationIndicator(levels: voice(), radius: look.radius) }
        }
        .modifier(WidgetSurface(shape: look.shape, theme: theme))
        .opacity(faded ? 0 : 1)
        .padding(DictationWidget.glow)
        .accessibilityElement(children: .contain)
        .onChange(of: dictation.state) { copied = false }
        // the panel is not in front of VoiceOver, so what it cannot be told to read is said
        .onChange(of: dictation.shown) { _, shown in
            switch (shown, dictation.state) {
            case (.copied, .copied(let reason)): AccessibilityNotification.Announcement(dictationKeptNotice(reason: reason)).post()
            case (.failed, .failed(let cause)): AccessibilityNotification.Announcement(Copy.dictationAnnounceFailed(cause: cause)).post()
            case (.pastedRaw, _): AccessibilityNotification.Announcement(Copy.dictationPastedRaw(cause: dictation.notCleaned ?? "")).post()
            default: break
            }
        }
        .task(id: look.fades) {
            faded = false
            guard look.fades else { return }
            try? await Task.sleep(for: .seconds(look.linger))
            // a state that changed during the wait cancels the task, and the widget has not ended
            guard Task.isCancelled == false else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: DictationWidget.fade)) { faded = true }
        }
    }

    @ViewBuilder private func boxed(_ look: DictationWidgetLook, _ box: DictationWidgetBox) -> some View {
        if case .copied(let reason) = dictation.state {
            WidgetBox(box: box, follows: false, notices: keptNotices(reason)) { Text(dictation.text).textSelection(.enabled) } foot: { keptButtons(reason) }
        } else if case .failed = dictation.state {
            // nothing is running: no clock and no finish key, only the way out
            WidgetBox(box: box) { shown } foot: {
                Spacer()
                Text(Copy.dictationEscToDismiss())
            }
        } else if look.fades {
            WidgetBox(box: box) { Text(dictation.text) } foot: {
                switch dictation.farewell {
                case .pasted: Label(Copy.dictationPasted(), icon: .check)
                case .pastedRaw: Label(Copy.dictationPastedRaw(cause: dictation.notCleaned ?? ""), icon: .warning).foregroundStyle(.orange).lineLimit(1)
                default: Label(Copy.dictationCancelled(), icon: .close)
                }
            }
        } else {
            WidgetBox(box: box) { shown } foot: {
                if let started = dictation.startedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(dictationClock(context.date.timeIntervalSince(started))).monospacedDigit()
                    }
                }
                Spacer()
                if dictation.shown == .cleaning {
                    Label(Copy.dictationCleaningSkip(), icon: .sparkles)
                } else if box.showsText == false, let caption = waitCaption {
                    // no words to say what it waits for: the line of the keys says it
                    Text(caption)
                } else {
                    Text(hint())
                }
            }
        }
    }

    /// Why the text was only copied, over the text, which is complete and scrolls under them.
    private func keptNotices(_ reason: PasteReason) -> [String] { dictationKeptNotices(reason: reason, notCleaned: dictation.notCleaned) }

    /// The buttons of a text that was only copied; when they do not fit the box's width they keep only their symbols.
    private func keptButtons(_ reason: PasteReason) -> some View {
        ViewThatFits(in: .horizontal) {
            keptRow(reason).labelStyle(.titleAndIcon)
            keptRow(reason).labelStyle(.iconOnly)
        }
        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
    }

    private func keptRow(_ reason: PasteReason) -> some View {
        HStack {
            if reason == .noPermission {
                Button { FocusedField.openSettings() } label: { Label(Copy.dictationOpenSystemSettings(), icon: .settings) }
                Button { FocusedField.resetPermission() } label: { Label(Copy.dictationResetPermission(), icon: .refresh) }
                    .help(Copy.dictationResetPermissionHelp())
            }
            Spacer()
            Button {
                dictation.copyAgain()
                copied = true
            } label: { Label(copied ? Copy.dictationCopied() : Copy.dictationCopy(), icon: copied ? .check : .copy) }
            .keyboardShortcut(.defaultAction)
            Button { dictation.dismissCopied() } label: { Label(Copy.dictationDismiss(), icon: .close) }
        }
    }

    /// What was heard: the firm words as normal text and the tentative ones in the partial colour with the dotted underline, as the message box draws them.
    private var heard: Text {
        let (firm, tentative) = dictation.split
        return Text("\(firm)\(Text(tentative).foregroundStyle(Color(nsColor: PillTextView.tentativeColor)).underline(pattern: .dot))")
    }

    /// What the widget says while it waits (Getting the model ready…, Transcribing…).
    private var waitCaption: String? {
        dictationPresentation(
            dictation.session.state, registered: true, modelReady: dictation.session.modelReady, answerIsSlow: dictation.session.answerIsSlow
        )?.caption
    }

    /// What the box says before the words come, and the cause when it cannot go on, over what was heard.
    @ViewBuilder private var shown: some View {
        let caption = waitCaption
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            if case .failed(let cause) = dictation.state { Text(cause).foregroundStyle(.red) }
            if dictation.text.isEmpty == false {
                // the raw text shimmers while the model cleans it
                heard.modifier(Shimmer(active: dictation.shown == .cleaning && reduceMotion == false))
            } else if dictation.state == .running, let caption {
                Text(caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The Pill's icon: the microphone in the accent while it listens, a spinner while it works, a sparkle while it cleans, a check when pasted, a warning
/// when it pasted without cleaning (`cause` says why, for VoiceOver) and an x when cancelled.
struct PillIcon: View {
    let icon: DictationWidgetIcon
    var cause: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch icon {
        case .sparkle:
            Glyph(.sparkles, label: Copy.dictationLabelCleaningIcon()).foregroundStyle(.tint).glyphPulsing(reduceMotion == false)
        case .warning:
            Glyph(.warningFilled, label: Copy.dictationPastedRaw(cause: cause ?? "")).foregroundStyle(.orange)
        case .mic: Glyph(.microphone, label: Copy.dictationListening()).foregroundStyle(.tint)
        case .spinner: ProgressView().controlSize(.small).accessibilityLabel(Copy.dictationWorking())
        case .check: Glyph(.check, label: Copy.dictationPasted()).foregroundStyle(.green)
        case .xmark: Glyph(.close, label: Copy.dictationCancelled()).foregroundStyle(.secondary)
        }
    }
}
