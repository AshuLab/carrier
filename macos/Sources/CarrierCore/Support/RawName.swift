import Foundation

/// A value the app has no words for (a stage, a harness or an outcome added later, a mark it does not know) shown by its own name, each word with a capital
/// first letter and the rest as it came ("gave up" is "Gave Up", "review" is "Review"). The one form of every such fallback: a value the app knows never
/// comes here, it has a copy key.
func capitalizingFirst(_ name: String) -> String {
    name.split(separator: " ", omittingEmptySubsequences: false).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}
