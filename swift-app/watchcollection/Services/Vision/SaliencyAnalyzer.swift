import UIKit
import CoreGraphics

struct SaliencyResult: Codable, Sendable {
    let offsetX: CGFloat
    let offsetY: CGFloat
    let confidence: Float
    let analyzedAt: Date
    let dialColorR: CGFloat?
    let dialColorG: CGFloat?
    let dialColorB: CGFloat?

    var hasDialColor: Bool {
        dialColorR != nil && dialColorG != nil && dialColorB != nil
    }
}

actor SaliencyAnalyzer {
    static let shared = SaliencyAnalyzer()
    private static let cacheKey = "WatchSaliencyCache"

    static func cachedResult(for key: String) -> SaliencyResult? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: SaliencyResult].self, from: data) else {
            return nil
        }
        return decoded[key]
    }

    private var cache: [String: SaliencyResult] = [:]
    private let maxCacheSize = 500
    private let retainedCacheSize = 300
    private let backgroundThreshold: CGFloat = 0.92

    private var centeredResult: SaliencyResult {
        SaliencyResult(offsetX: 0, offsetY: 0, confidence: 1.0, analyzedAt: Date(), dialColorR: nil, dialColorG: nil, dialColorB: nil)
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode([String: SaliencyResult].self, from: data) {
            cache = decoded
        }
    }

    func analyze(_ image: UIImage, cacheKey key: String) async -> SaliencyResult {
        if let cached = cache[key] { return cached }

        guard let cgImage = image.cgImage else {
            return centeredResult
        }

        return performAnalysis(cgImage: cgImage, cacheKey: key)
    }

    func analyzeFromURL(_ url: URL, cacheKey key: String) async -> SaliencyResult {
        if let cached = cache[key] { return cached }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data),
                  let cgImage = image.cgImage else {
                return cacheResult(centeredResult, for: key)
            }
            return performAnalysis(cgImage: cgImage, cacheKey: key)
        } catch {
            return cacheResult(centeredResult, for: key)
        }
    }

    private func performAnalysis(cgImage: CGImage, cacheKey key: String) -> SaliencyResult {
        let width = cgImage.width
        let height = cgImage.height

        guard width > 0, height > 0,
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return cacheResult(centeredResult, for: key)
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        let bgColor = detectBackgroundColor(ptr: ptr, width: width, height: height, bytesPerPixel: bytesPerPixel, bytesPerRow: bytesPerRow)

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0

        let sampleStep = max(1, min(width, height) / 150)
        let colorThreshold: CGFloat = 0.15

        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = y * bytesPerRow + x * bytesPerPixel

                let r = CGFloat(ptr[offset]) / 255.0
                let g = CGFloat(ptr[offset + 1]) / 255.0
                let b = CGFloat(ptr[offset + 2]) / 255.0

                let diff = abs(r - bgColor.r) + abs(g - bgColor.g) + abs(b - bgColor.b)
                let isContent = diff > colorThreshold

                if isContent {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX < maxX, minY < maxY else {
            return cacheResult(centeredResult, for: key)
        }

        let contentCenterX = CGFloat(minX + maxX) / 2.0 / CGFloat(width)
        let contentCenterY = CGFloat(minY + maxY) / 2.0 / CGFloat(height)

        let offsetX = (contentCenterX - 0.5) * 2
        let offsetY = (contentCenterY - 0.5) * 2

        let dialColor = extractDialColor(
            ptr: ptr,
            contentMinX: minX, contentMaxX: maxX,
            contentMinY: minY, contentMaxY: maxY,
            bytesPerPixel: bytesPerPixel, bytesPerRow: bytesPerRow
        )

        let result = SaliencyResult(
            offsetX: offsetX,
            offsetY: offsetY,
            confidence: 1.0,
            analyzedAt: Date(),
            dialColorR: dialColor?.r,
            dialColorG: dialColor?.g,
            dialColorB: dialColor?.b
        )

        return cacheResult(result, for: key)
    }

    private func extractDialColor(
        ptr: UnsafePointer<UInt8>,
        contentMinX: Int, contentMaxX: Int,
        contentMinY: Int, contentMaxY: Int,
        bytesPerPixel: Int, bytesPerRow: Int
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let contentWidth = contentMaxX - contentMinX
        let contentHeight = contentMaxY - contentMinY

        let dialRegionScale: CGFloat = 0.35
        let dialCenterX = (contentMinX + contentMaxX) / 2
        let dialCenterY = (contentMinY + contentMaxY) / 2
        let dialRadius = Int(CGFloat(min(contentWidth, contentHeight)) * dialRegionScale / 2)

        let dialMinX = dialCenterX - dialRadius
        let dialMaxX = dialCenterX + dialRadius
        let dialMinY = dialCenterY - dialRadius
        let dialMaxY = dialCenterY + dialRadius

        var colorSamples: [(r: CGFloat, g: CGFloat, b: CGFloat, saturation: CGFloat)] = []
        let sampleStep = max(1, dialRadius / 15)

        for y in stride(from: dialMinY, to: dialMaxY, by: sampleStep) {
            for x in stride(from: dialMinX, to: dialMaxX, by: sampleStep) {
                let dx = x - dialCenterX
                let dy = y - dialCenterY
                if dx * dx + dy * dy > dialRadius * dialRadius { continue }

                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = CGFloat(ptr[offset]) / 255.0
                let g = CGFloat(ptr[offset + 1]) / 255.0
                let b = CGFloat(ptr[offset + 2]) / 255.0

                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                let brightness = maxC

                if brightness > 0.1 && brightness < 0.95 {
                    colorSamples.append((r, g, b, saturation))
                }
            }
        }

        guard !colorSamples.isEmpty else { return nil }

        let sortedBySaturation = colorSamples.sorted { $0.saturation > $1.saturation }
        let topSaturated = sortedBySaturation.prefix(max(1, sortedBySaturation.count / 3))

        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0

        for sample in topSaturated {
            totalR += sample.r
            totalG += sample.g
            totalB += sample.b
        }

        let count = CGFloat(topSaturated.count)
        return (totalR / count, totalG / count, totalB / count)
    }

    private func detectBackgroundColor(ptr: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerPixel: Int, bytesPerRow: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var count: CGFloat = 0

        let edgeSamples = 20

        for i in 0..<edgeSamples {
            let x = width * i / edgeSamples
            for y in [0, height - 1] {
                let offset = y * bytesPerRow + x * bytesPerPixel
                totalR += CGFloat(ptr[offset]) / 255.0
                totalG += CGFloat(ptr[offset + 1]) / 255.0
                totalB += CGFloat(ptr[offset + 2]) / 255.0
                count += 1
            }
        }

        for i in 0..<edgeSamples {
            let y = height * i / edgeSamples
            for x in [0, width - 1] {
                let offset = y * bytesPerRow + x * bytesPerPixel
                totalR += CGFloat(ptr[offset]) / 255.0
                totalG += CGFloat(ptr[offset + 1]) / 255.0
                totalB += CGFloat(ptr[offset + 2]) / 255.0
                count += 1
            }
        }

        return (totalR / count, totalG / count, totalB / count)
    }

    private func cacheResult(_ result: SaliencyResult, for key: String) -> SaliencyResult {
        cache[key] = result
        pruneAndPersist()
        return result
    }

    private func pruneAndPersist() {
        if cache.count > maxCacheSize {
            let sorted = cache.sorted { $0.value.analyzedAt > $1.value.analyzedAt }
            cache = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(retainedCacheSize)))
        }

        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
        }
    }

    func clearCache() {
        cache.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }
}
