import Foundation
import Testing
@testable import Habits

@Suite("HabitCalendar & Streak Engine")
struct HabitCalendarTests {
    private let cal = TestCalendar.mondayUTC

    // MARK: - Date Keys & Monday-First Weeks

    @Test("dateKey zero-pads single-digit month and day")
    func dateKeyFormatting() {
        let d = TestCalendar.date(2026, 1, 5)
        #expect(HabitCalendar.dateKey(for: d, calendar: cal) == "2026-01-05")
    }

    @Test("startOfMondayWeek maps every day Mon–Sun back to Monday of that week", arguments: [
        16, // Monday
        17, // Tuesday
        18, // Wednesday
        19, // Thursday
        20, // Friday
        21, // Saturday
        22  // Sunday
    ])
    func startOfMondayWeekAcrossWeek(day: Int) {
        let input = TestCalendar.date(2026, 11, day, hour: 18, minute: 45)
        let weekStart = HabitCalendar.startOfMondayWeek(for: input, calendar: cal)
        #expect(HabitCalendar.dateKey(for: weekStart, calendar: cal) == "2026-11-16")
        #expect(cal.component(.hour, from: weekStart) == 0)
    }

    @Test("startOfMondayWeek crosses year boundary when Sunday falls in early January")
    func startOfMondayWeekCrossesYearBoundary() {
        // 2026-01-04 is Sunday; its Monday is 2025-12-29
        let sundayJan4 = TestCalendar.date(2026, 1, 4)
        let weekStart = HabitCalendar.startOfMondayWeek(for: sundayJan4, calendar: cal)
        #expect(HabitCalendar.dateKey(for: weekStart, calendar: cal) == "2025-12-29")
    }

    // MARK: - Rolling 7-Day Strip & Header Labels

