import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Habit.sortOrder, order: .forward)
    private var habits: [Habit]

    @State private var today: Date = HabitCalendar.startOfDay(Date())
    @State private var showingNewHabitSheet = false
    @State private var habitToEdit: Habit?
    @State private var habitPendingDelete: Habit?
    @State private var showingReorderSheet = false

    // Import / Export state
    @State private var isExporting = false
    @State private var exportDocument: HabitsBackupDocument?
    @State private var isImporting = false
    @State private var pendingImportPayload: HabitsBackupPayload?
    @State private var showingImportChoice = false
    @State private var alertMessage: String?

    private static let screenBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .systemBackground
    })

    private let titleColumnWidth: CGFloat = 110

    var body: some View {
        let rollingDays = HabitCalendar.rollingDays(count: 7, endingOn: today)

        NavigationStack {
            VStack(spacing: 0) {
                headerBar

                if habits.isEmpty {
                    emptyStateView
                } else {
                    weekdayHeaderRow(days: rollingDays)

                    Divider()
                        .opacity(0.65)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(habits.enumerated()), id: \.element.id) { index, habit in
                                habitRow(habit: habit, days: rollingDays)

                                if index < habits.count - 1 {
                                    Divider()
                                        .opacity(0.55)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .background(Self.screenBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Habit.self) { habit in
                HabitCalendarView(habit: habit, referenceDate: today)
            }
        }
        // New Habit Sheet
        .sheet(isPresented: $showingNewHabitSheet) {
            let nextOrder = (habits.map(\.sortOrder).max() ?? -1) + 1
            HabitEditorSheet(habitToEdit: nil, nextSortOrder: nextOrder)
        }
        // Edit Habit Sheet
        .sheet(item: $habitToEdit) { habit in
            HabitEditorSheet(habitToEdit: habit, nextSortOrder: habit.sortOrder)
        }
        // Reorder Sheet
        .sheet(isPresented: $showingReorderSheet) {
            ReorderHabitsSheet(habits: habits)
        }
        // Delete Confirmation
        .alert(
            "Delete Habit?",
            isPresented: Binding(
                get: { habitPendingDelete != nil },
                set: { if !$0 { habitPendingDelete = nil } }
            ),
            presenting: habitPendingDelete
        ) { habit in
            Button("Delete", role: .destructive) {
                modelContext.delete(habit)
                try? modelContext.save()
                habitPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                habitPendingDelete = nil
            }
        } message: { habit in
            Text("This will permanently remove \"\(habit.name)\" and its history.")
        }
        // Export JSON
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: BackupManager.defaultFilename(for: today)
        ) { result in
            if case .failure(let error) = result {
                alertMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        // Import JSON
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result)
        }
        // Merge vs Replace Choice
        .confirmationDialog(
            "Import Backup",
            isPresented: $showingImportChoice,
            titleVisibility: .visible
        ) {
            Button("Merge with Current Habits") {
                if let payload = pendingImportPayload {
                    applyImport(payload, mode: .merge)
                }
            }
            Button("Replace All Habits", role: .destructive) {
                if let payload = pendingImportPayload {
                    applyImport(payload, mode: .replaceAll)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingImportPayload = nil
            }
        } message: {
            if let count = pendingImportPayload?.habits.count {
                Text("Backup contains \(count) \(count == 1 ? "habit" : "habits"). Choose whether to merge completion history or replace your current list.")
            }
        }
        // Error / Status Alert
        .alert(
            "Notice",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        // Automatic Midnight / Foreground Day Refresh
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                today = HabitCalendar.startOfDay(Date())
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            today = HabitCalendar.startOfDay(Date())
        }
    }

    // MARK: - Top Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Habits")
                .font(.system(size: 25, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(.primary)

            Spacer()

            // Quiet ··· Menu (Export / Import / Reorder)
            Menu {
                Button {
                    exportDocument = BackupManager.makeDocument(from: habits)
                    isExporting = true
                } label: {
                    Label("Export Backup…", systemImage: "square.and.arrow.up")
                }
                .disabled(habits.isEmpty)

                Button {
                    isImporting = true
                } label: {
                    Label("Import Backup…", systemImage: "square.and.arrow.down")
                }

                if habits.count > 1 {
                    Divider()
                    Button {
                        showingReorderSheet = true
                    } label: {
                        Label("Reorder Habits", systemImage: "line.3.horizontal")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .strokeBorder(Color(uiColor: .systemGray4), lineWidth: 1)
                    )
            }
            .accessibilityLabel("More options")

            // + Add Habit Button
            Button {
                showingNewHabitSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .strokeBorder(Color(uiColor: .systemGray4), lineWidth: 1)
                    )
            }
            .accessibilityLabel("New Habit")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Sticky Rolling 7-Day Weekday Header

    private func weekdayHeaderRow(days: [RollingDay]) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            Text(HabitCalendar.headerMonthYear(for: today))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.secondary)
                .frame(width: titleColumnWidth, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(days) { day in
                    Text(day.weekdayLetter)
                        .font(.system(size: 10.5, weight: day.isToday ? .bold : .semibold))
                        .foregroundStyle(day.isToday ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Single-Line Habit Row (Polish C)

    private func habitRow(habit: Habit, days: [RollingDay]) -> some View {
        let completedSet = Set(habit.completedDates)
        let weekDone = habit.isDaily ? 0 : HabitCalendar.currentWeekCount(completedSet: completedSet, referenceDate: today)
        let weekGoalMet = !habit.isDaily && weekDone >= habit.targetPerWeek

        return HStack(alignment: .center, spacing: 6) {
            // Tappable Habit Title -> Calendar Push, Long-Press -> Manage Menu
            NavigationLink(value: habit) {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(habit.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !habit.isDaily {
                        Text(weekGoalMet
                             ? "\(weekDone)/\(habit.targetPerWeek) wk ✓"
                             : "\(weekDone)/\(habit.targetPerWeek) wk")
                            .font(.system(size: 10.5, weight: weekGoalMet ? .semibold : .medium))
                            .monospacedDigit()
                            .foregroundStyle(weekGoalMet ? habit.accentColor : Color.secondary)
                    }
                }
                .frame(width: titleColumnWidth, alignment: .leading)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    habitToEdit = habit
                } label: {
                    Label("Edit Habit", systemImage: "pencil")
                }

                if habits.count > 1 {
                    Button {
                        showingReorderSheet = true
                    } label: {
                        Label("Reorder List", systemImage: "line.3.horizontal")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    habitPendingDelete = habit
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            // Rolling 7 Numbered Hollow-Ring / Solid Circles
            HStack(spacing: 0) {
                ForEach(days) { day in
                    HoldDayCircle(
                        dayNumber: day.dayNumber,
                        isToday: day.isToday,
                        isCompleted: completedSet.contains(day.key),
                        accentColor: habit.accentColor
                    ) {
                        habit.toggle(dateKey: day.key)
                        try? modelContext.save()
                    }
                }
            }
        }
        .padding(.vertical, 5.5)
    }

    // MARK: - Minimal Empty State

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .strokeBorder(Color(uiColor: .systemGray4), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(HabitPalette.color(for: HabitPalette.defaultHex))
                    .frame(width: 16, height: 16)
            }
            .padding(.bottom, 2)

            Text("No habits yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Add your daily or weekly habits.\nHold any day circle briefly to check it off.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                showingNewHabitSheet = true
            } label: {
                Text("+ New Habit")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.primary, in: Capsule())
            }
            .padding(.top, 4)

            Button {
                isImporting = true
            } label: {
                Text("Import Backup…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Import Helpers

    private func handleImportedFile(_ result: Result<[URL], any Error>) {
        switch result {
        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let payload = try BackupManager.decodePayload(from: url)
                if habits.isEmpty {
                    applyImport(payload, mode: .replaceAll)
                } else {
                    pendingImportPayload = payload
                    showingImportChoice = true
                }
            } catch {
                alertMessage = "Invalid backup file: \(error.localizedDescription)"
            }
        }
    }

    private func applyImport(_ payload: HabitsBackupPayload, mode: BackupImportMode) {
        do {
            try BackupManager.apply(
                payload: payload,
                mode: mode,
                existingHabits: habits,
                in: modelContext
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            pendingImportPayload = nil
        } catch {
            alertMessage = "Could not apply backup: \(error.localizedDescription)"
        }
    }
}
