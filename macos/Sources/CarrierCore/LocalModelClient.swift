import Foundation

/// The `TextModelClient` over the HTTP API both LM Studio and Ollama serve: `GET /v1/models` and `POST /v1/chat/completions`, with the prompt as the
/// system message and the text as the user message, no tools. `baseURL` is on this Mac (the servers' loopback ports); tests point it at a stub.
public struct LocalModelClient: TextModelClient {
    private let baseURL: @Sendable (CleanupServer) -> URL
    private let session: URLSession

    public init(baseURL: @escaping @Sendable (CleanupServer) -> URL = { $0.baseURL }) {
        self.baseURL = baseURL
        // no cache, no cookies, no credentials: nothing about a dictation is kept by the loading system
        session = URLSession(configuration: .ephemeral)
    }

    public func models(of server: CleanupServer) async throws -> [String] {
        let data = try await send(server, path: "/v1/models", body: nil, timeout: 3, notFound: .badReply("\(server.title) has no list of models"))
        guard let ids = (try? JSONDecoder().decode(ModelList.self, from: data))?.data.map(\.id) else {
            throw CleanupFailure.badReply("\(server.title) answered something that is not a list of models")
        }
        return ids
    }

    public func complete(server: CleanupServer, model: String, system: String, text: String, timeout: Duration) async throws -> String {
        let body = Completion(model: model, messages: [Message(role: "system", content: system), Message(role: "user", content: text)], stream: false)
        let data = try await send(server, path: "/v1/chat/completions", body: JSONEncoder().encode(body), timeout: timeout.inSeconds, notFound: .noModel)
        guard let reply = (try? JSONDecoder().decode(Reply.self, from: data))?.choices.first?.message.content else {
            throw CleanupFailure.badReply("\(server.title) answered something that is not a completion")
        }
        return reply
    }

    private func send(_ server: CleanupServer, path: String, body: Data?, timeout: TimeInterval, notFound: CleanupFailure) async throws -> Data {
        var request = URLRequest(url: baseURL(server).appending(path: path), timeoutInterval: timeout)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // both servers answer 404 for a model they do not have
            if status == 404 { throw notFound }
            guard (200..<300).contains(status) else { throw CleanupFailure.badReply("\(server.title) answered HTTP \(status)") }
            return data
        } catch let error as URLError where error.code == .timedOut {
            throw CleanupFailure.timeout
        } catch let error as URLError where error.code != .cancelled {
            throw CleanupFailure.serverDown(server)
        }
    }

    private struct Message: Codable { let role: String; let content: String }
    private struct Completion: Encodable { let model: String; let messages: [Message]; let stream: Bool }
    private struct Reply: Decodable { struct Choice: Decodable { let message: Message }; let choices: [Choice] }
    private struct ModelList: Decodable { struct Item: Decodable { let id: String }; let data: [Item] }
}
