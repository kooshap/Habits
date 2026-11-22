import Foundation
import SwiftData
import Testing
@testable import Habits

@Suite("Apple Watch Sync & Shared Models")
struct HabitWatchSyncTests {
    private let cal = TestCalendar.mondayUTC

    @Test("makeWatchSnapshot preserves fixed sortOrder, prunes old dates, and matches widget summary")
    func makeWatchSnapshotPreservesOrderAndPrunes() throws {
        let now = TestCalendar.date(2026, 11, 22, hour: 10, minute: 0)

        let second = Habit(
            name: "Read",
            colorHex: "#D9822B",
            targetPerWeek: 7,
            sortOrder: 2,
            createdAt: Date(timeIntervalSince1970: 2_000),
            completedDates: [
                "2026-10-01", // Pruned (>14 days old)
                "2026-11-08", // Retained (14 days ago)
                "2026-11-22"  // Today
            ]
        )
        let first = Habit(
            name: "Cold shower",
            colorHex: "#2563EB",
            targetPerWeek: 4,
            sortOrder: 0,
            createdAt: Date(timeIntervalSince1970: 1_000),
            completedDates: ["2026-11-18", "2026-11-20"]
        )

        let snapshot = PhoneWatchSyncController.makeWatchSnapshot(
            from: [second, first],
            now: now,
            calendar: cal
        )

        #expect(snapshot.habits.count == 2)
        #expect(snapshot.habits[0].id == first.id)
        #expect(snapshot.habits[0].name == "Cold shower")
        #expect(snapshot.habits[0].colorHex == "#2563EB")
        #expect(snapshot.habits[0].targetPerWeek == 4)
        #expect(snapshot.habits[0].completedDates == ["2026-11-18", "2026-11-20"])

        #expect(snapshot.habits[1].id == second.id)
        #expect(snapshot.habits[1].name == "Read")
        #expect(snapshot.habits[1].completedDates == ["2026-11-08", "2026-11-22"])

        // Summary matches 1/2 completed today (Read done today; Cold shower 2/4 wk still open)
        let summary = snapshot.summary(referenceDate: now, calendar: cal)
        #expect(summary == HabitWidgetSummary(completed: 1, total: 2))

        // Round-trip JSON encoding/decoding
        let encoded = try snapshot.encodedData()
        let decoded = HabitWatchSnapshot.decode(from: encoded)
        #expect(decoded == snapshot)
    }

    @Test("weeklyProgressBadge formats flexible weekly habits and returns nil for daily habits")
    func weeklyProgressBadgeFormatting() {
        let sunday = TestCalendar.date(2026, 11, 22) // Mon–Sun week starts 2026-11-16

        let daily = WatchHabitRecord(name: "Meditate", targetPerWeek: 7, completedDates: ["2026-11-22"])
        #expect(daily.weeklyProgressBadge(referenceDate: sunday, calendar: cal) == nil)

        let openWeekly = WatchHabitRecord(
            name: "Exercise",
            targetPerWeek: 4,
            completedDates: ["2026-11-16", "2026-11-19"]
        )
        let openBadge = openWeekly.weeklyProgressBadge(referenceDate: sunday, calendar: cal)
        #expect(openBadge?.text == "2/4 wk")
        #expect(openBadge?.isGoalMet == false)

        let metWeekly = WatchHabitRecord(
            name: "Exercise",
            targetPerWeek: 3,
            completedDates: ["2026-11-16", "2026-11-18", "2026-11-21"]
        )
        let metBadge = metWeekly.weeklyProgressBadge(referenceDate: sunday, calendar: cal)
        #expect(metBadge?.text == "3/3 wk ✓")
        #expect(metBadge?.isGoalMet == true)
    }

    @Test("HabitWatchMerger preserves unacknowledged offline Watch toggles and drops acknowledged ones")
    func offlineMutationMerging() {
        let habitA = UUID()
        let habitB = UUID()
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        let t3 = Date(timeIntervalSince1970: 3_000)

        let stalePhoneSnapshot = HabitWatchSnapshot(
            updatedAt: t2,
            habits: [
                WatchHabitRecord(id: habitA, name: "Cold shower", sortOrder: 0, completedDates: ["2026-11-22"]),
                WatchHabitRecord(id: habitB, name: "Read", sortOrder: 1, completedDates: [])
            ]
        )

        // Mutation at t1 (older than snapshot t2) -> already reflected/superseded, should be dropped
        let olderMutation = WatchHabitToggleMutation(
            habitID: habitA,
            dateKey: "2026-11-22",
            isCompleted: false,
            timestamp: t1
        )
        // Mutation at t3 (newer than snapshot t2) -> offline check-off on Watch, must be preserved!
        let newerOfflineMutation = WatchHabitToggleMutation(
            habitID: habitB,
            dateKey: "2026-11-22",
            isCompleted: true,
            timestamp: t3
        )

        let result = HabitWatchMerger.merge(
            snapshot: stalePhoneSnapshot,
            pendingMutations: [olderMutation, newerOfflineMutation]
        )

        #expect(result.remainingPending == [newerOfflineMutation])
        #expect(result.mergedSnapshot.updatedAt == t3)
        #expect(result.mergedSnapshot.habits[0].isCompleted(on: "2026-11-22") == true)
        #expect(result.mergedSnapshot.habits[1].isCompleted(on: "2026-11-22") == true)
    }

    @Test("applyMutation updates SwiftData idempotently on iPhone")
    @MainActor
    func applyMutationIdempotentInSwiftData() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Habit.self, configurations: config)
        let context = container.mainContext

        let habit = Habit(name: "Cold shower", completedDates: ["2026-11-21"])
        context.insert(habit)
        try context.save()

        let checkToday = WatchHabitToggleMutation(
            habitID: habit.id,
            dateKey: "2026-11-22",
            isCompleted: true
        )

        // First delivery checks off 2026-11-22
        #expect(PhoneWatchSyncController.applyMutation(checkToday, in: context) == true)
        #expect(habit.completedDates == ["2026-11-21", "2026-11-22"])

        // Duplicate delivery is idempotent (does NOT uncheck)
        #expect(PhoneWatchSyncController.applyMutation(checkToday, in: context) == true)
        #expect(habit.completedDates == ["2026-11-21", "2026-11-22"])

        // Explicit uncheck removes 2026-11-22 cleanly
        let uncheckToday = WatchHabitToggleMutation(
            habitID: habit.id,
            dateKey: "2026-11-22",
            isCompleted: false
        )
        #expect(PhoneWatchSyncController.applyMutation(uncheckToday, in: context) == true)
        #expect(habit.completedDates == ["2026-11-21"])
    }
}
