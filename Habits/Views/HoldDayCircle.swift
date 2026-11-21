import SwiftUI
import UIKit

/// Polish C hollow-ring numbered circle with an intentional ~0.21s split-second press-and-hold toggle.
struct HoldDayCircle: View {
    let dayNumber: Int
    let isToday: Bool
    let isCompleted: Bool
    let accentColor: Color
    let onToggle: () -> Void

    @State private var isPressing = false
    @State private var justPopped = false

    private let holdDuration: Double = 0.21

    var body: some View {
        ZStack {
            // Subtle halo charge while holding
            Circle()
                .stroke(accentColor.opacity(isPressing ? 0.42 : 0.0), lineWidth: 3)
                .frame(width: 32, height: 32)

            Circle()
                .fill(isCompleted ? accentColor : Color.clear)
                .frame(width: 27, height: 27)
                .overlay {
                    if !isCompleted {
                        Circle()
                            .strokeBorder(
                                isToday ? Color.primary.opacity(0.85) : Color(uiColor: .systemGray4),
                                lineWidth: isToday ? 1.5 : 1.1
                            )
                    }
                }
                .overlay {
                    Text("\(dayNumber)")
                        .font(.system(size: 11.5, weight: (isCompleted || isToday) ? .semibold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(
                            isCompleted
                                ? Color.white
                                : (isToday ? Color.primary : Color.secondary)
                        )
                }
                .scaleEffect(justPopped ? 1.12 : (isPressing ? 0.82 : 1.0))
                .animation(
                    isPressing
                        ? .easeOut(duration: holdDuration)
                        : .spring(response: 0.24, dampingFraction: 0.62),
                    value: isPressing
                )
                .animation(.spring(response: 0.22, dampingFraction: 0.58), value: justPopped)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 22) {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.impactOccurred(intensity: 0.85)
            onToggle()
            justPopped = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                justPopped = false
            }
        } onPressingChanged: { pressing in
            if pressing {
                UIImpactFeedbackGenerator(style: .rigid).prepare()
            }
            isPressing = pressing
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(dayNumber)")
        .accessibilityValue(isCompleted ? "Completed" : "Not completed")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onToggle()
        }
    }
}
