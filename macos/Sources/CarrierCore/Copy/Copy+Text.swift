import Foundation

// The words of a text code (docs/adr/0055): the catalog holds `text.<code>` with a specifier per argument (and `text.<code>.<branch>` for a select),
// so the key is made from the code and the params, in the order `TextShapes.generated.swift` gives.

/// The arguments of the catalog key of one text code; `select` names the param that picks a branch, and `variants` maps a branch ("" without a select) to its arguments, `name:n` or `name:s`.
struct TextShape {
    let select: String?
    let variants: [String: String]
}

/// Every code's shape, read once from the lines `TextShapes.generated.swift` holds (`code|select|branch=args|branch=args`).
let textShapes: [String: TextShape] = {
    var shapes: [String: TextShape] = [:]
    for line in textShapeLines.split(separator: "\n") {
        let fields = line.split(separator: "|", omittingEmptySubsequences: false)
        var variants: [String: String] = [:]
        for field in fields.dropFirst(2) {
            let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            variants[String(pair[0])] = String(pair[1])
        }
        shapes[String(fields[0])] = TextShape(select: fields[1].isEmpty ? nil : String(fields[1]), variants: variants)
    }
    return shapes
}()

extension Copy {
    /// The words of `code` with `params` in the language of `bundle` and `locale`; nil when the catalog has no such code, a param the key takes is missing
    /// or is not of its kind (a string for a number, a number that is not whole), or a select's param names no branch. A param the key does not take is ignored.
    public static func text(_ code: String, _ params: [String: TextParam] = [:], bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        guard let shape = textShapes[code] else { return nil }
        var branch = ""
        if let select = shape.select {
            guard case .string(let chosen)? = params[select] else { return nil }
            branch = shape.variants[chosen] == nil ? "other" : chosen
        }
        guard let kinds = shape.variants[branch] else { return nil }
        var key = "text.\(code)"
        if shape.select != nil { key += ".\(branch)" }
        var arguments: [CVarArg] = []
        for argument in kinds.split(separator: " ") {
            let parts = argument.split(separator: ":")
            key += parts[1] == "n" ? " %lld" : " %@"
            switch params[String(parts[0])] {
            case .string(let value)? where parts[1] == "s": arguments.append(value)
            case .number(let value)? where parts[1] == "n" && value.rounded() == value: arguments.append(Int(value))
            default: return nil
            }
        }
        // not `String(localized:)` with an interpolation: the compiler's localization-key pass tries to evaluate that at build time and, over this loop, ran for minutes and grew to gigabytes
        let format = (bundle ?? carrierResources).localizedString(forKey: key, value: missing, table: nil)
        return format == missing ? nil : String(format: format, locale: locale, arguments: arguments)
    }
}

private let missing = "\u{1}"

/// What a person reads for a text Node or the app sent with a code: the copy of a known code, and `words` (English) for an unknown code, no code,
/// or a text stored before the codes.
public func shownText(_ words: String, code: String?, params: [String: TextParam]?, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    guard let code else { return words }
    return Copy.text(code, params ?? [:], bundle: bundle, locale: locale) ?? words
}

extension Refusal {
    /// What the person reads: the copy of the refusal's code, or its words (`text`), which stay what is logged and decided by.
    public func shown(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        shownText(text, code: code, params: params, bundle: bundle, locale: locale)
    }
}
