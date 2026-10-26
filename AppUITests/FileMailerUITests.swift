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

    func testStoreScreenshotsShowActualEnglishInterface() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-compose"]
        app.launchEnvironment["FILEMAILER_TEST_LANGUAGE"] = "en"
        app.launchEnvironment["FILEMAILER_TEST_SCREENSHOT"] = "1"
        app.launch()
        let window = app.windows["New message"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let sample = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectBrief.txt")
        try! "Project brief\n\nReview the next milestone and share the updated schedule.\n"
            .write(to: sample, atomically: true, encoding: .utf8)
        app.buttons["add-attachment"].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 4))
        path.typeText(sample.path)
        app.typeKey(.return, modifierFlags: [])
        let open = app.buttons["OKButton"]
        XCTAssertTrue(open.waitForExistence(timeout: 4))
        open.click()
        XCTAssertTrue(app.buttons["Remove ProjectBrief.txt"].waitForExistence(timeout: 8))
        let address = app.textFields["recipient-address-input"]
        address.click()
        address.typeText("alex@example.com")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Delete alex@example.com"].exists)
        XCTAssertEqual(address.value as? String, "")
        let subject = app.textFields["compose-subject"]
        subject.click()
        subject.typeText("Project brief")
        XCTAssertEqual(address.value as? String, "")
        let body = app.textViews["compose-body"]
        XCTAssertTrue(body.exists)
        body.click()
        body.typeText("Hello Alex,\n\nHere is the project brief for our next meeting.\n\nBest regards")
        XCTAssertEqual(window.frame.width, 1280, accuracy: 1)
        XCTAssertEqual(window.frame.height, 800, accuracy: 1)
        let compose = XCTAttachment(screenshot: window.screenshot())
        compose.name = "AppStore-01-Compose-en"
        compose.lifetime = .keepAlways
        add(compose)
        app.terminate()

        app.launchArguments = ["--ui-testing-settings"]
        app.launch()
        XCTAssertTrue(app.windows["General"].waitForExistence(timeout: 8))
        app.activate()
        app.staticTexts["General"].firstMatch.click()
        let settings = XCTAttachment(screenshot: app.windows["General"].screenshot())
        settings.name = "AppStore-02-Settings-en"
        settings.lifetime = .keepAlways
        add(settings)
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
