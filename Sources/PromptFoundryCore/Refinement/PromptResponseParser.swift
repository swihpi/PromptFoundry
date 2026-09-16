import Foundation

public enum PromptResponseParser {
    public static func parse(_ raw: String) throws -> PromptRefinementResponse {
        if let response = decode(raw) { return try validate(response, raw: raw) }
        let recovered = recoverJSON(from: raw)
        if recovered != raw, let response = decode(recovered) { return try validate(response, raw: raw) }
        throw PromptFoundryError.malformedResponse(raw: raw)
    }

    public static func partialProfessionalPrompt(from raw: String) -> String? {
        guard let keyRange = raw.range(of: "\"professionalPrompt\"") else { return nil }
        let tail = raw[keyRange.upperBound...]
        guard let colon = tail.firstIndex(of: ":") else { return nil }
        let afterColon = tail[tail.index(after: colon)...].drop(while: { $0.isWhitespace })
        guard afterColon.first == "\"" else { return nil }
        var escaped = false
        var encoded = ""
        for character in afterColon.dropFirst() {
            if !escaped && character == "\"" { break }
            encoded.append(character)
            if character == "\\" && !escaped { escaped = true } else { escaped = false }
        }
        guard let data = "\"\(encoded)\"".data(using: .utf8), let value = try? JSONDecoder().decode(String.self, from: data) else {
            return encoded.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"")
        }
        return value
    }

    private static func decode(_ text: String) -> PromptRefinementResponse? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PromptRefinementResponse.self, from: data)
    }

    private static func recoverJSON(from raw: String) -> String {
        let withoutFence = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let start = withoutFence.firstIndex(of: "{"), let end = withoutFence.lastIndex(of: "}"), start <= end else { return raw }
        return String(withoutFence[start...end])
    }

    private static func validate(_ response: PromptRefinementResponse, raw: String) throws -> PromptRefinementResponse {
        guard !response.professionalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !response.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              response.suggestedTitle.count <= 200 else {
            throw PromptFoundryError.malformedResponse(raw: raw)
        }
        return response
    }
}
