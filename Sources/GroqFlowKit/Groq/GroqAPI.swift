import Foundation

// Groq HTTP client. Two endpoints: Whisper transcription (multipart) and
// chat completions (JSON). 30 s per-request timeout, one retry on 5xx / network error.
public struct GroqAPI: Sendable {
    private static let baseURL = URL(string: "https://api.groq.com/openai/v1")!
    private static let timeout: TimeInterval = 30

    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Transcription

    public func transcribe(wav: Data, language: String?, prompt: String?) async throws -> String {
        let url = Self.baseURL.appendingPathComponent("audio/transcriptions")
        let boundary = "GroqFlowBoundary-\(UUID().uuidString)"

        var fields: [(String, String)] = [
            ("model", GroqModels.stt),
            ("response_format", "json"),
            ("temperature", "0"),
        ]
        if let language, !language.isEmpty {
            fields.append(("language", language))
        }
        if let prompt, !prompt.isEmpty {
            fields.append(("prompt", prompt))
        }

        let body = Self.multipartBody(
            boundary: boundary,
            fields: fields,
            fileField: "file",
            fileName: "audio.wav",
            fileMIME: "audio/wav",
            fileData: wav
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data = try await perform(request)
        return try Self.parseTranscription(data)
    }

    // MARK: - Chat

    public func chat(system: String, user: String, model: String, temperature: Double, jsonMode: Bool) async throws -> String {
        let url = Self.baseURL.appendingPathComponent("chat/completions")

        var payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if jsonMode {
            payload["response_format"] = ["type": "json_object"]
        }

        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let data = try await perform(request)
        return try Self.parseChatContent(data)
    }

    // MARK: - Key validation

    public func validateKey() async -> Bool {
        let url = Self.baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Transport

    // One request with a single retry on 5xx or transport error.
    private func perform(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw GroqError.badResponse
                }
                if http.statusCode == 200 {
                    return data
                }
                if (500...599).contains(http.statusCode), attempt == 0 {
                    attempt += 1
                    continue
                }
                throw GroqError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
            } catch let error as GroqError {
                throw error
            } catch {
                // Transport error (timeout, connection loss): retry once.
                if attempt == 0 {
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }

    // MARK: - Multipart

    static func multipartBody(boundary: String,
                              fields: [(String, String)],
                              fileField: String,
                              fileName: String,
                              fileMIME: String,
                              fileData: Data) -> Data {
        var body = Data()
        let dashes = "--\(boundary)\r\n"

        for (name, value) in fields {
            body.append(dashes)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        body.append(dashes)
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(fileMIME)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }

    // MARK: - Response parsing

    static func parseTranscription(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else {
            throw GroqError.badResponse
        }
        return text
    }

    static func parseChatContent(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GroqError.badResponse
        }
        return content
    }
}

public enum GroqModels {
    public static let stt = "whisper-large-v3-turbo"
    public static let formatter = "llama-3.3-70b-versatile"
}

// Internal error surface. Public API throws these as opaque Error values.
enum GroqError: Error, Equatable {
    case badResponse
    case http(status: Int, body: String?)
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
