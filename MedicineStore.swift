import CoreTransferable
import Foundation
import Observation
import UniformTypeIdentifiers

/// Storage for medicines shown by the app.
@MainActor
@Observable
final class MedicineStore {
    private(set) var medicines: [Medicine] = []

    /// Bumped whenever a photo changes without the medicine list itself changing.
    ///
    /// Photos live on disk keyed by medicine ID, so attaching one to an existing medicine
    /// does not mutate `medicines`. Views that show photos read this property so the
    /// Observation framework re-renders them after the change.
    private(set) var photoVersion = 0

    private let notificationScheduler: NotificationScheduling
    private let storageURL: URL?
    private let imageStore: MedicineImageStoring

    /// Creates the store used by the real app, wired to iOS local notifications and disk storage.
    ///
    /// Does not load from disk synchronously — call `load()` from the view's `.task` instead
    /// so the main actor is not blocked during app launch.
    init() {
        self.notificationScheduler = LocalNotificationScheduler()
        self.storageURL = Self.defaultStorageURL()
        self.imageStore = MedicineImageStore()
    }

    /// Loads saved medicines from disk on a background thread.
    ///
    /// Call this once from a SwiftUI `.task` modifier on the root view. The main actor is
    /// never blocked — only the result assignment runs there.
    func load() async {
        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let url = storageURL
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
            medicines = try Self.decoder.decode([Medicine].self, from: data)
        } catch {
            // File damaged or unreadable — stay empty.
        }
    }

    /// Creates the store with a custom scheduler.
    ///
    /// Passing `nil` for `storageURL` keeps the store memory-only, which avoids tests
    /// touching real app data.
    init(
        notificationScheduler: NotificationScheduling,
        storageURL: URL? = nil,
        imageStore: MedicineImageStoring = NullMedicineImageStore()
    ) {
        self.notificationScheduler = notificationScheduler
        self.storageURL = storageURL
        self.imageStore = imageStore

        if storageURL != nil {
            loadFromDisk()
        }
    }

    /// Validates, stores, persists, and schedules a reminder for a medicine.
    ///
    /// Saving an exact duplicate (same name and same calendar dates) is rejected with
    /// `MedicineValidationError.duplicateMedicine`. An optional photo is processed and
    /// stored alongside the record. Returns the saved medicine so the UI can show a
    /// confirmation with the stored (normalized) values.
    @discardableResult
    func save(
        name: String,
        manufacturingDate: Date,
        expiryDate: Date,
        reminderLeadDays: Int = 1,
        photoData: Data? = nil
    ) async throws -> Medicine {
        try MedicineValidator.validate(
            name: name,
            manufacturingDate: manufacturingDate,
            expiryDate: expiryDate
        )

        guard !medicines.contains(where: {
            $0.isDuplicate(ofName: name, manufacturingDate: manufacturingDate, expiryDate: expiryDate)
        }) else {
            throw MedicineValidationError.duplicateMedicine
        }

        let medicine = Medicine(
            name: name,
            manufacturingDate: manufacturingDate,
            expiryDate: expiryDate,
            reminderLeadDays: reminderLeadDays
        )

        if let photoData {
            try await imageStore.saveImage(photoData, for: medicine.id)
        }

        try await notificationScheduler.scheduleExpiryReminder(for: medicine)
        medicines.insert(medicine, at: 0)
        try persistToDisk()
        return medicine
    }

    /// Attaches (or replaces) the stored photo for an already-saved medicine.
    func attachPhoto(_ data: Data, to medicine: Medicine) async throws {
        try await imageStore.saveImage(data, for: medicine.id)
        photoVersion += 1
    }

    /// The stored full-size photo for a medicine, or `nil` when it has none.
    func imageURL(for medicine: Medicine) -> URL? {
        imageStore.imageURL(for: medicine.id)
    }

    /// The stored thumbnail for a medicine, or `nil` when it has none.
    func thumbnailURL(for medicine: Medicine) -> URL? {
        imageStore.thumbnailURL(for: medicine.id)
    }

    /// Applies changes to an existing medicine, saves them to disk, and refreshes its reminder.
    ///
    /// The `MedicineUpdate` struct is intentionally broader than the current UI. Right now
    /// only the reminder lead is editable, but future name/date edits can use the same path.
    func update(medicineID: UUID, changes: MedicineUpdate) async throws {
        guard let index = medicines.firstIndex(where: { $0.id == medicineID }) else { return }

        let current = medicines[index]
        let updated = Medicine(
            id: current.id,
            name: changes.name ?? current.name,
            manufacturingDate: changes.manufacturingDate ?? current.manufacturingDate,
            expiryDate: changes.expiryDate ?? current.expiryDate,
            reminderLeadDays: changes.reminderLeadDays ?? current.reminderLeadDays,
            createdAt: current.createdAt
        )

        try MedicineValidator.validate(
            name: updated.name,
            manufacturingDate: updated.manufacturingDate,
            expiryDate: updated.expiryDate
        )

        medicines[index] = updated
        do {
            try persistToDisk()
        } catch {
            medicines[index] = current
            throw error
        }
        try await notificationScheduler.scheduleExpiryReminder(for: updated)
    }

    /// Removes a medicine from memory, saves the changed list to disk, cancels its
    /// notification, and deletes its stored photo.
    ///
    /// The previous list is restored if disk writing fails. This avoids a confusing state
    /// where the UI hides a medicine but the saved JSON file still contains it.
    func delete(_ medicine: Medicine) async throws {
        let previousMedicines = medicines
        medicines.removeAll { $0.id == medicine.id }

        do {
            try persistToDisk()
        } catch {
            medicines = previousMedicines
            throw error
        }

        await notificationScheduler.cancelReminder(for: medicine.id)
        await imageStore.deleteImage(for: medicine.id)
    }

    /// Converts the medicines into JSON data.
    ///
    /// This keeps the storage portable because the array can be exported or imported as JSON.
    func exportData() throws -> Data {
        try Self.encoder.encode(medicines)
    }

    /// Replaces the current list from previously exported JSON data, saves it to disk,
    /// cancels all previous notifications, and schedules reminders for the imported medicines.
    func importData(_ data: Data) async throws {
        let previous = medicines
        medicines = try Self.decoder.decode([Medicine].self, from: data)
        do {
            try persistToDisk()
        } catch {
            medicines = previous
            throw error
        }
        for medicine in previous {
            await notificationScheduler.cancelReminder(for: medicine.id)
        }
        // Photos are device-local attachments keyed by medicine ID. Remove them only for
        // medicines that are gone after the import, so restoring a backup on the same
        // device keeps the photos of medicines that survived.
        for medicine in previous where !medicines.contains(where: { $0.id == medicine.id }) {
            await imageStore.deleteImage(for: medicine.id)
        }
        for medicine in medicines {
            try? await notificationScheduler.scheduleExpiryReminder(for: medicine)
        }
    }

    /// Location of the JSON file inside this app's sandbox.
    ///
    /// `Application Support` is private to this app. The system removes it when the app is
    /// uninstalled, which matches the requested behavior.
    private static func defaultStorageURL() -> URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent("PillEye", isDirectory: true)
            .appendingPathComponent("medicines.json")
    }

    /// Reads medicines from disk when the app starts.
    ///
    /// If the file does not exist yet, the app starts with an empty list. If the file is
    /// damaged, the app also starts empty instead of crashing.
    private func loadFromDisk() {
        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            medicines = try Self.decoder.decode([Medicine].self, from: data)
        } catch {
            medicines = []
        }
    }

    /// Writes the current medicine list to the app sandbox as JSON.
    ///
    /// `.completeFileProtection` keeps the saved medicine file encrypted and unavailable
    /// while the iPhone is locked. Notifications only carry the medicine ID, so the lock
    /// screen does not need this file to show the reminder.
    private func persistToDisk() throws {
        guard let storageURL else { return }

        let directoryURL = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directoryURL.path
        )

        let data = try exportData()
        try data.write(to: storageURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: storageURL.path
        )
    }

    /// Shared JSON encoder so dates are written in a stable, readable format.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// Shared JSON decoder that matches the encoder above.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// A shareable backup of every saved medicine.
///
/// Written lazily — only when the user picks a share destination — so the encode cost
/// is paid at share time, not on every tap of the Export button.
struct MedicineBackupFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { backup in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileName())
            try backup.data.write(to: url, options: [.atomic])
            // Match the protection level of the on-disk store so the file cannot be
            // read from the temp directory while the device is locked.
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            return SentTransferredFile(url)
        }
    }

    /// A dated file name such as `MedXpiryTracker-Backup-2026-07-12.json`.
    ///
    /// The date helps users tell backups apart when they keep several in Files.
    static func fileName(for date: Date = .now) -> String {
        "MedXpiryTracker-Backup-\(date.formatted(.iso8601.year().month().day())).json"
    }
}
