import SwiftUI

extension EnvironmentValues {
    /// Whether the row the view is in is selected or hovered: its project icon wears its colour then and is neutral otherwise. True
    /// outside the sidebar's rows, where the icon is always coloured.
    @Entry public var rowActive = true
    /// How the sidebar row the view is in stands: at rest, under the pointer, or selected. At rest outside the sidebar's rows.
    @Entry public var rowState = RowState.resting
}

public enum RowState { case resting, hovered, selected }
