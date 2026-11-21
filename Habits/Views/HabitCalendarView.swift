import SwiftUI
import UIKit

/// Polish B: 2-column compact 6-month Monday-first calendar inside subtle rounded tiles (100% read-only).
struct HabitCalendarView: View {
    let habit: Habit
    let referenceDate: Date

    @State private var scrollController = BottomScrollController()

    private static let tileSurfaceColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0) // #141416
            : UIColor(red: 0.969, green: 0.969, blue: 0.980, alpha: 1.0) // #F7F7FA
    })

    private static let screenBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .systemBackground
    })

    var body: some View {
        let completedSet = Set(habit.completedDates)
        let streakLabel = HabitCalendar.streakText(for: habit, completedSet: completedSet, referenceDate: referenceDate)
        let monthProgress = HabitCalendar.currentMonthProgress(completedSet: completedSet, referenceDate: referenceDate)
        let shortMonth = HabitCalendar.currentMonthShortName(for: referenceDate)
        let months = HabitCalendar.monthsHistory(for: habit, completedSet: completedSet, referenceDate: referenceDate)
        let monthPairs: [MonthPair] = stride(from: 0, to: months.count, by: 2).map { index in
            MonthPair(
                left: months[index],
                right: index + 1 < months.count ? months[index + 1] : nil
            )
        }

        VStack(spacing: 10) {
            // Quiet 2-Metric Summary Bar
            HStack {
                HStack(spacing: 5) {
                    Text("Streak")
                        .foregroundStyle(.secondary)
                    Text(streakLabel)
                        .fontWeight(.bold)
                        .foregroundStyle(habit.accentColor)
                }

                Spacer()

                HStack(spacing: 5) {
                    Text(shortMonth)
                        .foregroundStyle(.secondary)
                    Text("\(monthProgress.done) / \(monthProgress.elapsed)")
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
            .font(.system(size: 13.5, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Self.tileSurfaceColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.horizontal, 16)

            // Scrollable 2-Column Chronological Grid (anchored at bottom so newest months show first)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(monthPairs) { pair in
                        HStack(alignment: .top, spacing: 10) {
                            MonthTileView(
                                month: pair.left,
                                accentColor: habit.accentColor,
                                tileBackground: Self.tileSurfaceColor
                            )

                            if let right = pair.right {
                                MonthTileView(
                                    month: right,
                                    accentColor: habit.accentColor,
                                    tileBackground: Self.tileSurfaceColor
                                )
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .background(
                    BottomScrollIntrospector(controller: scrollController)
                )
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.top, for: .alignment)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .tracking || newPhase == .interacting {
                    scrollController.markUserInteracted()
                }
            }
            .onScrollGeometryChange(for: ScrollBottomCheck.self) { geometry in
                let maxOffsetY = max(
                    -geometry.contentInsets.top,
                    geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height
                )
                let canScroll = (geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom) > geometry.containerSize.height + 0.5
                return ScrollBottomCheck(
                    contentHeight: Int((geometry.contentSize.height * 2).rounded()),
                    containerHeight: Int((geometry.containerSize.height * 2).rounded()),
                    topInset: Int((geometry.contentInsets.top * 2).rounded()),
                    bottomInset: Int((geometry.contentInsets.bottom * 2).rounded()),
                    isShortOfBottom: canScroll && (maxOffsetY - geometry.contentOffset.y > 0.5)
                )
            } action: { _, check in
                guard check.isShortOfBottom else { return }
                scrollController.pinToBottomIfNeeded()
                scrollController.scheduleAsyncPin()
            }
        }
        .padding(.top, 4)
        .background(Self.screenBackground.ignoresSafeArea())
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(habit.scheduleShortLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MonthPair: Identifiable {
    let left: MonthSummary
    let right: MonthSummary?
    var id: String { left.id }
}

private struct ScrollBottomCheck: Equatable {
    var contentHeight: Int
    var containerHeight: Int
    var topInset: Int
    var bottomInset: Int
    var isShortOfBottom: Bool
}

/// Keeps the backing `UIScrollView` pinned all the way to `maxOffsetY` (including `adjustedContentInset.bottom`
/// and navigation-bar height changes during push) until the user first touches/scrolls the calendar.
@MainActor
private final class BottomScrollController {
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private(set) var hasUserInteracted = false
    private var isAsyncPinScheduled = false
    private var lastGeometryKey: GeometryKey?
    private var attemptsForCurrentGeometry = 0

    private struct GeometryKey: Equatable {
        var contentHeight: Int
        var boundsHeight: Int
        var topInset: Int
        var bottomInset: Int
    }

    func attach(_ candidate: UIScrollView) {
        if scrollView !== candidate {
            observations.removeAll()
            scrollView = candidate

            if !hasUserInteracted {
                observations.append(
                    candidate.observe(\.contentSize, options: [.old, .new]) { [weak self] _, change in
                        guard change.oldValue != change.newValue else { return }
                        MainActor.assumeIsolated {
                            self?.pinToBottomIfNeeded()
                            self?.scheduleAsyncPin()
                        }
                    }
                )
                observations.append(
                    candidate.observe(\.bounds, options: [.old, .new]) { [weak self] _, change in
                        guard change.oldValue?.size != change.newValue?.size else { return }
                        MainActor.assumeIsolated {
                            self?.pinToBottomIfNeeded()
                            self?.scheduleAsyncPin()
                        }
                    }
                )
            }
        }
        pinToBottomIfNeeded()
        scheduleAsyncPin()
    }

    func markUserInteracted() {
        hasUserInteracted = true
        observations.removeAll()
    }

    func scheduleAsyncPin() {
        guard !hasUserInteracted, !isAsyncPinScheduled else { return }
        isAsyncPinScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isAsyncPinScheduled = false
            self.pinToBottomIfNeeded()
        }
    }

    func pinToBottomIfNeeded() {
        guard !hasUserInteracted, let scrollView else { return }
        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            markUserInteracted()
            return
        }
        guard scrollView.bounds.height > 0, scrollView.contentSize.height > 0 else { return }

        let insets = scrollView.adjustedContentInset
        let key = GeometryKey(
            contentHeight: Int((scrollView.contentSize.height * 2).rounded()),
            boundsHeight: Int((scrollView.bounds.height * 2).rounded()),
            topInset: Int((insets.top * 2).rounded()),
            bottomInset: Int((insets.bottom * 2).rounded())
        )
        if key != lastGeometryKey {
            lastGeometryKey = key
            attemptsForCurrentGeometry = 0
        }

        let maxOffsetY = max(
            -insets.top,
            scrollView.contentSize.height + insets.bottom - scrollView.bounds.height
        )
        guard maxOffsetY - scrollView.contentOffset.y > 0.5 else { return }
        guard attemptsForCurrentGeometry < 8 else { return }
        attemptsForCurrentGeometry += 1

        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: maxOffsetY),
            animated: false
        )
    }
}

private struct BottomScrollIntrospector: UIViewRepresentable {
    let controller: BottomScrollController

    func makeUIView(context: Context) -> IntrospectorView {
        let view = IntrospectorView()
        view.controller = controller
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: IntrospectorView, context: Context) {
        uiView.controller = controller
        uiView.attachIfNeeded()
    }

    final class IntrospectorView: UIView {
        var controller: BottomScrollController?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attachIfNeeded()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            controller?.pinToBottomIfNeeded()
            controller?.scheduleAsyncPin()
        }

        func attachIfNeeded() {
            guard let controller else { return }
            var current = superview
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    controller.attach(scrollView)
                    return
                }
                current = view.superview
            }
        }
    }
}

