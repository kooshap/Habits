import XCTest

final class HabitsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateHabitHoldToCompleteAndOpenCalendar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        // 1. Starts in empty state
        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 5))

        // 2. Open New Habit sheet, configure a 3×/wk habit, and save
        app.buttons["New Habit"].tap()

        let nameField = app.textFields["e.g., Read 20 pages"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Read 20 pages")

        app.buttons["3×"].tap()
        app.buttons["Save"].tap()

        // 3. Habit row appears on Home screen with 0/3 weekly progress
        let progressZero = app.staticTexts["0/3 wk"]
        XCTAssertTrue(progressZero.waitForExistence(timeout: 3))

        // 4. Press-and-hold today's circle (>= 0.21s) to complete today
        let todayDay = Calendar.current.component(.day, from: Date())
        let todayCircle = app.buttons["Day \(todayDay)"]
        XCTAssertTrue(todayCircle.exists)
        XCTAssertEqual(todayCircle.value as? String, "Not completed")

        todayCircle.press(forDuration: 0.35)

        let progressOne = app.staticTexts["1/3 wk"]
        XCTAssertTrue(progressOne.waitForExistence(timeout: 3))
        XCTAssertEqual(todayCircle.value as? String, "Completed")

        // 5. Tap habit title to push read-only Calendar screen and verify summary metrics
        app.staticTexts["Read 20 pages"].tap()

        XCTAssertTrue(app.navigationBars["Read 20 pages"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["3×/wk"].exists)
        XCTAssertTrue(app.staticTexts["Streak"].exists)
    }
}
