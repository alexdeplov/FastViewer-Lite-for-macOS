//
//  SettingsManagerTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 18.12.25.
//

import XCTest
@testable import FastViewer_Lite

final class SettingsManagerTests: XCTestCase {
    
    var settingsManager: SettingsManager!
    
    override func setUp() {
        super.setUp()
        settingsManager = SettingsManager.shared
        
        // Reset PNG, WebP, and AVIF support to default (false) before each test
        settingsManager.isPNGSupportEnabled = false
        settingsManager.isWebPSupportEnabled = false
        settingsManager.isAVIFSupportEnabled = false
        
        // Clear UserDefaults for this test suite
        UserDefaults.standard.removeObject(forKey: "PNGSupportEnabled")
        UserDefaults.standard.removeObject(forKey: "WebPSupportEnabled")
        UserDefaults.standard.removeObject(forKey: "AVIFSupportEnabled")
        UserDefaults.standard.removeObject(forKey: "ShowFileSize")
        UserDefaults.standard.removeObject(forKey: "ShowImageResolution")
        UserDefaults.standard.removeObject(forKey: "ShowCreationDate")
        UserDefaults.standard.removeObject(forKey: "ShowFileTag")
        UserDefaults.standard.removeObject(forKey: "AutoResizeToImageSize")
        UserDefaults.standard.removeObject(forKey: "AutoResizeWithAnimation")
        UserDefaults.standard.removeObject(forKey: "WindowResizeAnchor")
        UserDefaults.standard.removeObject(forKey: "FileNameDisplayLocation")
        UserDefaults.standard.removeObject(forKey: "DefaultFileAssociationsSet")
    }
    
