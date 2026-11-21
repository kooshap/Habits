import Foundation
import SwiftData
import Testing
@testable import Habits

@Suite("BackupManager Export & Import")
@MainActor
struct BackupManagerTests {

    @Test("defaultFilename uses YYYY-MM-DD backup naming")
    func defaultFilenameFormat() {
        // Use noon local time on a fixed Y/M/D via HabitCalendar.monday so dateKey matches seamlessly
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 21
        comps.hour = 12
        let date = HabitCalendar.monday.date(from: comps)!
        #expect(BackupManager.defaultFilename(for: date) == "habits-backup-2026-11-21")
    }

    @Test("Round-trip export to JSON file and decodePayload preserves fields and normalizes sortOrder")
    func roundTripExportAndDecode() throws {
        let idA = UUID()
        let idB = UUID()
        let createdA = Date(timeIntervalSince1970: 1_760_000_000)
        let createdB = Date(timeIntervalSince1970: 1_760_500_000)

        let habitLateOrder = Habit(
            id: idB,
            name: "Workout",
            colorHex: "#E54D37",
            targetPerWeek: 4,
            sortOrder: 10,
            createdAt: createdB,
            completedDates: ["2026-11-20", "2026-11-18"]
        )
        let habitEarlyOrder = Habit(
            id: idA,
            name: "Read",
            colorHex: "#2563EB",
            targetPerWeek: 7,
            sortOrder: 2,
            createdAt: createdA,
            completedDates: ["2026-11-21"]
        )

        let document = BackupManager.makeDocument(from: [habitLateOrder, habitEarlyOrder])
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("habits-roundtrip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try document.data.write(to: tempURL)
        let decoded = try BackupManager.decodePayload(from: tempURL)

        #expect(decoded.version == 1)
        #expect(decoded.habits.count == 2)

        // Sorted by sortOrder and re-indexed 0, 1
        #expect(decoded.habits[0].id == idA)
        #expect(decoded.habits[0].name == "Read")
        #expect(decoded.habits[0].sortOrder == 0)
        #expect(decoded.habits[0].targetPerWeek == 7)
        #expect(abs(decoded.habits[0].createdAt.timeIntervalSince(createdA)) < 1.0)
        #expect(decoded.habits[0].completedDates == ["2026-11-21"])

        #expect(decoded.habits[1].id == idB)
        #expect(decoded.habits[1].name == "Workout")
        #expect(decoded.habits[1].sortOrder == 1)
        #expect(decoded.habits[1].colorHex == "#E54D37")
        #expect(decoded.habits[1].targetPerWeek == 4)
        #expect(decoded.habits[1].completedDates == ["2026-11-18", "2026-11-20"])
    }

    @Test("replaceAll deletes existing habits, skips blank names, sanitizes dates, and re-indexes sortOrder")
    func applyReplaceAll() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let oldHabit = Habit(name: "Old Habit", sortOrder: 0, completedDates: ["2026-10-01"])
        context.insert(oldHabit)
        try context.save()

        let payload = HabitsBackupPayload(
            exportedAt: Date(),
            habits: [
                HabitBackupEntry(
                    id: UUID(),
                    name: "   ", // Blank -> skipped
                    colorHex: "#2563EB",
                    targetPerWeek: 7,
                    sortOrder: 0,
                    createdAt: Date(),
                    completedDates: ["2026-11-01"]
                ),
                HabitBackupEntry(
                    id: UUID(),
                    name: "  Guitar  ",
                    colorHex: "#7C3AED",
                    targetPerWeek: 99, // Clamped to 7 by Habit.init
                    sortOrder: 5,
                    createdAt: Date(),
                    completedDates: ["2026-11-20", "bad-date", "2026-11-1", "2026-11-05", "2026-11-20"]
                ),
                HabitBackupEntry(
                    id: UUID(),
                    name: "Run",
                    colorHex: "#0891B2",
                    targetPerWeek: 3,
                    sortOrder: 1,
                    createdAt: Date(),
                    completedDates: ["2026-11-19"]
                )
            ]
        )

        try BackupManager.apply(
            payload: payload,
            mode: .replaceAll,
            existingHabits: [oldHabit],
            in: context
        )

        let fetched = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(fetched.count == 2)

        // "Run" had sortOrder 1, "Guitar" had sortOrder 5 (blank was skipped, though index enumeration is over sortedIncoming)
        #expect(fetched[0].name == "Run")
        #expect(fetched[0].targetPerWeek == 3)
        #expect(fetched[0].completedDates == ["2026-11-19"])

        #expect(fetched[1].name == "Guitar")
        #expect(fetched[1].targetPerWeek == 7)
        #expect(fetched[1].completedDates == ["2026-11-05", "2026-11-20"])
        #expect(fetched[0].sortOrder < fetched[1].sortOrder)
    }

