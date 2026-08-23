import XCTest

final class SalahUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingCanBeSkippedAndRootTabsAppear() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state"]
        app.launch()
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Calendar"].exists)
        XCTAssertTrue(app.tabBars.buttons["Tracker"].exists)
        XCTAssertTrue(app.tabBars.buttons["Qibla"].exists)
        XCTAssertTrue(app.tabBars.buttons["More"].exists)
        let locationMenu = app.buttons["today.location.menu"]
        XCTAssertTrue(locationMenu.exists)
        locationMenu.tap()
        XCTAssertTrue(app.buttons["Choose District Manually"].waitForExistence(timeout: 2))
    }

    func testBanglaOverrideLocalizesTabsPrayerAndSolarLabels() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-onboarding-complete", "-bangla-language"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["আজ"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.tabBars.buttons["ক্যালেন্ডার"].exists)
        XCTAssertTrue(app.tabBars.buttons["ট্র্যাকার"].exists)
        XCTAssertTrue(app.tabBars.buttons["কিবলা"].exists)
        XCTAssertTrue(app.tabBars.buttons["আরও"].exists)
        XCTAssertTrue(app.staticTexts["সূর্যোদয়"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["সূর্যাস্ত"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ফজর'" )).firstMatch.exists)
    }

    func testManualDistrictSelectionAndLocationDeniedRecovery() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-location-denied"]
        app.launch()
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Choose Prayer Location"].tap()
        app.buttons["Use Current Location"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Location access is denied'")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Choose District Manually"].tap()
        let dhaka = app.buttons["Dhaka, ঢাকা"]
        XCTAssertTrue(dhaka.waitForExistence(timeout: 3))
        dhaka.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 3))
    }

    func testTodayShowsLoadingThenLoadedAndCachedOfflineState() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-onboarding-complete", "-slow-loading"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Loading prayer times…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Prayer Schedule"].waitForExistence(timeout: 7))

        app.terminate()
        app.launchArguments = ["-ui-testing", "-onboarding-complete", "-offline"]
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Offline'" )).firstMatch.waitForExistence(timeout: 4))
    }

    func testMarkingPrayerCompletedPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-reset-tracker", "-onboarding-complete"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Prayer Schedule"].waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fajr, starts'")).firstMatch.tap()
        app.tabBars.buttons["Tracker"].tap()
        XCTAssertTrue(app.buttons["Fajr, completed"].waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = ["-ui-testing", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["Tracker"].tap()
        XCTAssertTrue(app.buttons["Fajr, completed"].waitForExistence(timeout: 3))
    }

    func testMarkingInTodayUpdatesAlreadyVisitedTrackerTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-reset-tracker", "-onboarding-complete"]
        app.launch()

        // Visit the Tracker first so its view model snapshots the empty state
        // instead of being created lazily after the prayer is already marked.
        app.tabBars.buttons["Tracker"].tap()
        XCTAssertTrue(app.buttons["Fajr, not completed"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Prayer Schedule"].waitForExistence(timeout: 4))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fajr, starts'")).firstMatch.tap()

        app.tabBars.buttons["Tracker"].tap()
        XCTAssertTrue(app.buttons["Fajr, completed"].waitForExistence(timeout: 3))
    }

    func testTrackerCompletionControlIsAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["Tracker"].tap()
        XCTAssertTrue(app.segmentedControls["Tracker section"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Today’s Ṣalāh"].waitForExistence(timeout: 3))
        let fajr = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Fajr'")).firstMatch
        XCTAssertTrue(fajr.exists)
        fajr.tap()
    }

    func testTrackerShowsOnlyRequestedNaflItemsWithoutToolbarActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-tracker", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["Tracker"].tap()

        XCTAssertFalse(app.buttons["Choose date"].exists)
        XCTAssertFalse(app.buttons["Prayer history"].exists)

        app.segmentedControls.buttons["Nafl"].tap()

        let expectedItems = [
            "Prayed Tahajjud",
            "Prayed Ishrak",
            "Morning Adhkar",
            "Evening Adhkar",
            "Read Quran"
        ]
        for item in expectedItems {
            XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 2))
        }

        XCTAssertFalse(app.buttons["Read the Qurʾān"].exists)
        XCTAssertFalse(app.buttons["Morning and evening adhkār"].exists)
        XCTAssertFalse(app.buttons["Gave ṣadaqah"].exists)
    }

    func testInsightsIsASeparateTrackerDestination() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-tracker", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["Tracker"].tap()

        XCTAssertFalse(app.segmentedControls.buttons["Insights"].exists)
        let fajr = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Fajr'")).firstMatch
        XCTAssertTrue(fajr.waitForExistence(timeout: 2))
        fajr.tap()

        let insights = app.buttons["tracker.insights"]
        XCTAssertTrue(insights.waitForExistence(timeout: 2))
        insights.tap()

        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Ṣalāh"].exists)
        XCTAssertTrue(app.staticTexts["Tasbih"].exists)
        XCTAssertTrue(app.staticTexts["Nafl"].exists)
        XCTAssertTrue(app.staticTexts["Charity"].exists)

        let chart = app.otherElements["insights.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 2))
        let recordedBar = chart.otherElements.matching(NSPredicate(format: "value == '1 prayers'")).firstMatch
        XCTAssertTrue(recordedBar.waitForExistence(timeout: 2))
        recordedBar.tap()
        let selectionDetail = app.staticTexts["insights.selection.detail"]
        XCTAssertTrue(selectionDetail.waitForExistence(timeout: 2))
        XCTAssertTrue(selectionDetail.label.contains("1 prayers"))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Insights overview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testTasbihCounterAndConfirmedReset() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-tracker", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["Tracker"].tap()
        app.segmentedControls.buttons["Tasbih"].tap()

        let emptyCounter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tasbih counter. Current count 0'")).firstMatch
        XCTAssertTrue(emptyCounter.waitForExistence(timeout: 3))
        emptyCounter.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tasbih counter. Current count 1'")).firstMatch.waitForExistence(timeout: 2))

        app.buttons["Reset counter"].tap()
        let confirmReset = app.buttons["Confirm reset counter"]
        XCTAssertTrue(confirmReset.waitForExistence(timeout: 2))
        confirmReset.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tasbih counter. Current count 0'")).firstMatch.waitForExistence(timeout: 2))
    }

    func testTasbihGoalCompletionResetsAfterAcknowledgement() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-tracker", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["Tracker"].tap()
        app.segmentedControls.buttons["Tasbih"].tap()

        let goalMenu = app.buttons["tasbih.goal.menu"]
        XCTAssertTrue(goalMenu.waitForExistence(timeout: 3))
        goalMenu.tap()
        let goal33 = app.buttons["33"]
        XCTAssertTrue(goal33.waitForExistence(timeout: 2))
        goal33.tap()

        let counter = app.buttons["tasbih.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 2))
        for _ in 0..<33 {
            counter.tap()
        }

        let completionAlert = app.alerts["Tasbih goal completed"]
        XCTAssertTrue(completionAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(completionAlert.staticTexts["You completed 33 counts."].exists)
        completionAlert.buttons["OK"].tap()

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tasbih counter. Current count 0'")).firstMatch.waitForExistence(timeout: 2))
    }

    func testCalculationAndReminderScreensRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["More"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Location & Calculation'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Location & Calculation"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prayer Reminders'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 3))
    }

    func testChangingCalculationMethodAndEnablingReminder() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-onboarding-complete", "-notification-authorized"]
        app.launch()
        app.tabBars.buttons["More"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Location & Calculation'")).firstMatch.tap()
        let method = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UIS Karachi'")).firstMatch
        XCTAssertTrue(method.waitForExistence(timeout: 3))
        method.tap()
        let isna = app.buttons["ISNA"]
        XCTAssertTrue(isna.waitForExistence(timeout: 3))
        isna.tap()
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prayer Reminders'")).firstMatch.tap()
        let fajrOff = app.buttons["Fajr reminder, off"]
        XCTAssertTrue(fajrOff.waitForExistence(timeout: 3))
        fajrOff.tap()
        let fajr = app.switches["Fajr"]
        XCTAssertTrue(fajr.waitForExistence(timeout: 3))
        XCTAssertEqual(fajr.value as? String, "1")
    }

    func testNotificationDeniedReminderSheetShowsSettingsShortcut() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-onboarding-complete", "-notification-denied"]
        app.launch()
        app.tabBars.buttons["More"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prayer Reminders'")).firstMatch.tap()
        let fajrOff = app.buttons["Fajr reminder, off"]
        XCTAssertTrue(fajrOff.waitForExistence(timeout: 3))
        fajrOff.tap()
        XCTAssertTrue(app.buttons["Enable Reminder"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'currently denied'")).firstMatch.exists)
    }

    func testCharityTrackerOpensDatedReminderControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-reset-tracker", "-onboarding-complete", "-notification-authorized"]
        app.launch()

        app.tabBars.buttons["Tracker"].tap()
        app.segmentedControls.buttons["Charity"].tap()
        XCTAssertTrue(app.buttons["charity.add-giving"].waitForExistence(timeout: 3))

        let reminderLink = app.buttons["charity.reminder.link"]
        XCTAssertTrue(reminderLink.waitForExistence(timeout: 3))
        reminderLink.tap()

        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 3))
        let reminderToggle = app.switches["charity.reminder.toggle"]
        XCTAssertTrue(reminderToggle.waitForExistence(timeout: 3))
        XCTAssertTrue(reminderToggle.isHittable)
        let nativeSwitch = reminderToggle.descendants(matching: .switch).firstMatch
        XCTAssertTrue(nativeSwitch.waitForExistence(timeout: 3))
        nativeSwitch.tap()
        XCTAssertTrue(app.staticTexts["First reminder"].waitForExistence(timeout: 3))

        let repeatPicker = app.segmentedControls["charity.reminder.repeat"]
        XCTAssertTrue(repeatPicker.waitForExistence(timeout: 3))
        let monthly = repeatPicker.buttons["Monthly"]
        XCTAssertTrue(monthly.exists)
        XCTAssertTrue(monthly.isSelected)

        let weekly = repeatPicker.buttons["Weekly"]
        weekly.tap()
        XCTAssertTrue(weekly.isSelected)
    }
}