    @Test("rollingDays returns 7 chronological days ending on referenceDate with accurate weekday letters")
    func rollingDaysSevenDayWindow() {
        // Saturday 2026-11-21 -> rolling 7 days starts Sunday 2026-11-15 ("S") through Saturday 2026-11-21 ("S")
        let ref = TestCalendar.date(2026, 11, 21)
        let days = HabitCalendar.rollingDays(count: 7, endingOn: ref, calendar: cal)

        #expect(days.count == 7)
        #expect(days.map(\.key) == [
            "2026-11-15",
            "2026-11-16",
            "2026-11-17",
            "2026-11-18",
            "2026-11-19",
            "2026-11-20",
            "2026-11-21"
        ])
        #expect(days.map(\.weekdayLetter) == ["S", "M", "T", "W", "T", "F", "S"])
        #expect(days.map(\.dayNumber) == [15, 16, 17, 18, 19, 20, 21])
        #expect(days.dropLast().allSatisfy { !$0.isToday })
        #expect(days.last?.isToday == true)
    }

    @Test("rollingDays crosses leap-year February boundary and handles zero/negative count safely")
    func rollingDaysLeapYearAndZeroCount() {
        // Sunday 2024-03-03 -> 7-day window includes 2024-02-29
        let ref = TestCalendar.date(2024, 3, 3)
        let days = HabitCalendar.rollingDays(count: 7, endingOn: ref, calendar: cal)
        #expect(days.map(\.dayNumber) == [26, 27, 28, 29, 1, 2, 3])
        #expect(days.map(\.weekdayLetter) == ["M", "T", "W", "T", "F", "S", "S"])

        #expect(HabitCalendar.rollingDays(count: 0, endingOn: ref, calendar: cal).isEmpty)
        #expect(HabitCalendar.rollingDays(count: -3, endingOn: ref, calendar: cal).isEmpty)
    }

    @Test("Header month/year and short month formatters respect injected calendar")
    func headerFormatters() {
        let ref = TestCalendar.date(2026, 11, 21)
        #expect(HabitCalendar.headerMonthYear(for: ref, calendar: cal) == "NOV 2026")
        #expect(HabitCalendar.currentMonthShortName(for: ref, calendar: cal) == "Nov")
    }

    // MARK: - Current Week & Current Month Progress

    @Test("currentWeekCount counts only completions within the Monday–Sunday week of referenceDate")
    func currentWeekCountIsolation() {
        // Week of Saturday 2026-11-21 is Mon 2026-11-16 ... Sun 2026-11-22
        let ref = TestCalendar.date(2026, 11, 21)
        let completed: Set<String> = [
            "2026-11-15", // Previous Sunday -> excluded
            "2026-11-16", // Monday -> included
            "2026-11-19", // Thursday -> included
            "2026-11-22", // Sunday of same week -> included
            "2026-11-23"  // Next Monday -> excluded
        ]
        #expect(HabitCalendar.currentWeekCount(completedSet: completed, referenceDate: ref, calendar: cal) == 3)
    }

    @Test("currentMonthProgress counts 1...todayDay and ignores other months or future days")
    func currentMonthProgressBounds() {
        let ref = TestCalendar.date(2026, 11, 10)
        let completed: Set<String> = [
            "2026-10-31", // Previous month -> excluded
            "2026-11-01", // Included
            "2026-11-05", // Included
            "2026-11-10", // Today -> included
            "2026-11-11"  // Future day in current month -> excluded
        ]
        let progress = HabitCalendar.currentMonthProgress(completedSet: completed, referenceDate: ref, calendar: cal)
        #expect(progress.done == 3)
        #expect(progress.elapsed == 10)
    }

    // MARK: - Daily Habit Streaks

    @Test("Daily streak handles 0 days, 1 day singular, multi-day, and grace period when today is unchecked")
    func dailyStreakCoreCases() {
        let habit = Habit(name: "Read", targetPerWeek: 7)
        let ref = TestCalendar.date(2026, 11, 21)

        // Empty
        #expect(HabitCalendar.streakText(for: habit, completedSet: [], referenceDate: ref, calendar: cal) == "0 days")

        // Today only -> singular "1 day"
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: ["2026-11-21"], referenceDate: ref, calendar: cal) == "1 day"
        )

        // Consecutive ending today
        let fourDays: Set<String> = ["2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21"]
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: fourDays, referenceDate: ref, calendar: cal) == "4 days"
        )

        // Grace period: today unchecked, yesterday + prior 2 days checked -> "3 days"
        let graceThreeDays: Set<String> = ["2026-11-16", "2026-11-18", "2026-11-19", "2026-11-20"]
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: graceThreeDays, referenceDate: ref, calendar: cal) == "3 days"
        )

        // Broken: neither today nor yesterday checked (even with older streak) -> "0 days"
        let broken: Set<String> = ["2026-11-17", "2026-11-18", "2026-11-19"]
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: broken, referenceDate: ref, calendar: cal) == "0 days"
        )
    }

    @Test("Daily streak spans across leap day and New Year boundary")
    func dailyStreakCalendarBoundaries() {
        let habit = Habit(name: "Walk", targetPerWeek: 7)

        // Leap year: Feb 28, Feb 29, Mar 1 2024
        let mar1 = TestCalendar.date(2024, 3, 1)
        let leapSet: Set<String> = ["2024-02-28", "2024-02-29", "2024-03-01"]
        #expect(HabitCalendar.streakText(for: habit, completedSet: leapSet, referenceDate: mar1, calendar: cal) == "3 days")

        // New Year: Dec 30, Dec 31 2025, Jan 1 2026
        let jan1 = TestCalendar.date(2026, 1, 1)
        let newYearSet: Set<String> = ["2025-12-30", "2025-12-31", "2026-01-01"]
        #expect(HabitCalendar.streakText(for: habit, completedSet: newYearSet, referenceDate: jan1, calendar: cal) == "3 days")
    }

    // MARK: - Weekly Flexible Streaks (1...6×/wk)

    @Test("Weekly streak counts current week when goal is met and adds consecutive qualifying prior weeks")
    func weeklyStreakGoalMetAndPriorWeeks() {
        let habit = Habit(name: "Lift", targetPerWeek: 3)
        let refSaturday = TestCalendar.date(2026, 11, 21) // Week start: 2026-11-16

        // Empty -> "0 weeks"
        #expect(HabitCalendar.streakText(for: habit, completedSet: [], referenceDate: refSaturday, calendar: cal) == "0 weeks")

        // Current week alone met 3× -> singular "1 week"
        let currentOnly: Set<String> = ["2026-11-16", "2026-11-18", "2026-11-20"]
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: currentOnly, referenceDate: refSaturday, calendar: cal) == "1 week"
        )

        // Current week (Nov 16) + 2 prior weeks (Nov 9, Nov 2) met 3×, week before (Oct 26) had only 2× -> "3 weeks"
        let threeWeeks: Set<String> = [
            "2026-10-26", "2026-10-28",               // 2/3 -> stops here
            "2026-11-02", "2026-11-04", "2026-11-06", // 3/3
            "2026-11-09", "2026-11-11", "2026-11-14", // 3/3
            "2026-11-16", "2026-11-18", "2026-11-21"  // 3/3
        ]
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: threeWeeks, referenceDate: refSaturday, calendar: cal) == "3 weeks"
        )
    }

    @Test("Weekly streak preserves prior streak while current week is still mathematically reachable, and resets once impossible")
    func weeklyStreakReachableVsImpossibleCurrentWeek() {
        let habit = Habit(name: "Run", targetPerWeek: 4)
        let priorTwoWeeks: Set<String> = [
            "2026-11-02", "2026-11-03", "2026-11-05", "2026-11-07", // Week 1: 4/4
            "2026-11-09", "2026-11-10", "2026-11-12", "2026-11-15"  // Week 2: 4/4
        ]

        // Case 1: Today is Monday 2026-11-16 (0 done so far, 7 days remaining including today -> 7 >= 4 reachable)
        let monday = TestCalendar.date(2026, 11, 16)
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: priorTwoWeeks, referenceDate: monday, calendar: cal) == "2 weeks"
        )

        // Case 2: Today is Friday 2026-11-20 (3 days left: Fri, Sat, Sun). 1 completion earlier this week -> 1 + 3 = 4 >= 4 reachable
        let friday = TestCalendar.date(2026, 11, 20)
        let reachableOnFriday = priorTwoWeeks.union(["2026-11-17"])
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: reachableOnFriday, referenceDate: friday, calendar: cal) == "2 weeks"
        )

        // Case 3: Today is Friday 2026-11-20 (3 days left: Fri, Sat, Sun). 0 completions earlier this week -> 0 + 3 = 3 < 4 impossible!
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: priorTwoWeeks, referenceDate: friday, calendar: cal) == "0 weeks"
        )

        // Case 4: Sunday boundary (dayIndexMon == 6, 1 day remaining including today):
        // With 3 done Mon–Sat (3 + 1 >= 4), prior 2-week streak holds before checking Sunday...
        let sunday = TestCalendar.date(2026, 11, 22)
        let sundayPending = priorTwoWeeks.union(["2026-11-16", "2026-11-18", "2026-11-20"])
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: sundayPending, referenceDate: sunday, calendar: cal) == "2 weeks"
        )
        // ...and checking off Sunday completes the 4th rep, advancing streak to "3 weeks"!
        let sundayCompleted = sundayPending.union(["2026-11-22"])
        #expect(
            HabitCalendar.streakText(for: habit, completedSet: sundayCompleted, referenceDate: sunday, calendar: cal) == "3 weeks"
        )
    }

    // MARK: - Month History Grid

    @Test("monthsHistory renders minimum 12 months and rounds older history up to an even month count")
    func monthsHistoryCountAndSymmetry() {
        let ref = TestCalendar.date(2026, 11, 21)

        // Empty history -> minimum 12 months ending in Nov 2026
        let recentHabit = Habit(name: "Stretch")
        let defaultMonths = HabitCalendar.monthsHistory(
            for: recentHabit,
            completedSet: [],
            referenceDate: ref,
            calendar: cal
        )
        #expect(defaultMonths.count == 12)
        #expect(defaultMonths.first?.year == 2025 && defaultMonths.first?.month == 12)
        #expect(defaultMonths.last?.year == 2026 && defaultMonths.last?.month == 11)
        #expect(defaultMonths.last?.isCurrentMonth == true)
        #expect(defaultMonths.last?.todayDay == 21)
        #expect(defaultMonths.dropLast().allSatisfy { !$0.isCurrentMonth && $0.todayDay == nil })

        // Earliest completion in Sep 2025 -> 15 months span (Sep 2025 ... Nov 2026), rounded up to 16 (even)
        let olderHabit = Habit(name: "Swim", completedDates: ["2025-09-14"])
        let expandedMonths = HabitCalendar.monthsHistory(
            for: olderHabit,
            completedSet: Set(olderHabit.completedDates),
            referenceDate: ref,
            calendar: cal
        )
        #expect(expandedMonths.count == 16)
        #expect(expandedMonths.count % 2 == 0)
        #expect(expandedMonths.first?.year == 2025 && expandedMonths.first?.month == 8)
        #expect(expandedMonths.last?.year == 2026 && expandedMonths.last?.month == 11)
    }

    @Test("monthsHistory computes Monday-first leadingEmptyCount, leap daysInMonth, titles, and statsLabel")
    func monthsHistoryTileMetadata() {
        let ref = TestCalendar.date(2026, 11, 21)
        let dates = [
            "2024-02-29", // Forces history back to Feb 2024 (leap month)
            "2026-06-01",
            "2026-06-15",
            "2026-11-01",
            "2026-11-21",
            "2026-11-25"  // Future date in current month -> should not count in current month stats
        ]
        let habit = Habit(name: "Code", completedDates: dates)
        let months = HabitCalendar.monthsHistory(
            for: habit,
            completedSet: Set(dates),
            referenceDate: ref,
            calendar: cal
        )

        // Feb 2024: leap year (29 days), 2024-02-01 was Thursday -> leadingEmptyCount == 3
        let feb2024 = months.first { $0.year == 2024 && $0.month == 2 }
        #expect(feb2024 != nil)
        #expect(feb2024?.daysInMonth == 29)
        #expect(feb2024?.leadingEmptyCount == 3)
        #expect(feb2024?.shortTitle == "Feb '24")
        #expect(feb2024?.statsLabel == "1/29")
        #expect(feb2024?.completedDays == [29])

        // Jun 2026: 2026-06-01 is Monday -> leadingEmptyCount == 0, same year title omits year ("Jun")
        let jun2026 = months.first { $0.year == 2026 && $0.month == 6 }
        #expect(jun2026?.leadingEmptyCount == 0)
        #expect(jun2026?.daysInMonth == 30)
        #expect(jun2026?.shortTitle == "Jun")
        #expect(jun2026?.statsLabel == "2/30")

        // Nov 2026 (current month): 2026-11-01 is Sunday -> leadingEmptyCount == 6, denominator is curDay (21), future day 25 ignored
        let nov2026 = months.last
        #expect(nov2026?.leadingEmptyCount == 6)
        #expect(nov2026?.statsLabel == "2/21")
        #expect(nov2026?.completedDays == [1, 21])
    }
}
