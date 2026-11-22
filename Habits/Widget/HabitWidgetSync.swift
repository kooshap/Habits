import Foundation
import SwiftData
import WidgetKit

enum HabitWidgetSync {
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func makeSnapshot(
        from habits: [Habit],
        now: Date = Date(),
        calendar: Calendar = HabitCalendar.monday
    ) -> HabitWidgetSnapshot {
        let sorted = habits.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.createdAt < $1.createdAt
        }
        let records = sorted.map { habit in
            WidgetHabitRecord(
                id: habit.id,
                targetPerWeek: habit.targetPerWeek,
                completedDates: habit.completedDates
            )
            .pruned(keepingDaysBefore: now, calendar: calendar)
        }
        return HabitWidgetSnapshot(updatedAt: now, habits: records)
    }

    @MainActor
    static func sync(habits: [Habit], now: Date = Date()) {
        guard !isRunningTests else { return }
        let snapshot = makeSnapshot(from: habits, now: now)
        if (try? HabitWidgetSnapshotStore.save(snapshot)) == true {
            WidgetCenter.shared.reloadTimelines(ofKind: HabitWidgetConstants.widgetKind)
        }
    }

    @MainActor
    static func sync(from context: ModelContext, now: Date = Date()) {
        guard !isRunningTests else { return }
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        guard let fetched = try? context.fetch(descriptor) else { return }
        sync(habits: fetched, now: now)
    }
}
