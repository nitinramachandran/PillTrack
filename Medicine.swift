import Foundation

/// The main data object for the app.
nonisolated struct Medicine: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var manufacturingDate: Date
    var expiryDate: Date
    var reminderLeadDays: Int
    let createdAt: Date

    /// Creates a new medicine record.
    init(
        id: UUID = UUID(),
        name: String,
        manufacturingDate: Date,
        expiryDate: Date,
        reminderLeadDays: Int = 1,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCapitalized
        self.manufacturingDate = manufacturingDate
        self.expiryDate = expiryDate
        self.reminderLeadDays = reminderLeadDays
        self.createdAt = createdAt
    }

    /// Restores a medicine from saved JSON.
    ///
    /// `reminderLeadDays` was added in version 1.2, so files and backups written by
    /// older versions do not contain it. Decoding falls back to the original one-day
    /// lead instead of failing, which keeps old data and old backups importable.
    /// Older files also carry a per-medicine `snoozeMinutes` value; it is ignored now
    /// that the notification snooze uses one fixed duration.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        manufacturingDate = try container.decode(Date.self, forKey: .manufacturingDate)
        expiryDate = try container.decode(Date.self, forKey: .expiryDate)
        reminderLeadDays = try container.decodeIfPresent(Int.self, forKey: .reminderLeadDays) ?? 1
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// Fires `reminderLeadDays` before expiry.
    var reminderDate: Date {
        Calendar.current.date(byAdding: .day, value: -reminderLeadDays, to: expiryDate) ?? expiryDate
    }

    /// Returns `true` when the medicine expiry date has already passed.
    var isExpired: Bool {
        expiryDate < Date()
    }

    /// How soon (in days) before expiry a medicine counts as "expiring soon".
    static let expiringSoonWindowDays = 60

    /// Returns `true` when the medicine has not expired yet but expires within the next
    /// `expiringSoonWindowDays` days. Already-expired medicines are excluded.
    ///
    /// The optional `now` and `calendar` parameters keep this testable with fixed inputs.
    func isExpiringSoon(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard expiryDate >= now else { return false }
        guard let threshold = calendar.date(byAdding: .day, value: Self.expiringSoonWindowDays, to: now) else {
            return false
        }
        return expiryDate <= threshold
    }

    /// Returns `true` when this record describes the same medicine as the given form values.
    ///
    /// Two records count as the same medicine when the names match (ignoring case and
    /// surrounding whitespace) and both dates fall on the same calendar days. The same
    /// name with a different expiry date is a separate box and is not a duplicate.
    func isDuplicate(
        ofName name: String,
        manufacturingDate: Date,
        expiryDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let candidateName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.name.caseInsensitiveCompare(candidateName) == .orderedSame
            && calendar.isDate(self.manufacturingDate, inSameDayAs: manufacturingDate)
            && calendar.isDate(self.expiryDate, inSameDayAs: expiryDate)
    }
}

/// Describes editable changes to an existing medicine.
nonisolated struct MedicineUpdate {
    var name: String?
    var manufacturingDate: Date?
    var expiryDate: Date?
    var reminderLeadDays: Int?
}

/// All validation failures that can happen while saving a medicine.
nonisolated enum MedicineValidationError: Error, Equatable, LocalizedError {
    case missingName
    case expiryNotAfterManufacturing
    case duplicateMedicine

    /// Converts each validation case into text that can be shown in the UI.
    var errorDescription: String? {
        switch self {
        case .missingName:
            return "Enter a medicine name."
        case .expiryNotAfterManufacturing:
            return "Expiry date must be after the manufacturing date."
        case .duplicateMedicine:
            return "This medicine is already saved with the same dates."
        }
    }
}

/// Validates medicine form values before saving.
nonisolated enum MedicineValidator {
    /// Checks that name is non-empty and expiry is after manufacturing.
    static func validate(name: String, manufacturingDate: Date, expiryDate: Date) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MedicineValidationError.missingName
        }

        guard expiryDate > manufacturingDate else {
            throw MedicineValidationError.expiryNotAfterManufacturing
        }
    }
}
