import SwiftUI
import WatchKit

struct WatchHomeView: View {
    @Environment(\.scenePhase) private var scenePhase

    let store: WatchHabitStore

    @State private var today: Date = HabitWidgetCalendar.monday.startOfDay(for: Date())

    private static let rowPlatterColor = Color(.sRGB, red: 0.082, green: 0.082, blue: 0.098, opacity: 1.0)

    var body: some View {
        let habits = store.orderedHabits
        let summary = store.summary(for: today)
        let todayKey = HabitWidgetCalendar.dateKey(for: today)

        Group {
            if habits.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        headerRow(summary: summary)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 2)

                        ForEach(habits) { habit in
                            WatchHabitPlatterRow(
                                habit: habit,
                                isCompleted: habit.isCompleted(on: todayKey),
                                weeklyBadge: habit.weeklyProgressBadge(referenceDate: today),
                                platterColor: Self.rowPlatterColor
                            ) {
                                store.toggleToday(habitID: habit.id, now: Date())
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            today = HabitWidgetCalendar.monday.startOfDay(for: Date())
            store.requestSnapshotFromPhone()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                today = HabitWidgetCalendar.monday.startOfDay(for: Date())
                store.requestSnapshotFromPhone()
            }
        }
    }

    // MARK: - Top Header ("Today" + Compact Ring Counter)

    private func headerRow(summary: HabitWidgetSummary) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("Today")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 4)

            if summary.hasHabits {
                HStack(spacing: 4.5) {
                    WatchMiniProgressRing(summary: summary)

                    Text("\(summary.completed)/\(summary.total)")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(summary.isAllDone ? .white : Color(white: 0.78))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today's progress")
                .accessibilityValue(summary.accessibilityValueText)
            }
        }
    }

    // MARK: - Minimal Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 4)

            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 34, height: 34)
                Circle()
                    .fill(WatchHabitPalette.color(for: "#2563EB"))
                    .frame(width: 12, height: 12)
            }

            Text("No habits yet")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("Open Habits on iPhone to add or sync your list.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if store.isReachable {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    store.requestSnapshotFromPhone()
                } label: {
                    Text("Sync Now")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 2)
            }

            Spacer(minLength: 4)
        }
    }
}

// MARK: - Single-Line Habit Platter Row with iOS-Style 0.21s Hold

private struct WatchHabitPlatterRow: View {
    let habit: WatchHabitRecord
    let isCompleted: Bool
    let weeklyBadge: (text: String, isGoalMet: Bool)?
    let platterColor: Color
    let onToggle: () -> Void

    @State private var isPressing = false
    @State private var justPopped = false

    private let holdDuration: Double = 0.21

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(habit.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(isCompleted ? Color(white: 0.88) : .white)
                    .lineLimit(1)

                if let weeklyBadge {
                    Text(weeklyBadge.text)
                        .font(.system(size: 10, weight: weeklyBadge.isGoalMet ? .semibold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(weeklyBadge.isGoalMet ? habit.accentColor : Color.secondary)
                }
            }

            Spacer(minLength: 2)

            WatchHoldCheckCircle(
                isCompleted: isCompleted,
                accentColor: habit.accentColor,
                isPressing: isPressing,
                justPopped: justPopped
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isPressing ? Color(white: 0.14) : platterColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 20) {
            WKInterfaceDevice.current().play(.click)
            onToggle()
            justPopped = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                justPopped = false
            }
        } onPressingChanged: { pressing in
            isPressing = pressing
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.name)
        .accessibilityValue(isCompleted ? "Completed today" : "Not completed today")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onToggle()
        }
    }
}

// MARK: - Compact Header Progress Ring

private struct WatchMiniProgressRing: View {
    let summary: HabitWidgetSummary

    private let size: CGFloat = 18
    private let lineWidth: CGFloat = 2.6
    private static let ringCobalt = Color(.sRGB, red: 0.15, green: 0.39, blue: 0.92, opacity: 1.0)

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)

            if summary.completed > 0 {
                Circle()
                    .trim(from: 0, to: summary.progress)
                    .stroke(
                        Self.ringCobalt,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: summary.progress)
    }
}

#Preview("Today List (4/7)") {
    let todayKey = HabitWidgetCalendar.dateKey(for: Date())
    let sampleHabits = [
        WatchHabitRecord(name: "Cold shower", colorHex: "#2563EB", targetPerWeek: 7, sortOrder: 0, completedDates: [todayKey]),
        WatchHabitRecord(name: "Wake up before 8", colorHex: "#4F46E5", targetPerWeek: 7, sortOrder: 1, completedDates: [todayKey]),
        WatchHabitRecord(name: "Exercise", colorHex: "#7C3AED", targetPerWeek: 4, sortOrder: 2, completedDates: []),
        WatchHabitRecord(name: "McGill", colorHex: "#DB2777", targetPerWeek: 7, sortOrder: 3, completedDates: [todayKey]),
        WatchHabitRecord(name: "Meditate", colorHex: "#E54D37", targetPerWeek: 7, sortOrder: 4, completedDates: []),
        WatchHabitRecord(name: "Read", colorHex: "#D9822B", targetPerWeek: 7, sortOrder: 5, completedDates: [todayKey]),
        WatchHabitRecord(name: "No YouTube", colorHex: "#0891B2", targetPerWeek: 7, sortOrder: 6, completedDates: [])
    ]
    WatchHomeView(store: WatchHabitStore(previewHabits: sampleHabits))
}
