import Foundation
import UIKit
import Photos

actor ProjectStore {
    static let shared = ProjectStore()
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PenPhoto", isDirectory: true)
    }
    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func list() throws -> [PhotoProject] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url.appendingPathComponent("recipe.json")) else { return nil }
                return try? JSONDecoder().decode(PhotoProject.self, from: data)
            }.sorted { $0.createdAt > $1.createdAt }
    }
    func save(_ project: PhotoProject, original: UIImage) throws {
        let directory = folder(project.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalURL = directory.appendingPathComponent("original.jpg")
        if !FileManager.default.fileExists(atPath: originalURL.path) {
            guard let data = original.jpegData(compressionQuality: 0.98) else { throw AppError.message("元写真を保存できませんでした。") }
            try data.write(to: originalURL, options: .atomic)
        }
        let thumbnail = ImageProcessor.shared.render(original, recipe: project.recipe, maxDimension: 480)
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.85) else { throw AppError.message("サムネイルを作成できませんでした。") }
        try thumbnailData.write(to: directory.appendingPathComponent("thumbnail.jpg"), options: .atomic)
        try JSONEncoder().encode(project).write(to: directory.appendingPathComponent("recipe.json"), options: .atomic)
    }
    func load(_ project: PhotoProject) throws -> EditingPhoto {
        let data = try Data(contentsOf: folder(project.id).appendingPathComponent("original.jpg"))
        guard let image = UIImage(data: data) else { throw AppError.message("元写真を読み込めませんでした。") }
        return EditingPhoto(project: project, image: image)
    }
    func thumbnail(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: folder(id).appendingPathComponent("thumbnail.jpg").path) }
}

enum PhotoExporter {
    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.message("編集内容はマイフォトに保存しました。写真アプリにも保存するには、設定で写真の追加を許可してください。")
        }
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
    }
}
