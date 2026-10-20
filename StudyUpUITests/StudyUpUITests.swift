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

    private func attachScreenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
