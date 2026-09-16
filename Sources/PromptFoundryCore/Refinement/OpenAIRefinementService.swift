import Foundation

public final class OpenAIRefinementService: PromptRefining {
    public static let credentialAccount = "openai-api-key"

    private let credentials: CredentialStoring
    private let session: URLSession
    private let endpoint: URL

    public init(credentials: CredentialStoring, session: URLSession = .shared, endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!) {
        self.credentials = credentials
        self.session = session
        self.endpoint = endpoint
    }

    public func refine(_ request: PromptRefinementRequest) -> AsyncThrowingStream<PromptRefinementEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let apiKey = try credentials.get(account: Self.credentialAccount)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let apiKey, !apiKey.isEmpty else { throw PromptFoundryError.missingCredential }
                    continuation.yield(.started)
                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = 120
                    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": request.model,
                        "instructions": PromptContract.instructions(for: request),
                        "input": [[
                            "role": "user",
                            "content": [["type": "input_text", "text": PromptContract.inputText(for: request)]]
                        ]],
                        "reasoning": ["effort": request.reasoning.rawValue],
                        "text": ["format": [
                            "type": "json_schema",
                            "name": "prompt_refinement",
                            "strict": true,
                            "schema": PromptContract.jsonSchema
                        ]],
                        "stream": true,
                        "store": false
                    ]
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw PromptFoundryError.offline }
                    guard (200..<300).contains(http.statusCode) else { throw mapHTTPStatus(http.statusCode) }

                    var raw = ""
                    var lastPartial = ""
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard payload != "[DONE]", let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = object["type"] as? String else { continue }
                        if type == "response.output_text.delta", let delta = object["delta"] as? String {
                            raw += delta
                            if let partial = PromptResponseParser.partialProfessionalPrompt(from: raw), partial != lastPartial {
                                let added = String(partial.dropFirst(lastPartial.count))
                                lastPartial = partial
                                if !added.isEmpty { continuation.yield(.delta(added)) }
                            }
                        } else if type == "response.failed" {
                            throw PromptFoundryError.offline
                        } else if type == "error" {
                            let message = object["message"] as? String ?? "The service returned an error."
                            throw PromptFoundryError.exportFailed(message)
                        }
                    }
                    try Task.checkCancellation()
                    let parsed = try PromptResponseParser.parse(raw)
                    continuation.yield(.completed(parsed, rawResponse: raw))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: PromptFoundryError.cancelled)
                } catch let error as URLError {
                    let mapped: PromptFoundryError = error.code == .timedOut ? .requestTimedOut : (error.code == .cancelled ? .cancelled : .offline)
                    continuation.finish(throwing: mapped)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func mapHTTPStatus(_ status: Int) -> PromptFoundryError {
        switch status {
        case 401, 403: return .invalidCredential
        case 404: return .modelUnavailable("selected model")
        case 408, 504: return .requestTimedOut
        case 429: return .rateLimited
        default: return .offline
        }
    }
}

public final class OpenAIModelCatalogService {
    private let credentials: CredentialStoring
    private let session: URLSession

    public init(credentials: CredentialStoring, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func fetch() async throws -> [ModelDescriptor] {
        guard let key = try credentials.get(account: OpenAIRefinementService.credentialAccount), !key.isEmpty else {
            throw PromptFoundryError.missingCredential
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PromptFoundryError.invalidCredential
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let dataItems = root["data"] as? [[String: Any]] else {
            throw PromptFoundryError.malformedResponse(raw: String(data: data, encoding: .utf8) ?? "")
        }
        return dataItems.compactMap { item in
            guard let id = item["id"] as? String, id.hasPrefix("gpt-") else { return nil }
            return ModelDescriptor(id: id, displayName: id, description: "Available through the configured OpenAI account", tier: ModelCatalog.tier(for: id), supportedEfforts: ModelCatalog.defaultEfforts(for: id))
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}

public enum ModelCatalog {
    public static let initialRefinerModels: [ModelDescriptor] = [
        ModelDescriptor(id: "gpt-5.6-luna", displayName: "Fast", description: "Quick, economical prompt refinement", tier: .fast, supportedEfforts: [.low, .medium, .high], available: false),
        ModelDescriptor(id: "gpt-5.6-terra", displayName: "Balanced", description: "Strong everyday refinement", tier: .balanced, supportedEfforts: [.low, .medium, .high, .xhigh], available: false),
        ModelDescriptor(id: "gpt-5.6-sol", displayName: "Deep", description: "Complex or demanding prompt development", tier: .deep, supportedEfforts: [.low, .medium, .high, .xhigh, .max, .ultra], available: false)
    ]

    public static func tier(for model: String) -> ModelTier {
        let name = model.lowercased()
        if name.contains("luna") || name.contains("mini") || name.contains("nano") { return .fast }
        if name.contains("terra") { return .balanced }
        if name.contains("sol") || name.contains("astra") || name.contains("pro") { return .deep }
        return .custom
    }

    public static func defaultEfforts(for model: String) -> [ReasoningEffort] {
        model.lowercased().contains("astra") ? [.low, .medium, .high, .xhigh, .max, .ultra] : [.none, .minimal, .low, .medium, .high, .xhigh]
    }
}
