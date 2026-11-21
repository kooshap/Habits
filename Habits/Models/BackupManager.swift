import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HabitBackupEntry: Codable, Sendable {
    var id: UUID
    var name: String
    var colorHex: String
    var targetPerWeek: Int
    var sortOrder: Int
    var createdAt: Date
    var completedDates: [String]
}

struct HabitsBackupPayload: Codable, Sendable {
    var version: Int = 1
    var exportedAt: Date
    var habits: [HabitBackupEntry]
}

struct HabitsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(payload: HabitsBackupPayload) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.data = (try? encoder.encode(payload)) ?? Data("{}".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupImportMode {
    case merge
    case replaceAll
}

enum BackupManager {
    static func defaultFilename(for date: Date = Date()) -> String {
        "habits-backup-\(HabitCalendar.dateKey(for: date))"
    }

    static func makeDocument(from habits: [Habit]) -> HabitsBackupDocument {
        let sorted = habits.sorted { $0.sortOrder < $1.sortOrder }
        let entries = sorted.enumerated().map { index, h in
            HabitBackupEntry(
                id: h.id,
                name: h.name,
                colorHex: h.colorHex,
                targetPerWeek: h.targetPerWeek,
                sortOrder: index,
                createdAt: h.createdAt,
                completedDates: h.completedDates.sorted()
            )
        }
        let payload = HabitsBackupPayload(exportedAt: Date(), habits: entries)
        return HabitsBackupDocument(payload: payload)
    }

    static func decodePayload(from url: URL) throws -> HabitsBackupPayload {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HabitsBackupPayload.self, from: data)
    }

    @MainActor
    static func apply(
        payload: HabitsBackupPayload,
        mode: BackupImportMode,
        existingHabits: [Habit],
        in context: ModelContext
    ) throws {
        let validDatePattern = #"^\d{4}-\d{2}-\d{2}$"#
        func sanitizeDates(_ raw: [String]) -> [String] {
            Array(Set(raw.filter { $0.range(of: validDatePattern, options: .regularExpression) != nil })).sorted()
        }

        switch mode {
        case .replaceAll:
            for old in existingHabits {
                context.delete(old)
            }
            let sortedIncoming = payload.habits.sorted { $0.sortOrder < $1.sortOrder }
            for (idx, item) in sortedIncoming.enumerated() {
                let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { continue }
                let habit = Habit(
                    id: item.id,
                    name: trimmedName,
                    colorHex: item.colorHex,
                    targetPerWeek: item.targetPerWeek,
                    sortOrder: idx,
                    createdAt: item.createdAt,
                    completedDates: sanitizeDates(item.completedDates)
                )
                context.insert(habit)
            }

        case .merge:
            var byID = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })
            var nextOrder = (existingHabits.map(\.sortOrder).max() ?? -1) + 1
            let sortedIncoming = payload.habits.sorted { $0.sortOrder < $1.sortOrder }

            for item in sortedIncoming {
                let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { continue }
                let cleanDates = sanitizeDates(item.completedDates)

                if let match = byID[item.id] ?? existingHabits.first(where: {
                    $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) {
                    let merged = Set(match.completedDates).union(cleanDates).sorted()
                    match.completedDates = merged
                } else {
                    let habit = Habit(
                        id: item.id,
                        name: trimmedName,
                        colorHex: item.colorHex,
                        targetPerWeek: item.targetPerWeek,
                        sortOrder: nextOrder,
                        createdAt: item.createdAt,
                        completedDates: cleanDates
                    )
                    context.insert(habit)
                    byID[habit.id] = habit
                    nextOrder += 1
                }
            }
        }

        try context.save()
    }
}
