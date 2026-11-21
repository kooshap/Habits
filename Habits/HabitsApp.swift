import SwiftData
import SwiftUI

@main
struct HabitsApp: App {
    private let useInMemoryStore = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: Habit.self, inMemory: useInMemoryStore)
    }
}
