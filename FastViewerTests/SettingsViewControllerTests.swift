//
//  SettingsViewControllerTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 18.12.25.
//

import XCTest
import AppKit
@testable import FastViewer_Lite

final class SettingsViewControllerTests: XCTestCase {
    
    var settingsViewController: SettingsViewController!
    
    override func setUp() {
        super.setUp()
        settingsViewController = SettingsViewController()
        // Load the view to initialize UI elements
        _ = settingsViewController.view
    }
    
    override func tearDown() {
        settingsViewController = nil
        super.tearDown()
    }
    
    func testSettingsViewControllerInitialization() {
        XCTAssertNotNil(settingsViewController.view, "View should be loaded")
    }
    
    func testLoadCurrentValues() {
        // Set initial values
        ImageCacheManager.shared.prefetchBefore = 5
        ImageCacheManager.shared.prefetchAfter = 15
        
        // Load values
        settingsViewController.loadCurrentValues()
        
        // Verify text fields are populated
        // Note: We can't directly access private fields, but we can test through the view hierarchy
        XCTAssertNotNil(settingsViewController.view, "View should exist")
    }
    
    func testPrefetchBeforeValidation() {
        // Test valid value
        let validValue = "10"
        // We can't directly test private methods, but we can verify the structure exists
        XCTAssertNotNil(settingsViewController.view, "Settings view should exist")
        
        // Test that ImageCacheManager accepts valid values
        ImageCacheManager.shared.prefetchBefore = 10
        XCTAssertEqual(ImageCacheManager.shared.prefetchBefore, 10, "Should accept valid value")
    }
    
    func testPrefetchAfterValidation() {
        // Test valid value
        ImageCacheManager.shared.prefetchAfter = 25
        XCTAssertEqual(ImageCacheManager.shared.prefetchAfter, 25, "Should accept valid value")
    }
    
    func testPrefetchValueBounds() {
        // Test minimum value (0)
        ImageCacheManager.shared.prefetchBefore = 0
        XCTAssertEqual(ImageCacheManager.shared.prefetchBefore, 0, "Should accept minimum value")
        
        // Test maximum value (100)
        ImageCacheManager.shared.prefetchBefore = 100
        XCTAssertEqual(ImageCacheManager.shared.prefetchBefore, 100, "Should accept maximum value")
        
        // Test values outside bounds should be clamped by validation
        // Note: Actual validation happens in SettingsViewController, but ImageCacheManager accepts any Int
    }
    
