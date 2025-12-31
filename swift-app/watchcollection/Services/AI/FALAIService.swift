import Foundation
import UIKit
import os

actor WatchAIService {
    static let shared = WatchAIService()

    private static let geminiAPIKey: String = {
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let key = plist["GEMINI_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    }()
    private static let geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "watchcollection.ai", category: "WatchAIService")
    private let maxRetries = 2

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 40
            self.session = URLSession(configuration: configuration)
        }
    }

    func describeWatch(imageData: Data, allowWebSearch: Bool) async throws -> WatchIdentification {
        let prompt = """
        You are extracting structured facts from a watch photo. Respond with strict JSON only.

        JSON schema:
        {
          "brand": string | null,
          "model": string | null,
          "reference": string | null,
          "collection": string | null,
          "material": string | null,
          "dialColor": string | null,
          "complications": [string],
          "description": string
        }

        Rules:
        - If a value is not visible, return null.
        - Use exactly the detected reference (do not invent new formats).
        - Keep description to one concise sentence of visible traits.
        """

        var body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["inline_data": ["mime_type": "image/jpeg", "data": imageData.base64EncodedString()]],
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 1024,
                "responseMimeType": "application/json"
            ]
        ]

        if allowWebSearch {
            body["tools"] = [["google_search": [:]]]
        }

        let response = try await sendGeminiRequest(body: body)
        guard let text = response.firstText else {
            throw WatchAIError.identificationFailed("No description returned")
        }

        let payload: IdentificationJSON = try parseJSON(text, as: IdentificationJSON.self)
        return payload.toModel(source: allowWebSearch ? "gemini.search" : "gemini.describe")
    }

    func rankCandidates(
        imageData: Data,
        candidates: [WatchModelWithBrand],
        hints: OCRHints,
        preferredIdentification: WatchIdentification?
    ) async throws -> (identification: WatchIdentification, matches: [IdentificationMatch]) {
        let candidateList = formatCandidates(candidates)
        let hintsBlock = buildHintsText(hints: hints, preferred: preferredIdentification)

        let prompt = """
        Use the photo plus the candidate list to pick the best catalog entries.
        Always return JSON only:
        {
          "identification": {"brand":..., "model":..., "reference":..., "collection":..., "material":..., "dialColor":..., "complications":[], "description": "..."},
          "matches": [{"index": 0, "confidence": 0.0-1.0, "reason": "why"}]
        }

        Guidance:
        - Exact reference or alias match => confidence >= 0.9.
        - If logo/visuals strongly align but reference differs, confidence 0.6-0.8 with reason.
        - Return up to 3 matches, ordered best first. Use [] if none are credible.
        - Keep reasons short and specific ("dial + bezel match", "alias M79000N").
        """

        var body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["inline_data": ["mime_type": "image/jpeg", "data": imageData.base64EncodedString()]],
                        ["text": candidateList],
                        ["text": hintsBlock],
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.15,
                "maxOutputTokens": 2048,
                "responseMimeType": "application/json"
            ]
        ]

        let response = try await sendGeminiRequest(body: body)
        guard let text = response.firstText else {
            throw WatchAIError.identificationFailed("No ranking returned")
        }

        let payload: RankingJSON = try parseJSON(text, as: RankingJSON.self)
        let identification = payload.identification?.toModel(source: "gemini.rank") ?? preferredIdentification ?? WatchIdentification(
            brand: hints.candidateBrands.first,
            model: nil,
            reference: hints.candidateReferences.first,
            collection: nil,
            material: nil,
            dialColor: nil,
            complications: [],
            rawDescription: hints.rawText.isEmpty ? "Gemini ranking" : hints.rawText,
            source: "fallback"
        )

        let matches = payload.matches.compactMap { match -> IdentificationMatch? in
            guard match.index >= 0, match.index < candidates.count else { return nil }
            let clamped = max(0.0, min(match.confidence, 1.0))
            return IdentificationMatch(
                watch: candidates[match.index],
                confidence: clamped,
                matchType: .ai,
                reason: match.reason
            )
        }

        return (identification, matches)
    }

    private func formatCandidates(_ candidates: [WatchModelWithBrand]) -> String {
        guard !candidates.isEmpty else { return "No catalog candidates were found." }

        return candidates.prefix(30).enumerated().map { index, watch in
            let brand = watch.brand?.name ?? "Unknown"
            let aliases = watch.watchModel.referenceAliases?.joined(separator: ", ") ?? "none"
            let dial = watch.watchModel.specs?.dialColor ?? "n/a"
            let material = watch.watchModel.specs?.caseMaterial ?? "n/a"
            return "[\(index)] \(brand) - \(watch.watchModel.displayName) | ref: \(watch.watchModel.reference) | aliases: \(aliases) | dial: \(dial) | material: \(material)"
        }.joined(separator: "\n")
    }

    private func buildHintsText(hints: OCRHints, preferred: WatchIdentification?) -> String {
        var lines: [String] = []
        if let preferred {
            lines.append("Existing identification: brand=\(preferred.brand ?? "?") model=\(preferred.model ?? "?") ref=\(preferred.reference ?? "?") dial=\(preferred.dialColor ?? "?")")
        }
        if !hints.rawText.isEmpty {
            lines.append("OCR text: \(hints.rawText)")
        }
        if !hints.candidateReferences.isEmpty {
            lines.append("OCR references: \(hints.candidateReferences.joined(separator: ", "))")
        }
        if !hints.candidateBrands.isEmpty {
            lines.append("OCR brands: \(hints.candidateBrands.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private func sendGeminiRequest(body: [String: Any]) async throws -> GeminiResponseDTO {
        guard !Self.geminiAPIKey.isEmpty else {
            throw WatchAIError.apiKeyMissing
        }
        guard let url = URL(string: Self.geminiEndpoint) else {
            throw WatchAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25

        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    #if DEBUG
                    logger.error("Gemini status \(code)")
                    #endif
                    throw WatchAIError.identificationFailed("Gemini status \(code)")
                }

                #if DEBUG
                if let rawString = String(data: data, encoding: .utf8) {
                    logger.debug("Raw Gemini response: \(rawString.prefix(1000))")
                }
                #endif
                let geminiResponse = try decoder.decode(GeminiResponseDTO.self, from: data)
                return geminiResponse
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 300_000_000
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
            }
        }

        if let lastError {
            throw lastError
        }

        throw WatchAIError.identificationFailed("Gemini request failed")
    }

    private func parseJSON<T: Decodable>(_ text: String, as type: T.Type) throws -> T {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        logger.debug("Parsing JSON response: \(trimmed.prefix(500))")
        #endif

        guard let data = trimmed.data(using: .utf8) else {
            throw WatchAIError.decodingFailed("Invalid UTF-8")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch let decodeError {
            #if DEBUG
            logger.error("Initial decode failed: \(decodeError.localizedDescription)")
            #endif

            if let start = trimmed.firstIndex(of: "{") ?? trimmed.firstIndex(of: "[") {
                if let end = trimmed.lastIndex(of: "}") ?? trimmed.lastIndex(of: "]") {
                    let jsonSlice = String(trimmed[start...end])
                    if let data = jsonSlice.data(using: .utf8), let recovered = try? decoder.decode(T.self, from: data) {
                        return recovered
                    }
                }
            }
            throw WatchAIError.decodingFailed(decodeError.localizedDescription)
        }
    }
}

