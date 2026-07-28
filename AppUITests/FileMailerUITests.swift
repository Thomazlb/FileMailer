import XCTest

@MainActor
final class FileMailerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingCanAdvanceWithoutAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-onboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Bienvenue dans FileMailer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continuer"].exists)
    }

    func testManualComposeExposesEditableReviewAndDisabledSend() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-compose"]
        app.launch()

        XCTAssertTrue(app.windows["Nouveau message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Objet"].exists)
        XCTAssertTrue(app.buttons["Envoyer"].exists)
        XCTAssertFalse(app.buttons["Envoyer"].isEnabled)
    }
}
