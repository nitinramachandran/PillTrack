import XCTest

/// UI tests that launch the app and interact with it like a user would.
///
/// UI tests are slower than unit tests because they run the full app in a simulator or device.
final class Medicine_Date_AlerterUITests: XCTestCase {

    /// Runs before each UI test.
    ///
    /// `continueAfterFailure = false` stops the test immediately after the first failure,
    /// which usually makes UI failures easier to understand.
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Runs after each UI test.
    ///
    /// This is empty for now, but it is where cleanup code would go if tests created
    /// shared state that needed to be reset.
    override func tearDownWithError() throws {}

    /// Verifies that the app can launch successfully.
    ///
    /// This is intentionally simple. More UI tests can later type into fields and tap
    /// buttons using the accessibility identifiers defined in `ContentView`.
    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    /// Measures how long the app takes to launch.
    ///
    /// Xcode records this as a performance metric so future changes can be compared.
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - App Store Screenshots

    /// Captures App Store screenshots: add form, Saved Medicines list, and full-size photo viewer.
    ///
    /// Run against the iPhone 17 Pro Max simulator with pre-seeded demo data. Screenshots are
    /// saved as test attachments in the xcresult bundle and extracted afterwards.
    @MainActor
    func testAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for the app to fully render
        let savedButton = app.buttons["savedMedicinesButton"]
        XCTAssertTrue(savedButton.waitForExistence(timeout: 5))

        // Screenshot 1: Add form with "Add photo" button
        saveScreenshot("01-add-form-photo-button", from: app)

        // Open Saved Medicines sheet
        savedButton.tap()

        // Wait for the list to appear
        let doneButton = app.buttons["savedMedicinesDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))

        // Screenshot 2: Saved Medicines list (Expiring filter — default)
        saveScreenshot("02-saved-medicines-list", from: app)

        // Switch to "All" filter to see the thumbnail and add-photo button together
        let allFilter = app.buttons["filterAll"]
        if allFilter.exists { allFilter.tap() }
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("02b-saved-medicines-all", from: app)

        // Tap the thumbnail to open the full-size photo viewer
        let thumbnail = app.buttons["medicinePhotoThumbnail"].firstMatch
        if thumbnail.exists {
            thumbnail.tap()
            Thread.sleep(forTimeInterval: 0.5)
            // Screenshot 3: Full-size photo viewer
            saveScreenshot("03-full-size-photo-viewer", from: app)

            // Dismiss the viewer
            let viewerDone = app.buttons["expandedPhotoDoneButton"]
            if viewerDone.exists { viewerDone.tap() }
        }
    }

    @MainActor
    private func saveScreenshot(_ name: String, from app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
