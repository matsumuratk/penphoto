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

    /// Landmark coordinates are normalized in Vision's bottom-left coordinate space.
    struct FaceRegion {
        var bounds: CGRect
        var protectedFeatures: [CGRect] = []
    }

    func detectFaces(_ image: CIImage) -> [FaceRegion] {
        let scale = min(1, 768 / max(image.extent.width, image.extent.height))
        let detectionImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let request = VNDetectFaceLandmarksRequest()
        #if targetEnvironment(simulator)
        request.usesCPUOnly = true
        #endif
        do { try VNImageRequestHandler(ciImage: detectionImage, options: [:]).perform([request]) }
        catch { NSLog("PenPhoto face detection unavailable: %@", error.localizedDescription); return [] }
        return (request.results ?? []).map { face in
            let features = [face.landmarks?.leftEye, face.landmarks?.rightEye,
                            face.landmarks?.leftEyebrow, face.landmarks?.rightEyebrow,
                            face.landmarks?.outerLips, face.landmarks?.nose]
            let boxes = features.compactMap { feature -> CGRect? in
                guard let points = feature?.normalizedPoints,
                      let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(),
                      let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max() else { return nil }
                return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            }
            return FaceRegion(bounds: face.boundingBox, protectedFeatures: boxes)
        }
    }

    func beauty(_ input: CIImage, strength: Double, style: BeautyStyle = .natural, faces suppliedFaces: [FaceRegion]? = nil) -> CIImage {
        let amount = min(1, max(0, strength))
        guard amount > 0.001 else { return input }
        let faces = suppliedFaces ?? detectFaces(input)
        guard !faces.isEmpty else { return input }
        let extent = input.extent
        let scale = 512 / max(extent.width, extent.height)
        let maskSize = CGSize(width: max(1, extent.width * scale), height: max(1, extent.height * scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let maskImage = UIGraphicsImageRenderer(size: maskSize, format: format).image { renderer in
            let cg = renderer.cgContext
            UIColor.black.setFill(); cg.fill(CGRect(origin: .zero, size: maskSize))
            for face in faces {
                let box = face.bounds
                let rect = CGRect(x: box.minX * maskSize.width, y: (1 - box.maxY) * maskSize.height,
                                  width: box.width * maskSize.width, height: box.height * maskSize.height)
                UIColor.white.setFill()
                // Stay inside the face boundary to reduce hair/background spill.
                cg.fillEllipse(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.09))
            }
            // Protect all faces' features after the union, including overlapping faces.
            UIColor.black.setFill()
            for face in faces {
                let box = face.bounds
                let rect = CGRect(x: box.minX * maskSize.width, y: (1 - box.maxY) * maskSize.height,
                                  width: box.width * maskSize.width, height: box.height * maskSize.height)
                for feature in face.protectedFeatures {
                    let region = CGRect(x: rect.minX + feature.minX * rect.width,
                                        y: rect.minY + (1 - feature.maxY) * rect.height,
                                        width: feature.width * rect.width, height: feature.height * rect.height)
                    cg.fillEllipse(in: region.insetBy(dx: -rect.width * 0.045, dy: -rect.height * 0.035))
                }
            }
        }
        guard let rawMask = CIImage(image: maskImage) else { return input }
        let faceWidth = faces.map { $0.bounds.width * extent.width }.max() ?? extent.width * 0.3
        let mask = rawMask.transformed(by: CGAffineTransform(scaleX: extent.width / maskSize.width, y: extent.height / maskSize.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.5, faceWidth * 0.008)]).cropped(to: extent)
        // Suppress processing around image edges as well as the protected landmarks.
        let edges = input.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 4])
            .applyingFilter("CIColorInvert")
            .applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1), "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)])
        let detailMask = mask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: edges])
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: amount * style.smoothing, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: amount * style.smoothing, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: amount * style.smoothing, w: 0)])
        let smooth = input.clampedToExtent()
            .applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.02 + amount * 0.055, "inputSharpness": 0.35])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.3, faceWidth * 0.006 * amount)])
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: amount * style.lift]).cropped(to: extent)
        return smooth.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: input, kCIInputMaskImageKey: detailMask]).cropped(to: extent)
    }

    func beautyFrame(_ image: CIImage, strength: Double, style: BeautyStyle) -> (image: UIImage?, faceCount: Int) {
        let faces = detectFaces(image)
        let processed = beauty(image, strength: strength, style: style, faces: faces)
        let rendered = context.createCGImage(processed, from: processed.extent).map { UIImage(cgImage: $0) }
        return (rendered, faces.count)
    }

    /// Beauty, brightness, capture-aspect crop and rotation — everything the crop step itself sits on top of.
    /// Shared by `base(_:recipe:)` and `CropEditorView`, so the photo the user positions the crop against
    /// is pixel-for-pixel the same one `base` crops from; preview and export can never disagree.
    func imageBeforeCrop(_ original: UIImage, recipe: PhotoRecipe, maxDimension: CGFloat? = nil) -> UIImage {
        let input = normalized(original, maxDimension: maxDimension)
        guard var ci = CIImage(image: input) else { return input }
        ci = beauty(ci, strength: recipe.beauty, style: recipe.beautyStyle ?? .natural)
        ci = ci.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: recipe.brightness])
        if let aspect = recipe.captureAspect { ci = ci.cropped(to: aspect.cropRect(in: ci.extent)) }
        // Normalizing into 0..<4 also covers a negative count, which `0..<` would otherwise trap on.
        for _ in 0..<(((recipe.quarterTurns % 4) + 4) % 4) { ci = ci.oriented(.right) }
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return input }
        return UIImage(cgImage: cg)
    }

    /// The centered crop rect used when a ratio is chosen but the user hasn't positioned it yet
    /// (and for every pre-existing draft, which only ever stored the ratio). Matches the crop this
    /// app always produced before positioning was introduced.
    static func defaultCropRect(ratio: CropRatio, extentSize: CGSize) -> NormalizedRect {
        guard let value = ratio.fixedValue, extentSize.width > 0, extentSize.height > 0 else { return NormalizedRect() }
        let width = min(extentSize.width, extentSize.height * value)
        let height = width / value
        return NormalizedRect(x: (extentSize.width - width) / 2 / extentSize.width,
                              y: (extentSize.height - height) / 2 / extentSize.height,
                              width: width / extentSize.width, height: height / extentSize.height)
    }

    /// Resolves a recipe's crop selection to a pixel rect within `extent`, flipping into Core Image's
    /// bottom-left origin. Used for both the exported image and (via `defaultCropRect`) the editor's
    /// initial/reset position, so the two stay in lockstep.
    static func resolvedCropRect(ratio: CropRatio, normalized rectOrNil: NormalizedRect?, extent: CGRect) -> CGRect {
        let rect = (rectOrNil ?? defaultCropRect(ratio: ratio, extentSize: extent.size)).clamped()
        let width = max(1, rect.width * extent.width)
        let height = max(1, rect.height * extent.height)
        let left = extent.minX + rect.x * extent.width
        let top = rect.y * extent.height
        let originY = extent.minY + (extent.height - top - height)
        let resolved = CGRect(x: left, y: originY, width: width, height: height)
        let clipped = resolved.intersection(extent)
        return clipped.isEmpty ? extent : clipped
    }

    func base(_ original: UIImage, recipe: PhotoRecipe, maxDimension: CGFloat? = nil) -> UIImage {
        let precrop = imageBeforeCrop(original, recipe: recipe, maxDimension: maxDimension)
        guard let crop = recipe.crop, let ci = CIImage(image: precrop) else { return precrop }
        let rect = Self.resolvedCropRect(ratio: crop, normalized: recipe.cropRect, extent: ci.extent)
        guard let cg = context.createCGImage(ci.cropped(to: rect), from: rect) else { return precrop }
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
