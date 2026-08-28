import Foundation
import ImageIO
import UIKit

/// Downscales and compresses photos before they are stored.
///
/// Uses ImageIO thumbnailing, which decodes straight to the target size instead of
/// loading the full-resolution photo into memory first. That keeps memory flat even
/// for very large camera images.
nonisolated enum MedicineImageProcessor {
    /// Returns JPEG data downscaled so the long edge is at most `maxPixelSize`.
    ///
    /// Returns `nil` when the data is not a decodable image. `compressionQuality`
    /// balances file size against label readability; 0.7 keeps text legible.
    static func downsampledJPEGData(
        from data: Data,
        maxPixelSize: CGFloat,
        compressionQuality: CGFloat = 0.7
    ) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage).jpegData(compressionQuality: compressionQuality)
    }
}

/// Boundary for storing medicine photos, so tests and previews can use fakes.
protocol MedicineImageStoring {
    /// Processes and stores the photo for one medicine, replacing any existing one.
    func saveImage(_ data: Data, for medicineID: UUID) async throws

    /// Removes the stored photo and thumbnail for one medicine, if present.
    func deleteImage(for medicineID: UUID) async

    /// The stored full-size image file, or `nil` when the medicine has no photo.
    func imageURL(for medicineID: UUID) -> URL?

    /// The stored thumbnail file, or `nil` when the medicine has no photo.
    func thumbnailURL(for medicineID: UUID) -> URL?
}

/// Stores medicine photos as files in the app sandbox.
///
/// Each medicine gets two JPEGs named by its UUID: a display image capped at 1280 px
/// and a small thumbnail for list rows. Files live in Application Support under
/// `PillEye/Images` with complete file protection, and iOS removes them with the app.
nonisolated struct MedicineImageStore: MedicineImageStoring {
    /// Long-edge cap for the stored display image. Large enough to read label text on
    /// a phone screen, small enough to keep files at a few hundred kilobytes.
    static let displayMaxPixelSize: CGFloat = 1280

    /// Long-edge cap for list thumbnails (sized for ~44 pt rows on 3x screens).
    static let thumbnailMaxPixelSize: CGFloat = 240

    private let directoryURL: URL?

    /// Creates the store rooted in the app's Application Support directory.
    init() {
        directoryURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("PillEye", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
    }

    /// Processes the photo off the main actor and writes both sizes atomically.
    func saveImage(_ data: Data, for medicineID: UUID) async throws {
        guard let directoryURL else { return }

        try await Task.detached(priority: .userInitiated) {
            guard
                let display = MedicineImageProcessor.downsampledJPEGData(
                    from: data,
                    maxPixelSize: Self.displayMaxPixelSize
                ),
                let thumbnail = MedicineImageProcessor.downsampledJPEGData(
                    from: data,
                    maxPixelSize: Self.thumbnailMaxPixelSize
                )
            else {
                throw CocoaError(.fileWriteUnknown)
            }

            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: directoryURL.path
            )

            for (fileData, url) in [
                (display, Self.imageFileURL(in: directoryURL, for: medicineID)),
                (thumbnail, Self.thumbnailFileURL(in: directoryURL, for: medicineID))
            ] {
                try fileData.write(to: url, options: [.atomic])
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: url.path
                )
            }
        }.value
    }

    /// Removes both stored files. Missing files are not an error.
    func deleteImage(for medicineID: UUID) async {
        guard let directoryURL else { return }
        try? FileManager.default.removeItem(at: Self.imageFileURL(in: directoryURL, for: medicineID))
        try? FileManager.default.removeItem(at: Self.thumbnailFileURL(in: directoryURL, for: medicineID))
    }

    func imageURL(for medicineID: UUID) -> URL? {
        existingFileURL { Self.imageFileURL(in: $0, for: medicineID) }
    }

    func thumbnailURL(for medicineID: UUID) -> URL? {
        existingFileURL { Self.thumbnailFileURL(in: $0, for: medicineID) }
    }

    /// Returns the built URL only when a file actually exists there.
    private func existingFileURL(_ build: (URL) -> URL) -> URL? {
        guard let directoryURL else { return nil }
        let url = build(directoryURL)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func imageFileURL(in directory: URL, for medicineID: UUID) -> URL {
        directory.appendingPathComponent("\(medicineID.uuidString).jpg")
    }

    private static func thumbnailFileURL(in directory: URL, for medicineID: UUID) -> URL {
        directory.appendingPathComponent("\(medicineID.uuidString)-thumb.jpg")
    }
}

/// Image store that keeps nothing, for tests and previews that don't exercise photos.
nonisolated struct NullMedicineImageStore: MedicineImageStoring {
    func saveImage(_ data: Data, for medicineID: UUID) async throws {}
    func deleteImage(for medicineID: UUID) async {}
    func imageURL(for medicineID: UUID) -> URL? { nil }
    func thumbnailURL(for medicineID: UUID) -> URL? { nil }
}