private struct GeminiResponseDTO: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content?
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }

    var firstText: String? {
        candidates.first?.content?.parts.first?.text
    }
}

private struct IdentificationJSON: Decodable {
    let brand: String?
    let model: String?
    let reference: String?
    let collection: String?
    let material: String?
    let dialColor: String?
    let complications: [String]?
    let description: String?

    func toModel(source: String) -> WatchIdentification {
        WatchIdentification(
            brand: brand,
            model: model,
            reference: reference,
            collection: collection,
            material: material,
            dialColor: dialColor,
            complications: complications ?? [],
            rawDescription: description ?? "",
            source: source
        )
    }
}

private struct RankingJSON: Decodable {
    let identification: IdentificationJSON?
    let matches: [MatchJSON]
}

private struct MatchJSON: Decodable {
    let index: Int
    let confidence: Double
    let reason: String?
}

enum WatchAIError: Error, LocalizedError {
    case invalidURL
    case apiKeyMissing
    case imageProcessingFailed
    case identificationFailed(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .apiKeyMissing:
            return "API configuration not available"
        case .imageProcessingFailed:
            return "Failed to process image"
        case .identificationFailed(let reason):
            return "Identification failed: \(reason)"
        case .decodingFailed(let reason):
            return "Decoding failed: \(reason)"
        }
    }
}

extension UIImage {
    /// Legacy helper preserved for compatibility. Prefer ImagePreprocessor for new calls.
    func prepareForAI(maxDimension: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resized?.jpegData(compressionQuality: quality)
    }
}
