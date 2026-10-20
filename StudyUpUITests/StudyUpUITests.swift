import XCTest

final class StudyUpUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStudyFlowWithSampleCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()
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
        app.launchArguments = ["-inMemoryStore"]
        app.launch()
        app.buttons["Add Sample Cards"].tap()

        // Grant notification permission the first time this simulator runs the app.
        let turnOn = app.buttons["Turn On Study Reminders"]
        if turnOn.waitForExistence(timeout: 3) {
            turnOn.tap()
            let allow = springboard.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Next reminder'")).firstMatch.waitForExistence(timeout: 5))
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
        app.launchArguments = ["-inMemoryStore"]
        app.launch()
        app.buttons["Add Sample Cards"].tap()
        allowNotificationsIfAsked(app, springboard)

        let studyNow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Study now'")).firstMatch
        XCTAssertTrue(studyNow.waitForExistence(timeout: 5))
        XCTAssertFalse(studyNow.label.contains("due"))

        app.buttons["Settings"].tap()
        app.buttons["Send a Test Reminder"].tap()
        app.buttons["Done"].tap()

        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'process and a thread'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        banner.press(forDuration: 1.0)
        let right = springboard.buttons["Right"]
        XCTAssertTrue(right.waitForExistence(timeout: 5))
        attachScreenshot("10-expanded-reminder", springboard)
        right.tap()

        // The card moved into learning (due again in 10 minutes), so it now counts as due.
        let updated = NSPredicate(format: "label CONTAINS '1 due'")
        expectation(for: updated, evaluatedWith: studyNow)
        waitForExpectations(timeout: 10)
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
