import Foundation

/// Extracts manufacturing and expiry dates from OCR text.
///
/// OCR means text recognized from the camera image. This parser intentionally stays
/// simple and testable: it takes a normal `String` and returns Swift `Date` values.
nonisolated struct MedicineDateParser {
    /// Regular expression for dates like `05/2026`, `05-2026`, `01/05/2026`, or `01-05-26`.
    ///
    /// The day/month/year alternative must come first: regex alternation is ordered,
    /// so with month/year first, `01/05/2026` would match as just `01/05` and the full
    /// date could never be recognized.
    private static let numericPattern = #"\b(\d{1,2})[./\-](\d{1,2})[./\-](\d{2}|\d{4})\b|\b(\d{1,2})[./\-](\d{2}|\d{4})\b"#

    /// Regular expression for month-name dates like `DEC-2026`, `NOV.2026`, or `JAN 26`.
    private static let monthNamePattern = #"\b(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|SEPT|OCT|NOV|DEC)[\s./\-]+(\d{2}|\d{4})\b"#

    private static let monthNumbersByName = [
        "JAN": 1,
        "FEB": 2,
        "MAR": 3,
        "APR": 4,
        "MAY": 5,
        "JUN": 6,
        "JUL": 7,
        "AUG": 8,
        "SEP": 9,
        "SEPT": 9,
        "OCT": 10,
        "NOV": 11,
        "DEC": 12
    ]

    /// Replaces OCR-common misreads (letter O → digit 0) before pattern matching.
    ///
    /// Only an O next to a digit is replaced (for example `2O26` → `2026`). Replacing
    /// every O would corrupt month names such as `NOV` and `OCT` before they can match.
    /// The loop handles runs like `2OO6`, where each pass exposes the next misread O.
    private static func normalizedForOCR(_ text: String) -> String {
        guard let regex = ocrMisreadZeroRegex else { return text }

        var normalized = text
        while true {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            let replaced = regex.stringByReplacingMatches(in: normalized, range: range, withTemplate: "0")
            if replaced == normalized {
                return normalized
            }
            normalized = replaced
        }
    }

    private static let ocrMisreadZeroRegex = try? NSRegularExpression(pattern: #"(?<=\d)O|O(?=\d)"#)

    /// Finds every date-looking string inside a block of OCR text.
    ///
    /// This is useful for the scanner UI because it lets the app show only date values
    /// and hide unrelated words like medicine names, labels, and dosage text.
    static func extractDateStrings(from text: String) -> [String] {
        let normalized = normalizedForOCR(text)
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)

        var seen: Set<String> = []
        var dateStrings: [String] = []

        for match in numericMatches(in: normalized, range: range) + monthNameMatches(in: normalized, range: range) {
            guard let range = Range(match.range, in: normalized) else { continue }
            let value = String(normalized[range])
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            dateStrings.append(value)
        }

        return dateStrings
    }

    /// Finds every recognizable date inside a block of OCR text.
    ///
    /// Returns dates sorted from earliest to latest. The optional `calendar` parameter
    /// makes the function easier to test because tests can pass a specific calendar.
    static func extractDates(from text: String, calendar: Calendar = .current) -> [Date] {
        let normalized = normalizedForOCR(text)
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let numericDates = numericMatches(in: normalized, range: range).compactMap { match in
            let values = (1..<match.numberOfRanges).compactMap { index -> Int? in
                guard let range = Range(match.range(at: index), in: normalized) else { return nil }
                return Int(normalized[range])
            }

            if values.count == 2 {
                return makeDate(day: 1, month: values[0], year: values[1], calendar: calendar)
            }

            if values.count == 3 {
                return makeDate(day: values[0], month: values[1], year: values[2], calendar: calendar)
            }

            return nil
        }

        let monthNameDates = monthNameMatches(in: normalized, range: range).compactMap { match in
            dateFromMonthNameMatch(match, in: normalized, calendar: calendar)
        }

        return (numericDates + monthNameDates).sorted()
    }

    /// Parses the first recognizable date from one selected OCR value.
    ///
    /// The single-date scanners use this after the user taps the correct detected date.
    static func firstDate(from text: String, calendar: Calendar = .current) -> Date? {
        extractDates(from: text, calendar: calendar).first
    }

    /// Uses the earliest parsed date as manufacturing date and the latest as expiry date.
    ///
    /// The return type is optional: `nil` means the parser could not confidently find
    /// two valid dates in the recognized text.
    static func inferredManufacturingAndExpiryDates(from text: String) -> (manufacturing: Date, expiry: Date)? {
        let dates = extractDates(from: text)
        guard let first = dates.first, let last = dates.last, first < last else {
            return nil
        }

        return (first, last)
    }

    /// Builds a real Swift `Date` from day/month/year numbers found by the regex.
    ///
    /// This function returns `nil` if the date pieces are clearly invalid. Two-digit
    /// years are treated as 2000-based years, so `26` becomes `2026`.
    private static func makeDate(day: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }

        var components = DateComponents()
        components.calendar = calendar
        components.day = day
        components.month = month
        components.year = year < 100 ? 2000 + year : year
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components)
    }

    private static let numericRegex = try? NSRegularExpression(pattern: numericPattern, options: [])
    private static let monthNameRegex = try? NSRegularExpression(pattern: monthNamePattern, options: [.caseInsensitive])

    private static func numericMatches(in text: String, range: NSRange) -> [NSTextCheckingResult] {
        numericRegex?.matches(in: text, range: range) ?? []
    }

    private static func monthNameMatches(in text: String, range: NSRange) -> [NSTextCheckingResult] {
        monthNameRegex?.matches(in: text, range: range) ?? []
    }

    /// Converts one month-name regex match into a `Date`.
    private static func dateFromMonthNameMatch(
        _ match: NSTextCheckingResult,
        in text: String,
        calendar: Calendar
    ) -> Date? {
        guard let monthRange = Range(match.range(at: 1), in: text),
              let yearRange = Range(match.range(at: 2), in: text),
              let month = monthNumbersByName[String(text[monthRange]).uppercased()],
              let year = Int(text[yearRange]) else {
            return nil
        }

        return makeDate(day: 1, month: month, year: year, calendar: calendar)
    }
}
