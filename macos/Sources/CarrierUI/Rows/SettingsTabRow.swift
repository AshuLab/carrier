import CarrierCore
import SwiftUI

/// A row of these tabs: a title and a line under it on the left, the control on the right. In a page that is a native `Form` it is a
/// `LabeledContent` of its section; elsewhere it is a row of a card.
public struct SettingsTabRow<Control: View>: View {
    /// What the search finds the row by (`SettingsIndex`), whatever its title says; a row that is not searched (a value, a model's name) has none.
    var id: String?
    let title: String
    let detail: String
    var first = false
    var mono = false
    /// More room above and below, for a form with many fields stacked; the line between rows stays halfway.
    var roomy = false
    /// A third line for what the row is and not what it says (a path, a login): monospaced and quieter than the detail.
    var note: String?
    /// What is wrong with the value, in words: it takes the place of the detail, in orange and with a warning mark, the title keeps its colour, and
    /// every `settingsField` and `NumberField` inside the row draws itself as invalid (`\.settingsInvalid`). One argument; nothing else to pass.
    var problem: String?
    /// The detail wraps over as many lines as it needs, for a report whose every line the person has to read (Projects' Last clean up), where it is otherwise cut at two.
    var wrapsDetail = false
    /// A tile at the row's left, before the title (an account's avatar); the text keeps its place after it.
    var leading: AnyView?
    @ViewBuilder var control: Control

    public init(
        id: String? = nil,
        title: String,
        detail: String,
        first: Bool = false,
        mono: Bool = false,
        roomy: Bool = false,
        note: String? = nil,
        problem: String? = nil,
        wrapsDetail: Bool = false,
        leading: AnyView? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.first = first
        self.mono = mono
        self.roomy = roomy
        self.note = note
        self.problem = problem
        self.wrapsDetail = wrapsDetail
        self.leading = leading
        self.control = control()
    }
    @Environment(\.settingsForm) private var form

    private var words: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Text(title).fontWeight(.medium)
            if detail.isEmpty == false || problem != nil {
                Group {
                    if let problem { Label(problem, icon: .warningFilled, size: 11).foregroundStyle(.orange) } else { Text(detail).foregroundStyle(.secondary) }
                }
                .scaledFont(mono ? 11.5 : 11, design: mono ? .monospaced : nil).lineLimit(wrapsDetail ? nil : 2).truncationMode(.middle)
            }
            if let note {
                // cut in the middle to one line: the whole of it (a long PATH) is in the tooltip, and it can be selected to copy
                Text(note).scaledFont(10.5, design: .monospaced).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).padding(.top, Tokens.Space.s1)
                    .help(note).textSelection(.enabled)
            }
        }
    }

    public var body: some View {
        if form {
            // an HStack and not a LabeledContent: that one sets the control at the height of the first line, so on a row with a detail line the
            // switches and selects would not sit in the middle of it
            HStack(spacing: Tokens.Space.s12) {
                if let leading { leading }
                words
                Spacer(minLength: 8)
                control.environment(\.settingsInvalid, problem != nil)
            }
            .frame(minHeight: 36)
            .settingsAnchored(id)
        } else {
            HStack(spacing: Tokens.Space.s12) {
                if let leading { leading }
                words
                Spacer(minLength: 8)
                control.environment(\.settingsInvalid, problem != nil)
            }
            .padding(.vertical, roomy ? Tokens.Space.s14 : Tokens.Space.s10).frame(minHeight: 46)
            .overlay(alignment: .top) { if first == false { SettingsDivider() } }
            .settingsAnchored(id)
        }
    }
}
