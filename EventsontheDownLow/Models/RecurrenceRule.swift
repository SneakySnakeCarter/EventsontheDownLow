import Foundation

/// Simplified RFC5545-style recurrence rule.
/// Supports DAILY / WEEKLY / MONTHLY / YEARLY frequencies with an interval,
/// an optional end (by count or by date), and (for weekly) specific weekdays.
enum RecurrenceFrequency: String, Codable, CaseIterable {
    case none
    case daily
    case weekly
    case monthly
    case yearly
}

struct RecurrenceRule: Codable, Equatable {
    var frequency: RecurrenceFrequency = .none
    var interval: Int = 1                 // every N days/weeks/months/years
    var byWeekday: [Int] = []             // 1=Sun ... 7=Sat, used for .weekly
    var count: Int? = nil                 // stop after N occurrences
    var until: Date? = nil                // stop after this date (inclusive)

    var isRecurring: Bool { frequency != .none }

    // MARK: - Serialization helpers for storing in a single SQLite TEXT column

    func toStorageString() -> String {
        guard isRecurring else { return "" }
        var parts: [String] = ["FREQ=\(frequency.rawValue.uppercased())", "INTERVAL=\(interval)"]
        if !byWeekday.isEmpty {
            parts.append("BYDAY=\(byWeekday.map(String.init).joined(separator: ","))")
        }
        if let count { parts.append("COUNT=\(count)") }
        if let until {
            parts.append("UNTIL=\(Int(until.timeIntervalSince1970))")
        }
        return parts.joined(separator: ";")
    }

    static func fromStorageString(_ string: String) -> RecurrenceRule {
        guard !string.isEmpty else { return RecurrenceRule() }
        var rule = RecurrenceRule()
        let pairs = string.split(separator: ";").map { $0.split(separator: "=") }
        for pair in pairs where pair.count == 2 {
            let key = pair[0]
            let value = String(pair[1])
            switch key {
            case "FREQ":
                rule.frequency = RecurrenceFrequency(rawValue: value.lowercased()) ?? .none
            case "INTERVAL":
                rule.interval = Int(value) ?? 1
            case "BYDAY":
                rule.byWeekday = value.split(separator: ",").compactMap { Int($0) }
            case "COUNT":
                rule.count = Int(value)
            case "UNTIL":
                if let epoch = Double(value) {
                    rule.until = Date(timeIntervalSince1970: epoch)
                }
            default:
                break
            }
        }
        return rule
    }
}
