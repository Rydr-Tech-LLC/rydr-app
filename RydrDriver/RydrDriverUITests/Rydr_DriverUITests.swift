//
//  Rydr_DriverUITests.swift
//  Rydr DriverUITests
//
//  Created by Khris Nunnally on 10/9/25.
//

import XCTest

final class Rydr_DriverUITests: XCTestCase {

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
