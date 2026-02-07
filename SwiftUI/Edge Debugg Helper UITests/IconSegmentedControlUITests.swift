import XCTest

final class IconSegmentedControlUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Crash Reproduction Tests
    // Note: UI tests can't drag sidebar splitters, so we simulate the crash scenario
    // by opening/closing inspector (which triggers layout recalculations) and clicking segments

    /// Reproduces crash scenario: Navigate -> Open inspector -> Click segments
    /// This matches steps 1-8 of reproduction as closely as UI tests allow
    @MainActor
    func testReproduceCrashScenario_InspectorThenClickSegments() throws {
        // Step 1-2: Launch and wait for app
        sleep(2)

        // Step 3: Navigate to MainStudioView by selecting first app
        let firstAppButton = app.buttons.matching(identifier: "AppCard").firstMatch
        if firstAppButton.exists && firstAppButton.isEnabled {
            firstAppButton.click()
            sleep(2)
        }

        // Step 4-6: Can't drag sidebar in UI tests, but opening inspector triggers similar layout changes
        let inspectorToggle = app.buttons["Toggle Inspector"]
        if inspectorToggle.exists && inspectorToggle.isEnabled {
            // Toggle inspector multiple times to trigger layout recalculations
            inspectorToggle.click()  // Open
            sleep(1)
            inspectorToggle.click()  // Close
            sleep(1)
            inspectorToggle.click()  // Open again
            sleep(1)
        }

        // Step 7: Click segments to navigate
        let segmentedControl = app.segmentedControls["SidebarSegmentedControl"]
        if segmentedControl.exists {
            let segments = segmentedControl.radioButtons.allElementsBoundByIndex

            // Click through all segments
            for (index, segment) in segments.enumerated() {
                if segment.exists && segment.isEnabled {
                    NSLog("Clicking segment \(index)")
                    segment.click()
                    sleep(1)
                }
            }
        }

        // Step 8: If we reach here, no crash occurred
        XCTAssertTrue(app.exists, "App should not crash after inspector toggles and navigation")
    }

    @MainActor
    func testMultipleInspectorTogglesWithSegmentClicks_DoesNotCrash() throws {
        sleep(2)

        // Navigate to MainStudioView
        let firstAppButton = app.buttons.matching(identifier: "AppCard").firstMatch
        if firstAppButton.exists && firstAppButton.isEnabled {
            firstAppButton.click()
            sleep(2)
        }

        let inspectorToggle = app.buttons["Toggle Inspector"]
        let segmentedControl = app.segmentedControls["SidebarSegmentedControl"]

        // Stress test: Toggle inspector and click segments repeatedly
        for iteration in 0..<5 {
            // Toggle inspector (triggers layout recalculation)
            if inspectorToggle.exists && inspectorToggle.isEnabled {
                inspectorToggle.click()
                usleep(500000)  // 0.5 seconds
            }

            // Click a segment after each toggle
            if segmentedControl.exists {
                let segments = segmentedControl.radioButtons.allElementsBoundByIndex
                if !segments.isEmpty {
                    let index = iteration % segments.count
                    if segments[index].exists && segments[index].isEnabled {
                        segments[index].click()
                        usleep(500000)
                    }
                }
            }
        }

        XCTAssertTrue(app.exists, "App should survive multiple inspector toggles and segment clicks")
    }

    @MainActor
    func testRapidSegmentSwitchingWithInspectorOpen_DoesNotCrash() throws {
        sleep(2)

        // Navigate to MainStudioView
        let firstAppButton = app.buttons.matching(identifier: "AppCard").firstMatch
        if firstAppButton.exists && firstAppButton.isEnabled {
            firstAppButton.click()
            sleep(2)
        }

        // Open inspector
        let inspectorToggle = app.buttons["Toggle Inspector"]
        if inspectorToggle.exists && inspectorToggle.isEnabled {
            inspectorToggle.click()
            sleep(1)
        }

        // Rapidly click through segments
        let segmentedControl = app.segmentedControls["SidebarSegmentedControl"]
        if segmentedControl.exists {
            let segments = segmentedControl.radioButtons.allElementsBoundByIndex

            // 20 rapid segment switches
            for iteration in 0..<20 {
                if !segments.isEmpty {
                    let index = iteration % segments.count
                    if segments[index].exists && segments[index].isEnabled {
                        segments[index].click()
                        usleep(100000)  // 0.1 seconds - rapid
                    }
                }
            }
        }

        XCTAssertTrue(app.exists, "App should survive rapid segment switching with inspector open")
    }

    @MainActor
    func testSegmentClicksAfterMultipleLayoutChanges_DoesNotCrash() throws {
        sleep(2)

        // Navigate to MainStudioView
        let firstAppButton = app.buttons.matching(identifier: "AppCard").firstMatch
        if firstAppButton.exists && firstAppButton.isEnabled {
            firstAppButton.click()
            sleep(2)
        }

        let inspectorToggle = app.buttons["Toggle Inspector"]
        let segmentedControl = app.segmentedControls["SidebarSegmentedControl"]

        // Create many layout changes by toggling inspector rapidly
        for _ in 0..<10 {
            if inspectorToggle.exists && inspectorToggle.isEnabled {
                inspectorToggle.click()
                usleep(300000)  // 0.3 seconds
            }
        }

        // Now click through all segments
        if segmentedControl.exists {
            let segments = segmentedControl.radioButtons.allElementsBoundByIndex
            for (index, segment) in segments.enumerated() {
                if segment.exists && segment.isEnabled {
                    NSLog("After layout changes, clicking segment \(index)")
                    segment.click()
                    sleep(1)
                }
            }
        }

        XCTAssertTrue(app.exists, "App should not crash after multiple layout changes and segment clicks")
    }

    @MainActor
    func testCycleAllSegmentsWithInspectorChanges_DoesNotCrash() throws {
        sleep(2)

        // Navigate to MainStudioView
        let firstAppButton = app.buttons.matching(identifier: "AppCard").firstMatch
        if firstAppButton.exists && firstAppButton.isEnabled {
            firstAppButton.click()
            sleep(2)
        }

        let inspectorToggle = app.buttons["Toggle Inspector"]
        let segmentedControl = app.segmentedControls["SidebarSegmentedControl"]

        // For each segment, toggle inspector then click segment
        if segmentedControl.exists {
            let segments = segmentedControl.radioButtons.allElementsBoundByIndex

            for (index, segment) in segments.enumerated() {
                // Toggle inspector before clicking each segment
                if inspectorToggle.exists && inspectorToggle.isEnabled {
                    inspectorToggle.click()
                    usleep(500000)
                }

                // Click the segment
                if segment.exists && segment.isEnabled {
                    NSLog("Segment \(index) click after inspector toggle")
                    segment.click()
                    sleep(1)
                }
            }
        }

        XCTAssertTrue(app.exists, "App should not crash when cycling through segments with inspector changes")
    }

    @MainActor
    func testBasicAppLaunchAndNavigation_DoesNotCrash() throws {
        // Basic smoke test
        sleep(2)

        XCTAssertTrue(app.exists, "App should launch successfully")

        // Navigate to MainStudioView
        let firstAppButton = app.buttons.matching(identifier: "AppCard").firstMatch
        if firstAppButton.exists && firstAppButton.isEnabled {
            firstAppButton.click()
            sleep(2)
        }

        // Toggle inspector a few times
        let inspectorToggle = app.buttons["Toggle Inspector"]
        if inspectorToggle.exists && inspectorToggle.isEnabled {
            inspectorToggle.click()
            sleep(1)
            inspectorToggle.click()
            sleep(1)
        }

        // Click through segments once
        let segmentedControl = app.segmentedControls["SidebarSegmentedControl"]
        if segmentedControl.exists {
            let segments = segmentedControl.radioButtons.allElementsBoundByIndex
            for segment in segments {
                if segment.exists && segment.isEnabled {
                    segment.click()
                    usleep(500000)
                }
            }
        }

        XCTAssertTrue(app.exists, "App should not crash during basic navigation")
    }
}
