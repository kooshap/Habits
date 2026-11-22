import SwiftUI

/// Watch-sized hollow-ring / solid-checkmark circle that animates in sync with the row's ~0.21s press-and-hold gesture.
struct WatchHoldCheckCircle: View {
    let isCompleted: Bool
    let accentColor: Color
    let isPressing: Bool
    let justPopped: Bool

    private let holdDuration: Double = 0.21

    var body: some View {
        ZStack {
            // Subtle accent halo ring charging while holding (matches iOS HoldDayCircle)
            Circle()
                .stroke(accentColor.opacity(isPressing ? 0.45 : 0.0), lineWidth: 2.6)
                .frame(width: 31, height: 31)
                .scaleEffect(isPressing ? 1.06 : 0.88)

            Circle()
                .fill(isCompleted ? accentColor : Color.clear)
                .frame(width: 25, height: 25)
                .overlay {
                    if !isCompleted {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.82), lineWidth: 1.6)
                    }
                }
                .overlay {
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .scaleEffect(justPopped ? 1.14 : (isPressing ? 0.82 : 1.0))
        }
        .animation(
            isPressing
                ? .easeOut(duration: holdDuration)
                : .spring(response: 0.24, dampingFraction: 0.62),
            value: isPressing
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.58), value: justPopped)
    }
}
