import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchHabitStore: NSObject {
    private(set) var snapshot: HabitWatchSnapshot
    fileprivate(set) var isReachable: Bool = false

    @ObservationIgnored
    private var pendingMutations: [WatchHabitToggleMutation] = []

    @ObservationIgnored
    private let storageDirectoryURL: URL?

    @ObservationIgnored
    private let isPreviewInstance: Bool

    @ObservationIgnored
    private lazy var sessionProxy = SessionDelegateProxy(owner: self)

    override init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("HabitsWatchStore", isDirectory: true)
        self.storageDirectoryURL = dir
        self.isPreviewInstance = false

        let cachedSnapshot = Self.loadSnapshot(in: dir) ?? HabitWatchSnapshot(updatedAt: .distantPast, habits: [])
        let cachedPending = Self.loadPendingMutations(in: dir)
        let merged = HabitWatchMerger.merge(snapshot: cachedSnapshot, pendingMutations: cachedPending)
        self.snapshot = merged.mergedSnapshot
        self.pendingMutations = merged.remainingPending
        super.init()

        activateConnectivity()
    }

    init(previewHabits: [WatchHabitRecord], referenceDate: Date = Date()) {
        self.storageDirectoryURL = nil
        self.isPreviewInstance = true
        self.snapshot = HabitWatchSnapshot(updatedAt: referenceDate, habits: previewHabits)
        self.pendingMutations = []
        super.init()
    }

    var orderedHabits: [WatchHabitRecord] {
        snapshot.habits.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func summary(for date: Date) -> HabitWidgetSummary {
        snapshot.summary(referenceDate: date)
    }

    // MARK: - User Actions

    @discardableResult
    func toggleToday(habitID: UUID, now: Date = Date()) -> Bool {
        let todayKey = HabitWidgetCalendar.dateKey(for: now)
        guard let index = snapshot.habits.firstIndex(where: { $0.id == habitID }) else {
            return false
        }

        let newState = !snapshot.habits[index].isCompleted(on: todayKey)
        snapshot.habits[index].setCompleted(newState, on: todayKey)
        snapshot.updatedAt = now

        let mutation = WatchHabitToggleMutation(
            habitID: habitID,
            dateKey: todayKey,
            isCompleted: newState,
            timestamp: now
        )

        // Replace any older pending mutation for the same habit + day
        pendingMutations.removeAll { $0.habitID == habitID && $0.dateKey == todayKey }
        pendingMutations.append(mutation)

        persistState()
        sendMutationToPhone(mutation)
        return newState
    }

    func requestSnapshotFromPhone() {
        guard !isPreviewInstance, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // First inspect any latest receivedApplicationContext delivered in background
        if let contextData = session.receivedApplicationContext[HabitWatchConstants.contextSnapshotKey] as? Data {
            ingestIncomingSnapshotData(contextData)
        }

        guard session.isReachable else { return }
        session.sendMessage(
            [HabitWatchConstants.messageTypeKey: HabitWatchConstants.messageRequestSnapshot],
            replyHandler: { [weak self] reply in
                guard let data = reply[HabitWatchConstants.replySnapshotDataKey] as? Data else { return }
                Task { @MainActor [weak self] in
                    self?.ingestIncomingSnapshotData(data)
                }
            },
            errorHandler: { _ in }
        )
    }

    // MARK: - Connectivity

    private func activateConnectivity() {
        guard !isPreviewInstance, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = sessionProxy
        session.activate()
    }

    private func sendMutationToPhone(_ mutation: WatchHabitToggleMutation) {
        guard !isPreviewInstance,
              WCSession.isSupported(),
              let mutationData = try? mutation.encodedData() else {
            return
        }

        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let payload: [String: Any] = [
            HabitWatchConstants.messageTypeKey: HabitWatchConstants.messageMutation,
            HabitWatchConstants.messageMutationDataKey: mutationData
        ]

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: { [weak self] reply in
                    guard let snapshotData = reply[HabitWatchConstants.replySnapshotDataKey] as? Data else { return }
                    Task { @MainActor [weak self] in
                        self?.ingestIncomingSnapshotData(snapshotData)
                    }
                },
                errorHandler: { _ in
                    session.transferUserInfo(payload)
                }
            )
        } else {
            session.transferUserInfo(payload)
        }
    }

    fileprivate func handleActivation(session: WCSession) {
        isReachable = session.isReachable
        if let contextData = session.receivedApplicationContext[HabitWatchConstants.contextSnapshotKey] as? Data {
            ingestIncomingSnapshotData(contextData)
        }
        // Flush any offline pending mutations queued before activation completed
        for mutation in pendingMutations {
            sendMutationToPhone(mutation)
        }
        requestSnapshotFromPhone()
    }

    fileprivate func ingestIncomingSnapshotData(_ data: Data) {
        guard let incoming = HabitWatchSnapshot.decode(from: data) else { return }
        // Ignore stale snapshots older than what we already synced (unless our store is empty)
        if !snapshot.habits.isEmpty && incoming.updatedAt < snapshot.updatedAt && pendingMutations.isEmpty {
            return
        }
        let merged = HabitWatchMerger.merge(snapshot: incoming, pendingMutations: pendingMutations)
        snapshot = merged.mergedSnapshot
        pendingMutations = merged.remainingPending
        persistState()
    }

    // MARK: - Local Persistence

    private func persistState() {
        guard !isPreviewInstance, let dir = storageDirectoryURL else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let snapshotData = try? snapshot.encodedData() {
            let fileURL = dir.appendingPathComponent(HabitWatchConstants.snapshotFilename)
            try? snapshotData.write(to: fileURL, options: .atomic)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let pendingData = try? encoder.encode(pendingMutations) {
            let pendingURL = dir.appendingPathComponent(HabitWatchConstants.pendingMutationsFilename)
            try? pendingData.write(to: pendingURL, options: .atomic)
        }
    }

    private static func loadSnapshot(in dir: URL?) -> HabitWatchSnapshot? {
        guard let fileURL = dir?.appendingPathComponent(HabitWatchConstants.snapshotFilename),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return HabitWatchSnapshot.decode(from: data)
    }

    private static func loadPendingMutations(in dir: URL?) -> [WatchHabitToggleMutation] {
        guard let fileURL = dir?.appendingPathComponent(HabitWatchConstants.pendingMutationsFilename),
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WatchHabitToggleMutation].self, from: data)) ?? []
    }
}

private final class SessionDelegateProxy: NSObject, WCSessionDelegate {
    weak var owner: WatchHabitStore?

    init(owner: WatchHabitStore) {
        self.owner = owner
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak owner] in
            owner?.handleActivation(session: session)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak owner] in
            owner?.isReachable = reachable
            if reachable {
                owner?.requestSnapshotFromPhone()
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[HabitWatchConstants.contextSnapshotKey] as? Data else { return }
        Task { @MainActor [weak owner] in
            owner?.ingestIncomingSnapshotData(data)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[HabitWatchConstants.replySnapshotDataKey] as? Data else { return }
        Task { @MainActor [weak owner] in
            owner?.ingestIncomingSnapshotData(data)
        }
    }
}
