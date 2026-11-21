import Foundation
import SwiftData
import SwiftUI

@Model
final class Habit {
    var id: UUID
    var name: String
    var colorHex: String
    /// `7` = Daily; `1...6` = flexible N times per week (Monday–Sunday).
    var targetPerWeek: Int
    var sortOrder: Int
    var createdAt: Date
    /// Normalized `"YYYY-MM-DD"` local calendar date strings.
    var completedDates: [String]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = HabitPalette.defaultHex,
        targetPerWeek: Int = 7,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        completedDates: [String] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.targetPerWeek = min(max(targetPerWeek, 1), 7)
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.completedDates = Array(Set(completedDates)).sorted()
    }

    var isDaily: Bool {
        targetPerWeek >= 7
    }

    var accentColor: Color {
        HabitPalette.color(for: colorHex)
    }

    var scheduleShortLabel: String {
        isDaily ? "Daily" : "\(targetPerWeek)×/wk"
    }

    func isCompleted(on dateKey: String) -> Bool {
        completedDates.contains(dateKey)
    }

    @discardableResult
    func toggle(dateKey: String) -> Bool {
        var set = Set(completedDates)
        let nowCompleted: Bool
        if set.contains(dateKey) {
            set.remove(dateKey)
            nowCompleted = false
        } else {
            set.insert(dateKey)
            nowCompleted = true
        }
        completedDates = set.sorted()
        return nowCompleted
    }
}

// MARK: - Curated 8 Non-Green Color Swatches

struct HabitSwatch: Identifiable, Equatable {
    let name: String
    let hex: String
    var id: String { hex }
}

enum HabitPalette {
    static let swatches: [HabitSwatch] = [
        HabitSwatch(name: "Cobalt",     hex: "#2563EB"),
        HabitSwatch(name: "Indigo",     hex: "#4F46E5"),
        HabitSwatch(name: "Violet",     hex: "#7C3AED"),
        HabitSwatch(name: "Rose",       hex: "#DB2777"),
        HabitSwatch(name: "Coral",      hex: "#E54D37"),
        HabitSwatch(name: "Amber",      hex: "#D9822B"),
        HabitSwatch(name: "Ocean Cyan", hex: "#0891B2"),
        HabitSwatch(name: "Slate",      hex: "#52525B")
    ]

    static var defaultHex: String { swatches[0].hex }

    static func color(for hex: String) -> Color {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized == "#52525B" {
            return Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1.0)
                    : UIColor(red: 0.32, green: 0.32, blue: 0.36, alpha: 1.0)
            })
        }
        return Color(hexString: normalized)
    }
}

extension Color {
    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

// MARK: - Monday-First Calendar & Streak Engine

struct RollingDay: Identifiable, Equatable {
    let date: Date
    let key: String
    let dayNumber: Int
    let weekdayLetter: String
    let isToday: Bool
    var id: String { key }
}

struct MonthSummary: Identifiable, Equatable {
    let year: Int
    let month: Int
    let shortTitle: String
    let statsLabel: String
    let leadingEmptyCount: Int
    let daysInMonth: Int
    let isCurrentMonth: Bool
    let todayDay: Int?
    let completedDays: Set<Int>

    var id: String { "\(year)-\(month)" }
}

enum HabitCalendar {
    static var monday: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = .autoupdatingCurrent
        cal.timeZone = .autoupdatingCurrent
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    static let mondayWeekdayHeaders = ["M", "T", "W", "T", "F", "S", "S"]

