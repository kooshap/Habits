import SwiftUI

@main
struct HabitsWatchApp: App {
    @State private var store = WatchHabitStore()

    var body: some Scene {
        WindowGroup {
            WatchHomeView(store: store)
        }
    }
}
