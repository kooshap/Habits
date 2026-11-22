import Foundation
import SwiftUI

enum HabitWatchConstants {
    static let snapshotFilename = "watch-habits-snapshot.json"
    static let pendingMutationsFilename = "watch-pending-mutations.json"

    // WatchConnectivity dictionary keys
    static let contextSnapshotKey = "watchSnapshotData"
    static let messageTypeKey = "type"
    static let messageRequestSnapshot = "requestSnapshot"
    static let messageMutation = "toggleMutation"
    static let messageMutationDataKey = "mutationData"
    static let replySnapshotDataKey = "snapshotData"
}

struct WatchHabitRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var colorHex: String
    var targetPerWeek: Int
    var sortOrder: Int
    var completedDates: [String]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#2563EB",
        targetPerWeek: Int = 7,
        sortOrder: Int = 0,
        completedDates: [String] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.targetPerWeek = min(max(targetPerWeek, 1), 7)
        self.sortOrder = sortOrder
        self.completedDates = Array(Set(completedDates)).sorted()
    }

    var isDaily: Bool {
        targetPerWeek >= 7
    }

    var accentColor: Color {
        WatchHabitPalette.color(for: colorHex)
    }

    func isCompleted(on dateKey: String) -> Bool {
        completedDates.contains(dateKey)
    }

    mutating func setCompleted(_ isCompleted: Bool, on dateKey: String) {
        var set = Set(completedDates)
        if isCompleted {
            set.insert(dateKey)
        } else {
            set.remove(dateKey)
        }
        completedDates = set.sorted()
    }

    func pruned(
        keepingDaysBefore referenceDate: Date,
        days: Int = HabitWidgetConstants.retentionDaysBeforeToday,
        calendar: Calendar = HabitWidgetCalendar.monday
    ) -> WatchHabitRecord {
        let todayStart = calendar.startOfDay(for: referenceDate)
        guard let cutoffDate = calendar.date(byAdding: .day, value: -max(days, 7), to: todayStart) else {
            return self
        }
        let cutoffKey = HabitWidgetCalendar.dateKey(for: cutoffDate, calendar: calendar)
        let recent = completedDates.filter { $0 >= cutoffKey }
        return WatchHabitRecord(
            id: id,
            name: name,
            colorHex: colorHex,
            targetPerWeek: targetPerWeek,
            sortOrder: sortOrder,
            completedDates: recent
        )
    }

    func currentWeekCount(
        referenceDate: Date = Date(),
        calendar: Calendar = HabitWidgetCalendar.monday
    ) -> Int {
        let weekStart = HabitWidgetCalendar.startOfMondayWeek(for: referenceDate, calendar: calendar)
        let completedSet = Set(completedDates)
        var count = 0
        for offset in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: weekStart),
               completedSet.contains(HabitWidgetCalendar.dateKey(for: day, calendar: calendar)) {
                count += 1
            }
        }
        return count
    }

    func weeklyProgressBadge(
        referenceDate: Date = Date(),
        calendar: Calendar = HabitWidgetCalendar.monday
    ) -> (text: String, isGoalMet: Bool)? {
        guard !isDaily else { return nil }
        let done = currentWeekCount(referenceDate: referenceDate, calendar: calendar)
        let met = done >= targetPerWeek
        let label = met ? "\(done)/\(targetPerWeek) wk ✓" : "\(done)/\(targetPerWeek) wk"
        return (label, met)
    }

    var asWidgetRecord: WidgetHabitRecord {
        WidgetHabitRecord(
            id: id,
            targetPerWeek: targetPerWeek,
            completedDates: completedDates
        )
    }
}

struct HabitWatchSnapshot: Codable, Equatable, Sendable {
    var version: Int
    var updatedAt: Date
    var habits: [WatchHabitRecord]

    init(version: Int = 1, updatedAt: Date = Date(), habits: [WatchHabitRecord]) {
        self.version = version
        self.updatedAt = updatedAt
        self.habits = habits
    }

    func summary(
        referenceDate: Date = Date(),
        calendar: Calendar = HabitWidgetCalendar.monday
    ) -> HabitWidgetSummary {
        HabitWidgetSummary.compute(
            from: habits.map(\.asWidgetRecord),
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(from data: Data) -> HabitWatchSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HabitWatchSnapshot.self, from: data)
    }
}

/// Idempotent habit completion mutation sent from Apple Watch to iPhone.
struct WatchHabitToggleMutation: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var habitID: UUID
    var dateKey: String
    var isCompleted: Bool
    var timestamp: Date

    init(
        id: UUID = UUID(),
        habitID: UUID,
        dateKey: String,
        isCompleted: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.habitID = habitID
        self.dateKey = dateKey
        self.isCompleted = isCompleted
        self.timestamp = timestamp
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(from data: Data) -> WatchHabitToggleMutation? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchHabitToggleMutation.self, from: data)
    }
}

/// Pure-SwiftUI dark-OLED color resolver for watchOS (matches `HabitPalette` hexes without UIKit).
enum WatchHabitPalette {
    static func color(for hex: String) -> Color {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized == "#52525B" {
            // Matches iOS dark-mode Slate swatch in `HabitPalette.color(for:)`
            return Color(.sRGB, red: 0.58, green: 0.64, blue: 0.72, opacity: 1.0)
        }
        let cleaned = normalized.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        } else {
            r = 0.15; g = 0.39; b = 0.92
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

enum HabitWatchMerger {
    /// Applies any pending Watch mutations that occurred after `snapshot.updatedAt` so offline or in-flight
    /// wrist check-offs never flicker when an older snapshot arrives.
    static func merge(
        snapshot: HabitWatchSnapshot,
        pendingMutations: [WatchHabitToggleMutation]
    ) -> (mergedSnapshot: HabitWatchSnapshot, remainingPending: [WatchHabitToggleMutation]) {
        let sortedMutations = pendingMutations.sorted { $0.timestamp < $1.timestamp }
        // Keep only mutations newer than the incoming snapshot timestamp
        let unacknowledged = sortedMutations.filter { $0.timestamp > snapshot.updatedAt }
        guard !unacknowledged.isEmpty else {
            return (snapshot, [])
        }

        var habitsByID = Dictionary(uniqueKeysWithValues: snapshot.habits.map { ($0.id, $0) })
        let orderedIDs = snapshot.habits.map(\.id)

        for mutation in unacknowledged {
            guard var record = habitsByID[mutation.habitID] else { continue }
            record.setCompleted(mutation.isCompleted, on: mutation.dateKey)
            habitsByID[mutation.habitID] = record
        }

        let mergedHabits = orderedIDs.compactMap { habitsByID[$0] }
        let latestTimestamp = unacknowledged.map(\.timestamp).max() ?? snapshot.updatedAt
        let merged = HabitWatchSnapshot(
            version: snapshot.version,
            updatedAt: max(snapshot.updatedAt, latestTimestamp),
            habits: mergedHabits
        )
        return (merged, unacknowledged)
    }
}
