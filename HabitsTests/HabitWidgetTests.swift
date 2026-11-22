import Foundation
import Testing
@testable import Habits

@Suite("Lock Screen Progress Ring Widget")
struct HabitWidgetTests {
    private let cal = TestCalendar.mondayUTC

    @Test("Empty state and summary clamping invariants")
    func emptyAndClampingInvariants() {
        let ref = TestCalendar.date(2026, 11, 22)
        let empty = HabitWidgetSummary.compute(from: [], referenceDate: ref, calendar: cal)

        #expect(empty == .empty)
        #expect(empty.completed == 0)
        #expect(empty.total == 0)
        #expect(!empty.hasHabits)
        #expect(!empty.isAllDone)
        #expect(empty.progress == 0)
        #expect(empty.accessibilityValueText == "No habits configured")

        let clampedOverflow = HabitWidgetSummary(completed: 12, total: 7)
        #expect(clampedOverflow.completed == 7)
        #expect(clampedOverflow.total == 7)
        #expect(clampedOverflow.isAllDone)
        #expect(clampedOverflow.progress == 1.0)

        let clampedNegative = HabitWidgetSummary(completed: -3, total: -5)
        #expect(clampedNegative == .empty)
        #expect(clampedNegative.progress == 0)
    }

    @Test("Daily habits progress transitions cleanly across 0/7, partial, and 7/7 complete")
    func dailyHabitsProgressCalculation() {
        let sunday = TestCalendar.date(2026, 11, 22)
        let allUnchecked = (0..<7).map { _ in
            WidgetHabitRecord(targetPerWeek: 7, completedDates: ["2026-11-21"]) // Yesterday only
        }

        let zeroSummary = HabitWidgetSummary.compute(from: allUnchecked, referenceDate: sunday, calendar: cal)
        #expect(zeroSummary == HabitWidgetSummary(completed: 0, total: 7))
        #expect(!zeroSummary.isAllDone)
        #expect(zeroSummary.progress == 0)
        #expect(zeroSummary.accessibilityValueText == "0 of 7 completed today")

        let fourChecked = (0..<7).map { idx in
            WidgetHabitRecord(
                targetPerWeek: 7,
                completedDates: idx < 4 ? ["2026-11-21", "2026-11-22"] : ["2026-11-21"]
            )
        }
        let partialSummary = HabitWidgetSummary.compute(from: fourChecked, referenceDate: sunday, calendar: cal)
        #expect(partialSummary == HabitWidgetSummary(completed: 4, total: 7))
        #expect(!partialSummary.isAllDone)
        #expect(abs(partialSummary.progress - (4.0 / 7.0)) < 0.0001)
        #expect(partialSummary.accessibilityValueText == "4 of 7 completed today")

        let allChecked = (0..<7).map { _ in
            WidgetHabitRecord(targetPerWeek: 7, completedDates: ["2026-11-22"])
        }
        let completeSummary = HabitWidgetSummary.compute(from: allChecked, referenceDate: sunday, calendar: cal)
        #expect(completeSummary == HabitWidgetSummary(completed: 7, total: 7))
        #expect(completeSummary.isAllDone)
        #expect(completeSummary.progress == 1.0)
        #expect(completeSummary.accessibilityValueText == "All 7 completed today")
    }

    @Test("Flexible weekly habits count while open this week, step aside once already banked, and include bonus reps")
    func weeklyFlexibleHabitsBehavior() {
        // Saturday 2026-11-21 (Mon–Sun week starts 2026-11-16)
        let saturday = TestCalendar.date(2026, 11, 21)
        let dailyDone = WidgetHabitRecord(targetPerWeek: 7, completedDates: ["2026-11-21"])

        // 1. Weekly 3× habit with only 2 prior reps this week -> still actionable on Saturday (1/2)
        let weeklyNeedsOneMore = WidgetHabitRecord(
            targetPerWeek: 3,
            completedDates: ["2026-11-16", "2026-11-18"]
        )
        let pendingSummary = HabitWidgetSummary.compute(
            from: [dailyDone, weeklyNeedsOneMore],
            referenceDate: saturday,
            calendar: cal
        )
        #expect(pendingSummary == HabitWidgetSummary(completed: 1, total: 2))
        #expect(!pendingSummary.isAllDone)

        // 2. Weekly 3× habit already hit 3/3 on Mon/Wed/Fri -> does not block closing Saturday's daily ring (1/1 ✓)
        let weeklyAlreadyBanked = WidgetHabitRecord(
            targetPerWeek: 3,
            completedDates: ["2026-11-16", "2026-11-18", "2026-11-20"]
        )
        let bankedSummary = HabitWidgetSummary.compute(
            from: [dailyDone, weeklyAlreadyBanked],
            referenceDate: saturday,
            calendar: cal
        )
        #expect(bankedSummary == HabitWidgetSummary(completed: 1, total: 1))
        #expect(bankedSummary.isAllDone)

        // 3. Logging a bonus 4th rep on Saturday includes it as completed (2/2 ✓)
        let weeklyBonusToday = WidgetHabitRecord(
            targetPerWeek: 3,
            completedDates: ["2026-11-16", "2026-11-18", "2026-11-20", "2026-11-21"]
        )
        let bonusSummary = HabitWidgetSummary.compute(
            from: [dailyDone, weeklyBonusToday],
            referenceDate: saturday,
            calendar: cal
        )
        #expect(bonusSummary == HabitWidgetSummary(completed: 2, total: 2))
        #expect(bonusSummary.isAllDone)

        // 4. Portfolio of ONLY weekly habits that are all already banked earlier this week -> reports satisfied (2/2 ✓)
        let secondBankedWeekly = WidgetHabitRecord(
            targetPerWeek: 2,
            completedDates: ["2026-11-17", "2026-11-19"]
        )
        let allWeeklyBanked = HabitWidgetSummary.compute(
            from: [weeklyAlreadyBanked, secondBankedWeekly],
            referenceDate: saturday,
            calendar: cal
        )
        #expect(allWeeklyBanked == HabitWidgetSummary(completed: 2, total: 2))
        #expect(allWeeklyBanked.isAllDone)
    }

