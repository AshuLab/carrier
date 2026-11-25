import SwiftUI

extension View {
    /// The small uppercase title over a group or a list: the type and the colour; the caller adds the padding its place needs.
    public func sectionLabel() -> some View { scaledFont(10, weight: .semibold).foregroundStyle(.secondary).textCase(.uppercase) }
}
