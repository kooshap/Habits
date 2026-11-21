import SwiftData
import SwiftUI

@main
struct HabitsApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: Habit.self)
    }
}
