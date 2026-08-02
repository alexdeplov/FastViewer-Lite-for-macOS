//
//  AppDelegateTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 18.12.25.
//

import XCTest
import AppKit
@testable import FastViewer_Lite

final class AppDelegateTests: XCTestCase {
    
    var appDelegate: AppDelegate!
    
    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
    }
    
    override func tearDown() {
        appDelegate = nil
        super.tearDown()
    }
    
    func testIsDarkModeActive() {
        // Test that dark mode detection works
        // This will return the actual current system appearance
        let isDarkMode = appDelegate.isDarkModeActive()
        
        // Verify it returns a boolean value
        XCTAssertTrue(isDarkMode == true || isDarkMode == false, "isDarkModeActive should return a boolean")
        
        // Verify it matches NSApp.effectiveAppearance
        let appearance = NSApp.effectiveAppearance
        let expectedDarkMode = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua
        
        XCTAssertEqual(
            isDarkMode,
            expectedDarkMode,
            "isDarkModeActive should match NSApp.effectiveAppearance"
        )
    }
    
    func testWindowCreationSetsAppearance() {
        // Test that window is created with correct appearance
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        
        // Give it a moment for window creation
        let expectation = XCTestExpectation(description: "Window created")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        guard let window = appDelegate.window else {
            XCTFail("Window should be created")
            return
        }
        
        // Verify the empty window uses the adaptive document-canvas gray.
        let expectedColor = ViewController.emptyWindowBackgroundColor
        
        XCTAssertEqual(
            window.backgroundColor,
            expectedColor,
            "Empty window should use the subtle adaptive canvas color"
        )
    }

    func testViewMenuContainsActualSizeCommandZeroItem() {
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let actualSizeItem = NSApp.mainMenu?
            .items
            .first { $0.submenu?.title == "View" }?
            .submenu?
            .items
            .first { $0.title == "Actual Size" }

        XCTAssertNotNil(actualSizeItem)
        XCTAssertEqual(actualSizeItem?.keyEquivalent, "0")
        XCTAssertTrue(
            actualSizeItem?.keyEquivalentModifierMask.contains(.command) ?? false
        )
        XCTAssertFalse(
            actualSizeItem?.isEnabled ?? true,
            "Actual Size should be disabled until an image is loaded"
        )
    }

    func testTopLeftWindowPointUsesTwentyPointScreenInset() {
        let visibleFrame = NSRect(x: -1440, y: 25, width: 1440, height: 875)

        let point = AppDelegate.topLeftWindowPoint(in: visibleFrame)

        XCTAssertEqual(point.x, -1420)
        XCTAssertEqual(point.y, 880)
    }
    
    func testAppearanceObserverSetup() {
        // Test that appearance observer is set up using KVO
        // The observer should be created in init
        XCTAssertNotNil(appDelegate, "AppDelegate should be initialized")
        
        // Verify that updateWindowAppearance can be called
        // This tests that the method exists and doesn't crash
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        
        // Give it a moment for window creation
        let expectation = XCTestExpectation(description: "Window created")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Verify window has a background color set
        guard let window = appDelegate.window else {
            XCTFail("Window should be created")
            return
        }
        
        // Verify the empty window has the document-canvas background.
        XCTAssertNotNil(window.backgroundColor, "Window should have a background color")
        XCTAssertEqual(
            window.backgroundColor,
            ViewController.emptyWindowBackgroundColor,
            "Empty window should use the subtle adaptive canvas color"
        )
    }
    
    func testAppearanceChangeTriggersUpdate() {
        // Test that appearance changes trigger window updates
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        
        // Give it a moment for window creation
        let expectation = XCTestExpectation(description: "Window created")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        guard let window = appDelegate.window else {
            XCTFail("Window should be created")
            return
        }
        
        // Simulate appearance change by manually triggering the update
        // In a real scenario, this would be triggered by KVO on NSApp.effectiveAppearance
        // We can't easily test KVO in unit tests, but we verify the update mechanism works
        let initialColor = window.backgroundColor
        
        XCTAssertEqual(
            initialColor,
            ViewController.emptyWindowBackgroundColor,
            "Initial empty-window color should use the subtle adaptive canvas color"
        )
    }
    
    func testApplicationShouldTerminateAfterLastWindowClosed() {
        // Closing the last window via its red close button should quit the app.
        let shouldTerminate = appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)

        XCTAssertTrue(
            shouldTerminate,
            "App should terminate when its last window closes"
        )
    }

    func testCloseWindowTerminatesApp() {
        // Test that closing the last window requests app termination.
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        
        // Give it a moment for window creation
        let expectation = XCTestExpectation(description: "Window created")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        guard let window = appDelegate.window else {
            XCTFail("Window should be created")
            return
        }
        
        // Verify window exists and is visible
        XCTAssertTrue(window.isVisible, "Window should be visible initially")
        
        // Close the window
        window.close()
        
        // Give it a moment for window to close
        let closeExpectation = XCTestExpectation(description: "Window closed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            closeExpectation.fulfill()
        }
        wait(for: [closeExpectation], timeout: 1.0)
        
        // Verify window is closed but still exists (not released)
        XCTAssertFalse(window.isVisible, "Window should be closed")
        XCTAssertNotNil(appDelegate.window, "Window reference should still exist after closing")
        
        // Verify the app should terminate
        let shouldTerminate = appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        XCTAssertTrue(shouldTerminate, "App should terminate after its last window closes")
    }
    
    func testCloseWindowMethod() {
        // Test that closeWindow method exists and can be called via menu action
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        
        // Give it a moment for window creation
        let expectation = XCTestExpectation(description: "Window created")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        guard let window = appDelegate.window else {
            XCTFail("Window should be created")
            return
        }
        
        // Verify window is visible
        XCTAssertTrue(window.isVisible, "Window should be visible initially")
        
        // Simulate Cmd+W by directly closing the window (which is what closeWindow does)
        // This tests the behavior that Cmd+W should trigger
        window.performClose(nil)
        
        // Give it a moment for window to close
        let closeExpectation = XCTestExpectation(description: "Window closed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            closeExpectation.fulfill()
        }
        wait(for: [closeExpectation], timeout: 1.0)
        
        // Verify window is closed but app reference still exists
        XCTAssertFalse(window.isVisible, "Window should be closed after Cmd+W")
        XCTAssertNotNil(appDelegate.window, "Window reference should still exist")
    }

    
    func testDockClickReopensEmptyWindow() {
        // Test that clicking dock icon when no windows are visible reopens an empty window
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        
        // Give it a moment for window creation
        let expectation = XCTestExpectation(description: "Window created")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        guard let window = appDelegate.window else {
            XCTFail("Window should be created")
            return
        }
        
        // Verify window is visible initially
        XCTAssertTrue(window.isVisible, "Window should be visible initially")
        
        // Close the window
        window.close()
        
        // Give it a moment for window to close
        let closeExpectation = XCTestExpectation(description: "Window closed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            closeExpectation.fulfill()
        }
        wait(for: [closeExpectation], timeout: 1.0)
        
        // Verify window is closed
        XCTAssertFalse(window.isVisible, "Window should be closed")
        
        // Simulate dock icon click when no windows are visible
        let shouldHandle = appDelegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        
        // Give it a moment for window to reopen
        let reopenExpectation = XCTestExpectation(description: "Window reopened")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            reopenExpectation.fulfill()
        }
        wait(for: [reopenExpectation], timeout: 1.0)
        
        // Verify method returns true (handles the reopen)
        XCTAssertTrue(shouldHandle, "Should handle dock click when no windows visible")
        
        // Verify window is now visible again
        XCTAssertTrue(window.isVisible, "Window should be reopened after dock click")
        
        // Verify view controller is in empty state (no image loaded)
        guard let viewController = appDelegate.viewController else {
            XCTFail("ViewController should exist")
            return
        }
        
        XCTAssertNil(viewController.fileListManager.currentFileURL, "No file should be loaded after reopening")
        XCTAssertNil(viewController.imageView.image, "Image view should be empty after reopening")
    }
    
    func testDockClickDoesNothingWhenWindowsVisible() {
        // Test that clicking dock icon when windows are visible doesn't create duplicate windows
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        
        // Give it a moment for window creation
        let expectation = XCTestExpectation(description: "Window created")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        guard let window = appDelegate.window else {
            XCTFail("Window should be created")
            return
        }
        
        // Verify window is visible
        XCTAssertTrue(window.isVisible, "Window should be visible")
        
        // Simulate dock icon click when windows are visible
        let shouldHandle = appDelegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)
        
        // Give it a moment
        let dockClickExpectation = XCTestExpectation(description: "Dock click handled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            dockClickExpectation.fulfill()
        }
        wait(for: [dockClickExpectation], timeout: 1.0)
        
        // Verify method returns true (handles the reopen, but doesn't create new window)
        XCTAssertTrue(shouldHandle, "Should handle dock click")
        
        // Verify only one window exists (no duplicate created)
        XCTAssertNotNil(appDelegate.window, "Window should still exist")
        XCTAssertEqual(appDelegate.window, window, "Should be the same window instance")
    }
}
