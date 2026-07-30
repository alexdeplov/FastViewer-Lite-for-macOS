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

    func testDefaultAppsButtonAlwaysOffersAnAction() throws {
        let defaultAppsBox = try XCTUnwrap(
            settingsViewController.view.subviews.compactMap { $0 as? NSBox }
                .first { $0.identifier?.rawValue == "defaultAppsContainer" }
        )
        let button = try XCTUnwrap(
            defaultAppsBox.contentView?.subviews.compactMap { $0 as? NSButton }.first
        )

        XCTAssertTrue(button.isEnabled)
        XCTAssertNotEqual(button.title, "FastViewer Is Default")
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
        let windowRect = NSRect(origin: .zero, size: SettingsViewController.preferredContentSize)
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

    func testSettingsLayoutUsesMacLayoutGuidelineSpacing() throws {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsViewController.preferredContentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = settingsViewController
        settingsViewController.view.layoutSubtreeIfNeeded()

        let rootView = settingsViewController.view
        XCTAssertEqual(rootView.frame.width, 440, accuracy: 0.5)
        XCTAssertEqual(rootView.frame.height, SettingsViewController.preferredContentSize.height, accuracy: 0.5)
        let defaultAppsBox = try XCTUnwrap(
            rootView.subviews.compactMap { $0 as? NSBox }
                .first { $0.identifier?.rawValue == "defaultAppsContainer" }
        )
        let displayBox = try XCTUnwrap(
            rootView.subviews.compactMap { $0 as? NSBox }
                .first { $0.identifier?.rawValue == "displayContainer" }
        )
        let defaultAppsSeparator = try XCTUnwrap(
            rootView.subviews.compactMap { $0 as? NSBox }
                .first { $0.boxType == .separator }
        )

        XCTAssertEqual(defaultAppsBox.frame.minX, 20, accuracy: 0.5)
        XCTAssertEqual(rootView.bounds.maxX - defaultAppsBox.frame.maxX, 20, accuracy: 0.5)
        XCTAssertEqual(rootView.bounds.maxY - defaultAppsBox.frame.maxY, 14, accuracy: 0.5)
        XCTAssertEqual(displayBox.frame.minX, defaultAppsBox.frame.minX, accuracy: 0.5)
        XCTAssertEqual(displayBox.frame.maxX, defaultAppsBox.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(displayBox.frame.minY, 20, accuracy: 0.5)
        XCTAssertEqual(defaultAppsBox.titlePosition, .noTitle)
        XCTAssertEqual(displayBox.titlePosition, .noTitle)
        XCTAssertTrue(defaultAppsBox.isTransparent)
        XCTAssertTrue(displayBox.isTransparent)

        let defaultAppsSeparatorAlignmentFrame = defaultAppsSeparator.alignmentRect(
            forFrame: defaultAppsSeparator.frame
        )
        XCTAssertEqual(
            defaultAppsBox.frame.minY - defaultAppsSeparatorAlignmentFrame.maxY,
            12,
            accuracy: 0.5
        )
        XCTAssertEqual(
            defaultAppsSeparatorAlignmentFrame.minY - displayBox.frame.maxY,
            12,
            accuracy: 0.5
        )
        XCTAssertEqual(defaultAppsSeparator.frame.minX, 20, accuracy: 0.5)
        XCTAssertEqual(rootView.bounds.maxX - defaultAppsSeparator.frame.maxX, 20, accuracy: 0.5)

        let defaultContent = try XCTUnwrap(defaultAppsBox.contentView)
        let displayContent = try XCTUnwrap(displayBox.contentView)
        let imageFilesLabel = try XCTUnwrap(
            defaultContent.subviews.compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "Image files:" }
        )
        let defaultAppsButton = try XCTUnwrap(
            defaultContent.subviews.compactMap { $0 as? NSButton }.first
        )
        let fileInfoLabel = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "File info:" }
        )
        let showFileSize = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Show file size" }
        )
        let showImageResolution = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Show image resolution" }
        )
        let autoResize = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Auto-resize window to image size" }
        )
        let resizeLabel = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "Resize from:" }
        )
        let centerAnchorButton = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Center" }
        )
        let topLeftAnchorButton = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Top Left" }
        )
        let transparencyLabel = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "Transparency:" }
        )
        let solidColorButton = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Solid color" }
        )
        let checkersButton = try XCTUnwrap(
            displayContent.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Checkers" }
        )
        let separators = displayContent.subviews.compactMap { $0 as? NSBox }
            .filter { $0.boxType == .separator }
            .sorted { $0.frame.maxY > $1.frame.maxY }

        let imageFilesAlignmentFrame = imageFilesLabel.alignmentRect(forFrame: imageFilesLabel.frame)
        let defaultButtonAlignmentFrame = defaultAppsButton.alignmentRect(forFrame: defaultAppsButton.frame)
        let fileInfoAlignmentFrame = fileInfoLabel.alignmentRect(forFrame: fileInfoLabel.frame)
        let fileSizeAlignmentFrame = showFileSize.alignmentRect(forFrame: showFileSize.frame)
        let resolutionAlignmentFrame = showImageResolution.alignmentRect(
            forFrame: showImageResolution.frame
        )
        let autoResizeAlignmentFrame = autoResize.alignmentRect(forFrame: autoResize.frame)
        let resizeLabelAlignmentFrame = resizeLabel.alignmentRect(forFrame: resizeLabel.frame)
        let centerAnchorAlignmentFrame = centerAnchorButton.alignmentRect(
            forFrame: centerAnchorButton.frame
        )
        let topLeftAnchorAlignmentFrame = topLeftAnchorButton.alignmentRect(
            forFrame: topLeftAnchorButton.frame
        )
        let transparencyLabelAlignmentFrame = transparencyLabel.alignmentRect(
            forFrame: transparencyLabel.frame
        )
        let solidColorAlignmentFrame = solidColorButton.alignmentRect(
            forFrame: solidColorButton.frame
        )
        let checkersAlignmentFrame = checkersButton.alignmentRect(forFrame: checkersButton.frame)

        XCTAssertEqual(
            imageFilesAlignmentFrame.maxX + 6,
            defaultButtonAlignmentFrame.minX,
            accuracy: 0.5
        )
        XCTAssertEqual(
            fileInfoAlignmentFrame.maxX + 6,
            fileSizeAlignmentFrame.minX,
            accuracy: 0.5
        )
        XCTAssertEqual(resizeLabelAlignmentFrame.minX, fileInfoAlignmentFrame.minX, accuracy: 0.5)
        XCTAssertEqual(resizeLabelAlignmentFrame.maxX, fileInfoAlignmentFrame.maxX, accuracy: 0.5)
        XCTAssertEqual(
            resizeLabelAlignmentFrame.maxX + 6,
            centerAnchorAlignmentFrame.minX,
            accuracy: 0.5
        )
        XCTAssertEqual(
            centerAnchorAlignmentFrame.minX,
            fileSizeAlignmentFrame.minX,
            accuracy: 0.5
        )
        XCTAssertEqual(
            autoResizeAlignmentFrame.minY - centerAnchorAlignmentFrame.maxY,
            14,
            accuracy: 0.5
        )
        XCTAssertEqual(
            centerAnchorAlignmentFrame.minX,
            topLeftAnchorAlignmentFrame.minX,
            accuracy: 0.5
        )
        XCTAssertEqual(
            centerAnchorAlignmentFrame.minY - topLeftAnchorAlignmentFrame.maxY,
            6,
            accuracy: 0.5
        )
        XCTAssertEqual(
            transparencyLabelAlignmentFrame.minX,
            fileInfoAlignmentFrame.minX,
            accuracy: 0.5
        )
        XCTAssertEqual(
            transparencyLabelAlignmentFrame.maxX,
            fileInfoAlignmentFrame.maxX,
            accuracy: 0.5
        )
        XCTAssertEqual(solidColorAlignmentFrame.minX, fileSizeAlignmentFrame.minX, accuracy: 0.5)
        XCTAssertEqual(solidColorAlignmentFrame.minX, checkersAlignmentFrame.minX, accuracy: 0.5)
        XCTAssertEqual(
            solidColorAlignmentFrame.minY - checkersAlignmentFrame.maxY,
            6,
            accuracy: 0.5
        )
        XCTAssertEqual(separators.count, 2)
        if separators.count == 2 {
            let fileInfoSeparator = separators[0]
            let windowSeparator = separators[1]
            let fileInfoSeparatorAlignmentFrame = fileInfoSeparator.alignmentRect(
                forFrame: fileInfoSeparator.frame
            )
            let windowSeparatorAlignmentFrame = windowSeparator.alignmentRect(
                forFrame: windowSeparator.frame
            )

            XCTAssertEqual(
                resolutionAlignmentFrame.minY - fileInfoSeparatorAlignmentFrame.maxY,
                12,
                accuracy: 0.5
            )
            XCTAssertEqual(
                fileInfoSeparatorAlignmentFrame.minY - autoResizeAlignmentFrame.maxY,
                12,
                accuracy: 0.5
            )
            XCTAssertEqual(
                topLeftAnchorAlignmentFrame.minY - windowSeparatorAlignmentFrame.maxY,
                12,
                accuracy: 0.5
            )
            XCTAssertEqual(
                windowSeparatorAlignmentFrame.minY - solidColorAlignmentFrame.maxY,
                12,
                accuracy: 0.5
            )
        }
        XCTAssertEqual(
            defaultAppsButton.frame.height,
            defaultAppsButton.intrinsicContentSize.height,
            accuracy: 0.5
        )
        XCTAssertEqual(
            showFileSize.frame.height,
            showFileSize.intrinsicContentSize.height,
            accuracy: 0.5
        )
        XCTAssertTrue(displayContent.subviews.compactMap { $0 as? NSPopUpButton }.isEmpty)
    }

    func testResizeAnchorRadioButtonsUpdatePreference() throws {
        let originalAutoResize = SettingsManager.shared.autoResizeToImageSize
        let originalAnchor = SettingsManager.shared.windowResizeAnchor
        defer {
            SettingsManager.shared.autoResizeToImageSize = originalAutoResize
            SettingsManager.shared.windowResizeAnchor = originalAnchor
        }

        SettingsManager.shared.autoResizeToImageSize = true
        SettingsManager.shared.windowResizeAnchor = .center
        settingsViewController.loadCurrentValues()

        let displayBox = try XCTUnwrap(
            settingsViewController.view.subviews.compactMap { $0 as? NSBox }
                .first { $0.identifier?.rawValue == "displayContainer" }
        )
        let contentView = try XCTUnwrap(displayBox.contentView)
        let resizeLabel = try XCTUnwrap(
            contentView.subviews.compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "Resize from:" }
        )
        let centerButton = try XCTUnwrap(
            contentView.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Center" }
        )
        let topLeftButton = try XCTUnwrap(
            contentView.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Top Left" }
        )

        XCTAssertTrue(centerButton.isEnabled)
        XCTAssertEqual(centerButton.state, .on)
        XCTAssertEqual(topLeftButton.state, .off)

        topLeftButton.performClick(nil)

        XCTAssertEqual(SettingsManager.shared.windowResizeAnchor, .topLeft)
        XCTAssertEqual(centerButton.state, .off)
        XCTAssertEqual(topLeftButton.state, .on)

        SettingsManager.shared.autoResizeToImageSize = false
        settingsViewController.loadCurrentValues()

        XCTAssertFalse(resizeLabel.isEnabled)
        XCTAssertEqual(resizeLabel.textColor, .disabledControlTextColor)
        XCTAssertFalse(centerButton.isEnabled)
        XCTAssertFalse(topLeftButton.isEnabled)
    }

    func testTransparencyRadioButtonsUpdatePreference() throws {
        let originalBackground = SettingsManager.shared.transparencyBackground
        defer {
            SettingsManager.shared.transparencyBackground = originalBackground
        }

        SettingsManager.shared.transparencyBackground = .solidColor
        settingsViewController.loadCurrentValues()

        let displayBox = try XCTUnwrap(
            settingsViewController.view.subviews.compactMap { $0 as? NSBox }
                .first { $0.identifier?.rawValue == "displayContainer" }
        )
        let contentView = try XCTUnwrap(displayBox.contentView)
        let solidColorButton = try XCTUnwrap(
            contentView.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Solid color" }
        )
        let checkersButton = try XCTUnwrap(
            contentView.subviews.compactMap { $0 as? NSButton }
                .first { $0.title == "Checkers" }
        )

        XCTAssertEqual(solidColorButton.state, .on)
        XCTAssertEqual(checkersButton.state, .off)

        checkersButton.performClick(nil)

        XCTAssertEqual(SettingsManager.shared.transparencyBackground, .checkers)
        XCTAssertEqual(solidColorButton.state, .off)
        XCTAssertEqual(checkersButton.state, .on)
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
        let displayContainer = settingsViewController.view.subviews.first {
            $0.identifier?.rawValue == "displayContainer"
        }
        XCTAssertNotNil(displayContainer, "Display settings container should exist")
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
        let displayContainer = settingsViewController.view.subviews.first {
            $0.identifier?.rawValue == "displayContainer"
        }
        XCTAssertNotNil(displayContainer, "Display settings container should exist")
    }
}
