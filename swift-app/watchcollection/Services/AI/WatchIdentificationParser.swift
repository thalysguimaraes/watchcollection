import Foundation

enum WatchIdentificationParser {
    static func parse(_ text: String) -> WatchIdentification {
        var identification = WatchIdentification(
            brand: nil,
            model: nil,
            reference: nil,
            collection: nil,
            material: nil,
            dialColor: nil,
            complications: [],
            rawDescription: text,
            source: "parser"
        )

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let colonIndex = trimmed.firstIndex(of: ":") {
                var key = String(trimmed[..<colonIndex]).lowercased().trimmingCharacters(in: .whitespaces)
                key = key.replacingOccurrences(of: "*", with: "")
                var value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                value = value.replacingOccurrences(of: "**", with: "")

                guard !value.isEmpty && value.lowercased() != "unknown" && value.lowercased() != "n/a" else {
                    continue
                }

                switch key {
                case "brand":
                    identification.brand = normalizeBrand(value)
                case "model":
                    identification.model = value
                case "reference", "ref":
                    identification.reference = normalizeReference(value)
                case "collection":
                    identification.collection = value
                case "material", "case material":
                    identification.material = value
                case "dial", "dial color":
                    identification.dialColor = value
                case "complications":
                    if value.lowercased() != "none" {
                        identification.complications = value
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                case "description":
                    identification.rawDescription = value
                default:
                    break
                }
            }
        }

        if identification.brand == nil {
            identification.brand = extractBrand(from: text)
        }

        if identification.reference == nil {
            identification.reference = extractReference(from: text)
        }

        return identification
    }

    private static func normalizeBrand(_ brand: String) -> String {
        let brandMappings: [String: String] = [
            "ap": "Audemars Piguet",
            "audemars": "Audemars Piguet",
            "pp": "Patek Philippe",
            "patek": "Patek Philippe",
            "vc": "Vacheron Constantin",
            "vacheron": "Vacheron Constantin",
            "jlc": "Jaeger-LeCoultre",
            "jaeger": "Jaeger-LeCoultre",
            "a. lange": "A. Lange & Söhne",
            "lange": "A. Lange & Söhne",
            "go": "Glashütte Original",
            "glashutte": "Glashütte Original",
        ]

        let lowered = brand.lowercased()
        return brandMappings[lowered] ?? brand
    }

    private static func normalizeReference(_ ref: String) -> String? {
        let cleaned = ref.replacingOccurrences(of: "Ref.", with: "")
            .replacingOccurrences(of: "ref", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty && cleaned.lowercased() != "unknown" else {
            return nil
        }

        return cleaned
    }

    static func extractBrand(from text: String) -> String? {
        let loweredText = text.lowercased()
        for brand in BrandLexicon.known {
            if loweredText.contains(brand.lowercased()) {
                return brand
            }
        }

        return nil
    }

    static func extractReference(from text: String) -> String? {
        let patterns = [
            #"(?:ref\.?\s*)?(\d{3,6}[A-Z]?[A-Z]?[-/]?\d*[A-Z]*)"#,
            #"([A-Z]{2,3}[-\s]?\d{4,6})"#,
            #"(\d{4,6}[-/][A-Z0-9]{2,6})"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let ref = String(text[range])
                if ref.count >= 4 {
                    return ref
                }
            }
        }

        return nil
    }
}
