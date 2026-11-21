import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Habits

@Suite("Habit Model & Palette")
struct HabitModelTests {

    @Test("Clamps targetPerWeek into 1...7 on initialization", arguments: [
        (-10, 1),
        (0, 1),
        (1, 1),
        (3, 3),
        (6, 6),
        (7, 7),
        (8, 7),
        (99, 7)
    ])
    func clampsTargetPerWeek(raw: Int, expected: Int) {
        let habit = Habit(name: "Exercise", targetPerWeek: raw)
        #expect(habit.targetPerWeek == expected)
    }

    @Test("Deduplicates and sorts completedDates on initialization")
    func normalizesCompletedDatesOnInit() {
        let habit = Habit(
            name: "Read",
            completedDates: ["2026-11-20", "2026-11-18", "2026-11-20", "2026-11-19"]
        )
        #expect(habit.completedDates == ["2026-11-18", "2026-11-19", "2026-11-20"])
    }

    @Test("Default initializer sets expected defaults")
    func defaultInitValues() {
        let habit = Habit(name: "Meditate")
        #expect(habit.colorHex == HabitPalette.defaultHex)
        #expect(habit.targetPerWeek == 7)
        #expect(habit.isDaily)
        #expect(habit.sortOrder == 0)
        #expect(habit.completedDates.isEmpty)
        #expect(habit.scheduleShortLabel == "Daily")
    }

    @Test("isDaily and scheduleShortLabel reflect weekly schedule")
    func scheduleLabels() {
        for count in 1...6 {
            let weekly = Habit(name: "Gym", targetPerWeek: count)
            #expect(!weekly.isDaily)
            #expect(weekly.scheduleShortLabel == "\(count)×/wk")
        }

        let daily = Habit(name: "Stretch", targetPerWeek: 7)
        #expect(daily.isDaily)
        #expect(daily.scheduleShortLabel == "Daily")
    }

    @Test("toggle inserts, removes, and keeps completedDates sorted")
    func toggleDateKey() {
        let habit = Habit(name: "Journal", completedDates: ["2026-11-19"])
        #expect(habit.isCompleted(on: "2026-11-19"))
        #expect(!habit.isCompleted(on: "2026-11-17"))

        // Insert earlier date -> returns true and maintains ascending order
        let addedEarlier = habit.toggle(dateKey: "2026-11-17")
        #expect(addedEarlier == true)
        #expect(habit.isCompleted(on: "2026-11-17"))
        #expect(habit.completedDates == ["2026-11-17", "2026-11-19"])

        // Insert later date -> returns true
        let addedLater = habit.toggle(dateKey: "2026-11-21")
        #expect(addedLater == true)
        #expect(habit.completedDates == ["2026-11-17", "2026-11-19", "2026-11-21"])

        // Toggle existing date off -> returns false and removes key
        let removedMiddle = habit.toggle(dateKey: "2026-11-19")
        #expect(removedMiddle == false)
        #expect(!habit.isCompleted(on: "2026-11-19"))
        #expect(habit.completedDates == ["2026-11-17", "2026-11-21"])
    }

    @Test("Curated palette has 8 unique swatches and valid hex codes")
    func paletteInvariants() {
        #expect(HabitPalette.swatches.count == 8)
        #expect(HabitPalette.defaultHex == "#2563EB")

        let uniqueIDs = Set(HabitPalette.swatches.map(\.id))
        #expect(uniqueIDs.count == 8)

        for swatch in HabitPalette.swatches {
            #expect(!swatch.name.isEmpty)
            #expect(swatch.hex.hasPrefix("#"))
            #expect(swatch.hex.count == 7)
        }
    }

    @Test("Color(hexString:) parses valid 6-digit hexes and falls back cleanly on invalid strings")
    func colorHexParsing() {
        func rgb(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b)
        }

        // Pure coral #FF8000 (with lowercase + whitespace)
        let parsed = rgb(HabitPalette.color(for: "  #ff8000 \n"))
        #expect(abs(parsed.r - 1.0) < 0.01)
        #expect(abs(parsed.g - (128.0 / 255.0)) < 0.01)
        #expect(abs(parsed.b - 0.0) < 0.01)

        // Malformed hex strings fall back to default Cobalt (~0.15, 0.39, 0.92)
        for invalid in ["", "#123", "#12345678"] {
            let fallback = rgb(Color(hexString: invalid))
            #expect(abs(fallback.r - 0.15) < 0.01)
            #expect(abs(fallback.g - 0.39) < 0.01)
            #expect(abs(fallback.b - 0.92) < 0.01)
        }
    }

    @Test("Slate swatch adapts dynamically between light and dark interface styles")
    func slateDynamicColorAdaptation() {
        let uiColor = UIColor(HabitPalette.color(for: "#52525b"))
        let light = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))

        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        light.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        dark.getRed(&dr, green: &dg, blue: &db, alpha: &da)

        #expect(dr > lr)
        #expect(dg > lg)
        #expect(db > lb)
    }
}
