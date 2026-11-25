import Foundation

// Starting the chat host from the app, the way `StartCarrier.swift` starts the engine: same command shape, same `PATH`, same
// outcome and alert. The app opening asks for it, and so does a session being started. The spawn lives in the shell.

/// `carrier chat-host` (`node <carrier> chat-host` for a script) with `CARRIER_HOME` set to the Carrier folder, its log in `<folder>/chat/logs/app-start.log`.
/// nil when `startMissing` is not empty.
public func startChatHostCommand(settings: SetupSettings, carrier: String?, environment: [String: String], home: String = NSHomeDirectory()) -> StartCommand? {
    guard let carrier, startMissing(settings, carrier: carrier).isEmpty else { return nil }
    let folder = carrierFolder(environment: environment, home: home)
    var environment = environment
    environment["PATH"] = enginePath(detected: settings.path, node: settings.node)
    environment["CARRIER_HOME"] = folder
    let places = CarrierPlaces(folder: folder)
    let run = carrierProgram(carrier: carrier, node: settings.node, arguments: ["chat-host"])
    return StartCommand(
        program: run.program, arguments: run.arguments, environment: environment,
        processDir: places.chat, logPath: places.chatStartLog, socketPath: places.chatSocket
    )
}

/// What the app does about the chat host when it opens, and when a session is being started: nothing (it answers, a start is
/// running, or the app is under `--fixture`, whose fake host answers and a real one must never start there), start it, or
/// say what the settings lack.
public enum ChatHostAtOpen: Equatable {
    case leave, start, missing([String])
}

public func chatHostAtOpen(settings: SetupSettings, carrier: String?, hostAnswers: Bool, startRunning: Bool, fixture: Bool) -> ChatHostAtOpen {
    guard hostAnswers == false, startRunning == false, fixture == false else { return .leave }
    let missing = startMissing(settings, carrier: carrier)
    return missing.isEmpty ? .start : .missing(missing)
}

/// What the Sessions section and the Sessions home say while the host cannot be started for lack of `node` or `carrier`.
public struct ChatHostNotice: Equatable {
    public var title: String
    public var line: String
}

/// nil when nothing is missing.
public func chatHostNotice(missing: [String], bundle: Bundle? = nil, locale: Locale = .current) -> ChatHostNotice? {
    guard missing.isEmpty == false else { return nil }
    // the names are the tools' own, joined with the word "and" of the language
    let names = missing.formatted(.list(type: .and).locale(locale))
    let line = missing.contains("carrier")
        ? Copy.lifecycleChatHostMissingCarrier(names: names, command: carrierInstallCommand.joined(separator: " "), bundle: bundle, locale: locale)
        : Copy.lifecycleChatHostMissingNode(names: names, bundle: bundle, locale: locale)
    return ChatHostNotice(title: Copy.lifecycleChatHostCannotStart(bundle: bundle, locale: locale), line: line)
}
