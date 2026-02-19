import Foundation

enum OpenAIClientError: Error, LocalizedError {
  case invalidResponse
  case httpError(Int, String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Invalid response"
    case .httpError(let code, let body):
      if body.isEmpty { return "HTTP \(code)" }
      return "HTTP \(code): \(body)"
    }
  }
}

final class OpenAIClient {
  struct Message {
    let role: String
    let content: String
  }

  func streamChatCompletion(apiKey: String, model: String, messages: [Message]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
          req.httpMethod = "POST"
          req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
          req.setValue("application/json", forHTTPHeaderField: "Content-Type")

          let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
          ]
          req.httpBody = try JSONSerialization.data(withJSONObject: payload)

          let (bytes, response) = try await URLSession.shared.bytes(for: req)
          guard let http = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
          }
          if http.statusCode < 200 || http.statusCode >= 300 {
            let body = try await bytesToString(bytes)
            throw OpenAIClientError.httpError(http.statusCode, body)
          }

          for try await line in bytes.lines {
            if Task.isCancelled {
              continuation.finish()
              return
            }
            guard line.hasPrefix("data: ") else { continue }
            let dataPart = String(line.dropFirst(6))
            if dataPart == "[DONE]" {
              continuation.finish()
              return
            }
            guard let jsonData = dataPart.data(using: .utf8) else { continue }
            if let delta = parseDeltaContent(jsonData) {
              continuation.yield(delta)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  func validateAPIKey(apiKey: String, model: String) async throws {
    var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let payload: [String: Any] = [
      "model": model,
      "stream": false,
      "max_tokens": 1,
      "temperature": 0,
      "messages": [
        ["role": "user", "content": "ping"],
      ],
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else {
      throw OpenAIClientError.invalidResponse
    }
    if http.statusCode < 200 || http.statusCode >= 300 {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw OpenAIClientError.httpError(http.statusCode, body)
    }
  }

  func streamResponseText(
    apiKey: String,
    model: String,
    instructions: String,
    input: String,
    previousResponseId: String?,
    onResponseId: @escaping (String) -> Void
  ) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          var req = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
          req.httpMethod = "POST"
          req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
          req.setValue("application/json", forHTTPHeaderField: "Content-Type")

          var payload: [String: Any] = [
            "model": model,
            "stream": true,
            "instructions": instructions,
            "input": input,
          ]
          if let previousResponseId {
            payload["previous_response_id"] = previousResponseId
          }
          req.httpBody = try JSONSerialization.data(withJSONObject: payload)

          let (bytes, response) = try await URLSession.shared.bytes(for: req)
          guard let http = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
          }
          if http.statusCode < 200 || http.statusCode >= 300 {
            let body = try await bytesToString(bytes)
            throw OpenAIClientError.httpError(http.statusCode, body)
          }

          for try await line in bytes.lines {
            if Task.isCancelled {
              continuation.finish()
              return
            }
            guard line.hasPrefix("data: ") else { continue }
            let dataPart = String(line.dropFirst(6))
            if dataPart == "[DONE]" {
              continuation.finish()
              return
            }
            guard let jsonData = dataPart.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }
            if let t = obj["type"] as? String {
              if t == "response.created" || t == "response.completed" {
                if let resp = obj["response"] as? [String: Any], let id = resp["id"] as? String {
                  onResponseId(id)
                }
              }
              if t == "response.output_text.delta" {
                if let delta = obj["delta"] as? String {
                  continuation.yield(delta)
                }
              }
              if t == "error" {
                let msg = (obj["error"] as? [String: Any])?["message"] as? String
                throw OpenAIClientError.httpError(http.statusCode, msg ?? "Unknown error")
              }
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  private func parseDeltaContent(_ jsonData: Data) -> String? {
    guard
      let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
      let choices = obj["choices"] as? [[String: Any]],
      let first = choices.first,
      let delta = first["delta"] as? [String: Any]
    else { return nil }

    return delta["content"] as? String
  }

  private func bytesToString(_ bytes: URLSession.AsyncBytes) async throws -> String {
    var out = ""
    for try await line in bytes.lines {
      out.append(line)
      out.append("\n")
      if out.count > 32_000 { break }
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
