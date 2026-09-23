import XCTest
import UIKit
import CoreImage
@testable import PenPhoto

final class PenPhotoTests: XCTestCase {
    func testJapaneseFontIsBundled() {
        XCTAssertNotNil(UIFont(name: "Yomogi-Regular", size: 30))
    }
    func testRecipeRoundTripPreservesEditableJapaneseText() throws {
        let recipe = PhotoRecipe(captions: [Caption(text: "京都で、ゆきと。☕️\nまた来よう", x: 0.23, y: 0.65, size: 0.07, rotation: -12, ink: .coral)], beauty: 0.4, brightness: 0.05, quarterTurns: 1)
        XCTAssertEqual(try JSONDecoder().decode(PhotoRecipe.self, from: JSONEncoder().encode(recipe)), recipe)
    }
    func testRotationSwapsPixelDimensions() {
        let original = solidImage(size: CGSize(width: 400, height: 600))
        let rendered = ImageProcessor.shared.render(original, recipe: PhotoRecipe(quarterTurns: 1))
        XCTAssertEqual(rendered.size, CGSize(width: 600, height: 400))
        XCTAssertEqual(rendered.scale, 1)
    }
    func testRotatingLeftUndoesRotatingRightAndWrapsWithoutGoingNegative() {
        var recipe = PhotoRecipe()
        recipe.rotate(clockwise: true)
        XCTAssertEqual(recipe.quarterTurns, 1)
        recipe.rotate(clockwise: false)
        XCTAssertEqual(recipe.quarterTurns, 0)
        recipe.rotate(clockwise: false)
        XCTAssertEqual(recipe.quarterTurns, 3, "Turning left from zero must wrap, not store a negative count.")
    }
    func testLeftRotationRendersIdenticallyToThreeRightTurns() {
        let original = quadrantImage(size: CGSize(width: 200, height: 300))
        var left = PhotoRecipe()
        left.rotate(clockwise: false)
        let right = PhotoRecipe(quarterTurns: 3)
        XCTAssertEqual(ImageProcessor.shared.render(original, recipe: left).pngData(),
                       ImageProcessor.shared.render(original, recipe: right).pngData())
    }
    func testNegativeQuarterTurnsRenderLikeTheEquivalentForwardTurn() {
        // Nothing in the editor stores a negative count, but a hand-written or future recipe could;
        // the renderer must normalize it instead of trapping on an invalid range.
        let original = quadrantImage(size: CGSize(width: 200, height: 300))
        XCTAssertEqual(ImageProcessor.shared.render(original, recipe: PhotoRecipe(quarterTurns: -1)).pngData(),
                       ImageProcessor.shared.render(original, recipe: PhotoRecipe(quarterTurns: 3)).pngData())
    }
    func testRotatingEitherDirectionResetsCropPositionButKeepsTheRatio() {
        let positioned = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        for clockwise in [true, false] {
            var recipe = PhotoRecipe(crop: .portrait, cropRect: positioned)
            recipe.rotate(clockwise: clockwise)
            XCTAssertEqual(recipe.crop, .portrait, "clockwise: \(clockwise)")
            XCTAssertNil(recipe.cropRect, "clockwise: \(clockwise)")
        }
    }
    func testExportBurnsCaptionIntoPixels() {
        let original = solidImage(size: CGSize(width: 400, height: 600))
        let plain = ImageProcessor.shared.render(original, recipe: PhotoRecipe())
        let captioned = ImageProcessor.shared.render(original, recipe: PhotoRecipe(captions: [Caption(text: "誰と来た？", ink: .charcoal)]))
        XCTAssertEqual(plain.size, captioned.size)
        XCTAssertNotEqual(plain.pngData(), captioned.pngData())
    }
    func testCenterCropUsesRequestedAspectRatio() {
        let original = solidImage(size: CGSize(width: 400, height: 600))
        let cropped = ImageProcessor.shared.render(original, recipe: PhotoRecipe(crop: .square))
        XCTAssertEqual(cropped.size, CGSize(width: 400, height: 400))
    }
    func testOldRecipesWithoutCropRectStillCropCentered() throws {
        // Drafts saved before positioning existed only ever stored the ratio; they must keep
        // cropping centered exactly as before, with no crash from the missing key.
        let json = #"{"captions":[],"beauty":0,"brightness":0,"quarterTurns":0,"crop":"square"}"#.data(using: .utf8)!
        let recipe = try JSONDecoder().decode(PhotoRecipe.self, from: json)
        XCTAssertNil(recipe.cropRect)
        let original = solidImage(size: CGSize(width: 400, height: 600))
        let cropped = ImageProcessor.shared.render(original, recipe: recipe)
        XCTAssertEqual(cropped.size, CGSize(width: 400, height: 400))
    }
    func testDefaultCropRectIsCenteredForEveryRatio() {
        let extent = CGSize(width: 400, height: 600)
        for ratio in [CropRatio.square, .portrait, .wide] {
            let rect = ImageProcessor.defaultCropRect(ratio: ratio, extentSize: extent)
            XCTAssertEqual(rect.x + rect.width / 2, 0.5, accuracy: 0.0001, "\(ratio) should default to horizontally centered")
            XCTAssertEqual(rect.y + rect.height / 2, 0.5, accuracy: 0.0001, "\(ratio) should default to vertically centered")
            XCTAssertEqual((rect.width * extent.width) / (rect.height * extent.height), ratio.fixedValue!, accuracy: 0.001)
        }
        XCTAssertEqual(ImageProcessor.defaultCropRect(ratio: .free, extentSize: extent), NormalizedRect())
    }
    func testCropRectPositionsTheRequestedRegionOfTheImage() throws {
        // Four solid quadrants let us prove both axes of the crop rect map correctly, not just its size.
        let quadrants = quadrantImage(size: CGSize(width: 200, height: 200))
        let topLeft = PhotoRecipe(crop: .square, cropRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let bottomRight = PhotoRecipe(crop: .square, cropRect: NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let croppedTopLeft = ImageProcessor.shared.render(quadrants, recipe: topLeft)
        let croppedBottomRight = ImageProcessor.shared.render(quadrants, recipe: bottomRight)
        XCTAssertEqual(croppedTopLeft.size, CGSize(width: 100, height: 100))
        try assertDominant(red: 255, green: 0, blue: 0, in: croppedTopLeft) // red quadrant
        try assertDominant(red: 0, green: 0, blue: 0, in: croppedBottomRight) // black quadrant
    }
    func testFreeCropAllowsAnArbitraryAspectRatio() {
        let original = solidImage(size: CGSize(width: 400, height: 600))
        let recipe = PhotoRecipe(crop: .free, cropRect: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.5))
        let cropped = ImageProcessor.shared.render(original, recipe: recipe)
        XCTAssertEqual(cropped.size, CGSize(width: 120, height: 300))
    }
    func testCropRectClampsOutOfRangeSelectionsInsideTheImage() {
        let extent = CGRect(x: 0, y: 0, width: 400, height: 600)
        let outOfRange = NormalizedRect(x: 1.5, y: -0.5, width: 2, height: 2)
        let rect = ImageProcessor.resolvedCropRect(ratio: .free, normalized: outOfRange, extent: extent)
        XCTAssertTrue(extent.contains(CGPoint(x: rect.minX, y: rect.minY)))
        XCTAssertLessThanOrEqual(rect.maxX, extent.maxX + 0.01)
        XCTAssertLessThanOrEqual(rect.maxY, extent.maxY + 0.01)
    }
    func testPreviewAndExportAgreeOnAPositionedCrop() throws {
        // The editor previews with `base(maxDimension:)`; export/save uses the full-resolution
        // `render`. They must select the same region even though their pixel sizes differ.
        let quadrants = quadrantImage(size: CGSize(width: 2000, height: 2000))
        let recipe = PhotoRecipe(crop: .square, cropRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let preview = ImageProcessor.shared.base(quadrants, recipe: recipe, maxDimension: 1400)
        let exported = ImageProcessor.shared.render(quadrants, recipe: recipe)
        XCTAssertEqual(exported.size, CGSize(width: 1000, height: 1000))
        XCTAssertLessThan(preview.size.width, exported.size.width, "Preview is downscaled for live editing; export stays full resolution.")
        XCTAssertEqual(preview.size.width / preview.size.height, 1, accuracy: 0.01)
        try assertDominant(red: 255, green: 0, blue: 0, in: preview)
        try assertDominant(red: 255, green: 0, blue: 0, in: exported)
    }
    func testCropCombinesWithRotationKeepingExactRatio() {
        // A crop applied after a 90° rotation must still respect the requested ratio exactly,
        // the same guarantee the pre-positioning center crop always gave.
        let original = solidImage(size: CGSize(width: 400, height: 600))
        let rotatedThenCropped = ImageProcessor.shared.render(original, recipe: PhotoRecipe(quarterTurns: 1, crop: .wide))
        XCTAssertEqual(rotatedThenCropped.size.width / rotatedThenCropped.size.height, 16.0 / 9.0, accuracy: 0.01)
    }
    func testCropSelectionRoundTripsThroughJSON() throws {
        let recipe = PhotoRecipe(crop: .portrait, cropRect: NormalizedRect(x: 0.12, y: 0.34, width: 0.5, height: 0.4))
        XCTAssertEqual(try JSONDecoder().decode(PhotoRecipe.self, from: JSONEncoder().encode(recipe)), recipe)
    }
    func testProjectReloadKeepsPositionedCropForReEditing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let cropRect = NormalizedRect(x: 0.15, y: 0.05, width: 0.6, height: 0.6)
        let project = PhotoProject(recipe: PhotoRecipe(crop: .square, cropRect: cropRect))
        try await store.save(project, original: solidImage(size: CGSize(width: 400, height: 400)))
        let reloaded = try await store.list().first
        XCTAssertEqual(reloaded?.recipe.crop, .square)
        XCTAssertEqual(reloaded?.recipe.cropRect, cropRect)
    }
    func testNormalizedRectClampStaysInsideUnitSquareWithoutShrinkingValidSizes() {
        let valid = NormalizedRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4)
        XCTAssertEqual(valid.clamped(), valid)
        let overflowing = NormalizedRect(x: 0.9, y: 0.9, width: 0.4, height: 0.4)
        let clamped = overflowing.clamped()
        XCTAssertEqual(clamped.width, 0.4); XCTAssertEqual(clamped.height, 0.4)
        XCTAssertEqual(clamped.x, 0.6, accuracy: 0.0001); XCTAssertEqual(clamped.y, 0.6, accuracy: 0.0001)
    }
    func testWideCaptureExportsLandscapeAndPortrait() {
        for size in [CGSize(width: 640, height: 480), CGSize(width: 480, height: 640)] {
            let original = solidImage(size: size)
            let output = ImageProcessor.shared.render(original, recipe: PhotoRecipe(captions: [Caption(text: "16:9で撮影")], captureAspect: .wide))
            let expected = size.width > size.height ? CGSize(width: 640, height: 360) : CGSize(width: 360, height: 640)
            XCTAssertEqual(output.size, expected)
        }
    }
    func testWideCaptureRotationKeepsWholeCapturedFrame() {
        let original = solidImage(size: CGSize(width: 480, height: 640))
        let output = ImageProcessor.shared.render(original, recipe: PhotoRecipe(quarterTurns: 1, captureAspect: .wide))
        XCTAssertEqual(output.size, CGSize(width: 640, height: 360))
    }
    func testPreviewAndCaptureShareCenteredAspect() {
        for aspect in CaptureAspect.allCases {
            let preview = aspect.previewSize(in: CGSize(width: 370, height: 470))
            XCTAssertLessThanOrEqual(preview.width, 370)
            XCTAssertLessThanOrEqual(preview.height, 470)
            let source = CGRect(x: 0, y: 0, width: 480, height: 640)
            let crop = aspect.cropRect(in: source)
            XCTAssertEqual(preview.width / preview.height, crop.width / crop.height, accuracy: 0.0001)
            XCTAssertEqual(crop.midX, source.midX)
            XCTAssertEqual(crop.midY, source.midY)
        }
    }
    func testOldRecipesDecodeWithoutCaptureAspect() throws {
        let json = #"{"captions":[],"beauty":0,"brightness":0,"quarterTurns":0}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(PhotoRecipe.self, from: json).captureAspect)
    }
    func testBeautyWithNoFacePreservesImage() {
        let original = solidImage(size: CGSize(width: 80, height: 120))
        let plain = ImageProcessor.shared.base(original, recipe: PhotoRecipe())
        let beauty = ImageProcessor.shared.base(original, recipe: PhotoRecipe(beauty: 0.8))
        XCTAssertEqual(plain.pngData(), beauty.pngData())
    }
    func testProjectReloadKeepsOriginalWhileRecipeChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        var project = PhotoProject(recipe: PhotoRecipe(captions: [Caption(text: "最初のことば")], captureAspect: .wide))
        try await store.save(project, original: solidImage(size: CGSize(width: 40, height: 60)))
        project.recipe.captions[0].text = "あとから書き直した"
        try await store.save(project, original: solidImage(size: CGSize(width: 90, height: 90)))
        let projects = try await store.list()
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.recipe.captureAspect, .wide)
        XCTAssertEqual(projects.first?.recipe.captions.first?.text, "あとから書き直した")
        let loaded = try await store.load(projects[0])
        XCTAssertEqual(loaded.image.size, CGSize(width: 40, height: 60))
    }
    func testBeautyDetectsAndProcessesRealFace() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "astronaut", withExtension: "png"))
        let photo = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let ci = try XCTUnwrap(CIImage(image: photo))
        let processor = ImageProcessor.shared
        let faces = processor.detectFaces(ci)
        XCTAssertFalse(faces.isEmpty, "The real portrait must exercise face detection, not the no-face fallback.")
        XCTAssertFalse(try XCTUnwrap(faces.first).protectedFeatures.isEmpty)
        let normal = processor.base(photo, recipe: PhotoRecipe())
        let soft = processor.base(photo, recipe: PhotoRecipe(beauty: 1, beautyStyle: .soft))
        let clear = processor.base(photo, recipe: PhotoRecipe(beauty: 1, beautyStyle: .clear))
        XCTAssertEqual(normal.size, soft.size)
        XCTAssertNotEqual(normal.pngData(), soft.pngData())
        XCTAssertNotEqual(clear.pngData(), soft.pngData())
        let processedCI = processor.beauty(ci, strength: 1, style: .soft, faces: faces)
        XCTAssertEqual(pixels(ci, rect: CGRect(x: 0, y: 0, width: 20, height: 20)), pixels(processedCI, rect: CGRect(x: 0, y: 0, width: 20, height: 20)), "Background away from the face must be untouched.")
        for (name, image) in [("Beauty original", normal), ("Beauty soft", soft), ("Beauty clear", clear)] {
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    func testBeautyProtectsFeaturesAndClampsStrength() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { ctx in
            UIColor(white: 0.5, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        let ci = try XCTUnwrap(CIImage(image: photo))
        let faces = [ImageProcessor.FaceRegion(bounds: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), protectedFeatures: [CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)])]
        let processor = ImageProcessor.shared
        let processed = processor.beauty(ci, strength: 1, style: .clear, faces: faces)
        let protected = CGRect(x: 95, y: 95, width: 10, height: 10)
        XCTAssertEqual(pixels(ci, rect: protected), pixels(processed, rect: protected))
        let cheek = CGRect(x: 48, y: 95, width: 10, height: 10)
        XCTAssertNotEqual(pixels(ci, rect: cheek), pixels(processed, rect: cheek))
        XCTAssertTrue(processor.beauty(ci, strength: 0, faces: faces) === ci)
        XCTAssertTrue(processor.beauty(ci, strength: -1, faces: faces) === ci)
        XCTAssertEqual(pixels(processed, rect: ci.extent), pixels(processor.beauty(ci, strength: 2, style: .clear, faces: faces), rect: ci.extent))
    }
    func testBeautyPreviewTimingOnPortraitFixture() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "astronaut", withExtension: "png"))
        let photo = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let source = try XCTUnwrap(CIImage(image: photo))
        let input = source.transformed(by: CGAffineTransform(scaleX: 1.25, y: 1.25))
        let processor = ImageProcessor.shared
        _ = processor.beautyFrame(input, strength: 0.55, style: .natural)
        var milliseconds: [Double] = []
        for _ in 0..<30 {
            autoreleasepool {
                let start = CFAbsoluteTimeGetCurrent()
                let result = processor.beautyFrame(input, strength: 0.55, style: .natural)
                milliseconds.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                XCTAssertNotNil(result.image)
                XCTAssertGreaterThan(result.faceCount, 0)
            }
        }
        milliseconds.sort()
        let report = String(format: "640px portrait, 30 frames; median %.1f ms; p95 %.1f ms; thermal state %d. Processor-only measurement, excludes live camera capture and display.", milliseconds[15], milliseconds[28], ProcessInfo.processInfo.thermalState.rawValue)
        print("BEAUTY_BENCHMARK: " + report)
        let attachment = XCTAttachment(string: report); attachment.name = "Beauty processing timing"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testBeautyStylePersistsAndOldRecipeDefaults() throws {
        let recipe = PhotoRecipe(beauty: 0.72, beautyStyle: .clear)
        XCTAssertEqual(try JSONDecoder().decode(PhotoRecipe.self, from: JSONEncoder().encode(recipe)), recipe)
        let data = #"{"captions":[],"beauty":0.4,"brightness":0,"quarterTurns":0}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(PhotoRecipe.self, from: data).beautyStyle)
    }
    private func pixels(_ image: CIImage, rect: CGRect) -> Data {
        var data = Data(count: Int(rect.width * rect.height) * 4)
        data.withUnsafeMutableBytes { buffer in
            CIContext().render(image, toBitmap: buffer.baseAddress!, rowBytes: Int(rect.width) * 4, bounds: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        return data
    }
    private func solidImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in UIColor.white.setFill(); renderer.fill(CGRect(origin: .zero, size: size)) }
    }
    /// Red top-left / green top-right / blue bottom-left / black bottom-right, in UIKit's
    /// top-left-origin, y-down space — matching `NormalizedRect`'s convention.
    private func quadrantImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let halfW = size.width / 2, halfH = size.height / 2
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: halfW, height: halfH))
            UIColor.green.setFill(); ctx.fill(CGRect(x: halfW, y: 0, width: halfW, height: halfH))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: halfH, width: halfW, height: halfH))
            UIColor.black.setFill(); ctx.fill(CGRect(x: halfW, y: halfH, width: halfW, height: halfH))
        }
    }
    private func assertDominant(red: UInt8, green: UInt8, blue: UInt8, in image: UIImage, file: StaticString = #filePath, line: UInt = #line) throws {
        let ci = try XCTUnwrap(CIImage(image: image), file: file, line: line)
        let rect = CGRect(x: ci.extent.midX - 2, y: ci.extent.midY - 2, width: 4, height: 4)
        let data = pixels(ci, rect: rect)
        XCTAssertEqual(Int(data[0]), Int(red), accuracy: 4, "red channel", file: file, line: line)
        XCTAssertEqual(Int(data[1]), Int(green), accuracy: 4, "green channel", file: file, line: line)
        XCTAssertEqual(Int(data[2]), Int(blue), accuracy: 4, "blue channel", file: file, line: line)
    }
}
