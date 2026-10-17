//
//  Rydr_DriverUITests.swift
//  Rydr DriverUITests
//
//  Created by Khris Nunnally on 10/9/25.
//

import XCTest

final class Rydr_DriverUITests: XCTestCase {
    @MainActor
    func testPayoutMethodsNavigationAndRefreshRecovery() {
        let app = XCUIApplication()
        app.launchArguments = ["-DriverPayoutMethodsUITest", "-MethodsError"]
        app.launch()
        XCTAssertTrue(app.staticTexts["payoutMethodsError"].waitForExistence(timeout: 15))
        app.buttons["refreshPayoutMethods"].tap()
        XCTAssertTrue(app.buttons["payoutMethod_ba_fixture"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["payoutMethodsError"].exists)
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "rydr-payout-methods"; proof.lifetime = .keepAlways; add(proof)
        for id in ["addPayoutBank", "addPayoutCard"] {
            let button = app.buttons[id]
            for _ in 0..<4 where !button.isHittable { app.swipeUp() }
            button.tap()
            let save = app.buttons["saveNativePayoutMethod"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            XCTAssertFalse(save.isEnabled)
            if id == "addPayoutBank" {
                XCTAssertTrue(app.textFields["payoutBankHolder"].exists)
                XCTAssertTrue(app.textFields["payoutBankRouting"].exists)
                XCTAssertTrue(app.secureTextFields["payoutBankConfirm"].exists)
            } else {
                XCTAssertTrue(app.otherElements["payoutDebitCardFields"].exists || app.textFields.count > 0)
            }
            XCTAssertFalse(app.staticTexts["Industry"].exists)
            XCTAssertFalse(app.staticTexts["Your website"].exists)
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
        }
        app.swipeDown()
        app.buttons["payoutMethod_ba_fixture"].tap()
        XCTAssertTrue(app.staticTexts["This is your default destination. Choose another default before removing it."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Remove payout method"].exists)
        app.buttons["Add a replacement"].tap()
        XCTAssertTrue(app.buttons["saveNativePayoutMethod"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["payoutMethodsDone"].exists)

    }

    @MainActor
    func testOnboardingResumeAfterRelaunchAndFailClosed() {
        for scenario in ["-ResumeAddress", "-ResumePayouts", "-ResumeUnavailable", "-ResumeComplete"] {
            let app = XCUIApplication()
            app.launchArguments = ["-DriverOnboardingResumeUITest", scenario]
            for _ in 0..<2 {
                app.launch()
                if scenario == "-ResumeComplete" { XCTAssertTrue(app.staticTexts["driverDashboardFixture"].waitForExistence(timeout: 15)) }
                else if scenario == "-ResumeUnavailable" {
                    XCTAssertTrue(app.staticTexts["driverOnboardingError"].waitForExistence(timeout: 15))
                    XCTAssertFalse(app.staticTexts["driverDashboardFixture"].exists)
                } else if scenario == "-ResumePayouts" {
                    XCTAssertTrue(app.buttons["Set Up Payouts"].waitForExistence(timeout: 15))
                    XCTAssertFalse(app.staticTexts["driverDashboardFixture"].exists)
                } else {
                    XCTAssertTrue(app.textFields["Street Address"].waitForExistence(timeout: 15))
                    XCTAssertEqual(app.textFields["Street Address"].value as? String, "1 Main St")
                    let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "onboarding-resumed-address"; proof.lifetime = .keepAlways; add(proof)
                    XCTAssertFalse(app.staticTexts["driverDashboardFixture"].exists)
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testPayoutPlatformRestrictionShowsPersistentUsefulError() {
        let app = XCUIApplication()
        app.launchArguments = ["-DriverPayoutErrorUITest"]
        app.launch()
        let setup = app.buttons["Set Up Payouts"]
        XCTAssertTrue(setup.waitForExistence(timeout: 15))
        for _ in 0..<8 where !setup.isHittable { app.swipeUp() }
        setup.tap()
        let message = app.staticTexts["payoutSetupMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("Rydr support must resolve a Stripe account restriction"))
        XCTAssertFalse(message.label.contains("check your connection"))
        XCTAssertTrue(setup.isEnabled)
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "payout-platform-restriction"; proof.lifetime = .keepAlways; add(proof)
    }

    @MainActor
    func testIdentityPendingAndURLRecoveryContinueWithoutVerification() {
        for scenario in ["-IdentityProcessing", "-IdentityURLFailure", "-IdentityResume", "-IdentityVerified"] {
            let app = XCUIApplication()
            app.launchArguments = ["-DriverIdentityUITest", scenario]
            app.launch()
            let next = app.buttons["identityContinue"]
            XCTAssertTrue(next.waitForExistence(timeout: 15))
            if scenario != "-IdentityResume" {
                XCTAssertFalse(next.isEnabled)
                let start = app.buttons["Start Verification"]
                XCTAssertTrue(start.waitForExistence(timeout: 5))
                start.tap()
            }
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            let enabled = NSPredicate(format: "enabled == true")
            expectation(for: enabled, evaluatedWith: next)
            waitForExpectations(timeout: 10)
            if scenario != "-IdentityVerified" { XCTAssertTrue(app.staticTexts["identityPendingNotice"].exists) }
            for _ in 0..<4 where !next.isHittable { app.swipeUp() }
            let pendingProof = XCTAttachment(screenshot: app.screenshot()); pendingProof.name = scenario + "-before-continue"; pendingProof.lifetime = .keepAlways; add(pendingProof)
            next.tap()
            XCTAssertTrue(app.staticTexts["identityNextStep"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["identityVerificationValue"].label, scenario == "-IdentityVerified" ? "verified" : "unverified")
            let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = scenario; proof.lifetime = .keepAlways; add(proof)
            app.terminate()
        }
    }

    @MainActor
    func testIdentityErrorsAndUnconfirmedSubmissionRemainBlocked() {
        for scenario in ["-IdentityRequiresInput", "-IdentityUnavailable", "-IdentityCanceled", "-IdentityUnconfirmed"] {
            let app = XCUIApplication()
            app.launchArguments = ["-DriverIdentityUITest", scenario]
            app.launch()
            let next = app.buttons["identityContinue"]
            XCTAssertTrue(next.waitForExistence(timeout: 15))
            let start = app.buttons["Start Verification"]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            start.tap()
            let expectedMessage: String
            switch scenario {
            case "-IdentityRequiresInput": expectedMessage = "Stripe needs more information. Complete identity verification to continue."
            case "-IdentityCanceled": expectedMessage = "Verification was canceled. Please complete identity verification to continue."
            case "-IdentityUnconfirmed": expectedMessage = "Waiting for submission confirmation. Check verification again before continuing."
            default: expectedMessage = URLError(.notConnectedToInternet).localizedDescription
            }
            let errorLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expectedMessage)).firstMatch
            XCTAssertTrue(errorLabel.waitForExistence(timeout: 10))
            XCTAssertFalse(next.isEnabled)
            XCTAssertFalse(app.staticTexts["identityNextStep"].exists)
            XCTAssertFalse(app.staticTexts["identityPendingNotice"].exists)
            let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = scenario; proof.lifetime = .keepAlways; add(proof)
            app.terminate()
        }
    }

    @MainActor
    func testDocumentPhotoLibrarySelectionAndConfirmation() {
        for vehicle in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = vehicle ? ["-DriverDocumentUITest", "-DocumentVehicle"] : ["-DriverDocumentUITest"]
            app.launch()
            for identifier in vehicle ? ["registration", "insurance"] : ["licenseFront", "licenseBack"] {
                let source = app.buttons[identifier + "Source"]
                XCTAssertTrue(source.waitForExistence(timeout: 15))
                for _ in 0..<8 where !source.isHittable { app.swipeUp() }
                source.tap()
                XCTAssertTrue(app.buttons["Take Photo"].exists)
                let library = app.buttons["Choose from Photo Library"]
                XCTAssertTrue(library.waitForExistence(timeout: 5))
                library.tap()
                let photo = app.images.matching(NSPredicate(format: "label CONTAINS[c] 'Photo'")).firstMatch
                XCTAssertTrue(photo.waitForExistence(timeout: 10), app.debugDescription)
                // The system photo grid exposes frames but can report false
                // hittability across the picker service boundary on Simulator.
                photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                XCTAssertTrue(app.images["documentReviewPreview"].waitForExistence(timeout: 10), app.debugDescription)
                XCTAssertFalse(app.images[identifier + "Preview"].exists)
                app.buttons["documentUsePhoto"].tap()
                XCTAssertTrue(app.images[identifier + "Preview"].waitForExistence(timeout: 5))
            }
            let next = app.buttons[vehicle ? "vehicleDocumentsContinue" : "licenseContinue"]
            XCTAssertTrue(next.isEnabled)
            let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = vehicle ? "gallery-vehicle-documents" : "gallery-license"; proof.lifetime = .keepAlways; add(proof)
            app.terminate()
        }
    }

    @MainActor
    func testLicensePhotosRequireConfirmationAndContinueWorks() {
        let app = XCUIApplication()
        app.launchArguments = ["-DriverDocumentUITest"]
        app.launch()
        let next = app.buttons["licenseContinue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCTAssertFalse(next.isEnabled)
        confirmDocument(app, identifier: "licenseFront")
        XCTAssertTrue(app.images["licenseFrontPreview"].exists)
        XCTAssertFalse(next.isEnabled)
        confirmDocument(app, identifier: "licenseBack")
        XCTAssertTrue(app.images["licenseBackPreview"].exists)
        XCTAssertTrue(next.isEnabled)
        for _ in 0..<6 where !next.isHittable { app.swipeUp() }
        next.tap()
        XCTAssertTrue(app.staticTexts["licenseStepComplete"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRegistrationAndInsurancePhotosEnableContinue() {
        let app = XCUIApplication()
        app.launchArguments = ["-DriverDocumentUITest", "-DocumentVehicle"]
        app.launch()
        let next = app.buttons["vehicleDocumentsContinue"]
        for _ in 0..<8 where !app.buttons["registrationSource"].isHittable { app.swipeUp() }
        XCTAssertFalse(next.isEnabled)
        confirmDocument(app, identifier: "registration")
        XCTAssertTrue(app.images["registrationPreview"].exists)
        XCTAssertFalse(next.isEnabled)
        confirmDocument(app, identifier: "insurance")
        XCTAssertTrue(app.images["insurancePreview"].exists)
        XCTAssertTrue(next.isEnabled)
    }

    @MainActor
    private func confirmDocument(_ app: XCUIApplication, identifier: String) {
        let source = app.buttons[identifier + "Source"]
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        for _ in 0..<8 where !source.isHittable { app.swipeUp() }
        source.tap()
        XCTAssertTrue(app.buttons["Take Photo"].exists)
        app.buttons["Use sample document"].tap()
        XCTAssertTrue(app.images["documentReviewPreview"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["documentUsePhoto"].tap()
    }

    @MainActor
    func testSMSDuplicateRequestsCooldownAndPersistentResendError() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrSMSUITest", "-RydrSMSResetUITest"]
        app.launch()
        let openPhone = app.buttons["Switch to phone login"]
        XCTAssertTrue(openPhone.waitForExistence(timeout: 15))
        for _ in 0..<4 where !openPhone.isHittable { app.swipeUp() }
        openPhone.tap()
        let phone = app.textFields["smsPhoneNumber"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15))
        phone.tap(); phone.typeText("2025550123")
        let send = app.buttons["smsSend"]
        if !send.isHittable { app.swipeUp() }
        send.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        XCTAssertFalse(send.isEnabled)
        XCTAssertEqual(app.staticTexts["smsRequestCount"].label, "SMS transport calls: 1")
        let resend = app.buttons["smsResend"]
        XCTAssertTrue(resend.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["smsDestinationPhone"].label, "+1 (202) 555-0123")
        if !resend.isHittable { app.swipeUp() }
        XCTAssertFalse(resend.isEnabled)
        XCTAssertTrue(resend.waitForEnabled(timeout: 8))
        resend.tap()
        XCTAssertFalse(resend.isEnabled)
        let error = app.staticTexts["smsCodeError"]
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(error.label.contains("Firebase temporarily blocked"))
        XCTAssertEqual(app.staticTexts["smsCodeRequestCount"].label, "SMS transport calls: 2")
        // The error stays on the visible code screen beyond the local cooldown.
        XCTAssertTrue(resend.waitForEnabled(timeout: 8))
        XCTAssertTrue(error.exists)
        XCTAssertTrue(error.label.contains("email and password"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Visible persistent SMS resend error"; attachment.lifetime = .keepAlways
        add(attachment)
        resend.tap()
        let session = app.staticTexts["smsActiveSession"]
        XCTAssertTrue(NSPredicate(format: "label == %@", "simulator-session-3").evaluateEventually(on: session, timeout: 8))
        XCTAssertFalse(error.exists)
        XCTAssertEqual(app.staticTexts["smsCodeRequestCount"].label, "SMS transport calls: 3")
        // A completed authentication clears the deadline immediately, before its natural expiry.
        let complete = app.buttons["smsCompleteAuthentication"]
        if !complete.isHittable { app.swipeUp() }
        complete.tap()
        XCTAssertTrue(resend.waitForEnabled(timeout: 2))
        app.terminate()
        app.launchArguments = ["-RydrSMSUITest"]
        app.launch()
        let freshLogin = app.buttons["Switch to phone login"]
        XCTAssertTrue(freshLogin.waitForExistence(timeout: 15))
        for _ in 0..<4 where !freshLogin.isHittable { app.swipeUp() }
        freshLogin.tap()

        let freshPhone = app.textFields["smsPhoneNumber"]
        XCTAssertTrue(freshPhone.waitForExistence(timeout: 15))
        freshPhone.tap(); freshPhone.typeText("2025550123")
        XCTAssertTrue(app.buttons["smsSend"].isEnabled)

    }

    @MainActor
    func testSMSBlockedRequestCooldownSurvivesRelaunchAndEmailRemainsAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrSMSUITest", "-RydrSMSResetUITest", "-RydrSMSBlockedUITest", "-RydrSMSPersistenceUITest"]
        app.launch()
        let openPhone = app.buttons["Switch to phone login"]
        XCTAssertTrue(openPhone.waitForExistence(timeout: 15))
        for _ in 0..<4 where !openPhone.isHittable { app.swipeUp() }
        openPhone.tap()
        let phone = app.textFields["smsPhoneNumber"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15))
        phone.tap(); phone.typeText("2025550123")
        let send = app.buttons["smsSend"]
        if !send.isHittable { app.swipeUp() }
        send.tap()
        let error = app.staticTexts["smsLoginError"]
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(error.label.contains("Firebase temporarily blocked"))
        XCTAssertFalse(send.isEnabled)
        XCTAssertEqual(app.staticTexts["smsRequestCount"].label, "SMS transport calls: 1")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.textFields["Email Field"].exists)
        app.terminate()
        app.launchArguments = ["-RydrSMSUITest", "-RydrSMSBlockedUITest", "-RydrSMSPersistenceUITest"]
        app.launch()
        let reopen = app.buttons["Switch to phone login"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 10))
        for _ in 0..<4 where !reopen.isHittable { app.swipeUp() }
        reopen.tap()
        XCTAssertTrue(app.buttons["smsSend"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["smsSend"].label.contains("Try again in"))
    }



    @MainActor
    func testPromotionCodeScreenReturnsToWallet() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrWalletNavigationUITest"]
        app.launch()
        XCTAssertTrue(app.buttons["driverMenu"].waitForExistence(timeout: 15))
        app.buttons["driverMenu"].tap()
        app.buttons["Wallet & Payouts"].tap()
        let promotions = app.buttons["Driver promotions & bonuses"]
        for _ in 0..<4 where !promotions.isHittable { app.swipeUp() }
        XCTAssertTrue(promotions.isHittable, app.debugDescription)
        promotions.tap()
        let code = app.textFields["promotionCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["promotionEnroll"].isEnabled)
        code.tap(); code.typeText("TESTCODE")
        app.buttons["promotionDone"].tap()
        XCTAssertTrue(app.buttons["walletBack"].waitForExistence(timeout: 5))
        app.buttons["walletBack"].tap()
        XCTAssertTrue(app.buttons["driverMenu"].isHittable)
    }

    @MainActor
    func testGarageAddAndDeletePreservesCurrentVehicle() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrWalletNavigationUITest", "-RydrGarageUITest"]
        app.launch()
        let menu = app.buttons["driverMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        app.buttons["Vehicle & Rydr Hub"].tap()
        let current = app.staticTexts["vehicleCard-current"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        app.buttons["Add a new vehicle"].tap()
        let save = app.buttons["Save Vehicle"]
        for _ in 0..<8 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable, app.debugDescription)
        save.tap()
        let saved = app.staticTexts["vehicleCard-fixture-saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(current.exists)
        let delete = app.buttons["deleteVehicle-fixture-saved"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(saved.exists)
        delete.tap()
        app.buttons["Delete Vehicle"].tap()
        XCTAssertTrue(saved.waitForNonExistence(timeout: 5))
        XCTAssertTrue(current.exists)
    }

    @MainActor
    func testDocumentReminderOpensDocumentsAndReturnsToDashboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrWalletNavigationUITest", "-RydrDocumentReminderUITest", "-RydrDocumentFixtureUITest"]
        app.launch()
        let done = app.buttons["documentsBack"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), app.debugDescription)
        let signInAlert = app.alerts["Documents"].buttons["OK"]
        if signInAlert.exists { signInAlert.tap() }
        XCTAssertTrue(app.navigationBars["Documents"].exists)
        XCTAssertTrue(app.staticTexts["documentComplianceNotice"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Nov 13, 2026")).firstMatch.exists, app.debugDescription)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["driverMenu"].isHittable)
    }

    @MainActor
    func testPremiumSedanAndSUVChoices() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrWalletNavigationUITest"]
        app.launch()
        let menu = app.buttons["driverMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        app.buttons["Vehicle & Rydr Hub"].tap()
        for title in ["Rydr Prestine Sedan", "Rydr Prestine SUV", "Rydr Executive Sedan", "Rydr Executive SUV"] {
            let label = app.staticTexts[title]
            for _ in 0..<5 where !label.isHittable { app.swipeUp() }
            XCTAssertTrue(label.exists, app.debugDescription)
        }
    }

    @MainActor
    func testWalletBackReturnsToDashboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrWalletNavigationUITest"]
        app.launch()
        for _ in 0..<2 {
            let menu = app.buttons["driverMenu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 15))
            menu.tap()
            let wallet = app.buttons["Wallet & Payouts"]
            XCTAssertTrue(wallet.waitForExistence(timeout: 5), app.debugDescription)
            wallet.tap()
            let back = app.buttons["walletBack"]
            XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
            back.tap()
            XCTAssertTrue(back.waitForNonExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(menu.isHittable, app.debugDescription)
        }
    }

    @MainActor
    func testRateCardPersistsAfterReopen() throws {
        let app = XCUIApplication()
        app.launch()

        let phoneLogin = app.buttons["Switch to phone login"]
        if phoneLogin.waitForExistence(timeout: 8) {
            let environment = ProcessInfo.processInfo.environment
            guard let phoneNumber = environment["RYDR_DRIVER_TEST_PHONE"],
                  let verificationCode = environment["RYDR_DRIVER_TEST_CODE"] else {
                throw XCTSkip("Set RYDR_DRIVER_TEST_PHONE and RYDR_DRIVER_TEST_CODE to run the authenticated rate-card test.")
            }
            phoneLogin.tap()

            let phone = app.textFields["Phone Number Field"]
            XCTAssertTrue(phone.waitForExistence(timeout: 5), app.debugDescription)
            phone.tap()
            phone.typeText(phoneNumber)
            app.buttons["Send Verification Code"].tap()

            let code = app.textFields["Verification Code Field"]
            XCTAssertTrue(code.waitForExistence(timeout: 15), app.debugDescription)
            code.tap()
            code.typeText(verificationCode)
            app.buttons["Verify Code"].tap()
        }

        let rateCard = app.buttons["Rate Card"]
        XCTAssertTrue(rateCard.waitForExistence(timeout: 20), app.debugDescription)
        rateCard.tap()

        XCTAssertTrue(app.staticTexts["Current Rates"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertGreaterThanOrEqual(app.textFields.count, 3, app.debugDescription)
        let originalValues = (0..<3).map { app.textFields.element(boundBy: $0).value as? String ?? "" }
        let testValues = originalValues.map { value in
            String(format: "%.2f", (Double(value) ?? 0) + 0.05)
        }
        let addButtons = app.buttons.matching(identifier: "Add")
        XCTAssertGreaterThanOrEqual(addButtons.count, 3, app.debugDescription)
        for index in 0..<3 { addButtons.element(boundBy: index).tap() }

        let save = app.buttons["Save Changes"]
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        save.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(3))

        app.terminate()
        app.launch()
        XCTAssertTrue(rateCard.waitForExistence(timeout: 8), app.debugDescription)
        rateCard.tap()
        XCTAssertTrue(app.staticTexts["Current Rates"].waitForExistence(timeout: 8), app.debugDescription)

        XCTAssertTrue(waitForValues(testValues, in: app), app.debugDescription)

        // Put the real test account back exactly as it was before the check.
        let removeButtons = app.buttons.matching(identifier: "Remove")
        XCTAssertGreaterThanOrEqual(removeButtons.count, 3, app.debugDescription)
        for index in 0..<3 { removeButtons.element(boundBy: index).tap() }
        XCTAssertTrue(save.isEnabled, app.debugDescription)
        save.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        app.terminate()
        app.launch()
        XCTAssertTrue(rateCard.waitForExistence(timeout: 20), app.debugDescription)
        rateCard.tap()
        XCTAssertTrue(waitForValues(originalValues, in: app), app.debugDescription)
    }

    @MainActor
    private func waitForValues(_ expected: [String], in app: XCUIApplication) -> Bool {
        let predicate = NSPredicate { _, _ in
            guard app.textFields.count >= expected.count else { return false }
            return expected.enumerated().allSatisfy { index, value in
                (app.textFields.element(boundBy: index).value as? String) == value
            }
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 15) == .completed
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

private extension XCUIElement {
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        NSPredicate(format: "enabled == true").evaluateEventually(on: self, timeout: timeout)
    }
}
private extension NSPredicate {
    func evaluateEventually(on object: Any, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: self, object: object)], timeout: timeout) == .completed
    }
}
