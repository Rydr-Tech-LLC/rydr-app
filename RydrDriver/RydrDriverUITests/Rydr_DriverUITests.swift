//
//  Rydr_DriverUITests.swift
//  Rydr DriverUITests
//
//  Created by Khris Nunnally on 10/9/25.
//

import XCTest

final class Rydr_DriverUITests: XCTestCase {

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
