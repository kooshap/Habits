import Foundation
import SwiftData
import WatchConnectivity

final class PhoneWatchSyncController: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchSyncController()

    private var modelContainer: ModelContainer?

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private override init() {
        super.init()
    }

    func configure(modelContainer: ModelContainer) {
        guard !Self.isRunningTests, WCSession.isSupported() else { return }
        self.modelContainer = modelContainer
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Pure Snapshot & Mutation Logic

    static func makeWatchSnapshot(
        from habits: [Habit],
        now: Date = Date(),
        calendar: Calendar = HabitCalendar.monday
    ) -> HabitWatchSnapshot {
        let sorted = habits.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.createdAt < $1.createdAt
        }
        let records = sorted.map { habit in
            WatchHabitRecord(
                id: habit.id,
                name: habit.name,
                colorHex: habit.colorHex,
                targetPerWeek: habit.targetPerWeek,
                sortOrder: habit.sortOrder,
                completedDates: habit.completedDates
            )
            .pruned(keepingDaysBefore: now, calendar: calendar)
        }
        return HabitWatchSnapshot(updatedAt: now, habits: records)
    }

    @MainActor
    @discardableResult
    static func applyMutation(
        _ mutation: WatchHabitToggleMutation,
        in context: ModelContext
    ) -> Bool {
        let descriptor = FetchDescriptor<Habit>()
        guard let habits = try? context.fetch(descriptor),
              let target = habits.first(where: { $0.id == mutation.habitID }) else {
            return false
        }

        var dates = Set(target.completedDates)
        if mutation.isCompleted {
            dates.insert(mutation.dateKey)
        } else {
            dates.remove(mutation.dateKey)
        }
        target.completedDates = dates.sorted()
        try? context.save()
        return true
    }

    // MARK: - Outbound Sync to Apple Watch

    @MainActor
    func pushSnapshot(habits: [Habit], now: Date = Date()) {
        guard !Self.isRunningTests, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let snapshot = Self.makeWatchSnapshot(from: habits, now: now)
        guard let data = try? snapshot.encodedData() else { return }

        try? session.updateApplicationContext([
            HabitWatchConstants.contextSnapshotKey: data
        ])

        if session.isReachable {
            session.sendMessage(
                [HabitWatchConstants.replySnapshotDataKey: data],
                replyHandler: nil,
                errorHandler: { _ in }
            )
        }
    }

    @MainActor
    private func currentSnapshotData() -> Data? {
        guard let context = modelContainer?.mainContext else { return nil }
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        guard let habits = try? context.fetch(descriptor) else { return nil }
        let snapshot = Self.makeWatchSnapshot(from: habits)
        return try? snapshot.encodedData()
    }

    @MainActor
    private func handleIncomingMutationData(_ data: Data) -> Data? {
        guard let mutation = WatchHabitToggleMutation.decode(from: data),
              let context = modelContainer?.mainContext else {
            return currentSnapshotData()
        }

        let now = max(Date(), mutation.timestamp.addingTimeInterval(0.001))
        if Self.applyMutation(mutation, in: context) {
            HabitWidgetSync.sync(from: context, now: now)
        }
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        guard let habits = try? context.fetch(descriptor) else { return nil }
        return try? Self.makeWatchSnapshot(from: habits, now: now).encodedData()
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            guard let context = self.modelContainer?.mainContext else { return }
            let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
            if let habits = try? context.fetch(descriptor) {
                self.pushSnapshot(habits: habits)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.activationState == .activated else { return }
        Task { @MainActor in
            guard let context = self.modelContainer?.mainContext else { return }
            let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
            if let habits = try? context.fetch(descriptor) {
                self.pushSnapshot(habits: habits)
            }
        }
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let type = message[HabitWatchConstants.messageTypeKey] as? String
        let mutationData = message[HabitWatchConstants.messageMutationDataKey] as? Data

        Task { @MainActor in
            if type == HabitWatchConstants.messageMutation, let mutationData {
                if let snapshotData = self.handleIncomingMutationData(mutationData) {
                    replyHandler([HabitWatchConstants.replySnapshotDataKey: snapshotData])
                } else {
                    replyHandler([:])
                }
            } else if type == HabitWatchConstants.messageRequestSnapshot {
                if let snapshotData = self.currentSnapshotData() {
                    replyHandler([HabitWatchConstants.replySnapshotDataKey: snapshotData])
                } else {
                    replyHandler([:])
                }
            } else {
                replyHandler([:])
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let type = message[HabitWatchConstants.messageTypeKey] as? String
        let mutationData = message[HabitWatchConstants.messageMutationDataKey] as? Data

        guard type == HabitWatchConstants.messageMutation, let mutationData else { return }
        Task { @MainActor in
            _ = self.handleIncomingMutationData(mutationData)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let type = userInfo[HabitWatchConstants.messageTypeKey] as? String
        let mutationData = userInfo[HabitWatchConstants.messageMutationDataKey] as? Data

        guard type == HabitWatchConstants.messageMutation, let mutationData else { return }
        Task { @MainActor in
            _ = self.handleIncomingMutationData(mutationData)
        }
    }
}
