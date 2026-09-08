import XCTest
import UIKit
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
    private func solidImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in UIColor.white.setFill(); renderer.fill(CGRect(origin: .zero, size: size)) }
    }
}
