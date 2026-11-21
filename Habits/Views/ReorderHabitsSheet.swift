import SwiftData
import SwiftUI

struct ReorderHabitsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var orderedHabits: [Habit]

    init(habits: [Habit]) {
        _orderedHabits = State(initialValue: habits)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedHabits) { habit in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(habit.accentColor)
                            .frame(width: 10, height: 10)

                        Text(habit.name)
                            .font(.system(size: 15, weight: .medium))

                        Spacer()

                        Text(habit.scheduleShortLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { indices, newOffset in
                    orderedHabits.move(fromOffsets: indices, toOffset: newOffset)
                    for (index, habit) in orderedHabits.enumerated() {
                        habit.sortOrder = index
                    }
                    try? modelContext.save()
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Habits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
