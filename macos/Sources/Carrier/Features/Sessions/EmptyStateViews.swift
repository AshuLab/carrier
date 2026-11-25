import CarrierCore
import SwiftUI

extension EmptyStateView {
    /// The empty state `state` says: its icon, title and line, and an optional button under them.
    init(
        state: EmptyState,
        action: (title: String, run: () -> Void)? = nil,
        actionIcon: AppIcon? = nil,
        actionStyle: EmptyStateActionStyle = .secondary
    ) {
        self.init(icon: state.icon, title: state.title(), line: state.line(), action: action, actionIcon: actionIcon, actionStyle: actionStyle)
    }
}

extension SidebarEmptyBlock where Action == EmptyView {
    init(state: EmptyState) { self.init(icon: state.icon, title: state.title(), line: state.line()) { EmptyView() } }
}

extension SidebarNoResults {
    /// What a section says when `query` matches nothing in it.
    init(query: String, clear: @escaping () -> Void) {
        self.init(icon: EmptyState.noResults.icon, title: EmptyState.noResults.title(), line: EmptyState.noResultsLine(for: query), clear: clear)
    }
}
