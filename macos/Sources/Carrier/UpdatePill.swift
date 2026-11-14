import SwiftUI

/// The sidebar's title bar, after the window's buttons: the version a scheduled check found, as a glass pill that opens Sparkle's window.
/// Absent while there is nothing new.
struct UpdatePill: View {
    let available = AppUpdater.available

    @ToolbarContentBuilder static var item: some ToolbarContent {
        ToolbarItem(placement: .automatic) { UpdatePill() }.sharedBackgroundVisibility(.hidden)
    }

    var body: some View {
        if let version = available.version {
            ToolbarPillButton(title: "Update \(version)", icon: "arrow.down.circle", iconTint: .themeAccent) { AppUpdater.showUpdate() }
                .glassEffect(.regular, in: .capsule)
                .help("Carrier \(version) is available")
        }
    }
}
