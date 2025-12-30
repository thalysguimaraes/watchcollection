import Foundation
import UIKit

actor WatchAIService {
    static let shared = WatchAIService()

    private static let geminiAPIKey = "AIzaSyB8jKQqzcukEtj8rrlfXiocob1TsT4_f_8"
    private static let geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    private static let visionPrompt = """
        Describe ONLY what you can see in this watch image. Do NOT guess the model name.

        DESCRIBE EXACTLY:
        1. Brand logo visible (shield, crown, text, etc.)
        2. Case shape (round, rectangular, tonneau)
        3. Dial color and texture
        4. Hand style (sword, dauphine, snowflake, Mercedes, etc.)
        5. Bezel type (smooth, diving, tachymeter)
        6. Sub-dials: COUNT THEM. 0 = no sub-dials, 2 = chronograph, etc.
        7. Date window location (none, 3, 6, etc.)
        8. Crown guards (YES if metal protects crown, NO if exposed)
        9. Any text visible on dial

        CRITICAL: Only describe what you ACTUALLY SEE. Do not infer or guess.
        If there are NO sub-dials, say "Sub-dials: 0"
        """

    private static let searchPrompt = """
        Based on this watch description, identify the EXACT model and reference number.

        WATCH DESCRIPTION:
        %@

        INSTRUCTIONS:
        1. Search to find watches matching these specific visual features
        2. Determine if this is a CURRENT PRODUCTION or VINTAGE model
        3. CRITICAL: Find the reference number by searching "[brand] [model] reference number"

        BRAND-SPECIFIC REFERENCES:
        - Tudor Black Bay 54 turquoise/lagoon: M79000N-0001 or 79000N
        - Tudor Black Bay 58 blue: M79030B-0001
        - Rolex Submariner black: 126610LN
        - Cartier Tank Must: WSTA0040, WSTA0041

        Respond in this format:
        Brand: [brand]
        Model: [exact model name]
        Reference: [reference number - MUST search for this]
        Material: [material]
        Dial: [color]
        Complications: [list or "none"]
        Description: [key features]
        """

    func identifyWatch(imageData: Data) async throws -> WatchIdentification {
        let description = try await describeWatch(imageData: imageData)
        print("Vision description: \(description)")

        let identification = try await searchForWatch(description: description)
        return identification
    }

    private func describeWatch(imageData: Data) async throws -> String {
        let base64 = imageData.base64EncodedString()

        guard let url = URL(string: Self.geminiEndpoint) else {
            throw WatchAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64
                            ]
                        ],
                        [
                            "text": Self.visionPrompt
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WatchAIError.identificationFailed("Vision request failed")
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponseDTO.self, from: data)

        guard let candidate = geminiResponse.candidates.first,
              let part = candidate.content.parts.first,
              let text = part.text else {
            throw WatchAIError.identificationFailed("No description returned")
        }

        return text
    }

    private func searchForWatch(description: String) async throws -> WatchIdentification {
        guard let url = URL(string: Self.geminiEndpoint) else {
            throw WatchAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")

        let prompt = String(format: Self.searchPrompt, description)

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "tools": [
                ["google_search": [:]]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WatchAIError.identificationFailed("Search request failed")
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponseDTO.self, from: data)

        guard let candidate = geminiResponse.candidates.first,
              let part = candidate.content.parts.first,
              let text = part.text else {
            throw WatchAIError.identificationFailed("No search result returned")
        }

        print("Search result: \(text)")

        return WatchIdentificationParser.parse(text)
    }
}

private struct GeminiResponseDTO: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }
}

enum WatchAIError: Error, LocalizedError {
    case invalidURL
    case apiKeyMissing
    case imageProcessingFailed
    case identificationFailed(String)

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
        }
    }
}

extension UIImage {
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
