import Foundation

/// A value as one word for a POSIX shell: wrapped in single quotes, where nothing is special, and each single
/// quote written as `'\''` (close, an escaped quote, open again). Any text survives, newlines and a leading dash
/// included; only a NUL byte cannot be passed through a shell, so callers validate their values first.
public func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
