import SwiftUI
import WidgetKit

struct HabitRingEntry: TimelineEntry {
    let date: Date
    let summary: HabitWidgetSummary
}

struct HabitRingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitRingEntry {
        HabitRingEntry(date: Date(), summary: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitRingEntry) -> Void) {
        let now = Date()
        if let snapshot = HabitWidgetSnapshotStore.load() {
            let liveSummary = HabitWidgetSummary.compute(from: snapshot.habits, referenceDate: now)
            if context.isPreview && !liveSummary.hasHabits {
                completion(HabitRingEntry(date: now, summary: .preview))
            } else {
                completion(HabitRingEntry(date: now, summary: liveSummary))
            }
        } else {
            completion(HabitRingEntry(date: now, summary: context.isPreview ? .preview : .empty))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitRingEntry>) -> Void) {
        let now = Date()
        let snapshot = HabitWidgetSnapshotStore.load()
        let schedule = HabitWidgetSummary.timelineSchedule(from: snapshot, now: now)
        let entries = schedule.entries.map {
            HabitRingEntry(date: $0.date, summary: $0.summary)
        }
        completion(Timeline(entries: entries, policy: .after(schedule.reloadAfter)))
    }
}

struct HabitProgressRingEntryView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let summary: HabitWidgetSummary

    private let lineWidth: CGFloat = 6

    private var trackColor: Color {
        Color.primary.opacity(renderingMode == .fullColor ? 0.18 : 0.22)
    }

    private var progressColor: Color {
        if renderingMode == .fullColor {
            return Color(.sRGB, red: 0.15, green: 0.39, blue: 0.92, opacity: 1.0)
        }
        return Color.primary
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            if summary.completed > 0 {
                Circle()
                    .trim(from: 0, to: summary.progress)
                    .stroke(
                        progressColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }

            centerLabel
                .padding(.horizontal, 8)
        }
        .padding(lineWidth / 2)
        .containerBackground(.clear, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Habits today")
        .accessibilityValue(summary.accessibilityValueText)
    }

    @ViewBuilder
    private var centerLabel: some View {
        if summary.isAllDone {
            VStack(spacing: 1) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.primary)
                    .widgetAccentable()

                Text("\(summary.completed)/\(summary.total)")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else if summary.hasHabits {
            VStack(spacing: 0.5) {
                HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                    Text("\(summary.completed)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Text("/\(summary.total)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Text("TODAY")
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 0.5) {
                Text("0")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text("HABITS")
                    .font(.system(size: 7, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@main
struct HabitsProgressRingWidget: Widget {
    let kind: String = HabitWidgetConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitRingTimelineProvider()) { entry in
            HabitProgressRingEntryView(summary: entry.summary)
        }
        .configurationDisplayName("Today's Progress")
        .description("See how many habits you've completed today.")
        .supportedFamilies([.accessoryCircular])
    }
}

#Preview("R1 · Partial (4/7)", as: .accessoryCircular) {
    HabitsProgressRingWidget()
} timeline: {
    HabitRingEntry(date: .now, summary: HabitWidgetSummary(completed: 0, total: 7))
    HabitRingEntry(date: .now, summary: HabitWidgetSummary(completed: 4, total: 7))
    HabitRingEntry(date: .now, summary: HabitWidgetSummary(completed: 7, total: 7))
}