    @Test("merge matches by UUID first, then case/diacritic-insensitive name, and appends new habits")
    func applyMergeMode() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let sharedID = UUID()
        let byIDHabit = Habit(
            id: sharedID,
            name: "Meditate",
            colorHex: "#2563EB",
            targetPerWeek: 7,
            sortOrder: 0,
            completedDates: ["2026-11-01", "2026-11-02"]
        )
        let byNameHabit = Habit(
            name: "Café Walk",
            colorHex: "#D9822B",
            targetPerWeek: 5,
            sortOrder: 4,
            completedDates: ["2026-11-10"]
        )
        context.insert(byIDHabit)
        context.insert(byNameHabit)
        try context.save()

        let payload = HabitsBackupPayload(
            exportedAt: Date(),
            habits: [
                // Matches by UUID even though incoming name differs
                HabitBackupEntry(
                    id: sharedID,
                    name: "Morning Meditation",
                    colorHex: "#E54D37",
                    targetPerWeek: 3,
                    sortOrder: 0,
                    createdAt: Date(),
                    completedDates: ["2026-11-02", "2026-11-03", "invalid"]
                ),
                // Different UUID, matches "Café Walk" case- and diacritic-insensitively
                HabitBackupEntry(
                    id: UUID(),
                    name: "  cafe walk ",
                    colorHex: "#0891B2",
                    targetPerWeek: 2,
                    sortOrder: 1,
                    createdAt: Date(),
                    completedDates: ["2026-11-11"]
                ),
                // Brand new habit -> appended at max(sortOrder) + 1 == 5
                HabitBackupEntry(
                    id: UUID(),
                    name: "Stretch",
                    colorHex: "#4F46E5",
                    targetPerWeek: 4,
                    sortOrder: 2,
                    createdAt: Date(),
                    completedDates: ["2026-11-21"]
                )
            ]
        )

        try BackupManager.apply(
            payload: payload,
            mode: .merge,
            existingHabits: [byIDHabit, byNameHabit],
            in: context
        )

        let fetched = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(fetched.count == 3)

        // 1. Matched by ID: preserves existing metadata & sortOrder, unions valid dates
        #expect(fetched[0].id == sharedID)
        #expect(fetched[0].name == "Meditate")
        #expect(fetched[0].sortOrder == 0)
        #expect(fetched[0].completedDates == ["2026-11-01", "2026-11-02", "2026-11-03"])

        // 2. Matched by case/diacritic-insensitive name: unions dates without duplicating habit
        #expect(fetched[1].name == "Café Walk")
        #expect(fetched[1].sortOrder == 4)
        #expect(fetched[1].completedDates == ["2026-11-10", "2026-11-11"])

        // 3. Appended new habit gets sortOrder == 5
        #expect(fetched[2].name == "Stretch")
        #expect(fetched[2].sortOrder == 5)
        #expect(fetched[2].targetPerWeek == 4)
        #expect(fetched[2].completedDates == ["2026-11-21"])
    }

    @Test("decodePayload throws cleanly on invalid JSON and missing files")
    func decodePayloadErrorHandling() throws {
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: badURL) }

        try Data("{ not valid json".utf8).write(to: badURL)
        #expect(throws: (any Error).self) {
            _ = try BackupManager.decodePayload(from: badURL)
        }

        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        #expect(throws: (any Error).self) {
            _ = try BackupManager.decodePayload(from: missingURL)
        }
    }
}
