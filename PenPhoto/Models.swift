import SwiftUI
import UIKit

struct Caption: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var x: Double = 0.5
    var y: Double = 0.78
    var size: Double = 0.065
    var rotation: Double = -4
    var ink: Ink = .white
    var backdrop = true
}

enum Ink: String, Codable, CaseIterable {
    case white, charcoal, coral, yellow
    var uiColor: UIColor {
        switch self {
        case .white: return .white
        case .charcoal: return UIColor(red: 0.16, green: 0.19, blue: 0.18, alpha: 1)
        case .coral: return UIColor(red: 0.98, green: 0.48, blue: 0.37, alpha: 1)
        case .yellow: return UIColor(red: 1, green: 0.87, blue: 0.48, alpha: 1)
        }
    }
}

/// The UI remains portrait; turning the phone produces the corresponding landscape photo.
enum CaptureAspect: String, Codable, CaseIterable {
    case standard, wide
    var title: String { self == .standard ? "4:3" : "16:9" }
    var portraitRatio: CGFloat { self == .standard ? 3.0 / 4.0 : 9.0 / 16.0 }

    func previewSize(in available: CGSize) -> CGSize {
        let height = max(1, min(available.height, available.width / portraitRatio))
        return CGSize(width: height * portraitRatio, height: height)
    }

    func cropRect(in extent: CGRect) -> CGRect {
        let ratio = extent.width > extent.height ? 1 / portraitRatio : portraitRatio
        let width = min(extent.width, extent.height * ratio)
        let height = width / ratio
        return CGRect(x: extent.midX - width / 2, y: extent.midY - height / 2, width: width, height: height)
    }
}

enum CropRatio: String, Codable, CaseIterable {
    case square, portrait, wide, free
    var title: String { switch self { case .square: return "1:1"; case .portrait: return "4:5"; case .wide: return "16:9"; case .free: return "自由" } }
    /// Fixed width/height ratio for the presets; `free` has no fixed ratio, the user's selection defines it.
    var fixedValue: CGFloat? { switch self { case .square: return 1; case .portrait: return 4 / 5; case .wide: return 16 / 9; case .free: return nil } }
}

/// A crop selection expressed as a fraction of the (post-rotation) photo, using the same
/// top-left-origin, y-down convention as `Caption.x`/`.y` so the two line up visually.
/// `ImageProcessor` resolves this against the actual pixel extent for both the live preview
/// and the exported image, so the two always match.
struct NormalizedRect: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1

    /// Keeps the rect fully inside the unit square without changing its size unless the size itself is invalid.
    func clamped() -> NormalizedRect {
        let w = min(max(width, 0.01), 1)
        let h = min(max(height, 0.01), 1)
        let x = min(max(self.x, 0), 1 - w)
        let y = min(max(self.y, 0), 1 - h)
        return NormalizedRect(x: x, y: y, width: w, height: h)
    }
}

enum BeautyStyle: String, Codable, CaseIterable {
    case natural, clear, soft
    var title: String { switch self { case .natural: return "ナチュラル"; case .clear: return "明るめ"; case .soft: return "なめらか" } }
    var smoothing: Double { self == .soft ? 0.85 : 0.6 }
    var lift: Double { self == .clear ? 0.065 : 0.025 }
}

struct PhotoRecipe: Codable, Equatable {
    var captions: [Caption] = []
    var beauty: Double = 0
    var beautyStyle: BeautyStyle? = nil
    var brightness: Double = 0
    var quarterTurns = 0
    var crop: CropRatio? = nil
    /// The user's chosen crop position/extent, normalized to the post-rotation photo.
    /// `nil` means "use the centered default for `crop`" — keeps pre-existing drafts (and any
    /// draft where the ratio was just picked but not yet repositioned) rendering exactly as before.
    var cropRect: NormalizedRect? = nil
    var captureAspect: CaptureAspect? = nil // nil preserves projects created before capture ratios were added.
}

struct PhotoProject: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var recipe = PhotoRecipe()
    var title: String { recipe.captions.first(where: { !$0.text.isEmpty })?.text ?? "ことばを待つ写真" }
}

struct EditingPhoto: Identifiable {
    var id: UUID { project.id }
    var project: PhotoProject
    var image: UIImage
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum Palette {
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let ink = Color(red: 0.18, green: 0.24, blue: 0.22)
    static let accent = Color(red: 0.76, green: 0.34, blue: 0.24)
}
