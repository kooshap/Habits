import Foundation
import SwiftData
@testable import Habits

enum TestCalendar {
    /// Deterministic Monday-first Gregorian calendar pinned to UTC and `en_US_POSIX`.
    static var mondayUTC: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.calendar = mondayUTC
        comps.timeZone = mondayUTC.timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return mondayUTC.date(from: comps)!
    }
}

@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Habit.self, configurations: config)
}
