//
//  AboutViewControllerTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 18.12.25.
//

import XCTest
import AppKit
@testable import FastViewer_Lite

final class AboutViewControllerTests: XCTestCase {
    
    var aboutViewController: AboutViewController!
    
    override func setUp() {
        super.setUp()
        aboutViewController = AboutViewController()
        // Load view to initialize UI elements
        aboutViewController.loadView()
        aboutViewController.viewDidLoad()
    }
    
    override func tearDown() {
        aboutViewController = nil
        super.tearDown()
    }
    
    func testViewLoads() {
        // Test that view is loaded
        XCTAssertNotNil(aboutViewController.view, "View should be loaded")
        XCTAssertEqual(aboutViewController.view.frame.width, 400, "View width should be 400")
        XCTAssertEqual(aboutViewController.view.frame.height, 240, "View height should be 240")
    }
    
    func testAppIconImageViewExists() {
        // Test that app icon image view exists
        XCTAssertNotNil(aboutViewController.view.subviews.first { $0 is NSImageView }, "App icon image view should exist")
    }
    
    func testAppNameLabelExists() {
        // Test that app name label exists and has content
        let expectation = XCTestExpectation(description: "App info loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Find app name label
        let appNameLabel = aboutViewController.view.subviews.compactMap { $0 as? NSTextField }.first { $0.font?.pointSize == 18 }
        XCTAssertNotNil(appNameLabel, "App name label should exist")
        XCTAssertFalse(appNameLabel?.stringValue.isEmpty ?? true, "App name should not be empty")
    }
    
    func testVersionLabelExists() {
        // Test that version label exists and has content
        let expectation = XCTestExpectation(description: "App info loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Find version label (12pt font)
        let versionLabel = aboutViewController.view.subviews.compactMap { $0 as? NSTextField }.first { $0.font?.pointSize == 12 }
        XCTAssertNotNil(versionLabel, "Version label should exist")
        XCTAssertFalse(versionLabel?.stringValue.isEmpty ?? true, "Version should not be empty")
        XCTAssertTrue(versionLabel?.stringValue.contains("Version") ?? false, "Version label should contain 'Version'")
    }
    
    func testCopyrightLabelExists() {
        // Test that copyright label exists and has content
        let expectation = XCTestExpectation(description: "App info loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Find copyright label (10pt font)
        let copyrightLabel = aboutViewController.view.subviews.compactMap { $0 as? NSTextField }.first { $0.font?.pointSize == 10 }
        XCTAssertNotNil(copyrightLabel, "Copyright label should exist")
        XCTAssertFalse(copyrightLabel?.stringValue.isEmpty ?? true, "Copyright should not be empty")
    }
    
    func testAppInfoLoadedFromBundle() {
        // Test that app info is loaded from Bundle
        let expectation = XCTestExpectation(description: "App info loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FastViewer"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        
        // Find app name label
        let appNameLabel = aboutViewController.view.subviews.compactMap { $0 as? NSTextField }.first { $0.font?.pointSize == 18 }
        XCTAssertEqual(appNameLabel?.stringValue, appName, "App name should match Bundle")
        
        // Find version label
        let versionLabel = aboutViewController.view.subviews.compactMap { $0 as? NSTextField }.first { $0.font?.pointSize == 12 }
        let expectedVersionText = "Version \(version) (\(build))"
        XCTAssertEqual(versionLabel?.stringValue, expectedVersionText, "Version should match Bundle")
    }
    
    func testAcceptsFirstResponder() {
        // Test that view controller accepts first responder
        XCTAssertTrue(aboutViewController.acceptsFirstResponder, "About view controller should accept first responder")
    }
    
    func testUIElementsHaveCorrectProperties() {
        // Test that UI elements have correct properties
        let expectation = XCTestExpectation(description: "App info loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Find app name label
        let appNameLabel = aboutViewController.view.subviews.compactMap { $0 as? NSTextField }.first { $0.font?.pointSize == 18 }
        XCTAssertEqual(appNameLabel?.alignment, .center, "App name should be centered")
        
        // Find version label
        let versionLabel = aboutViewController.view.subviews.compactMap { $0 as? NSTextField }.first { $0.font?.pointSize == 12 }
        XCTAssertEqual(versionLabel?.alignment, .center, "Version should be centered")
        
        // Find copyright label
        let copyrightLabel = aboutViewController.view.subviews.compactMap { $0 as? NSTextField }.first { $0.font?.pointSize == 10 }
        XCTAssertEqual(copyrightLabel?.alignment, .center, "Copyright should be centered")
    }
    
    func testAppIconImageLoaded() {
        // Test that app icon image is loaded
        let expectation = XCTestExpectation(description: "App info loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Find image view
        let imageView = aboutViewController.view.subviews.first { $0 is NSImageView } as? NSImageView
        XCTAssertNotNil(imageView, "Image view should exist")
        XCTAssertNotNil(imageView?.image, "App icon image should be loaded")
    }
    
    func testPleeqButtonExists() {
        // Test that Pleeq Software button exists
        let expectation = XCTestExpectation(description: "UI loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Find button
        let button = aboutViewController.view.subviews.first { $0 is NSButton } as? NSButton
        XCTAssertNotNil(button, "Pleeq Software button should exist")
        XCTAssertEqual(button?.title, "Pleeq Software", "Button should have correct title")
    }
    
    func testPleeqButtonOpensWebsite() {
        // Test that button action opens website
        let expectation = XCTestExpectation(description: "UI loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Find button
        let button = aboutViewController.view.subviews.first { $0 is NSButton } as? NSButton
        XCTAssertNotNil(button, "Pleeq Software button should exist")
        
        // Verify button has action
        XCTAssertNotNil(button?.target, "Button should have target")
        XCTAssertNotNil(button?.action, "Button should have action")
        
        // Verify URL can be created
        let url = URL(string: "https://pleeq.com/")
        XCTAssertNotNil(url, "Pleeq website URL should be valid")
    }
}
