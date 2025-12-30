import Foundation
import UIKit
import CryptoKit
import CoreImage.CIFilterBuiltins

struct ProcessedImage: @unchecked Sendable {
    let uploadData: Data
    let processedImage: UIImage
    let saliency: SaliencyResult
    let cacheKey: String
}

actor ImagePreprocessor {
    static let shared = ImagePreprocessor()

    func process(
        _ image: UIImage,
        maxDimension: CGFloat = 1024,
        blurBackground: Bool = true,
        cacheKey: String? = nil
    ) async -> ProcessedImage? {
        let key = cacheKey ?? makeCacheKey(from: image)
        let saliency = await SaliencyAnalyzer.shared.analyze(image, cacheKey: key)

        let cropped = image.cropped(
            using: saliency,
            coverage: 0.9,
            targetDimension: maxDimension
        ) ?? image

        let finalImage: UIImage
        if blurBackground, let blurred = cropped.blurEdges() {
            finalImage = blurred
        } else {
            finalImage = cropped
        }

        guard let resized = finalImage.resized(maxDimension: maxDimension),
              let data = resized.jpegData(compressionQuality: 0.82) else {
            return nil
        }

        return ProcessedImage(
            uploadData: data,
            processedImage: resized,
            saliency: saliency,
            cacheKey: key
        )
    }

    private func makeCacheKey(from image: UIImage) -> String {
        guard let data = image.pngData() else {
            return UUID().uuidString
        }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private extension UIImage {
    func cropped(using saliency: SaliencyResult, coverage: CGFloat, targetDimension: CGFloat) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height) * coverage

        let centerX = width * (0.5 + saliency.offsetX / 2.0)
        let centerY = height * (0.5 + saliency.offsetY / 2.0)

        let originX = max(0, min(centerX - side / 2, width - side))
        let originY = max(0, min(centerY - side / 2, height - side))

        let cropRect = CGRect(x: originX, y: originY, width: side, height: side)

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let croppedImage = UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
        return croppedImage.resized(maxDimension: targetDimension)
    }

    func resized(maxDimension: CGFloat) -> UIImage? {
        let maxSide = max(size.width, size.height)
        let scale = min(1.0, maxDimension / maxSide)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }

    func blurEdges(radius: Double = 8, insetRatio: CGFloat = 0.08) -> UIImage? {
        guard let ciImage = CIImage(image: self) else { return nil }

        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = ciImage
        blurFilter.radius = Float(radius)

        guard let blurred = blurFilter.outputImage?.cropped(to: ciImage.extent) else {
            return nil
        }

        let blurredImage = UIImage(ciImage: blurred)

        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        blurredImage.draw(in: CGRect(origin: .zero, size: size))

        let inset = min(size.width, size.height) * insetRatio
        let overlayRect = CGRect(
            x: inset,
            y: inset,
            width: size.width - inset * 2,
            height: size.height - inset * 2
        )

        draw(in: overlayRect)

        let composited = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return composited
    }
}