    @Test("timelineSchedule precomputes exact midnight rollover and resets weekly targets on Monday")
    func midnightRolloverAndNewWeekReset() {
        // Sunday 2026-11-22 at 23:45 UTC -> midnight rolls into Monday 2026-11-23 00:00 UTC (new Mon–Sun week)
        let sundayNight = TestCalendar.date(2026, 11, 22, hour: 23, minute: 45)
        let expectedMondayMidnight = TestCalendar.date(2026, 11, 23, hour: 0, minute: 0)

        let dailyDoneSunday = WidgetHabitRecord(targetPerWeek: 7, completedDates: ["2026-11-22"])
        let weeklyBankedLastWeek = WidgetHabitRecord(
            targetPerWeek: 3,
            completedDates: ["2026-11-16", "2026-11-18", "2026-11-20"]
        )
        let snapshot = HabitWidgetSnapshot(
            updatedAt: sundayNight,
            habits: [dailyDoneSunday, weeklyBankedLastWeek]
        )

        let schedule = HabitWidgetSummary.timelineSchedule(
            from: snapshot,
            now: sundayNight,
            calendar: cal
        )

        #expect(schedule.entries.count == 2)
        #expect(schedule.reloadAfter == expectedMondayMidnight)

        // Entry 0 (Sunday 23:45): daily is done and weekly was banked earlier in week -> 1/1 complete
        #expect(schedule.entries[0].date == sundayNight)
        #expect(schedule.entries[0].summary == HabitWidgetSummary(completed: 1, total: 1))
        #expect(schedule.entries[0].summary.isAllDone)

        // Entry 1 (Monday 00:00): new day AND new Monday–Sunday week -> resets to 0/2 automatically
        #expect(schedule.entries[1].date == expectedMondayMidnight)
        #expect(schedule.entries[1].summary == HabitWidgetSummary(completed: 0, total: 2))
        #expect(!schedule.entries[1].summary.isAllDone)
    }

    @Test("HabitWidgetSync prunes old dates while preserving sortOrder, and SnapshotStore round-trips atomically")
    func snapshotPruningAndPersistenceRoundTrip() throws {
        let now = TestCalendar.date(2026, 11, 22, hour: 9, minute: 30)

        let secondHabit = Habit(
            name: "Read",
            targetPerWeek: 7,
            sortOrder: 5,
            createdAt: Date(timeIntervalSince1970: 2_000),
            completedDates: [
                "2025-07-08", // Older than 14-day retention window -> pruned
                "2026-11-07", // 15 days ago -> pruned
                "2026-11-08", // 14 days ago -> retained
                "2026-11-22"  // Today -> retained
            ]
        )
        let firstHabit = Habit(
            name: "Cold shower",
            targetPerWeek: 4,
            sortOrder: 1,
            createdAt: Date(timeIntervalSince1970: 1_000),
            completedDates: ["2026-11-20"]
        )

        let snapshot = HabitWidgetSync.makeSnapshot(
            from: [secondHabit, firstHabit],
            now: now,
            calendar: cal
        )

        #expect(snapshot.version == 1)
        #expect(snapshot.habits.count == 2)
        #expect(snapshot.habits[0].id == firstHabit.id)
        #expect(snapshot.habits[0].targetPerWeek == 4)
        #expect(snapshot.habits[0].completedDates == ["2026-11-20"])

        #expect(snapshot.habits[1].id == secondHabit.id)
        #expect(snapshot.habits[1].completedDates == ["2026-11-08", "2026-11-22"])

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-store-\(UUID().uuidString)", isDirectory: true)
        let fileURL = tempDir.appendingPathComponent(HabitWidgetConstants.snapshotFilename)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(try HabitWidgetSnapshotStore.save(snapshot, to: nil) == false)
        #expect(HabitWidgetSnapshotStore.load(from: nil) == nil)
        #expect(HabitWidgetSnapshotStore.load(from: fileURL) == nil)

        let saved = try HabitWidgetSnapshotStore.save(snapshot, to: fileURL)
        #expect(saved == true)

        let loaded = HabitWidgetSnapshotStore.load(from: fileURL)
        #expect(loaded?.version == 1)
        #expect(loaded?.habits == snapshot.habits)

        // Corrupt payload returns nil safely instead of throwing into WidgetKit timeline provider
        try Data("corrupt-json".utf8).write(to: fileURL, options: .atomic)
        #expect(HabitWidgetSnapshotStore.load(from: fileURL) == nil)
    }
}