private struct MonthTileView: View, Equatable {
    let month: MonthSummary
    let accentColor: Color
    let tileBackground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Month Header
            HStack(alignment: .firstTextBaseline) {
                Text(month.shortTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(month.statsLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Monday–Sunday Header
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { col in
                    Text(HabitCalendar.mondayWeekdayHeaders[col])
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 13, maxHeight: 13)
                }
            }

            // Compact Numbered Circles Grid (uniform 6 rows for crisp horizontal alignment across pairs)
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let index = week * 7 + col
                            let dayNumber = index - month.leadingEmptyCount + 1
                            if dayNumber >= 1 && dayNumber <= month.daysInMonth {
                                dayCell(day: dayNumber)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 19, maxHeight: 19)
                            }
                        }
                    }
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(tileBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func dayCell(day: Int) -> some View {
        let isFuture = month.isCurrentMonth && (month.todayDay.map { day > $0 } ?? false)
        let isDone = !isFuture && month.completedDays.contains(day)
        let isTodayUnchecked = month.isCurrentMonth && (month.todayDay == day) && !isDone

        ZStack {
            if isDone {
                Circle()
                    .fill(accentColor)
            } else if isTodayUnchecked {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: 1.1)
            }

            Text("\(day)")
                .font(.system(size: 9.5, weight: (isDone || isTodayUnchecked) ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(
                    isDone
                        ? Color.white
                        : (isTodayUnchecked
                            ? Color.primary
                            : (isFuture ? Color.secondary.opacity(0.32) : Color.secondary))
                )
        }
        .frame(width: 19, height: 19)
    }
}
