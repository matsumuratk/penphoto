import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Shared by preview and full-resolution export; all caption coordinates are image-relative.
final class ImageProcessor: @unchecked Sendable {
    static let shared = ImageProcessor()
    private let context = CIContext(options: [.cacheIntermediates: false])

    func normalized(_ image: UIImage, maxDimension: CGFloat? = nil) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = min(1, (maxDimension ?? max(pixels.width, pixels.height)) / max(pixels.width, pixels.height))
        let size = CGSize(width: max(1, pixels.width * ratio), height: max(1, pixels.height * ratio))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    func beauty(_ input: CIImage, strength: Double) -> CIImage {
        guard strength > 0.001 else { return input }
        let request = VNDetectFaceLandmarksRequest()
        guard (try? VNImageRequestHandler(ciImage: input, options: [:]).perform([request])) != nil,
              let faces = request.results, !faces.isEmpty else { return input }
        let extent = input.extent
        let maskFormat = UIGraphicsImageRendererFormat(); maskFormat.scale = 1
        // A small, feathered mask avoids allocating another full-resolution bitmap.
        let maskSize = CGSize(width: 512, height: 512 * extent.height / extent.width)
        let maskImage = UIGraphicsImageRenderer(size: maskSize, format: maskFormat).image { renderer in
            let cg = renderer.cgContext
            cg.setFillColor(UIColor.black.cgColor); cg.fill(CGRect(origin: .zero, size: maskSize))
            for face in faces {
                let box = face.boundingBox
                let rect = CGRect(x: box.minX * maskSize.width, y: (1 - box.maxY) * maskSize.height,
                                  width: box.width * maskSize.width, height: box.height * maskSize.height)
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.06))
                // Preserve eyes, eyebrows, and lips; this remains an initial approximation of skin.
                let features = [face.landmarks?.leftEye, face.landmarks?.rightEye,
                                face.landmarks?.leftEyebrow, face.landmarks?.rightEyebrow, face.landmarks?.outerLips]
                cg.setFillColor(UIColor.black.cgColor)
                for feature in features.compactMap({ $0 }) {
                    let points = feature.normalizedPoints
                    guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                          let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { continue }
                    let featureRect = CGRect(x: rect.minX + minX * rect.width, y: rect.minY + (1 - maxY) * rect.height,
                                             width: (maxX - minX) * rect.width, height: (maxY - minY) * rect.height)
                    cg.fillEllipse(in: featureRect.insetBy(dx: -rect.width * 0.035, dy: -rect.height * 0.025))
                }
            }
        }
        guard let mask = CIImage(image: maskImage) else { return input }
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: extent.width / maskSize.width, y: extent.height / maskSize.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: extent.width * 0.003])
        let smooth = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: extent.width * 0.0015 * strength])
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: strength * 0.025]).cropped(to: extent)
        let opacityMask = scaledMask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: strength * 0.65, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: strength * 0.65, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: strength * 0.65, w: 0)])
        return smooth.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: input, kCIInputMaskImageKey: opacityMask]).cropped(to: extent)
    }

    func frame(_ image: CIImage, strength: Double) -> UIImage? {
        let processed = beauty(image, strength: strength)
        guard let cg = context.createCGImage(processed, from: processed.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func base(_ original: UIImage, recipe: PhotoRecipe, maxDimension: CGFloat? = nil) -> UIImage {
        let input = normalized(original, maxDimension: maxDimension)
        guard var ci = CIImage(image: input) else { return input }
        ci = beauty(ci, strength: recipe.beauty)
        ci = ci.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: recipe.brightness])
        if let aspect = recipe.captureAspect { ci = ci.cropped(to: aspect.cropRect(in: ci.extent)) }
        for _ in 0..<(recipe.quarterTurns % 4) { ci = ci.oriented(.right) }
        if let crop = recipe.crop {
            let extent = ci.extent
            let width = min(extent.width, extent.height * crop.value)
            let height = width / crop.value
            ci = ci.cropped(to: CGRect(x: extent.midX - width / 2, y: extent.midY - height / 2, width: width, height: height))
        }
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return input }
        return UIImage(cgImage: cg)
    }

    func captionImage(_ caption: Caption, imageWidth: CGFloat) -> UIImage {
        let font = UIFont(name: "Yomogi-Regular", size: imageWidth * caption.size) ?? UIFont.systemFont(ofSize: imageWidth * caption.size)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: caption.ink.uiColor, .paragraphStyle: paragraph]
        let text = caption.text as NSString
        let padding = imageWidth * 0.025
        let bounds = text.boundingRect(with: CGSize(width: imageWidth * 0.82, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        let size = CGSize(width: ceil(bounds.width) + padding * 2, height: ceil(bounds.height) + padding * 2)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            if caption.backdrop {
                UIColor.black.withAlphaComponent(0.3).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: padding * 0.6).fill()
            } else {
                renderer.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: imageWidth * 0.004, color: UIColor.black.withAlphaComponent(0.5).cgColor)
            }
            text.draw(with: CGRect(x: padding, y: padding, width: ceil(bounds.width), height: ceil(bounds.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        }
    }

    func composite(base: UIImage, captions: [Caption]) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: base.size, format: format).image { renderer in
            base.draw(at: .zero)
            for caption in captions where !caption.text.isEmpty {
                let label = captionImage(caption, imageWidth: base.size.width)
                let cg = renderer.cgContext; cg.saveGState()
                cg.translateBy(x: caption.x * base.size.width, y: caption.y * base.size.height)
                cg.rotate(by: caption.rotation * .pi / 180)
                label.draw(in: CGRect(x: -label.size.width / 2, y: -label.size.height / 2, width: label.size.width, height: label.size.height))
                cg.restoreGState()
            }
        }
    }

    func render(_ original: UIImage, recipe: PhotoRecipe, maxDimension: CGFloat? = nil) -> UIImage {
        composite(base: base(original, recipe: recipe, maxDimension: maxDimension), captions: recipe.captions)
    }
}
