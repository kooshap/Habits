import Foundation

enum HabitWidgetConstants {
    static let appGroupIdentifier = "group.com.koosha.habits"
    static let widgetKind = "com.koosha.habits.progressRing"
    static let snapshotFilename = "widget-habits-snapshot.json"
    /// Retain recent completion history needed across Monday–Sunday week boundaries while keeping snapshots tiny.
    static let retentionDaysBeforeToday = 14
}

enum HabitWidgetCalendar {
    static var monday: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = .autoupdatingCurrent
        cal.timeZone = .autoupdatingCurrent
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    static func dateKey(for date: Date, calendar: Calendar = monday) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func startOfMondayWeek(for date: Date, calendar: Calendar = monday) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart) // 1 = Sun, 2 = Mon ... 7 = Sat
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: dayStart) ?? dayStart
    }

    static func nextMidnight(after date: Date, calendar: Calendar = monday) -> Date {
        let todayStart = calendar.startOfDay(for: date)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) {
            return tomorrow
        }
        return date.addingTimeInterval(86_400)
    }
}

struct WidgetHabitRecord: Codable, Equatable, Sendable {
    var id: UUID
    var targetPerWeek: Int
    var completedDates: [String]

    init(id: UUID = UUID(), targetPerWeek: Int = 7, completedDates: [String] = []) {
        self.id = id
        self.targetPerWeek = min(max(targetPerWeek, 1), 7)
        self.completedDates = Array(Set(completedDates)).sorted()
    }

    func pruned(
        keepingDaysBefore referenceDate: Date,
        days: Int = HabitWidgetConstants.retentionDaysBeforeToday,
        calendar: Calendar = HabitWidgetCalendar.monday
    ) -> WidgetHabitRecord {
        let todayStart = calendar.startOfDay(for: referenceDate)
        guard let cutoffDate = calendar.date(byAdding: .day, value: -max(days, 7), to: todayStart) else {
            return self
        }
        let cutoffKey = HabitWidgetCalendar.dateKey(for: cutoffDate, calendar: calendar)
        let recent = completedDates.filter { $0 >= cutoffKey }
        return WidgetHabitRecord(id: id, targetPerWeek: targetPerWeek, completedDates: recent)
    }
}

struct HabitWidgetSnapshot: Codable, Equatable, Sendable {
    var version: Int
    var updatedAt: Date
    var habits: [WidgetHabitRecord]

    init(version: Int = 1, updatedAt: Date = Date(), habits: [WidgetHabitRecord]) {
        self.version = version
        self.updatedAt = updatedAt
        self.habits = habits
    }
}

struct HabitWidgetScheduledEntry: Equatable, Sendable {
    let date: Date
    let summary: HabitWidgetSummary
}

struct HabitWidgetTimelineSchedule: Equatable, Sendable {
    let entries: [HabitWidgetScheduledEntry]
    let reloadAfter: Date
}

struct HabitWidgetSummary: Equatable, Sendable {
    let completed: Int
    let total: Int

    init(completed: Int, total: Int) {
        let safeTotal = max(total, 0)
        let safeCompleted = min(max(completed, 0), safeTotal)
        self.completed = safeCompleted
        self.total = safeTotal
    }

    static let empty = HabitWidgetSummary(completed: 0, total: 0)
    static let preview = HabitWidgetSummary(completed: 4, total: 7)

    var hasHabits: Bool {
        total > 0
    }

    var isAllDone: Bool {
        total > 0 && completed >= total
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    var accessibilityValueText: String {
        guard hasHabits else { return "No habits configured" }
        if isAllDone {
            return "All \(total) completed today"
        }
        return "\(completed) of \(total) completed today"
    }

    /// Computes today's ring progress:
    /// - Daily habits (`targetPerWeek == 7`) are always part of today's count.
    /// - Weekly habits (`1...6`) are included when logged today or while their Monday–Sunday weekly target
    ///   has not yet been met on prior days this week; once already satisfied earlier in the week, they do
    ///   not block closing today's ring.
    static func compute(
        from habits: [WidgetHabitRecord],
        referenceDate: Date = Date(),
        calendar: Calendar = HabitWidgetCalendar.monday
    ) -> HabitWidgetSummary {
        guard !habits.isEmpty else { return .empty }

        let today = calendar.startOfDay(for: referenceDate)
        let todayKey = HabitWidgetCalendar.dateKey(for: today, calendar: calendar)
        let weekStart = HabitWidgetCalendar.startOfMondayWeek(for: today, calendar: calendar)
        let weekday = calendar.component(.weekday, from: today)
        let dayIndexMon = (weekday + 5) % 7 // 0 = Mon ... 6 = Sun

        var priorWeekKeys: [String] = []
        if dayIndexMon > 0 {
            priorWeekKeys.reserveCapacity(dayIndexMon)
            for offset in 0..<dayIndexMon {
                if let d = calendar.date(byAdding: .day, value: offset, to: weekStart) {
                    priorWeekKeys.append(HabitWidgetCalendar.dateKey(for: d, calendar: calendar))
                }
            }
        }

        var completedCount = 0
        var activeTotal = 0

        for habit in habits {
            let target = min(max(habit.targetPerWeek, 1), 7)
            let completedSet = Set(habit.completedDates)
            let doneToday = completedSet.contains(todayKey)

            if target >= 7 {
                activeTotal += 1
                if doneToday {
                    completedCount += 1
                }
            } else {
                let doneEarlierThisWeek = priorWeekKeys.reduce(0) { count, key in
                    completedSet.contains(key) ? count + 1 : count
                }
                if doneToday {
                    activeTotal += 1
                    completedCount += 1
                } else if doneEarlierThisWeek < target {
                    activeTotal += 1
                }
            }
        }

        // If every habit is a flexible weekly habit whose weekly goal was already banked earlier this week,
        // treat the ring as fully satisfied rather than showing 0/0.
        if activeTotal == 0 {
            return HabitWidgetSummary(completed: habits.count, total: habits.count)
        }

        return HabitWidgetSummary(completed: completedCount, total: activeTotal)
    }

    /// Generates an immediate timeline entry for `now` plus an automatic midnight rollover entry so the
    /// Lock Screen ring resets at 00:00 without requiring the user to open the app.
    static func timelineSchedule(
        from snapshot: HabitWidgetSnapshot?,
        now: Date = Date(),
        calendar: Calendar = HabitWidgetCalendar.monday
    ) -> HabitWidgetTimelineSchedule {
        let records = snapshot?.habits ?? []
        let todaySummary = compute(from: records, referenceDate: now, calendar: calendar)
        let midnight = HabitWidgetCalendar.nextMidnight(after: now, calendar: calendar)
        let tomorrowSummary = compute(from: records, referenceDate: midnight, calendar: calendar)

        return HabitWidgetTimelineSchedule(
            entries: [
                HabitWidgetScheduledEntry(date: now, summary: todaySummary),
                HabitWidgetScheduledEntry(date: midnight, summary: tomorrowSummary)
            ],
            reloadAfter: midnight
        )
    }
}

enum HabitWidgetSnapshotStore {
    static func defaultSnapshotURL(
        appGroupIdentifier: String = HabitWidgetConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(HabitWidgetConstants.snapshotFilename, isDirectory: false)
    }

    @discardableResult
    static func save(_ snapshot: HabitWidgetSnapshot, to fileURL: URL? = defaultSnapshotURL()) throws -> Bool {
        guard let fileURL else { return false }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        return true
    }

    static func load(from fileURL: URL? = defaultSnapshotURL()) -> HabitWidgetSnapshot? {
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HabitWidgetSnapshot.self, from: data)
    }
}
