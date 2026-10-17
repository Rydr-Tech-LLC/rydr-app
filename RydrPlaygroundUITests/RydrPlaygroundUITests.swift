//
//  RydrPlaygroundUITests.swift
//  RydrPlaygroundUITests
//
//  Created by Khris Nunnally on 6/11/25.
//

import XCTest

final class RydrPlaygroundUITests: XCTestCase {
    @MainActor
    func testNativeSplashLightAndDark() {
        for mode in ["-SplashLight", "-SplashDark"] {
            let app = XCUIApplication()
            app.launchArguments = ["-RydrSplashUITest", mode]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["rydrSplashLogo"].waitForExistence(timeout: 5))
            let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "native-splash" + mode; proof.lifetime = .keepAlways; add(proof)
            XCTAssertTrue(app.staticTexts["splashComplete"].waitForExistence(timeout: 15))
            app.terminate()
        }
    }

    @MainActor
    func testCardSaveLocksRepeatedTapsAndReusesAttemptAfterNetworkFailure() {
        let app = XCUIApplication()
        app.launchArguments = ["-RiderCardSaveUITest"]
        app.launch()
        let save = app.buttons["Save & Continue"]
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertFalse(app.buttons["Working..."].isEnabled)
        XCTAssertEqual(app.staticTexts["cardSaveRequestCount"].label, "Requests: 1")
        XCTAssertTrue(app.staticTexts["Network unavailable. Retry your card save."].waitForExistence(timeout: 10))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["cardSaveCompleted"].waitForExistence(timeout: 10))
    }


    @MainActor
    func testBrandedRestorationLoading() {
        let app = XCUIApplication()
        app.launchArguments = ["-RiderOnboardingResumeUITest", "-ResumeLoading", "-ResumeComplete"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["rydrLoading"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Restoring your onboarding…"].exists)
        let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "rider-branded-loading"; proof.lifetime = .keepAlways; add(proof)
        XCTAssertTrue(app.staticTexts["riderDashboardFixture"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testOnboardingResumeAfterRelaunchAndFailClosed() {
        for scenario in ["-ResumeAddress", "-ResumeUnavailable", "-ResumeComplete"] {
            let app = XCUIApplication()
            app.launchArguments = ["-RiderOnboardingResumeUITest", scenario]
            for _ in 0..<2 {
                app.launch()
                if scenario == "-ResumeComplete" { XCTAssertTrue(app.staticTexts["riderDashboardFixture"].waitForExistence(timeout: 15)) }
                else if scenario == "-ResumeUnavailable" {
                    XCTAssertTrue(app.staticTexts["riderOnboardingError"].waitForExistence(timeout: 15))
                    XCTAssertFalse(app.staticTexts["riderDashboardFixture"].exists)
                } else {
                    XCTAssertTrue(app.staticTexts["Where Are You Located?"].waitForExistence(timeout: 15))
                    XCTAssertEqual(app.textFields["Street Address"].value as? String, "1 Main St")
                    let proof = XCTAttachment(screenshot: app.screenshot()); proof.name = "onboarding-resumed-address"; proof.lifetime = .keepAlways; add(proof)
                    XCTAssertFalse(app.staticTexts["riderDashboardFixture"].exists)
                }
                app.terminate()
            }
        }
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
    func testIdentitySubmittedAndVerifiedContinueOnboarding() {
        for scenario in ["-IdentityProcessing", "-IdentityVerified", "-IdentityReturnFailure"] {
            let app = XCUIApplication()
            app.launchArguments = ["-RydrIdentityOnboardingUITest", scenario]
            app.launch()
            let verify = app.buttons["riderVerifyIdentity"]
            XCTAssertTrue(verify.waitForExistence(timeout: 15))
            for _ in 0..<5 where !verify.isHittable { app.swipeUp() }
            verify.tap()
            XCTAssertTrue(app.staticTexts["identityOnboardingComplete"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    @MainActor
    func testIdentityIncompleteReturnFailureStaysOnOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrIdentityOnboardingUITest", "-IdentityIncomplete"]
        app.launch()
        let verify = app.buttons["riderVerifyIdentity"]
        XCTAssertTrue(verify.waitForExistence(timeout: 15))
        for _ in 0..<5 where !verify.isHittable { app.swipeUp() }
        verify.tap()
        XCTAssertFalse(app.staticTexts["identityOnboardingComplete"].exists)
        XCTAssertTrue(app.staticTexts["riderIdentityErrorOrStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(verify.isEnabled)
    }

    @MainActor
    func testSMSDuplicateRequestsCooldownAndPersistentResendError() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrSMSUITest", "-RydrSMSResetUITest"]
        app.launch()
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
        let email = app.buttons["Switch to email and password login"]
        XCTAssertTrue(email.isEnabled)
        app.terminate()
        app.launchArguments = ["-RydrSMSUITest", "-RydrSMSBlockedUITest", "-RydrSMSPersistenceUITest"]
        app.launch()
        XCTAssertTrue(app.buttons["smsSend"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["smsSend"].label.contains("Try again in"))
    }

    @MainActor
    func testPromotionCodeScreenAcceptsInputAndRequiresSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-RydrPromotionsUITest"]
        app.launch()
        let code = app.textFields["promotionCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["promotionEnroll"].isEnabled)
        code.tap(); code.typeText("TESTCODE")
        XCTAssertTrue(app.buttons["promotionEnroll"].isEnabled)
        app.buttons["promotionEnroll"].tap()
        XCTAssertTrue(app.staticTexts["promotionMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["promotionDone"].exists)
    }

    @MainActor
    func testPrestineSUVContinuesToBooking() throws {
        try verifyPrestineFlow(choice: "SUV")
    }

    @MainActor
    func testPrestineSedanContinuesToBooking() throws {
        try verifyPrestineFlow(choice: "Sedan")
    }

    @MainActor
    private func verifyPrestineFlow(choice: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PrestineBookingUITest", "-appAppearance", choice == "SUV" ? "dark" : "light"]
        app.launch()
        let prestine = app.buttons["rideTypePrestine"]
        XCTAssertTrue(prestine.waitForExistence(timeout: 15))
        if !prestine.isHittable { app.swipeUp() }
        prestine.tap()
        let option = app.buttons["prestineChoice\(choice)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        let next = app.buttons["prestineContinue"]
        if !next.isHittable { app.swipeUp() }
        XCTAssertTrue(next.label.contains(choice))
        next.tap()
        let selectedType = app.staticTexts["bookingSelectedRideType"]
        XCTAssertTrue(selectedType.waitForExistence(timeout: 10))
        XCTAssertEqual(selectedType.label, "Rydr Prestine \(choice)")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["prestineChoice\(choice)"].waitForExistence(timeout: 5))
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
