import Foundation

actor ClaudeMatcher {
    private static let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    private static let endpoint = "https://api.anthropic.com/v1/messages"

    func matchToCatalog(
        identification: WatchIdentification,
        candidates: [WatchModelWithBrand]
    ) async throws -> [IdentificationMatch] {
        guard !candidates.isEmpty else { return [] }

        let candidatesList = candidates.prefix(30).enumerated().map { index, watch in
            let aliases = watch.watchModel.referenceAliases?.joined(separator: ", ") ?? "none"
            return """
            [\(index)] \(watch.brand?.name ?? "Unknown") - \(watch.watchModel.displayName)
               Reference: \(watch.watchModel.reference)
               Aliases: \(aliases)
               Collection: \(watch.watchModel.collection ?? "n/a")
               Dial: \(watch.watchModel.specs?.dialColor ?? "n/a")
            """
        }.joined(separator: "\n")

        let prompt = """
        Match this watch identification to the best catalog entries.

        IDENTIFIED WATCH:
        Brand: \(identification.brand ?? "unknown")
        Model: \(identification.model ?? "unknown")
        Reference: \(identification.reference ?? "unknown")
        Material: \(identification.material ?? "unknown")
        Dial: \(identification.dialColor ?? "unknown")

        CATALOG CANDIDATES:
        \(candidatesList)

        INSTRUCTIONS:
        - Find the BEST matching catalog entry based on brand, model name, and reference
        - Reference numbers may have different formats (e.g., "2413" = "WSTA0040", "M79000-0001" = "79000N")
        - Check the Aliases field - if the identified reference appears in aliases, it's a strong match
        - Return up to 3 matches, best first

        Respond ONLY with a JSON array of matches:
        [{"index": 0, "confidence": 0.95, "reason": "exact reference match via alias"}]

        If no good matches exist, return: []
        """

        guard let url = URL(string: Self.endpoint) else {
            throw ClaudeMatcherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 500,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("Claude API error: \(statusCode)")
            if let errorText = String(data: data, encoding: .utf8) {
                print("Error body: \(errorText)")
            }
            throw ClaudeMatcherError.apiError(statusCode)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let content = claudeResponse.content.first?.text else {
            return []
        }

        print("Claude matcher response: \(content)")

        return parseMatches(content, candidates: Array(candidates.prefix(30)))
    }

    private func parseMatches(_ text: String, candidates: [WatchModelWithBrand]) -> [IdentificationMatch] {
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIndex = jsonText.firstIndex(of: "["),
           let endIndex = jsonText.lastIndex(of: "]") {
            jsonText = String(jsonText[startIndex...endIndex])
        }

        guard let data = jsonText.data(using: .utf8),
              let matches = try? JSONDecoder().decode([ClaudeMatch].self, from: data) else {
            return []
        }

        return matches.compactMap { match in
            guard match.index >= 0, match.index < candidates.count else { return nil }
            let candidate = candidates[match.index]
            return IdentificationMatch(
                watch: candidate,
                confidence: match.confidence,
                matchType: .reference
            )
        }
    }
}

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let text: String?
    }
}

private struct ClaudeMatch: Decodable {
    let index: Int
    let confidence: Double
    let reason: String?
}

enum ClaudeMatcherError: Error, LocalizedError {
    case invalidURL
    case apiError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let code):
            return "API error: \(code)"
        }
    }
}