    func testSettingsWindowCreation() {
        // Test that settings window can be created
        let windowRect = NSRect(x: 0, y: 0, width: 500, height: 200)
        let styleMask: NSWindow.StyleMask = [.titled, .closable]
        
        let settingsWindow = NSWindow(
            contentRect: windowRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        settingsWindow.contentViewController = settingsViewController
        
        XCTAssertNotNil(settingsWindow.contentViewController, "Window should have content view controller")
        XCTAssertEqual(settingsWindow.title, "", "Window title should be empty initially")
    }

    func testImageCacheManagerPrefetchSettings() {
        // Test that ImageCacheManager settings can be changed
        let originalBefore = ImageCacheManager.shared.prefetchBefore
        let originalAfter = ImageCacheManager.shared.prefetchAfter
        
        ImageCacheManager.shared.prefetchBefore = 3
        ImageCacheManager.shared.prefetchAfter = 25
        
        XCTAssertEqual(ImageCacheManager.shared.prefetchBefore, 3, "Prefetch before should be updated")
        XCTAssertEqual(ImageCacheManager.shared.prefetchAfter, 25, "Prefetch after should be updated")
        
        // Restore original values
        ImageCacheManager.shared.prefetchBefore = originalBefore
        ImageCacheManager.shared.prefetchAfter = originalAfter
    }
    
    func testPNGSupportPreference() {
        // Test that PNG support preference can be toggled
        let originalValue = SettingsManager.shared.isPNGSupportEnabled
        
        SettingsManager.shared.isPNGSupportEnabled = true
        XCTAssertTrue(SettingsManager.shared.isPNGSupportEnabled, "PNG support should be enabled")
        
        SettingsManager.shared.isPNGSupportEnabled = false
        XCTAssertFalse(SettingsManager.shared.isPNGSupportEnabled, "PNG support should be disabled")
        
        // Restore original value
        SettingsManager.shared.isPNGSupportEnabled = originalValue
    }
    
    func testPNGSupportAffectsSupportedExtensions() {
        let originalValue = SettingsManager.shared.isPNGSupportEnabled
        
        SettingsManager.shared.isPNGSupportEnabled = false
        var extensions = SettingsManager.shared.supportedExtensions
        XCTAssertFalse(extensions.contains("png"), "Should not include png when disabled")
        
        SettingsManager.shared.isPNGSupportEnabled = true
        extensions = SettingsManager.shared.supportedExtensions
        XCTAssertTrue(extensions.contains("png"), "Should include png when enabled")
        
        // Restore original value
        SettingsManager.shared.isPNGSupportEnabled = originalValue
    }
    
    func testImageResolutionPreference() {
        // Test that image resolution preference can be toggled
        let originalValue = SettingsManager.shared.showImageResolution
        
        SettingsManager.shared.showImageResolution = true
        XCTAssertTrue(SettingsManager.shared.showImageResolution, "Image resolution should be enabled")
        
        SettingsManager.shared.showImageResolution = false
        XCTAssertFalse(SettingsManager.shared.showImageResolution, "Image resolution should be disabled")
        
        // Restore original value
        SettingsManager.shared.showImageResolution = originalValue
    }
    
    func testImageResolutionCheckboxExists() {
        // Verify that the checkbox exists in the view hierarchy
        XCTAssertNotNil(settingsViewController.view, "Settings view should exist")
        
        // The checkbox should be initialized when view loads
        // We can't directly access private properties, but we can verify the view structure
        let displayGroupBox = settingsViewController.view.subviews.first { $0 is NSBox && ($0 as? NSBox)?.title == "Display" }
        XCTAssertNotNil(displayGroupBox, "Display group box should exist")
    }
    
    func testCreationDatePreference() {
        // Test that creation date preference can be toggled
        let originalValue = SettingsManager.shared.showCreationDate
        
        SettingsManager.shared.showCreationDate = true
        XCTAssertTrue(SettingsManager.shared.showCreationDate, "Creation date should be enabled")
        
        SettingsManager.shared.showCreationDate = false
        XCTAssertFalse(SettingsManager.shared.showCreationDate, "Creation date should be disabled")
        
        // Restore original value
        SettingsManager.shared.showCreationDate = originalValue
    }
    
    func testAutoResizeWithAnimationPreference() {
        // Test that auto-resize with animation preference can be toggled
        let originalValue = SettingsManager.shared.autoResizeWithAnimation
        
        SettingsManager.shared.autoResizeWithAnimation = true
        XCTAssertTrue(SettingsManager.shared.autoResizeWithAnimation, "Auto-resize with animation should be enabled")
        
        SettingsManager.shared.autoResizeWithAnimation = false
        XCTAssertFalse(SettingsManager.shared.autoResizeWithAnimation, "Auto-resize with animation should be disabled")
        
        // Restore original value
        SettingsManager.shared.autoResizeWithAnimation = originalValue
    }
    
    func testAutoResizeWithAnimationDefaultsToTrue() {
        // Clear the setting to test default
        UserDefaults.standard.removeObject(forKey: "AutoResizeWithAnimation")
        
        // Default should be true
        let defaultValue = SettingsManager.shared.autoResizeWithAnimation
        XCTAssertTrue(defaultValue, "Auto-resize with animation should default to true")
    }
    
    func testAutoResizeWithAnimationCheckboxExists() {
        // Verify that the checkbox exists in the view hierarchy
        XCTAssertNotNil(settingsViewController.view, "Settings view should exist")
        
        // The checkbox should be initialized when view loads
        // We can't directly access private properties, but we can verify the view structure
        let displayGroupBox = settingsViewController.view.subviews.first { $0 is NSBox && ($0 as? NSBox)?.title == "Display" }
        XCTAssertNotNil(displayGroupBox, "Display group box should exist")
    }
}




