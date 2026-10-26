import XCTest

final class StudyUpUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches with an empty in-memory library. New cards only start when today's reminders have room,
    /// so these give reminders all day with plenty of room: tests don't then depend on the time of day,
    /// or on the simulator's own settings (shared with manual use). Launch arguments don't persist.
    private func launch(_ app: XCUIApplication, _ extra: [String] = []) {
        app.launchArguments = [
            "-inMemoryStore", "-reminderStartMinute", "0", "-reminderEndMinute", "1439",
            "-remindersPerDay", "20", "-cardsPerReminder", "10", "-newCardsPerDay", "10",
        ] + extra
        app.launch()
    }

    @MainActor
    func testStudyFlowWithSampleCards() throws {
        let app = XCUIApplication()
        launch(app)
        attachScreenshot("1-empty", app)

        app.buttons["Add Sample Cards"].tap()
        let topic = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'OS Fundamentals'")).firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        attachScreenshot("2-home", app)

        topic.tap()
        let subfolder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Memory'")).firstMatch
        XCTAssertTrue(subfolder.waitForExistence(timeout: 5))
        subfolder.tap()
        XCTAssertTrue(app.staticTexts["What is a page fault?"].waitForExistence(timeout: 5))
        attachScreenshot("3-folder", app)

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Study now'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Show Answer"].waitForExistence(timeout: 5))
        attachScreenshot("4-question", app)

        app.buttons["Show Answer"].tap()
        let right = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Right'")).firstMatch
        XCTAssertTrue(right.waitForExistence(timeout: 5))
        attachScreenshot("5-answer", app)

        right.tap()
        XCTAssertTrue(app.buttons["Show Answer"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTappingReminderOpensQuickReview() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        launch(app)
        app.buttons["Add Sample Cards"].tap()

        // Grant notification permission the first time this simulator runs the app.
        let turnOn = app.buttons["Turn On Study Reminders"]
        if turnOn.waitForExistence(timeout: 3) {
            turnOn.tap()
            let allow = springboard.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
        }
        let today = app.buttons.matching(NSPredicate(format: "label CONTAINS 'next at'")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        attachScreenshot("6-home-with-reminders", app)

        app.buttons["Settings"].tap()
        attachScreenshot("7-settings", app)
        app.buttons["Send a Test Reminder"].tap()

        // The test reminder shows the first sample card's question.
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'process and a thread'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        attachScreenshot("8-banner", springboard)
        banner.tap()

        XCTAssertTrue(app.navigationBars["Quick Review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What is the difference between a process and a thread?"].exists)
        attachScreenshot("9-quick-review", app)
    }

    @MainActor
    func testGradingFromReminderRecordsReview() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        launch(app)
        app.buttons["Add Sample Cards"].tap()
        allowNotificationsIfAsked(app, springboard)

        let studyNow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Study now'")).firstMatch
        XCTAssertTrue(studyNow.waitForExistence(timeout: 5))
        XCTAssertTrue(studyNow.label.contains("7 new"), studyNow.label)

        app.buttons["Settings"].tap()
        app.buttons["Send a Test Reminder"].tap()
        app.buttons["Done"].tap()

        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'process and a thread'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        banner.press(forDuration: 1.0)
        // The content extension labels each button with where it sends the card next.
        let right = springboard.buttons["Right · in a few hours"]
        XCTAssertTrue(right.waitForExistence(timeout: 5))
        attachScreenshot("10-expanded-reminder", springboard)
        right.tap()

        // The card moved into learning (a check in a few hours), so it's no longer a new card.
        let updated = NSPredicate(format: "label CONTAINS '6 new'")
        expectation(for: updated, evaluatedWith: studyNow)
        waitForExpectations(timeout: 10)
    }

    @MainActor
    func testRichCardShowsCodeAndImage() throws {
        let app = XCUIApplication()
        launch(app, ["-richCardSample"])
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Study now'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Show Answer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["uint64_t cr3 = read_cr3(); // page table root"].exists)
        app.buttons["Show Answer"].tap()
        let image = app.buttons["Image"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        app.swipeUp()
        attachScreenshot("13-rich-card", app)
        image.tap()
        XCTAssertTrue(app.buttons["Close Image"].waitForExistence(timeout: 5))
        attachScreenshot("14-zoomed-image", app)
        app.buttons["Close Image"].tap()
        XCTAssertTrue(app.buttons["Image"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTodayScheduleListsPlannedReminders() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        launch(app)
        app.buttons["Add Sample Cards"].tap()
        allowNotificationsIfAsked(app, springboard)

        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Today: 7 cards left'")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        attachScreenshot("15-home-today", app)
        today.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        attachScreenshot("16-today-schedule", app)

        // The first upcoming reminder lists its cards and can be studied early. ("1 card" or "3 cards",
        // depending on the simulator's settings.)
        let reminder = app.buttons.matching(NSPredicate(format: "label MATCHES '.*[0-9]+ cards?.*'")).firstMatch
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        reminder.tap()
        XCTAssertTrue(app.buttons["Study These Now"].waitForExistence(timeout: 5))
        attachScreenshot("17-reminder-cards", app)
        app.buttons["Study These Now"].tap()
        XCTAssertTrue(app.navigationBars["Quick Review"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSyncScreenShowsPairingSteps() throws {
        let app = XCUIApplication()
        launch(app)
        app.buttons["Settings"].tap()
        attachScreenshot("11-settings-with-sync", app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sync with Mac'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Sync with Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pair"].exists)
        XCTAssertFalse(app.buttons["Pair"].isEnabled)
        attachScreenshot("12-sync-pairing", app)
    }

    private func allowNotificationsIfAsked(_ app: XCUIApplication, _ springboard: XCUIApplication) {
        let turnOn = app.buttons["Turn On Study Reminders"]
        if turnOn.waitForExistence(timeout: 3) {
            turnOn.tap()
            let allow = springboard.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
        }
    }

    private func attachScreenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
