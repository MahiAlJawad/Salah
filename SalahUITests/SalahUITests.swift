import XCTest

final class SalahUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingRequiresLocationAndRootTabsAppearAfterSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state"]
        app.launch()
        XCTAssertFalse(app.buttons["Skip"].exists)
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Choose Prayer Location"].tap()
        app.buttons["Use Current Location"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Calendar"].exists)
        XCTAssertTrue(app.tabBars.buttons["Tracker"].exists)
        XCTAssertTrue(app.tabBars.buttons["Qibla"].exists)
        XCTAssertTrue(app.tabBars.buttons["More"].exists)
        let locationMenu = app.buttons["today.location.menu"]
        XCTAssertTrue(locationMenu.exists)
        locationMenu.tap()
        XCTAssertTrue(app.buttons["Change Location"].waitForExistence(timeout: 2))
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

    func testGlobalSearchAndLocationDeniedRecovery() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-location-denied"]
        app.launch()
        app.buttons["Continue"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Choose Prayer Location"].tap()
        app.buttons["Use Current Location"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Location access is denied'")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Search for a City or Place"].tap()
        let searchField = app.searchFields["City, town, or address"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("Dhaka")
        let dhaka = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Dhaka'" )).firstMatch
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

extension SalahUITests {
    func testCalendarPreviousDayEditingUndoAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-reset-tracker", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        let selectedDate = app.staticTexts["calendar.selected-date"]
        XCTAssertTrue(selectedDate.waitForExistence(timeout: 5))
        let today = selectedDate.label
        app.buttons["calendar.collapse"].tap()
        app.buttons["calendar.previous-day"].tap()
        let changedDate = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", today), object: selectedDate)
        XCTAssertEqual(XCTWaiter.wait(for: [changedDate], timeout: 3), .completed)
        let previousDate = selectedDate.label
        app.segmentedControls.buttons["Nafl"].tap()
        let quran = app.buttons["Read Quran"]
        XCTAssertTrue(quran.waitForExistence(timeout: 3))
        quran.tap()
        XCTAssertEqual(quran.value as? String, "completed")
        app.buttons["Undo"].tap()
        XCTAssertEqual(quran.value as? String, "not completed")
        quran.tap()
        app.segmentedControls.buttons["Tasbih"].tap()
        XCTAssertEqual(selectedDate.label, previousDate)
        app.buttons["calendar.edit-tasbih"].tap()
        let input = app.textFields["calendar.tasbih-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText(XCUIKeyboardKey.delete.rawValue + "42")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["42"].waitForExistence(timeout: 3))
        app.buttons["calendar.edit-tasbih"].tap()
        input.tap()
        input.typeText("9")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["42"].exists)
        app.buttons["calendar.today"].tap()
        XCTAssertEqual(selectedDate.label, today)
        XCTAssertFalse(app.buttons["calendar.next-day"].isEnabled)
        XCTAssertTrue(app.staticTexts["0"].exists)
        app.buttons["calendar.previous-day"].tap()
        XCTAssertTrue(app.staticTexts["42"].exists)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.collapse"].waitForExistence(timeout: 3))
        app.buttons["calendar.collapse"].tap()
        app.buttons["calendar.previous-day"].tap()
        app.segmentedControls.buttons["Tasbih"].tap()
        XCTAssertTrue(app.staticTexts["42"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["Nafl"].tap()
        XCTAssertEqual(app.buttons["Read Quran"].value as? String, "completed")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Calendar previous-day Nafl"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCalendarTodaySynchronizesWithTrackerAndGivingUsesSelectedDay() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-reset-tracker", "-onboarding-complete"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.collapse"].waitForExistence(timeout: 5))
        app.buttons["calendar.collapse"].tap()
        app.segmentedControls.buttons["Tasbih"].tap()
        app.buttons["calendar.edit-tasbih"].tap()
        let input = app.textFields["calendar.tasbih-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.tap()
        input.typeText(XCUIKeyboardKey.delete.rawValue + "7")
        app.buttons["Save"].tap()
        app.tabBars.buttons["Tracker"].tap()
        app.segmentedControls.buttons["Tasbih"].tap()
        let counter = app.buttons["tasbih.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 3))
        XCTAssertTrue(counter.label.contains("Current count 7"))
        counter.tap()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.staticTexts["8"].waitForExistence(timeout: 3))
        app.buttons["calendar.previous-day"].tap()
        app.segmentedControls.buttons["Charity"].tap()
        app.buttons["calendar.add-giving"].tap()
        XCTAssertTrue(app.navigationBars["Add Giving"].waitForExistence(timeout: 3))
        let amount = app.textFields["0"]
        amount.tap()
        amount.typeText("50")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Given this day"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No giving recorded for this day."].exists)
        app.buttons["calendar.today"].tap()
        XCTAssertTrue(app.staticTexts["No giving recorded for this day."].waitForExistence(timeout: 3))
        app.buttons["calendar.previous-day"].tap()
        XCTAssertFalse(app.staticTexts["No giving recorded for this day."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Calendar daily and monthly giving"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCalendarRecordsRemainEditableWithoutPrayerTimes() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-reset-tracker", "-onboarding-complete", "-prayer-times-unavailable"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.collapse"].waitForExistence(timeout: 5))
        app.buttons["calendar.collapse"].tap()
        app.buttons["calendar.previous-day"].tap()
        XCTAssertTrue(app.staticTexts["Prayer times could not be loaded. Your records are still available."].waitForExistence(timeout: 5))
        let fajr = app.buttons["Fajr"]
        fajr.tap()
        XCTAssertEqual(fajr.value as? String, "completed")
        app.segmentedControls.buttons["Nafl"].tap()
        app.buttons["Prayed Tahajjud"].tap()
        XCTAssertEqual(app.buttons["Prayed Tahajjud"].value as? String, "completed")
        app.segmentedControls.buttons["Tasbih"].tap()
        XCTAssertTrue(app.buttons["calendar.edit-tasbih"].exists)
    }

    func testCalendarAccessibilityTextSizeKeepsDateAndCategoryControlsUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-reset-tracker", "-onboarding-complete",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.collapse"].waitForExistence(timeout: 5))
        app.buttons["calendar.collapse"].tap()
        app.buttons["calendar.previous-day"].tap()
        XCTAssertTrue(app.staticTexts["calendar.selected-date"].exists)
        XCTAssertEqual(app.segmentedControls.count, 0)
        app.buttons["calendar.categories"].tap()
        app.buttons["Tasbih"].tap()
        let edit = app.buttons["calendar.edit-tasbih"]
        for _ in 0..<3 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.textFields["calendar.tasbih-input"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Calendar accessibility text Tasbih editor"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCalendarBanglaSelectedDateAndEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset-state", "-reset-tracker", "-onboarding-complete", "-bangla-language"]
        app.launch()
        app.tabBars.buttons["ক্যালেন্ডার"].tap()
        XCTAssertTrue(app.buttons["calendar.collapse"].waitForExistence(timeout: 5))
        app.buttons["calendar.collapse"].tap()
        app.buttons["calendar.previous-day"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "অতীতের দিন")).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        app.segmentedControls.buttons["তাসবিহ"].tap()
        app.buttons["calendar.edit-tasbih"].tap()
        XCTAssertTrue(app.navigationBars["তাসবিহ সম্পাদনা"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Calendar Bangla Tasbih editor"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
