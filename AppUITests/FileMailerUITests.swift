import XCTest

@MainActor
final class FileMailerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ screen: String, language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-" + screen]
        app.launchEnvironment["FILEMAILER_TEST_LANGUAGE"] = language
        app.launch()
        return app
    }

    func testOnboardingCanAdvanceWithoutAccount() {
        let app = launch("onboarding", language: "fr")
        XCTAssertTrue(app.staticTexts["Bienvenue dans FileMailer"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Continuer"].exists)
        app.terminate()
    }

    func testFrenchAndEnglishComposeUseSelectedAppLanguage() {
        for (language, title, subject, send) in [
            ("fr", "Nouveau message", "Objet", "Envoyer"),
            ("en", "New message", "Subject", "Send")
        ] {
            let app = launch("compose", language: language)
            XCTAssertTrue(app.windows[title].waitForExistence(timeout: 8))
            XCTAssertTrue(app.textFields["compose-subject"].exists && app.staticTexts[subject].exists)
            XCTAssertTrue(app.buttons[send].exists)
            XCTAssertFalse(app.buttons[send].isEnabled)
            XCTAssertTrue(app.popUpButtons["draft-language-picker"].exists)
            let attachment = XCTAttachment(screenshot: app.windows[title].screenshot())
            attachment.name = "Compose-" + language
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    func testChangingLanguageUpdatesExistingSettingsWindow() {
        let app = launch("settings", language: "en")
        let picker = app.popUpButtons["app-language-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertTrue(app.windows["General"].exists)
        picker.click()
        app.menuItems["Français"].click()
        XCTAssertTrue(app.windows["Général"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Langue de l’application"].exists)
        XCTAssertTrue(app.menuBars.menuBarItems["Édition"].waitForExistence(timeout: 4))
        picker.click()
        app.menuItems["English"].click()
        XCTAssertTrue(app.windows["General"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Application language"].exists)
        XCTAssertTrue(app.menuBars.menuBarItems["Edit"].waitForExistence(timeout: 4))
        app.terminate()
    }

    func testNativeEditingMenuFollowsAppLanguage() {
        for (language, menu, copy, undo) in [("fr", "Édition", "Copier", "Annuler"),
                                             ("en", "Edit", "Copy", "Undo")] {
            let app = launch("compose", language: language)
            XCTAssertTrue(app.textFields["compose-subject"].waitForExistence(timeout: 8))
            app.textFields["compose-subject"].click()
            let editing = app.menuBars.menuBarItems[menu]
            XCTAssertTrue(editing.waitForExistence(timeout: 8))
            editing.click()
            XCTAssertTrue(app.menuItems[copy].waitForExistence(timeout: 4))
            XCTAssertTrue(app.menuItems[undo].exists)
            let capture = XCTAttachment(screenshot: editing.menus.firstMatch.screenshot())
            capture.name = "Editing-menu-" + language
            capture.lifetime = .keepAlways
            add(capture)
            app.typeKey(.escape, modifierFlags: [])
            app.terminate()
        }
    }

    func testGoogleDisclosureAndRecipientEditorFollowEnglishAppLanguage() {
        let app = launch("settings", language: "en")
        XCTAssertTrue(app.windows["General"].waitForExistence(timeout: 8))
        app.staticTexts["Gmail accounts"].click()
        app.buttons["Add an account"].click()
        XCTAssertTrue(app.staticTexts["Before connecting Google"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Continue with Google"].isEnabled)
        let disclosure = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        disclosure.name = "Google-disclosure-en"
        disclosure.lifetime = .keepAlways
        add(disclosure)
        app.buttons["Cancel"].click()
        app.staticTexts["Recipients"].click()
        app.buttons["Add"].click()
        XCTAssertTrue(app.textFields["recipient-name"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Name"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        let recipient = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        recipient.name = "Recipient-en"
        recipient.lifetime = .keepAlways
        add(recipient)
        app.buttons["Cancel"].click()
        app.terminate()
    }

    func testJapaneseAndArabicSettingsRenderLocalizedLanguageControls() {
        for (language, label) in [("ja", "アプリの言語"), ("ar", "لغة التطبيق")] {
            let app = launch("settings", language: language)
            XCTAssertTrue(app.popUpButtons["app-language-picker"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts[label].exists, app.debugDescription)
            let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            attachment.name = "Settings-" + language
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
