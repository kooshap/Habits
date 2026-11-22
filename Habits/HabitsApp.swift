import SwiftData
import SwiftUI

@main
struct HabitsApp: App {
    private let modelContainer: ModelContainer

    init() {
        let useInMemoryStore = ProcessInfo.processInfo.arguments.contains("-ui-testing")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        do {
            let container: ModelContainer
            if useInMemoryStore {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(for: Habit.self, configurations: configuration)
            } else {
                container = try ModelContainer(for: Habit.self)
                PhoneWatchSyncController.shared.configure(modelContainer: container)
            }
            self.modelContainer = container
        } catch {
            fatalError("Failed to initialize Habits ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(modelContainer)
    }
}
