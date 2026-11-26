import Foundation

/// Only a UUID goes on the wire as the session id, as the host accepts nothing else.
func wireId(_ id: String) throws -> String {
    guard let id = UUID(uuidString: id)?.uuidString.lowercased() else { throw ControlError.remote(.sessionIdInvalid) }
    return id
}

/// A string as a JSON literal, so quotes, newlines and anything else in it stay inside the string on the wire.
func jsonString(_ text: String) -> String { String(decoding: (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8), as: UTF8.self) }

/// Makes one request the host said it can answer, on a connection whose hello was read, and decodes its reply.
func chatExchange<Reply: Decodable>(
    _ client: ControlClient, _ command: String, requires capability: ControlClient.Capability, fields: String = "",
    also: [(capability: ControlClient.Capability, fields: String)] = []
) throws -> Reply {
    // fields only a host that lists their capability understands: an older one is not sent them
    let sent = fields + also.filter { client.capabilities.contains($0.capability) }.map(\.fields).joined()
    guard let reply = try client.request(command, requires: capability, fields: sent, as: Reply.self) else {
        throw ControlError.remote(.hostLacks(command))
    }
    return reply
}

/// Connects, reads the hello, makes one request the host said it can answer and decodes its reply.
func chatRequest<Reply: Decodable>(
    _ path: String, _ command: String, requires capability: ControlClient.Capability, fields: String = "", also: [(capability: ControlClient.Capability, fields: String)] = [],
    timeout: TimeInterval = 5
) throws -> Reply {
    let signpost = Signposts.poll.beginInterval("chat request", id: Signposts.poll.makeSignpostID(), "\(command, privacy: .public)")
    defer { Signposts.poll.endInterval("chat request", signpost) }
    guard let client = ControlClient.connect(path: path, timeout: timeout) else { throw ControlError.closed }
    defer { client.close() }
    _ = try client.supportedHello()
    return try chatExchange(client, command, requires: capability, fields: fields, also: also)
}

/// `chatRequest`, but a host that does not list the request is told in the words of what to do about it.
func usageRequest<Reply: Decodable>(_ path: String, _ command: String, requires capability: ControlClient.Capability, fields: String, timeout: TimeInterval = 5) throws -> Reply {
    do { return try chatRequest(path, command, requires: capability, fields: fields, timeout: timeout) } catch ControlError.remote(let reason) where reason.isHostLacking(command) {
        throw ControlError.remote(.usageNeedsNewerHost)
    }
}

/// `chatRequest` for the `projects` capability (or `capability`, for a request whose reply changed later), but a host that does not list it is told in the words of what to do about it.
func projectsRequest<Reply: Decodable>(_ path: String, _ command: String, requires capability: ControlClient.Capability = .projects, fields: String = "", timeout: TimeInterval = 5) throws -> Reply {
    do { return try chatRequest(path, command, requires: capability, fields: fields, timeout: timeout) } catch ControlError.remote(let reason) where reason.isHostLacking(command) {
        throw ControlError.remote(.projectsNeedNewerHost)
    }
}

public let hostNotRunning = "The chat host is not running"