    override func tearDown() {
        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: "PNGSupportEnabled")
        UserDefaults.standard.removeObject(forKey: "WebPSupportEnabled")
        UserDefaults.standard.removeObject(forKey: "AVIFSupportEnabled")
        UserDefaults.standard.removeObject(forKey: "ShowFileSize")
        UserDefaults.standard.removeObject(forKey: "ShowImageResolution")
        UserDefaults.standard.removeObject(forKey: "ShowCreationDate")
        UserDefaults.standard.removeObject(forKey: "ShowFileTag")
        UserDefaults.standard.removeObject(forKey: "AutoResizeToImageSize")
        UserDefaults.standard.removeObject(forKey: "AutoResizeWithAnimation")
        UserDefaults.standard.removeObject(forKey: "WindowResizeAnchor")
        UserDefaults.standard.removeObject(forKey: "FileNameDisplayLocation")
        UserDefaults.standard.removeObject(forKey: "DefaultFileAssociationsSet")
        super.tearDown()
    }
    
    func testPNGSupportDefaultsToFalse() {
        // When not set, should default to false
        let isEnabled = settingsManager.isPNGSupportEnabled
        XCTAssertFalse(isEnabled, "PNG support should default to false")
    }
    
    func testPNGSupportCanBeEnabled() {
        settingsManager.isPNGSupportEnabled = true
        XCTAssertTrue(settingsManager.isPNGSupportEnabled, "PNG support should be enabled")
    }
    
    func testPNGSupportCanBeDisabled() {
        settingsManager.isPNGSupportEnabled = true
        settingsManager.isPNGSupportEnabled = false
        XCTAssertFalse(settingsManager.isPNGSupportEnabled, "PNG support should be disabled")
    }
    
    func testPNGSupportPersistsInUserDefaults() {
        settingsManager.isPNGSupportEnabled = true
        let persistedValue = UserDefaults.standard.bool(forKey: "PNGSupportEnabled")
        XCTAssertTrue(persistedValue, "PNG support preference should persist in UserDefaults")
    }
    
    func testSupportedExtensionsWithoutPNG() {
        settingsManager.isPNGSupportEnabled = false
        let extensions = settingsManager.supportedExtensions
        XCTAssertEqual(extensions.count, 2, "Should have 2 extensions (jpg, jpeg)")
        XCTAssertTrue(extensions.contains("jpg"), "Should include jpg")
        XCTAssertTrue(extensions.contains("jpeg"), "Should include jpeg")
        XCTAssertFalse(extensions.contains("png"), "Should not include png when disabled")
    }
    
    func testSupportedExtensionsWithPNG() {
        settingsManager.isPNGSupportEnabled = true
        let extensions = settingsManager.supportedExtensions
        XCTAssertEqual(extensions.count, 3, "Should have 3 extensions (jpg, jpeg, png)")
        XCTAssertTrue(extensions.contains("jpg"), "Should include jpg")
        XCTAssertTrue(extensions.contains("jpeg"), "Should include jpeg")
        XCTAssertTrue(extensions.contains("png"), "Should include png when enabled")
    }
    
    func testIsExtensionSupportedJPEG() {
        settingsManager.isPNGSupportEnabled = false
        
        XCTAssertTrue(settingsManager.isExtensionSupported("jpg"), "Should support jpg")
        XCTAssertTrue(settingsManager.isExtensionSupported("JPG"), "Should support JPG (case-insensitive)")
        XCTAssertTrue(settingsManager.isExtensionSupported("jpeg"), "Should support jpeg")
        XCTAssertTrue(settingsManager.isExtensionSupported("JPEG"), "Should support JPEG (case-insensitive)")
    }
    
    func testIsExtensionSupportedPNGWhenDisabled() {
        settingsManager.isPNGSupportEnabled = false
        
        XCTAssertFalse(settingsManager.isExtensionSupported("png"), "Should not support png when disabled")
        XCTAssertFalse(settingsManager.isExtensionSupported("PNG"), "Should not support PNG when disabled (case-insensitive)")
    }
    
    func testIsExtensionSupportedPNGWhenEnabled() {
        settingsManager.isPNGSupportEnabled = true
        
        XCTAssertTrue(settingsManager.isExtensionSupported("png"), "Should support png when enabled")
        XCTAssertTrue(settingsManager.isExtensionSupported("PNG"), "Should support PNG when enabled (case-insensitive)")
    }
    
    func testIsExtensionSupportedUnsupportedFormats() {
        settingsManager.isPNGSupportEnabled = true
        settingsManager.isWebPSupportEnabled = true
        
        XCTAssertFalse(settingsManager.isExtensionSupported("gif"), "Should not support gif")
        XCTAssertFalse(settingsManager.isExtensionSupported("bmp"), "Should not support bmp")
        XCTAssertFalse(settingsManager.isExtensionSupported("txt"), "Should not support txt")
        XCTAssertFalse(settingsManager.isExtensionSupported(""), "Should not support empty string")
    }
    
    func testWebPSupportDefaultsToFalse() {
        // When not set, should default to false
        let isEnabled = settingsManager.isWebPSupportEnabled
        XCTAssertFalse(isEnabled, "WebP support should default to false")
    }
    
    func testWebPSupportCanBeEnabled() {
        settingsManager.isWebPSupportEnabled = true
        XCTAssertTrue(settingsManager.isWebPSupportEnabled, "WebP support should be enabled")
    }
    
    func testWebPSupportCanBeDisabled() {
        settingsManager.isWebPSupportEnabled = true
        settingsManager.isWebPSupportEnabled = false
        XCTAssertFalse(settingsManager.isWebPSupportEnabled, "WebP support should be disabled")
    }
    
    func testWebPSupportPersistsInUserDefaults() {
        settingsManager.isWebPSupportEnabled = true
        let persistedValue = UserDefaults.standard.bool(forKey: "WebPSupportEnabled")
        XCTAssertTrue(persistedValue, "WebP support preference should persist in UserDefaults")
    }
    
    func testSupportedExtensionsWithoutWebP() {
        settingsManager.isPNGSupportEnabled = false
        settingsManager.isWebPSupportEnabled = false
        let extensions = settingsManager.supportedExtensions
        XCTAssertEqual(extensions.count, 2, "Should have 2 extensions (jpg, jpeg)")
        XCTAssertTrue(extensions.contains("jpg"), "Should include jpg")
        XCTAssertTrue(extensions.contains("jpeg"), "Should include jpeg")
        XCTAssertFalse(extensions.contains("webp"), "Should not include webp when disabled")
    }
    
    func testSupportedExtensionsWithWebP() {
        settingsManager.isPNGSupportEnabled = false
        settingsManager.isWebPSupportEnabled = true
        let extensions = settingsManager.supportedExtensions
        XCTAssertEqual(extensions.count, 3, "Should have 3 extensions (jpg, jpeg, webp)")
        XCTAssertTrue(extensions.contains("jpg"), "Should include jpg")
        XCTAssertTrue(extensions.contains("jpeg"), "Should include jpeg")
        XCTAssertTrue(extensions.contains("webp"), "Should include webp when enabled")
    }
    
    func testSupportedExtensionsWithPNGAndWebP() {
        settingsManager.isPNGSupportEnabled = true
        settingsManager.isWebPSupportEnabled = true
        let extensions = settingsManager.supportedExtensions
        XCTAssertEqual(extensions.count, 4, "Should have 4 extensions (jpg, jpeg, png, webp)")
        XCTAssertTrue(extensions.contains("jpg"), "Should include jpg")
        XCTAssertTrue(extensions.contains("jpeg"), "Should include jpeg")
        XCTAssertTrue(extensions.contains("png"), "Should include png when enabled")
        XCTAssertTrue(extensions.contains("webp"), "Should include webp when enabled")
    }
    
    func testIsExtensionSupportedWebPWhenDisabled() {
        settingsManager.isWebPSupportEnabled = false
        
        XCTAssertFalse(settingsManager.isExtensionSupported("webp"), "Should not support webp when disabled")
        XCTAssertFalse(settingsManager.isExtensionSupported("WEBP"), "Should not support WEBP when disabled (case-insensitive)")
    }
    
    func testIsExtensionSupportedWebPWhenEnabled() {
        settingsManager.isWebPSupportEnabled = true
        
        XCTAssertTrue(settingsManager.isExtensionSupported("webp"), "Should support webp when enabled")
        XCTAssertTrue(settingsManager.isExtensionSupported("WEBP"), "Should support WEBP when enabled (case-insensitive)")
    }
    
    func testAVIFSupportDefaultsToFalse() {
        // When not set, should default to false
        let isEnabled = settingsManager.isAVIFSupportEnabled
        XCTAssertFalse(isEnabled, "AVIF support should default to false")
    }
    
    func testAVIFSupportCanBeEnabled() {
        settingsManager.isAVIFSupportEnabled = true
        XCTAssertTrue(settingsManager.isAVIFSupportEnabled, "AVIF support should be enabled")
    }
    
    func testAVIFSupportCanBeDisabled() {
        settingsManager.isAVIFSupportEnabled = true
        settingsManager.isAVIFSupportEnabled = false
        XCTAssertFalse(settingsManager.isAVIFSupportEnabled, "AVIF support should be disabled")
    }
    
    func testAVIFSupportPersistsInUserDefaults() {
        settingsManager.isAVIFSupportEnabled = true
        let persistedValue = UserDefaults.standard.bool(forKey: "AVIFSupportEnabled")
        XCTAssertTrue(persistedValue, "AVIF support preference should persist in UserDefaults")
    }
    
    func testSupportedExtensionsWithoutAVIF() {
        settingsManager.isPNGSupportEnabled = false
        settingsManager.isWebPSupportEnabled = false
        settingsManager.isAVIFSupportEnabled = false
        let extensions = settingsManager.supportedExtensions
        XCTAssertEqual(extensions.count, 2, "Should have 2 extensions (jpg, jpeg)")
        XCTAssertTrue(extensions.contains("jpg"), "Should include jpg")
        XCTAssertTrue(extensions.contains("jpeg"), "Should include jpeg")
        XCTAssertFalse(extensions.contains("avif"), "Should not include avif when disabled")
    }
    
    func testSupportedExtensionsWithAVIF() {
        settingsManager.isPNGSupportEnabled = false
        settingsManager.isWebPSupportEnabled = false
        settingsManager.isAVIFSupportEnabled = true
        let extensions = settingsManager.supportedExtensions
        XCTAssertEqual(extensions.count, 3, "Should have 3 extensions (jpg, jpeg, avif)")
        XCTAssertTrue(extensions.contains("jpg"), "Should include jpg")
        XCTAssertTrue(extensions.contains("jpeg"), "Should include jpeg")
        XCTAssertTrue(extensions.contains("avif"), "Should include avif when enabled")
    }
    
    func testSupportedExtensionsWithPNGWebPAndAVIF() {
        settingsManager.isPNGSupportEnabled = true
        settingsManager.isWebPSupportEnabled = true
        settingsManager.isAVIFSupportEnabled = true
        let extensions = settingsManager.supportedExtensions
        XCTAssertEqual(extensions.count, 5, "Should have 5 extensions (jpg, jpeg, png, webp, avif)")
        XCTAssertTrue(extensions.contains("jpg"), "Should include jpg")
        XCTAssertTrue(extensions.contains("jpeg"), "Should include jpeg")
        XCTAssertTrue(extensions.contains("png"), "Should include png when enabled")
        XCTAssertTrue(extensions.contains("webp"), "Should include webp when enabled")
        XCTAssertTrue(extensions.contains("avif"), "Should include avif when enabled")
    }
    
    func testIsExtensionSupportedAVIFWhenDisabled() {
        settingsManager.isAVIFSupportEnabled = false
        
        XCTAssertFalse(settingsManager.isExtensionSupported("avif"), "Should not support avif when disabled")
        XCTAssertFalse(settingsManager.isExtensionSupported("AVIF"), "Should not support AVIF when disabled (case-insensitive)")
    }
    
    func testIsExtensionSupportedAVIFWhenEnabled() {
        settingsManager.isAVIFSupportEnabled = true
        
        XCTAssertTrue(settingsManager.isExtensionSupported("avif"), "Should support avif when enabled")
        XCTAssertTrue(settingsManager.isExtensionSupported("AVIF"), "Should support AVIF when enabled (case-insensitive)")
    }
    
    func testSettingsManagerIsSingleton() {
        let instance1 = SettingsManager.shared
        let instance2 = SettingsManager.shared
        XCTAssertTrue(instance1 === instance2, "SettingsManager should be a singleton")
    }
    
    func testShowImageResolutionDefaultsToTrue() {
        // When not set, should default to true
        let isEnabled = settingsManager.showImageResolution
        XCTAssertTrue(isEnabled, "Image resolution display should default to true")
    }
    
    func testShowImageResolutionCanBeEnabled() {
        settingsManager.showImageResolution = true
        XCTAssertTrue(settingsManager.showImageResolution, "Image resolution display should be enabled")
    }
    
    func testShowImageResolutionCanBeDisabled() {
        settingsManager.showImageResolution = true
        settingsManager.showImageResolution = false
        XCTAssertFalse(settingsManager.showImageResolution, "Image resolution display should be disabled")
    }
    
    func testShowImageResolutionPersistsInUserDefaults() {
        settingsManager.showImageResolution = true
        let persistedValue = UserDefaults.standard.bool(forKey: "ShowImageResolution")
        XCTAssertTrue(persistedValue, "Image resolution preference should persist in UserDefaults")
    }
    
    func testShowCreationDateDefaultsToFalse() {
        // When not set, should default to false
        let isEnabled = settingsManager.showCreationDate
        XCTAssertFalse(isEnabled, "Creation date display should default to false")
    }
    
    func testShowCreationDateCanBeEnabled() {
        settingsManager.showCreationDate = true
        XCTAssertTrue(settingsManager.showCreationDate, "Creation date display should be enabled")
    }
    
    func testShowCreationDateCanBeDisabled() {
        settingsManager.showCreationDate = true
        settingsManager.showCreationDate = false
        XCTAssertFalse(settingsManager.showCreationDate, "Creation date display should be disabled")
    }
    
    func testShowCreationDatePersistsInUserDefaults() {
        settingsManager.showCreationDate = true
        let persistedValue = UserDefaults.standard.bool(forKey: "ShowCreationDate")
        XCTAssertTrue(persistedValue, "Creation date preference should persist in UserDefaults")
    }
    
    func testShowFileSizeDefaultsToTrue() {
        // When not set, should default to true for backward compatibility
        let isEnabled = settingsManager.showFileSize
        XCTAssertTrue(isEnabled, "File size display should default to true")
    }
    
    func testShowFileSizeCanBeEnabled() {
        settingsManager.showFileSize = true
        XCTAssertTrue(settingsManager.showFileSize, "File size display should be enabled")
    }
    
    func testShowFileSizeCanBeDisabled() {
        settingsManager.showFileSize = true
        settingsManager.showFileSize = false
        XCTAssertFalse(settingsManager.showFileSize, "File size display should be disabled")
    }
    
    func testShowFileSizePersistsInUserDefaults() {
        settingsManager.showFileSize = true
        let persistedValue = UserDefaults.standard.bool(forKey: "ShowFileSize")
        XCTAssertTrue(persistedValue, "File size preference should persist in UserDefaults")
    }
    
    func testShowFileInfoPillWhenAllDisabled() {
        // When all options are disabled, pill should be hidden
        settingsManager.showFileSize = false
        settingsManager.showCreationDate = false
        settingsManager.showImageResolution = false
        XCTAssertFalse(settingsManager.showFileInfoPill, "Pill should be hidden when all options are disabled")
    }
    
    func testShowFileInfoPillWhenFileSizeEnabled() {
        // When file size is enabled, pill should be shown
        settingsManager.showFileSize = true
        settingsManager.showCreationDate = false
        settingsManager.showImageResolution = false
        XCTAssertTrue(settingsManager.showFileInfoPill, "Pill should be shown when file size is enabled")
    }
    
    func testShowFileInfoPillWhenCreationDateEnabled() {
        // When creation date is enabled, pill should be shown
        settingsManager.showFileSize = false
        settingsManager.showCreationDate = true
        settingsManager.showImageResolution = false
        XCTAssertTrue(settingsManager.showFileInfoPill, "Pill should be shown when creation date is enabled")
    }
    
    func testShowFileInfoPillWhenResolutionEnabled() {
        // When resolution is enabled, pill should be shown
        settingsManager.showFileSize = false
        settingsManager.showCreationDate = false
        settingsManager.showImageResolution = true
        XCTAssertTrue(settingsManager.showFileInfoPill, "Pill should be shown when resolution is enabled")
    }
    
    func testShowFileInfoPillWhenMultipleEnabled() {
        // When multiple options are enabled, pill should be shown
        settingsManager.showFileSize = true
        settingsManager.showCreationDate = true
        settingsManager.showImageResolution = true
        XCTAssertTrue(settingsManager.showFileInfoPill, "Pill should be shown when multiple options are enabled")
    }
    
    func testAutoResizeToImageSizeDefaultsToTrue() {
        // When not set, should default to true
        let isEnabled = settingsManager.autoResizeToImageSize
        XCTAssertTrue(isEnabled, "Auto-resize to image size should default to true")
    }
    
    func testAutoResizeToImageSizeCanBeEnabled() {
        settingsManager.autoResizeToImageSize = true
        XCTAssertTrue(settingsManager.autoResizeToImageSize, "Auto-resize to image size should be enabled")
    }
    
    func testAutoResizeToImageSizeCanBeDisabled() {
        settingsManager.autoResizeToImageSize = true
        settingsManager.autoResizeToImageSize = false
        XCTAssertFalse(settingsManager.autoResizeToImageSize, "Auto-resize to image size should be disabled")
    }
    
    func testAutoResizeToImageSizePersistsInUserDefaults() {
        settingsManager.autoResizeToImageSize = true
        let persistedValue = UserDefaults.standard.bool(forKey: "AutoResizeToImageSize")
        XCTAssertTrue(persistedValue, "Auto-resize to image size preference should persist in UserDefaults")
    }
    
    func testFileNameDisplayLocationDefaultsToInTitle() {
        // When not set, should default to .inTitle
        let location = settingsManager.fileNameDisplayLocation
        XCTAssertEqual(location, .inTitle, "File name display location should default to .inTitle")
    }
    
    func testFileNameDisplayLocationCanBeSetToInCorner() {
        settingsManager.fileNameDisplayLocation = .inCorner
        XCTAssertEqual(settingsManager.fileNameDisplayLocation, .inCorner, "File name display location should be .inCorner")
    }
    
    func testFileNameDisplayLocationCanBeSetToOff() {
        settingsManager.fileNameDisplayLocation = .off
        XCTAssertEqual(settingsManager.fileNameDisplayLocation, .off, "File name display location should be .off")
    }
    
    func testFileNameDisplayLocationCanBeSetBackToInTitle() {
        settingsManager.fileNameDisplayLocation = .inCorner
        settingsManager.fileNameDisplayLocation = .inTitle
        XCTAssertEqual(settingsManager.fileNameDisplayLocation, .inTitle, "File name display location should be .inTitle")
    }
    
    func testFileNameDisplayLocationPersistsInUserDefaults() {
        settingsManager.fileNameDisplayLocation = .inCorner
        let persistedValue = UserDefaults.standard.string(forKey: "FileNameDisplayLocation")
        XCTAssertEqual(persistedValue, "inCorner", "File name display location preference should persist in UserDefaults")
    }
    
    func testFileNameDisplayLocationDisplayNames() {
        XCTAssertEqual(FileNameDisplayLocation.inTitle.displayName, "in the title", "Display name should be 'in the title'")
        XCTAssertEqual(FileNameDisplayLocation.inCorner.displayName, "in the corner", "Display name should be 'in the corner'")
        XCTAssertEqual(FileNameDisplayLocation.off.displayName, "off", "Display name should be 'off'")
    }
    
    func testFileNameDisplayLocationAllCases() {
        let allCases = FileNameDisplayLocation.allCases
        XCTAssertEqual(allCases.count, 3, "Should have 3 cases")
        XCTAssertTrue(allCases.contains(.inTitle), "Should include .inTitle")
        XCTAssertTrue(allCases.contains(.inCorner), "Should include .inCorner")
        XCTAssertTrue(allCases.contains(.off), "Should include .off")
    }
    
    func testShowFileTagDefaultsToFalse() {
        // When not set, should default to false
        let isEnabled = settingsManager.showFileTag
        XCTAssertFalse(isEnabled, "File tag display should default to false")
    }
    
    func testShowFileTagCanBeEnabled() {
        settingsManager.showFileTag = true
        XCTAssertTrue(settingsManager.showFileTag, "File tag display should be enabled")
    }
    
    func testShowFileTagCanBeDisabled() {
        settingsManager.showFileTag = true
        settingsManager.showFileTag = false
        XCTAssertFalse(settingsManager.showFileTag, "File tag display should be disabled")
    }
    
    func testShowFileTagPersistsInUserDefaults() {
        settingsManager.showFileTag = true
        let persistedValue = UserDefaults.standard.bool(forKey: "ShowFileTag")
        XCTAssertTrue(persistedValue, "File tag preference should persist in UserDefaults")
    }
    
    func testAutoResizeWithAnimationDefaultsToTrue() {
        // When not set, should default to true
        let isEnabled = settingsManager.autoResizeWithAnimation
        XCTAssertTrue(isEnabled, "Auto-resize with animation should default to true")
    }
    
    func testAutoResizeWithAnimationCanBeEnabled() {
        settingsManager.autoResizeWithAnimation = true
        XCTAssertTrue(settingsManager.autoResizeWithAnimation, "Auto-resize with animation should be enabled")
    }
    
    func testAutoResizeWithAnimationCanBeDisabled() {
        settingsManager.autoResizeWithAnimation = true
        settingsManager.autoResizeWithAnimation = false
        XCTAssertFalse(settingsManager.autoResizeWithAnimation, "Auto-resize with animation should be disabled")
    }
    
    func testAutoResizeWithAnimationPersistsInUserDefaults() {
        settingsManager.autoResizeWithAnimation = true
        let persistedValue = UserDefaults.standard.bool(forKey: "AutoResizeWithAnimation")
        XCTAssertTrue(persistedValue, "Auto-resize with animation preference should persist in UserDefaults")
    }

    func testWindowResizeAnchorCanBeChanged() {
        settingsManager.windowResizeAnchor = .topLeft
        XCTAssertEqual(settingsManager.windowResizeAnchor, .topLeft)

        settingsManager.windowResizeAnchor = .center
        XCTAssertEqual(settingsManager.windowResizeAnchor, .center)
    }

    func testWindowResizeAnchorDefaultsToCenter() {
        XCTAssertEqual(settingsManager.windowResizeAnchor, .center)
    }

    func testWindowResizeAnchorPersistsInUserDefaults() {
        settingsManager.windowResizeAnchor = .topLeft
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "WindowResizeAnchor"),
            WindowResizeAnchor.topLeft.rawValue
        )
    }

    func testWindowResizeAnchorDisplayNames() {
        XCTAssertEqual(WindowResizeAnchor.center.displayName, "Center")
        XCTAssertEqual(WindowResizeAnchor.topLeft.displayName, "Top Left")
    }
    
}