    static func dateKey(for date: Date, calendar: Calendar = monday) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func startOfDay(_ date: Date, calendar: Calendar = monday) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Start of the Monday–Sunday week containing `date`.
    static func startOfMondayWeek(for date: Date, calendar: Calendar = monday) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart) // 1 = Sun, 2 = Mon ... 7 = Sat
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: dayStart) ?? dayStart
    }

    /// Rolling last `count` days ending with `referenceDate` (Today).
    static func rollingDays(
        count: Int = 7,
        endingOn referenceDate: Date = Date(),
        calendar: Calendar = monday
    ) -> [RollingDay] {
        let cal = calendar
        let today = cal.startOfDay(for: referenceDate)
        let lettersByWeekday = [1: "S", 2: "M", 3: "T", 4: "W", 5: "T", 6: "F", 7: "S"]

        return (0..<max(count, 0)).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayNum = cal.component(.day, from: date)
            let weekday = cal.component(.weekday, from: date)
            return RollingDay(
                date: date,
                key: dateKey(for: date, calendar: cal),
                dayNumber: dayNum,
                weekdayLetter: lettersByWeekday[weekday] ?? "",
                isToday: offset == 0
            )
        }
    }

    static func headerMonthYear(for date: Date = Date(), calendar: Calendar = monday) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    static func currentMonthShortName(for date: Date = Date(), calendar: Calendar = monday) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    /// Progress in the current Monday–Sunday week.
    static func currentWeekCount(
        completedSet: Set<String>,
        referenceDate: Date = Date(),
        calendar: Calendar = monday
    ) -> Int {
        let cal = calendar
        let weekStart = startOfMondayWeek(for: referenceDate, calendar: cal)
        var count = 0
        for offset in 0..<7 {
            if let d = cal.date(byAdding: .day, value: offset, to: weekStart),
               completedSet.contains(dateKey(for: d, calendar: cal)) {
                count += 1
            }
        }
        return count
    }

    /// Current month `done` vs `elapsedDays` (1...todayDay).
    static func currentMonthProgress(
        completedSet: Set<String>,
        referenceDate: Date = Date(),
        calendar: Calendar = monday
    ) -> (done: Int, elapsed: Int) {
        let cal = calendar
        let comps = cal.dateComponents([.year, .month, .day], from: referenceDate)
        guard let y = comps.year, let m = comps.month, let todayDay = comps.day else {
            return (0, 1)
        }
        var done = 0
        for d in 1...todayDay {
            let key = String(format: "%04d-%02d-%02d", y, m, d)
            if completedSet.contains(key) {
                done += 1
            }
        }
        return (done, todayDay)
    }

    /// Streak label for the quiet Calendar stats bar.
    /// - Daily habits: consecutive completed days (includes today if done; otherwise counts from yesterday).
    /// - N×/wk habits: consecutive Monday–Sunday weeks meeting `targetPerWeek` (includes current week if already met, plus consecutive prior weeks).
    static func streakText(
        for habit: Habit,
        completedSet: Set<String>,
        referenceDate: Date = Date(),
        calendar: Calendar = monday
    ) -> String {
        let cal = calendar
        let today = cal.startOfDay(for: referenceDate)

        if habit.isDaily {
            var streak = 0
            let todayKey = dateKey(for: today, calendar: cal)
            var cursor: Date
            if completedSet.contains(todayKey) {
                cursor = today
            } else if let yesterday = cal.date(byAdding: .day, value: -1, to: today) {
                cursor = yesterday
            } else {
                return "0 days"
            }

            while completedSet.contains(dateKey(for: cursor, calendar: cal)) {
                streak += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            }
            return streak == 1 ? "1 day" : "\(streak) days"
        } else {
            let target = habit.targetPerWeek
            let currentWeekStart = startOfMondayWeek(for: today, calendar: cal)

            func completionsInWeek(starting weekStart: Date) -> Int {
                var c = 0
                for i in 0..<7 {
                    if let d = cal.date(byAdding: .day, value: i, to: weekStart),
                       completedSet.contains(dateKey(for: d, calendar: cal)) {
                        c += 1
                    }
                }
                return c
            }

            var weekStreak = 0
            if completionsInWeek(starting: currentWeekStart) >= target {
                weekStreak += 1
            }
            // Check how many days remain in the current week: if current week already failed
            // (even hitting all remaining days can't reach target), streak breaks unless current week met target.
            let weekday = cal.component(.weekday, from: today)
            let dayIndexMon = (weekday + 5) % 7 // 0 = Mon ... 6 = Sun
            let remainingDaysIncludingToday = 7 - dayIndexMon
            let doneBeforeTodayThisWeek: Int = {
                var c = 0
                if dayIndexMon > 0 {
                    for i in 0..<dayIndexMon {
                        if let d = cal.date(byAdding: .day, value: i, to: currentWeekStart),
                           completedSet.contains(dateKey(for: d, calendar: cal)) {
                            c += 1
                        }
                    }
                }
                return c
            }()
            let canStillMeetCurrentWeek = (doneBeforeTodayThisWeek + remainingDaysIncludingToday) >= target

            if weekStreak == 0 && !canStillMeetCurrentWeek {
                return "0 weeks"
            }

            guard var cursorWeek = cal.date(byAdding: .day, value: -7, to: currentWeekStart) else {
                return weekStreak == 1 ? "1 week" : "\(weekStreak) weeks"
            }

            // Cap backward scan to 520 weeks (~10 years) for safety
            for _ in 0..<520 {
                if completionsInWeek(starting: cursorWeek) >= target {
                    weekStreak += 1
                    guard let prevWeek = cal.date(byAdding: .day, value: -7, to: cursorWeek) else { break }
                    cursorWeek = prevWeek
                } else {
                    break
                }
            }
            return weekStreak == 1 ? "1 week" : "\(weekStreak) weeks"
        }
    }

    /// Generates months chronologically from oldest to the current month (at least 12 months, or further back if older history exists).
    static func monthsHistory(
        for habit: Habit,
        completedSet: Set<String>,
        referenceDate: Date = Date(),
        calendar: Calendar = monday
    ) -> [MonthSummary] {
        let cal = calendar
        let nowComps = cal.dateComponents([.year, .month, .day], from: referenceDate)
        guard let curYear = nowComps.year, let curMonth = nowComps.month, let curDay = nowComps.day else {
            return []
        }
        guard let currentMonthFirst = cal.date(from: DateComponents(year: curYear, month: curMonth, day: 1)) else {
            return []
        }

        // Determine how many months back to render (minimum 12 so at least 2 screens of 6-month grids scroll smoothly)
        var monthsCount = 12
        if let earliestKey = habit.completedDates.min(),
           earliestKey.count >= 7,
           let ey = Int(earliestKey.prefix(4)),
           let em = Int(earliestKey.dropFirst(5).prefix(2)) {
            let diff = (curYear - ey) * 12 + (curMonth - em) + 1
            if diff > monthsCount {
                // Round up to an even number so the 2-column grid stays symmetrical
                // and the most recent month always lands in the bottom-right slot.
                monthsCount = diff % 2 == 0 ? diff : diff + 1
            }
        }

        let shortFormatter = DateFormatter()
        shortFormatter.calendar = cal
        shortFormatter.locale = cal.locale
        shortFormatter.timeZone = cal.timeZone

        return (0..<monthsCount).reversed().compactMap { offset in
            guard let monthStart = cal.date(byAdding: .month, value: -offset, to: currentMonthFirst) else { return nil }
            let y = cal.component(.year, from: monthStart)
            let m = cal.component(.month, from: monthStart)
            let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            let firstWeekday = cal.component(.weekday, from: monthStart) // 1 = Sun, 2 = Mon ...
            let leadingEmpty = (firstWeekday + 5) % 7 // Monday = 0 ... Sunday = 6
            let isCurrent = (offset == 0)
            let maxCountedDay = isCurrent ? curDay : daysInMonth

            var doneDays = Set<Int>()
            for d in 1...maxCountedDay {
                let key = String(format: "%04d-%02d-%02d", y, m, d)
                if completedSet.contains(key) {
                    doneDays.insert(d)
                }
            }

            shortFormatter.dateFormat = (y == curYear) ? "MMM" : "MMM ''yy"
            let title = shortFormatter.string(from: monthStart)

            return MonthSummary(
                year: y,
                month: m,
                shortTitle: title,
                statsLabel: "\(doneDays.count)/\(maxCountedDay)",
                leadingEmptyCount: leadingEmpty,
                daysInMonth: daysInMonth,
                isCurrentMonth: isCurrent,
                todayDay: isCurrent ? curDay : nil,
                completedDays: doneDays
            )
        }
    }
}
