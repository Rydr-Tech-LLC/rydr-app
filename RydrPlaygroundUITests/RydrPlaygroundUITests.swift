//
//  RydrPlaygroundUITests.swift
//  RydrPlaygroundUITests
//
//  Created by Khris Nunnally on 6/11/25.
//

import XCTest

final class RydrPlaygroundUITests: XCTestCase {

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
