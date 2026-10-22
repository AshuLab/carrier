import CarrierCore
import SwiftUI

/// The Menu bar tab of Settings: the icon's style, its animation and the epics in the menu. The values live in user defaults
/// (`MenuBarStore`); the icon and the menu follow them.
struct MenuBarTabView: View {
    @AppStorage(MenuBarStore.styleKey) private var style = IconStyle.countAndBar
    @AppStorage(MenuBarStore.animatesKey) private var animates = true
    @AppStorage(showEpicsKey) private var showEpics = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Menu bar icon").fontWeight(.medium)
                Text("What the icon shows while Carrier works").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(IconStyle.allCases, id: \.self) { option in
                        IconStyleChoice(option: option, selected: style == option) { style = option }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            MenuBarSwitchRow(
                title: "Animate while working", detail: "A small bouncing segment, capped at 20 frames per second", isOn: $animates
            )
            MenuBarSwitchRow(title: "Show epics in the menu", detail: "List each epic and its state under the status line", isOn: $showEpics)
        }
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
    }
}

private struct MenuBarSwitchRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.vertical, 10).frame(minHeight: 46)
        .overlay(alignment: .top) { Divider() }
    }
}

/// One style as a small preview of the icon in a button, ringed when it is the chosen one.
private struct IconStyleChoice: View {
    let option: IconStyle
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    if option != .barOnly { Text("2").font(.system(size: 12, weight: .semibold).monospacedDigit()) }
                    if option != .countOnly {
                        Capsule().fill(.white.opacity(0.28)).frame(width: 26, height: 5)
                            .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 14, height: 5) }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.16)))
                Text(option.title).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8).frame(minWidth: 96)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.secondary.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.accentColor, lineWidth: selected ? 1.5 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
