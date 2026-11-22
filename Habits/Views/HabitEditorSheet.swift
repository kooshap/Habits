import SwiftData
import SwiftUI

struct HabitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let habitToEdit: Habit?
    let nextSortOrder: Int

    @State private var name: String
    @State private var selectedHex: String
    @State private var targetPerWeek: Int
    @FocusState private var isNameFocused: Bool

    init(habitToEdit: Habit? = nil, nextSortOrder: Int = 0) {
        self.habitToEdit = habitToEdit
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: habitToEdit?.name ?? "")
        _selectedHex = State(initialValue: habitToEdit?.colorHex ?? HabitPalette.defaultHex)
        _targetPerWeek = State(initialValue: habitToEdit?.targetPerWeek ?? 7)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeColor: Color {
        HabitPalette.color(for: selectedHex)
    }

    private var scheduleDescription: String {
        if targetPerWeek >= 7 {
            return "Every day of the week"
        } else if targetPerWeek == 1 {
            return "Once per week on any day"
        } else {
            return "\(targetPerWeek) times per week on any days"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Name
                VStack(alignment: .leading, spacing: 7) {
                    Text("NAME")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    TextField("e.g., Read 20 pages", text: $name)
                        .focused($isNameFocused)
                        .font(.system(size: 16, weight: .medium))
                        .submitLabel(.done)
                        .onSubmit {
                            if !trimmedName.isEmpty {
                                save()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(
                            Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                }

                // Curated 8 Non-Green Color Swatches
                VStack(alignment: .leading, spacing: 9) {
                    Text("COLOR")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 0) {
                        ForEach(HabitPalette.swatches) { swatch in
                            let isSelected = swatch.hex.caseInsensitiveCompare(selectedHex) == .orderedSame
                            let swatchColor = HabitPalette.color(for: swatch.hex)

                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                selectedHex = swatch.hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(swatchColor)
                                        .frame(width: 28, height: 28)

                                    if isSelected {
                                        Circle()
                                            .strokeBorder(swatchColor, lineWidth: 2)
                                            .frame(width: 36, height: 36)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 38)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(swatch.name)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                // Schedule (Mon–Sun)
                VStack(alignment: .leading, spacing: 7) {
                    Text("SCHEDULE (MON–SUN)")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        scheduleSegment(title: "Daily", value: 7, isWide: true)
                        ForEach(1...6, id: \.self) { count in
                            scheduleSegment(title: "\(count)×", value: count, isWide: false)
                        }
                    }
                    .padding(4)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                    Text(scheduleDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .navigationTitle(habitToEdit == nil ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(trimmedName.isEmpty ? Color.secondary : activeColor)
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                if habitToEdit == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isNameFocused = true
                    }
                }
            }
        }
        .presentationDetents([.height(345), .medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func scheduleSegment(title: String, value: Int, isWide: Bool) -> some View {
        let isSelected = (targetPerWeek == value)
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.14)) {
                targetPerWeek = value
            }
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(minWidth: isWide ? 48 : 30)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let existing = habitToEdit {
            existing.name = trimmedName
            existing.colorHex = selectedHex
            existing.targetPerWeek = targetPerWeek
        } else {
            let newHabit = Habit(
                name: trimmedName,
                colorHex: selectedHex,
                targetPerWeek: targetPerWeek,
                sortOrder: nextSortOrder
            )
            modelContext.insert(newHabit)
        }
        try? modelContext.save()
        HabitWidgetSync.sync(from: modelContext)
        dismiss()
    }
}
