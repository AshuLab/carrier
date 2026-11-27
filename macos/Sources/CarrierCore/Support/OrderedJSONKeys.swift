import Foundation

/// The keys of the JSON object that `path` leads to in `data`, in the order the file has them; nil when `path` leads to anything but an object.
/// A step that is a whole number goes into the array at the cursor by position (`["repos", "1", "agents", "extraReviewers"]`).
/// `JSONSerialization` gives a dictionary, which loses the order, and the map of extra reviewers keeps it (ADR 0057). The keys are read as they are
/// written, which is all a slug needs; `data` is already known to be JSON, so a malformed one just gives nil.
func jsonKeys(in data: Data, at path: [String]) -> [String]? {
    var scanner = KeyScanner(bytes: Array(data))
    return scanner.keys(at: path[...])
}

private struct KeyScanner {
    let bytes: [UInt8]
    var index = 0

    private mutating func skipSpace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func take(_ character: Character) -> Bool {
        skipSpace()
        guard index < bytes.count, bytes[index] == character.asciiValue else { return false }
        index += 1
        return true
    }

    /// A string at the cursor, as written between the quotes.
    private mutating func string() -> String? {
        guard take("\"") else { return nil }
        let start = index
        while index < bytes.count, bytes[index] != UInt8(ascii: "\"") { index += bytes[index] == UInt8(ascii: "\\") ? 2 : 1 }
        guard index < bytes.count else { return nil }
        defer { index += 1 }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    /// Moves past the value at the cursor.
    private mutating func skipValue() -> Bool {
        skipSpace()
        guard index < bytes.count else { return false }
        switch bytes[index] {
        case UInt8(ascii: "\""): return string() != nil
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            repeat {
                guard index < bytes.count else { return false }
                switch bytes[index] {
                case UInt8(ascii: "\""): if string() == nil { return false }; continue
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
                default: break
                }
                index += 1
            } while depth > 0
            return true
        default:
            while index < bytes.count, ",}] \n\t\r".utf8.contains(bytes[index]) == false { index += 1 }
            return true
        }
    }

    /// The members of the object at the cursor: the keys when `path` is spent, else the keys of the member `path` names.
    mutating func keys(at path: ArraySlice<String>) -> [String]? {
        if let position = path.first.flatMap({ Int($0) }), take("[") {
            for _ in 0..<position { guard skipValue(), take(",") else { return nil } }
            return keys(at: path.dropFirst())
        }
        guard take("{") else { return nil }
        var found: [String] = []
        while take("}") == false {
            _ = take(",")
            guard let key = string(), take(":") else { return nil }
            if key == path.first { return keys(at: path.dropFirst()) }
            found.append(key)
            guard skipValue() else { return nil }
        }
        return path.isEmpty ? found : nil
    }
}
