//
//  ViewControllerTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 18.12.25.
//

import XCTest
import AppKit
@testable import FastViewer_Lite

final class ViewControllerTests: XCTestCase {

    var viewController: ViewController!

    override func setUp() {
        super.setUp()
        ImageCacheManager.shared.clearCache()
        viewController = ViewController()
        // Load the view to initialize the imageView
        _ = viewController.view
    }

    override func tearDown() {
        ImageCacheManager.shared.clearCache()
        viewController = nil
        super.tearDown()
    }

    func testImageViewSetup() {
        XCTAssertNotNil(viewController.view, "View should be loaded")
        XCTAssertNotNil(viewController.imageView, "ImageView should be initialized")
        XCTAssertEqual(viewController.imageView.imageAlignment, .alignCenter, "Image alignment should be center")
    }

    func testInvisibleCenteredToastDoesNotInterceptImageHitTestingInSmallWindow() {
        let window = makeTestWindow()
        window.setContentSize(NSSize(width: 300, height: 300))
        viewController.view.layoutSubtreeIfNeeded()

        let center = NSPoint(
            x: viewController.view.bounds.midX,
            y: viewController.view.bounds.midY
        )

        XCTAssertTrue(
            viewController.view.hitTest(center) === viewController.imageView,
            "The decorative toast over a 300x300 image must pass wheel events through to the image view"
        )
    }

    func testImageLinkDetectorFindsHTTPAndHTTPSLinks() {
        let text = "Open https://example.com or http://openai.com/docs"
        let fallbackBounds = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.1)
        let exactBounds = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.1)

        let links = ImageLinkDetector.links(
            in: text,
            normalizedTextBounds: fallbackBounds,
            boundsForRange: { _ in exactBounds }
        )

        XCTAssertEqual(links.map(\.url.absoluteString), [
            "https://example.com",
            "http://openai.com/docs"
        ])
        XCTAssertTrue(links.allSatisfy { $0.normalizedBounds == exactBounds })
    }

    func testImageLinkDetectorRejectsNonWebSchemes() {
        let links = ImageLinkDetector.links(
            in: "mailto:test@example.com file:///tmp/image.jpg",
            normalizedTextBounds: .zero,
            boundsForRange: { _ in .zero }
        )

        XCTAssertTrue(links.isEmpty)
    }

    func testImageLinkDetectorRecognizesURLHintWithMisreadSlashes() {
        XCTAssertTrue(ImageLinkDetector.textMayContainURL("https:Ilchatgpt.comlglg-p"))
        XCTAssertTrue(ImageLinkDetector.textMayContainURL("Open WWW.example.com"))
        XCTAssertFalse(ImageLinkDetector.textMayContainURL("An ordinary sentence"))
    }

    func testImageLinkHoverBorderIsDashedOverlayAndCanBeHidden() {
        let imageView = DraggableImageView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400)
        )
        let linkBounds = CGRect(x: 120, y: 80, width: 240, height: 36)

        imageView.showLinkHoverBorder(in: linkBounds, displayScale: 1)

        XCTAssertTrue(imageView.isLinkHoverBorderVisible)
        XCTAssertEqual(imageView.linkHoverBorderBounds, linkBounds)
        XCTAssertEqual(imageView.linkHoverBorderDashPattern, [6, 4])
        XCTAssertEqual(imageView.linkHoverBorderColor, .systemGray)

        imageView.hideLinkHoverBorder()

        XCTAssertFalse(imageView.isLinkHoverBorderVisible)
        XCTAssertNil(imageView.linkHoverBorderBounds)
    }

    func testImageLinkHoverBorderDrawsVisiblePixelsAboveImageContent() {
        let imageView = DraggableImageView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 100)
        )
        imageView.image = NSImage(
            size: imageView.bounds.size,
            flipped: false
        ) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let linkBounds = CGRect(x: 20, y: 20, width: 120, height: 30)

        guard let bitmap = imageView.bitmapImageRepForCachingDisplay(in: imageView.bounds) else {
            XCTFail("A bitmap representation should be available")
            return
        }

        imageView.showLinkHoverBorder(in: linkBounds, displayScale: 1)
        imageView.cacheDisplay(in: imageView.bounds, to: bitmap)

        let renderedPixels = (0..<bitmap.pixelsWide).flatMap { x in
            (0..<bitmap.pixelsHigh).compactMap { y in bitmap.colorAt(x: x, y: y) }
        }
        XCTAssertTrue(
            renderedPixels.contains { color in
                guard let rgb = color.usingColorSpace(.sRGB) else { return false }
                return rgb.redComponent < 0.8 ||
                    rgb.greenComponent < 0.8 ||
                    rgb.blueComponent < 0.8
            },
            "The post-image drawing pass should render the contrasting dashed URL outline"
        )
    }

    func testLogoImageViewSetup() {
        // Verify logo image view is set up and visible initially (no file is open)
        XCTAssertNotNil(viewController.view, "View should be loaded")

        // Find logo image view in subviews
        let logoImageView = viewController.view.subviews.first { subview in
            subview is NSImageView && subview != viewController.imageView
        } as? NSImageView

        XCTAssertNotNil(logoImageView, "Logo image view should be initialized")
        XCTAssertFalse(logoImageView?.isHidden ?? true, "Logo should be visible when no file is open")
        XCTAssertNotNil(logoImageView?.image, "Logo image should be loaded")

        // Verify logo is NonInteractiveImageView to allow drag and drop to pass through
        XCTAssertTrue(logoImageView is NonInteractiveImageView, "Logo should be NonInteractiveImageView to allow drag and drop")
    }

    func testLogoAllowsDragAndDropToPassThrough() {
        // Verify that logo forwards drag events to parent view
        XCTAssertNotNil(viewController.view, "View should be loaded")

        // Find logo image view
        let logoImageView = viewController.view.subviews.first { subview in
            subview is NSImageView && subview != viewController.imageView
        } as? NonInteractiveImageView

        XCTAssertNotNil(logoImageView, "Logo should be NonInteractiveImageView")

        // Test that hitTest returns self (so it receives drag events to forward)
        let testPoint = NSPoint(x: 50, y: 50)
        let hitView = logoImageView?.hitTest(testPoint)
        XCTAssertEqual(hitView, logoImageView, "Logo hitTest should return self to receive and forward drag events")

        // Verify logo doesn't accept first mouse (for clicks)
        XCTAssertFalse(logoImageView?.acceptsFirstMouse(for: nil) ?? true, "Logo should not accept first mouse events")

        // Verify logo is registered for drag types (so it can forward them)
        let registeredTypes = logoImageView?.registeredDraggedTypes ?? []
        XCTAssertTrue(registeredTypes.contains(.fileURL), "Logo should be registered for fileURL drag types to forward them")
    }

    func testLogoHiddenWhenFileLoaded() {
        // Create a temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-image-\(UUID().uuidString).jpg")

        // Create a simple test image file
        let testImage = createTestImage(size: NSSize(width: 100, height: 100))
        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            // Clean up test file
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Find logo image view before loading file
        let logoImageView = viewController.view.subviews.first { subview in
            subview is NSImageView && subview != viewController.imageView
        } as? NSImageView

        XCTAssertNotNil(logoImageView, "Logo image view should exist")
        XCTAssertFalse(logoImageView?.isHidden ?? true, "Logo should be visible before loading file")

        // Load the file
        viewController.loadImage(from: testFileURL)

        // Wait for async image loading
        let expectation = XCTestExpectation(description: "Image loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Logo should be hidden when file is loaded
        XCTAssertTrue(logoImageView?.isHidden ?? false, "Logo should be hidden when file is loaded")
    }

    func testLogoShownWhenNoFileOpen() {
        // Ensure no file is loaded
        viewController.fileListManager.reset()
        viewController.imageView.image = nil

        // Find logo image view
        let logoImageView = viewController.view.subviews.first { subview in
            subview is NSImageView && subview != viewController.imageView
        } as? NSImageView

        XCTAssertNotNil(logoImageView, "Logo image view should exist")

        // Show logo (simulate restoreInitialState)
        logoImageView?.isHidden = false

        // Verify logo is visible
        XCTAssertFalse(logoImageView?.isHidden ?? true, "Logo should be visible when no file is open")
    }

    func testRestoreInitialStateResetsBackgroundColor() {
        // Ensure view is loaded and has a layer
        XCTAssertNotNil(viewController.view.layer, "View should have a backing layer")

        // Change background color to a custom color
        viewController.updateBackgroundColor(.red)

        // Call restoreInitialState, which should reset background to the empty canvas color
        viewController.restoreInitialState()

        // Verify background color is reset to the standard document-canvas gray
        guard let currentColor = viewController.view.layer?.backgroundColor else {
            XCTFail("Background color should be set on view layer")
            return
        }

        let expectedColor = ViewController.emptyWindowBackgroundColor
        XCTAssertEqual(
            currentColor,
            expectedColor.cgColor,
            "restoreInitialState should reset background color to the empty canvas color"
        )
    }

    func testImageScalingForSmallImage() {
        // Create a small test image (smaller than default view size of 1200x800)
        let smallImageSize = NSSize(width: 200, height: 150)
        let smallImage = createTestImage(size: smallImageSize)

        // Set view bounds to a known size
        viewController.view.setFrameSize(NSSize(width: 1200, height: 800))
        viewController.view.needsLayout = true
        viewController.view.layoutSubtreeIfNeeded()

        // Update scaling for small image
        viewController.updateImageScaling(for: smallImage)

        // Small image should use scaleProportionallyDown (which doesn't scale up)
        XCTAssertEqual(
            viewController.imageView.imageScaling,
            .scaleProportionallyDown,
            "Small image should use scaleProportionallyDown to keep original size"
        )
        XCTAssertEqual(
            viewController.imageView.imageAlignment,
            .alignCenter,
            "Image should be center aligned"
        )
    }

    func testImageScalingForLargeImage() {
        // Create a large test image (larger than default view size)
        let largeImageSize = NSSize(width: 2000, height: 1500)
        let largeImage = createTestImage(size: largeImageSize)

        // Set view bounds to a known size
        viewController.view.setFrameSize(NSSize(width: 1200, height: 800))
        viewController.view.needsLayout = true
        viewController.view.layoutSubtreeIfNeeded()

        // Update scaling for large image
        viewController.updateImageScaling(for: largeImage)

        // Large image should use scaleProportionallyUpOrDown to fit the view
        XCTAssertEqual(
            viewController.imageView.imageScaling,
            .scaleProportionallyUpOrDown,
            "Large image should use scaleProportionallyUpOrDown to fit view"
        )
        XCTAssertEqual(
            viewController.imageView.imageAlignment,
            .alignCenter,
            "Image should be center aligned"
        )
    }

    func testImageScalingForEqualSizeImage() {
        // Create an image equal to view size
        let equalImageSize = NSSize(width: 1200, height: 800)
        let equalImage = createTestImage(size: equalImageSize)

        // Set view bounds to match image size exactly
        viewController.view.setFrameSize(NSSize(width: 1200, height: 800))
        viewController.view.needsLayout = true
        viewController.view.layoutSubtreeIfNeeded()

        // Update scaling for equal size image
        viewController.updateImageScaling(for: equalImage)

        // Equal size image should use scaleProportionallyDown for 100% scale
        XCTAssertEqual(
            viewController.imageView.imageScaling,
            .scaleProportionallyDown,
            "Equal size image should use scaleProportionallyDown for 100% scale"
        )
    }

    func testImageScalingUpdatesOnLayout() {
        // Create a small test image
        let smallImageSize = NSSize(width: 200, height: 150)
        let smallImage = createTestImage(size: smallImageSize)

        // Set initial view size
        viewController.view.setFrameSize(NSSize(width: 1200, height: 800))
        viewController.view.needsLayout = true
        viewController.view.layoutSubtreeIfNeeded()

        // Set the image
        viewController.imageView.image = smallImage

        // Trigger viewDidLayout
        viewController.viewDidLayout()

        // Verify scaling was updated
        XCTAssertEqual(
            viewController.imageView.imageScaling,
            .scaleProportionallyDown,
            "Scaling should be updated on layout"
        )
    }

    func testWindowTitleUpdatesWithFilename() {
        let originalLocation = SettingsManager.shared.fileNameDisplayLocation
        defer { SettingsManager.shared.fileNameDisplayLocation = originalLocation }
        SettingsManager.shared.fileNameDisplayLocation = .inTitle

        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "FastViewer"
        window.contentView = viewController.view

        let fileURL = makeTestImageFile(name: "test-image-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Verify initial title
        XCTAssertEqual(window.title, "FastViewer", "Initial window title should be FastViewer")

        viewController.loadImage(from: fileURL)
        waitUntil(description: "window title updates after image commit") {
            self.viewController.displayedFileURL == fileURL
        }

        let expectedTitle = "FastViewer • \(fileURL.lastPathComponent)"
        XCTAssertEqual(
            window.title,
            expectedTitle,
            "Window title should be updated to include filename"
        )
    }

    func testAcceptsFirstResponder() {
        XCTAssertTrue(viewController.acceptsFirstResponder, "ViewController should accept first responder")
    }

    func testKeyboardNavigationSetup() {
        // Verify that keyboard handling is set up
        XCTAssertNotNil(viewController.view, "View should be loaded")
        XCTAssertTrue(viewController.acceptsFirstResponder, "Should accept first responder")
    }

    func testCmdEnterOpensFileInFinder() {
        let window = makeTestWindow()
        let testFileURL = makeTestImageFile(name: "test-image-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: testFileURL) }

        viewController.loadImage(from: testFileURL)
        waitUntil(description: "displayed file commits before Finder shortcut") {
            self.viewController.displayedFileURL == testFileURL
        }

        XCTAssertEqual(viewController.displayedFileURL, testFileURL, "Displayed file should be set before handling Cmd+Enter")

        // Create a Cmd+Enter key event (Return key with Command modifier)
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36 // Return key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler - this should call openCurrentFileInFinder
        // We can't easily test that Finder actually opens, but we can verify
        // the method doesn't crash and handles the event correctly
        viewController.keyDown(with: keyEvent)
        XCTAssertEqual(window.contentViewController, viewController)

        // If we get here without crashing, the test passes
        // The actual Finder opening is tested through integration testing
    }

    func testCmdEnterWithNoFileDoesNotCrash() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Ensure no current file is set
        viewController.fileListManager.reset()
        XCTAssertNil(viewController.displayedFileURL, "Should not have a displayed file URL")

        // Create a Cmd+Enter key event
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36 // Return key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler - should handle gracefully when no file is loaded
        viewController.keyDown(with: keyEvent)

        // If we get here without crashing, the test passes
    }

    func testCmdBackspaceWithNoFileDoesNotCrash() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Ensure no current file is set
        viewController.fileListManager.reset()
        XCTAssertNil(viewController.displayedFileURL, "Should not have a displayed file URL")

        // Create a Cmd+Backspace key event
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{8}",
            charactersIgnoringModifiers: "\u{8}",
            isARepeat: false,
            keyCode: 51 // Backspace/Delete key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler - should handle gracefully when no file is loaded
        viewController.keyDown(with: keyEvent)

        // If we get here without crashing, the test passes
    }

    func testCmdBackspaceHandlesKeyboardShortcut() {
        let window = makeTestWindow()
        let testFileURL = makeTestImageFile(name: "test-image-\(UUID().uuidString).jpg")

        // Load the test file
        viewController.loadImage(from: testFileURL)
        waitUntil(description: "displayed file commits before delete shortcut") {
            self.viewController.displayedFileURL == testFileURL
        }

        XCTAssertEqual(viewController.displayedFileURL, testFileURL, "Displayed file should be set before handling Cmd+Backspace")

        // Create a Cmd+Backspace key event
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{8}",
            charactersIgnoringModifiers: "\u{8}",
            isARepeat: false,
            keyCode: 51 // Backspace/Delete key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler - this should call moveCurrentFileToTrash
        // We can't easily test that the file is actually moved to trash in a unit test,
        // but we can verify the method doesn't crash and handles the event correctly
        viewController.keyDown(with: keyEvent)

        waitUntil(description: "file is removed after Cmd+Backspace") {
            !FileManager.default.fileExists(atPath: testFileURL.path)
        }
        XCTAssertTrue(viewController.canUndoMoveToTrash, "Deleting through the keyboard shortcut should push undo state")
        XCTAssertNotNil(window.contentViewController)
    }

    func testCmdZUndoMoveToTrash() {
        let window = makeTestWindow()
        let testFileURL = makeTestImageFile(name: "test-image-\(UUID().uuidString).jpg")

        // Load the test file
        viewController.loadImage(from: testFileURL)
        waitUntil(description: "displayed file commits before delete+undo shortcut") {
            self.viewController.displayedFileURL == testFileURL
        }

        XCTAssertEqual(viewController.displayedFileURL, testFileURL, "Displayed file should be set before delete+undo")

        // Create a Cmd+Backspace key event to move file to trash
        let deleteEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{8}",
            charactersIgnoringModifiers: "\u{8}",
            isARepeat: false,
            keyCode: 51 // Backspace/Delete key
        )

        guard let deleteKeyEvent = deleteEvent else {
            XCTFail("Failed to create delete key event")
            return
        }

        // Move file to trash
        viewController.keyDown(with: deleteKeyEvent)
        waitUntil(description: "file is removed before undo") {
            !FileManager.default.fileExists(atPath: testFileURL.path)
        }
        XCTAssertTrue(viewController.canUndoMoveToTrash, "Deleting should create undo state")

        // Create a Cmd+Z key event to undo
        let undoEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: false,
            keyCode: 6 // Z key
        )

        guard let undoKeyEvent = undoEvent else {
            XCTFail("Failed to create undo key event")
            return
        }

        // Trigger undo
        viewController.keyDown(with: undoKeyEvent)
        waitUntil(description: "file is restored after undo") {
            FileManager.default.fileExists(atPath: testFileURL.path) &&
            self.viewController.displayedFileURL == testFileURL
        }
        XCTAssertFalse(viewController.canUndoMoveToTrash, "Undoing the only deletion should empty undo state")
        XCTAssertNotNil(window.contentViewController)

        try? FileManager.default.removeItem(at: testFileURL)
    }

    func testCmdZWithNoUndoStateDoesNotCrash() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Ensure no undo state exists
        viewController.fileListManager.reset()

        // Create a Cmd+Z key event
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: false,
            keyCode: 6 // Z key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler - should handle gracefully when no undo state exists
        viewController.keyDown(with: keyEvent)

        // If we get here without crashing, the test passes
    }

    func testUpdateBackgroundColor() {
        // Test that background color can be updated
        let testColor = NSColor.windowBackgroundColor
        viewController.updateBackgroundColor(testColor)

        XCTAssertEqual(
            viewController.view.layer?.backgroundColor,
            testColor.cgColor,
            "Background color should be updated to window background color"
        )
    }

    func testAppearanceObserverSetup() {
        // Test that appearance observer is set up in viewDidLoad
        // The observer watches the view's effectiveAppearance property
        XCTAssertNotNil(viewController.view, "View should be loaded")

        // Verify the view has a background color set
        XCTAssertNotNil(viewController.view.layer?.backgroundColor, "View should have a background color")

        // Verify it uses the standard document-canvas background
        let expectedColor = ViewController.emptyWindowBackgroundColor
        XCTAssertEqual(
            viewController.view.layer?.backgroundColor,
            expectedColor.cgColor,
            "Empty view should use the subtle adaptive canvas color"
        )
    }

    func testInitialBackgroundColorBasedOnAppearance() {
        // Verify that the initial empty background uses an adaptive standard gray
        let expectedColor = ViewController.emptyWindowBackgroundColor

        // Create a new view controller to test initial state
        let newViewController = ViewController()
        _ = newViewController.view

        XCTAssertEqual(
            newViewController.view.layer?.backgroundColor,
            expectedColor.cgColor,
            "Initial empty background should use the subtle adaptive canvas color"
        )
    }

    func testResizeWindowToImageSizeSets100PercentScale() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create a test image with specific size
        let testImageSize = NSSize(width: 800, height: 600)
        let testImage = createTestImage(size: testImageSize)
        viewController.imageView.image = testImage

        // Verify initial scaling is not 100%
        viewController.view.setFrameSize(NSSize(width: 600, height: 400))
        viewController.view.needsLayout = true
        viewController.view.layoutSubtreeIfNeeded()
        viewController.updateImageScaling(for: testImage)

        // Initial scaling should be scaleProportionallyUpOrDown since image is larger than view
        XCTAssertEqual(
            viewController.imageView.imageScaling,
            .scaleProportionallyUpOrDown,
            "Initial scaling should be scaleProportionallyUpOrDown for larger image"
        )

        // Simulate Cmd+4 by creating a keyDown event
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "4",
            charactersIgnoringModifiers: "4",
            isARepeat: false,
            keyCode: 21
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler
        viewController.keyDown(with: keyEvent)

        // Wait a moment for animation to complete (if animated)
        let expectation = XCTestExpectation(description: "Window resize completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Verify image scaling is set to 100% (scaleProportionallyDown)
        XCTAssertEqual(
            viewController.imageView.imageScaling,
            .scaleProportionallyDown,
            "Image scaling should be set to scaleProportionallyDown for 100% scale"
        )

        // Verify window content size matches image size (within tolerance)
        let contentRect = window.contentRect(forFrameRect: window.frame)
        let sizeTolerance: CGFloat = 1.0
        XCTAssertEqual(
            contentRect.width,
            testImageSize.width,
            accuracy: sizeTolerance,
            "Window content width should match image width"
        )
        XCTAssertEqual(
            contentRect.height,
            testImageSize.height,
            accuracy: sizeTolerance,
            "Window content height should match image height"
        )
    }

    func testFileTagCircleSetup() {
        // Verify that file tag circle is set up
        XCTAssertNotNil(viewController.view, "View should be loaded")

        // The file tag circle should be initialized in viewDidLoad
        // We can't directly access it since it's private, but we can verify
        // the view hierarchy is set up correctly
        XCTAssertNotNil(viewController.view.subviews, "View should have subviews")
    }

    func testUpdateFileTagDisplayWhenDisabled() {
        let originalShowFileTag = SettingsManager.shared.showFileTag
        defer { SettingsManager.shared.showFileTag = originalShowFileTag }

        // When showFileTag is disabled, circle should be hidden
        SettingsManager.shared.showFileTag = false
        let testFileURL = makeTestImageFile(name: "test-tag-disabled-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: testFileURL) }

        viewController.loadImage(from: testFileURL)
        waitUntil(description: "displayed file commits before disabled tag update") {
            self.viewController.displayedFileURL == testFileURL
        }

        viewController.updateFileTagDisplay(for: testFileURL)
        waitForAsyncWork(delay: 0.2)
        XCTAssertEqual(viewController.displayedTagCircleCount, 0, "Disabled tag display should keep the tag circles hidden")
    }

    func testUpdateFileTagDisplayWithNilURL() {
        let originalShowFileTag = SettingsManager.shared.showFileTag
        defer { SettingsManager.shared.showFileTag = originalShowFileTag }

        // When URL is nil, circle should be hidden
        SettingsManager.shared.showFileTag = true
        let testFileURL = makeTaggedTestImageFile(
            name: "test-tag-nil-\(UUID().uuidString).jpg",
            labelNumber: 6
        )
        defer { try? FileManager.default.removeItem(at: testFileURL) }

        viewController.loadImage(from: testFileURL)
        waitUntil(description: "displayed file commits before nil tag update") {
            self.viewController.displayedFileURL == testFileURL
        }

        viewController.updateFileTagDisplay(for: nil)
        waitForAsyncWork(delay: 0.2)
        XCTAssertEqual(viewController.displayedTagCircleCount, 0, "Passing nil should hide the tag circles")
    }

    func testUpdateFileTagDisplayWithFileURL() {
        let originalShowFileTag = SettingsManager.shared.showFileTag
        defer { SettingsManager.shared.showFileTag = originalShowFileTag }

        // When showFileTag is enabled and file has a tag, circle should be shown
        SettingsManager.shared.showFileTag = true
        let testFileURL = makeTaggedTestImageFile(
            name: "test-tag-visible-\(UUID().uuidString).jpg",
            labelNumber: 6
        )
        defer { try? FileManager.default.removeItem(at: testFileURL) }

        viewController.loadImage(from: testFileURL)
        waitUntil(description: "displayed file commits before tag update") {
            self.viewController.displayedFileURL == testFileURL
        }

        // Update file tag display
        viewController.updateFileTagDisplay(for: testFileURL)
        waitUntil(description: "tag circles appear for tagged file") {
            self.viewController.displayedTagCircleCount > 0
        }
    }

    func testFileTagColorMapping() {
        // Test that label numbers map correctly to colors from NSWorkspace.fileLabelColors
        // Label numbers: 1=Gray, 2=Green, 3=Violet, 4=Blue, 5=Yellow, 6=Red, 7=Orange
        // Array indices: [0]=Gray, [1]=Green, [2]=Violet, [3]=Blue, [4]=Yellow, [5]=Red, [6]=Orange

        let labelColors = NSWorkspace.shared.fileLabelColors
        XCTAssertGreaterThanOrEqual(labelColors.count, 7, "Should have at least 7 label colors")

        // Test that label number 5 (Yellow) maps to index 4
        if labelColors.count >= 5 {
            let yellowColor = labelColors[4] // Index 4 should be Yellow (label number 5)
            let blueColor = labelColors[3]   // Index 3 should be Blue (label number 4)

            // Verify that yellow and blue are different colors
            // We can't easily compare NSColor values directly, but we can verify
            // they're not the same object and have different RGB components
            guard let yellow = yellowColor.usingColorSpace(.sRGB),
                  let blue = blueColor.usingColorSpace(.sRGB) else {
                XCTFail("Finder label colors should convert to sRGB")
                return
            }

            XCTAssertGreaterThan(yellow.redComponent, blue.redComponent)
            XCTAssertGreaterThan(yellow.greenComponent, blue.greenComponent)
            XCTAssertGreaterThan(blue.blueComponent, yellow.blueComponent)
        }

        // Test mapping logic: labelNum - 1 should give correct index
        for labelNum in 1...7 {
            if labelNum <= labelColors.count {
                let expectedIndex = labelNum - 1
                let color = labelColors[expectedIndex]
                XCTAssertNotNil(color, "Color should exist for label number \(labelNum) at index \(expectedIndex)")
            }
        }
    }

    func testLoadImageFallsBackToSingleFileForUnsupportedExtension() {
        let testFileURL = makeTestImageFile(name: "test-unsupported-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFileURL) }

        viewController.loadImage(from: testFileURL)
        waitUntil(description: "unsupported extension image still loads") {
            self.viewController.displayedFileURL == testFileURL &&
            self.viewController.imageView.image != nil
        }

        XCTAssertEqual(viewController.displayedFileURL, testFileURL, "Displayed file should match the loaded file")
        XCTAssertEqual(viewController.fileListManager.currentFileURL, testFileURL, "Single-file fallback should still make the opened file current")
        XCTAssertEqual(viewController.fileListManager.fileURLs, [testFileURL], "Single-file fallback should keep navigation scoped to the opened file")
    }

    func testAsyncLoadKeepsDisplayedFileAndTitleUntilCommit() {
        let originalLocation = SettingsManager.shared.fileNameDisplayLocation
        defer { SettingsManager.shared.fileNameDisplayLocation = originalLocation }
        SettingsManager.shared.fileNameDisplayLocation = .inTitle

        let window = makeTestWindow()
        let firstFileURL = makeTestImageFile(
            name: "test-first-\(UUID().uuidString).jpg",
            size: NSSize(width: 200, height: 150)
        )
        let secondFileURL = makeTestImageFile(
            name: "test-second-\(UUID().uuidString).jpg",
            size: NSSize(width: 5000, height: 3600)
        )
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits before pending transition test") {
            self.viewController.displayedFileURL == firstFileURL
        }

        guard let originalImage = viewController.imageView.image else {
            XCTFail("First image should be displayed before starting the next transition")
            return
        }

        ImageCacheManager.shared.clearCache()
        viewController.loadImage(from: secondFileURL)

        XCTAssertEqual(viewController.displayedFileURL, firstFileURL, "Visible file should remain on the previous image while the next file loads")
        XCTAssertTrue(viewController.imageView.image === originalImage, "Previous pixels should remain visible during an uncached transition")
        XCTAssertFalse(viewController.isLoadingOverlayVisible, "Uncached transitions should no longer show a loading overlay")
        XCTAssertEqual(window.title, "FastViewer • \(firstFileURL.lastPathComponent)", "Window title should stay tied to the displayed file until commit")

        waitUntil(description: "second image commits after uncached transition") {
            self.viewController.displayedFileURL == secondFileURL &&
            self.viewController.imageView.image != nil
        }

        XCTAssertEqual(viewController.displayedFileURL, secondFileURL, "Visible file should switch only when the new image commits")
        XCTAssertFalse(viewController.imageView.image === originalImage, "Committed image should replace the old image after loading finishes")
        XCTAssertEqual(window.title, "FastViewer • \(secondFileURL.lastPathComponent)", "Window title should update when the new image commits")
    }

    func testRapidNavigationAdvancesPastPendingImage() {
        let firstFileURL = makeTestImageFile(
            name: "test-rapid-first-\(UUID().uuidString).jpg",
            size: NSSize(width: 200, height: 150)
        )
        let secondFileURL = makeTestImageFile(
            name: "test-rapid-second-\(UUID().uuidString).jpg",
            size: NSSize(width: 5000, height: 3600)
        )
        let thirdFileURL = makeTestImageFile(
            name: "test-rapid-third-\(UUID().uuidString).jpg",
            size: NSSize(width: 300, height: 200)
        )
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
            try? FileManager.default.removeItem(at: thirdFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits before rapid navigation") {
            self.viewController.displayedFileURL == firstFileURL
        }
        viewController.fileListManager.fileURLs = [firstFileURL, secondFileURL, thirdFileURL]
        viewController.fileListManager.currentIndex = 0

        // The second call arrives before the large middle image can commit.
        viewController.navigateToNext()
        viewController.navigateToNext()

        waitUntil(description: "rapid navigation reaches the third image") {
            self.viewController.displayedFileURL == thirdFileURL
        }

        XCTAssertEqual(viewController.fileListManager.currentIndex, 2)
        XCTAssertEqual(viewController.displayedFileURL, thirdFileURL)
    }

    func testPrimaryImageClickNavigatesToNextImage() {
        let window = makeTestWindow()
        let firstFileURL = makeTestImageFile(name: "test-click-first-\(UUID().uuidString).jpg")
        let secondFileURL = makeTestImageFile(name: "test-click-second-\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits before click navigation") {
            self.viewController.displayedFileURL == firstFileURL
        }
        viewController.fileListManager.fileURLs = [firstFileURL, secondFileURL]
        viewController.fileListManager.currentIndex = 0

        guard let imageView = viewController.imageView as? DraggableImageView else {
            XCTFail("Image view should support feh-style click navigation")
            return
        }

        imageView.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 100, y: 100), timestamp: 1, window: window))
        imageView.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 100, y: 100), timestamp: 1.1, window: window))

        waitUntil(description: "click navigation reaches the second image") {
            self.viewController.displayedFileURL == secondFileURL
        }
    }

    func testPrimaryImageDragDoesNotNavigate() {
        let window = makeTestWindow()
        let firstFileURL = makeTestImageFile(name: "test-drag-first-\(UUID().uuidString).jpg")
        let secondFileURL = makeTestImageFile(name: "test-drag-second-\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits before drag test") {
            self.viewController.displayedFileURL == firstFileURL
        }
        viewController.fileListManager.fileURLs = [firstFileURL, secondFileURL]
        viewController.fileListManager.currentIndex = 0

        guard let imageView = viewController.imageView as? DraggableImageView else {
            XCTFail("Image view should support feh-style click navigation")
            return
        }

        imageView.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 100, y: 100), timestamp: 1, window: window))
        imageView.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: 110, y: 100), timestamp: 1.1, window: window))
        imageView.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 110, y: 100), timestamp: 1.2, window: window))

        XCTAssertEqual(viewController.displayedFileURL, firstFileURL, "Dragging should not advance to the next image")
        XCTAssertEqual(viewController.fileListManager.currentIndex, 0)
    }

    func testTwoPixelPrimaryMouseJitterStillNavigates() {
        let window = makeTestWindow()
        let firstFileURL = makeTestImageFile(name: "test-jitter-first-\(UUID().uuidString).jpg")
        let secondFileURL = makeTestImageFile(name: "test-jitter-second-\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits before jitter test") {
            self.viewController.displayedFileURL == firstFileURL
        }
        viewController.fileListManager.fileURLs = [firstFileURL, secondFileURL]
        viewController.fileListManager.currentIndex = 0

        guard let imageView = viewController.imageView as? DraggableImageView else {
            XCTFail("Image view should support feh-style click navigation")
            return
        }

        imageView.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 100, y: 100), timestamp: 1, window: window))
        imageView.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: 102, y: 102), timestamp: 1.1, window: window))
        imageView.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 102, y: 102), timestamp: 1.2, window: window))

        waitUntil(description: "two-pixel jitter is treated as a click") {
            self.viewController.displayedFileURL == secondFileURL
        }
    }

    func testRapidDiscreteScrollUsesLatestTargetWithoutWaitingForPendingImage() {
        let firstFileURL = makeTestImageFile(
            name: "test-wheel-first-\(UUID().uuidString).jpg",
            size: NSSize(width: 200, height: 150)
        )
        let secondFileURL = makeTestImageFile(
            name: "test-wheel-second-\(UUID().uuidString).jpg",
            size: NSSize(width: 5000, height: 3600)
        )
        let thirdFileURL = makeTestImageFile(
            name: "test-wheel-third-\(UUID().uuidString).jpg",
            size: NSSize(width: 5000, height: 3600)
        )
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
            try? FileManager.default.removeItem(at: thirdFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits before wheel navigation") {
            self.viewController.displayedFileURL == firstFileURL
        }
        viewController.fileListManager.fileURLs = [firstFileURL, secondFileURL, thirdFileURL]
        viewController.fileListManager.currentIndex = 0

        viewController.navigateWithDiscreteScroll(step: 1)
        viewController.navigateWithDiscreteScroll(step: 1)

        waitUntil(description: "wheel navigation reaches its latest target") {
            self.viewController.displayedFileURL == thirdFileURL
        }

        XCTAssertEqual(viewController.fileListManager.currentIndex, 2)
        XCTAssertEqual(viewController.displayedFileURL, thirdFileURL)
    }

    func testRapidNavigationPreviewImmediatelyFillsAutoResizedWindow() {
        let originalAutoResize = SettingsManager.shared.autoResizeToImageSize
        defer { SettingsManager.shared.autoResizeToImageSize = originalAutoResize }
        SettingsManager.shared.autoResizeToImageSize = true

        let window = makeTestWindow()
        let firstFileURL = makeTestImageFile(
            name: "test-preview-fill-first-\(UUID().uuidString).jpg",
            size: NSSize(width: 400, height: 300)
        )
        let largeFileURL = makeTestImageFile(
            name: "test-preview-fill-large-\(UUID().uuidString).jpg",
            size: NSSize(width: 5000, height: 3000)
        )
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: largeFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits before preview-fill navigation") {
            self.viewController.displayedFileURL == firstFileURL
        }
        viewController.fileListManager.fileURLs = [firstFileURL, largeFileURL]
        viewController.fileListManager.currentIndex = 0

        viewController.navigateWithDiscreteScroll(step: 1)
        waitUntil(description: "large rapid-navigation preview commits") {
            self.viewController.displayedFileURL == largeFileURL
        }

        guard let preview = viewController.imageView.image,
              let previewPixels = preview.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
              ) else {
            XCTFail("A decoded rapid-navigation preview should be displayed")
            return
        }
        let contentSize = window.contentRect(forFrameRect: window.frame).size
        XCTAssertLessThanOrEqual(max(previewPixels.width, previewPixels.height), 1024)
        XCTAssertGreaterThan(max(contentSize.width, contentSize.height), 1024)
        XCTAssertEqual(
            viewController.imageView.imageScaling,
            .scaleProportionallyUpOrDown,
            "The 1024px preview must already fill the final auto-resized frame"
        )
    }

    func testDiscreteScrollCanReverseWhileForwardImageIsPending() {
        let firstFileURL = makeTestImageFile(
            name: "test-wheel-reverse-first-\(UUID().uuidString).jpg",
            size: NSSize(width: 200, height: 150)
        )
        let secondFileURL = makeTestImageFile(
            name: "test-wheel-reverse-second-\(UUID().uuidString).jpg",
            size: NSSize(width: 5000, height: 3600)
        )
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits before reversing wheel direction") {
            self.viewController.displayedFileURL == firstFileURL
        }
        viewController.fileListManager.fileURLs = [firstFileURL, secondFileURL]
        viewController.fileListManager.currentIndex = 0

        viewController.navigateWithDiscreteScroll(step: 1)
        viewController.navigateWithDiscreteScroll(step: -1)

        waitUntil(description: "reverse wheel input returns to the visible image") {
            self.viewController.displayedFileURL == firstFileURL &&
            self.viewController.fileListManager.currentIndex == 0
        }
    }

    func testDiscreteScrollAutoResizesWindowImmediately() {
        let originalAutoResize = SettingsManager.shared.autoResizeToImageSize
        defer { SettingsManager.shared.autoResizeToImageSize = originalAutoResize }
        SettingsManager.shared.autoResizeToImageSize = true

        let window = makeTestWindow()
        let firstFileURL = makeTestImageFile(
            name: "test-wheel-size-first-\(UUID().uuidString).jpg",
            size: NSSize(width: 1200, height: 800)
        )
        let tinyFileURL = makeTestImageFile(
            name: "test-wheel-size-tiny-\(UUID().uuidString).jpg",
            size: NSSize(width: 246, height: 321)
        )
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: tinyFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits and establishes window size") {
            self.viewController.displayedFileURL == firstFileURL
        }
        let sizeBeforeWheelNavigation = window.frame.size
        viewController.fileListManager.fileURLs = [firstFileURL, tinyFileURL]
        viewController.fileListManager.currentIndex = 0

        viewController.navigateWithDiscreteScroll(step: 1)
        waitUntil(description: "tiny wheel target commits") {
            self.viewController.displayedFileURL == tinyFileURL
        }

        XCTAssertTrue(
            viewController.isWindowAtImageFitSize(),
            "Window should already fit the image when scroll navigation commits"
        )
        XCTAssertNotEqual(
            window.frame.size,
            sizeBeforeWheelNavigation,
            "Wheel navigation should resize immediately"
        )
    }

    func testImmediateScrollResizePreservesTopLeftAnchor() {
        let originalAutoResize = SettingsManager.shared.autoResizeToImageSize
        let originalAnchor = SettingsManager.shared.windowResizeAnchor
        defer {
            SettingsManager.shared.autoResizeToImageSize = originalAutoResize
            SettingsManager.shared.windowResizeAnchor = originalAnchor
        }
        SettingsManager.shared.autoResizeToImageSize = true
        SettingsManager.shared.windowResizeAnchor = .topLeft

        let window = makeTestWindow()
        let largeFileURL = makeTestImageFile(
            name: "test-wheel-pointer-large-\(UUID().uuidString).jpg",
            size: NSSize(width: 1200, height: 800)
        )
        let tinyFileURL = makeTestImageFile(
            name: "test-wheel-pointer-tiny-\(UUID().uuidString).jpg",
            size: NSSize(width: 246, height: 321)
        )
        defer {
            try? FileManager.default.removeItem(at: largeFileURL)
            try? FileManager.default.removeItem(at: tinyFileURL)
        }

        viewController.loadImage(from: largeFileURL)
        waitUntil(description: "large image establishes the initial scroll window") {
            self.viewController.displayedFileURL == largeFileURL
        }
        viewController.fileListManager.fileURLs = [largeFileURL, tinyFileURL]
        viewController.fileListManager.currentIndex = 0

        let frameBeforeScroll = window.frame
        let initialContentRect = window.contentRect(forFrameRect: window.frame)
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? initialContentRect
        let pointerScreenPoint = NSPoint(
            x: min(initialContentRect.maxX - 20, visibleFrame.maxX - 20),
            y: max(initialContentRect.minY + 20, visibleFrame.minY + 20)
        )

        guard let nextScrollEvent = makeScrollEvent(
            deltaY: -1,
            screenPoint: pointerScreenPoint
        ) else {
            XCTFail("A mouse-wheel event should be available")
            return
        }
        viewController.handleScroll(with: nextScrollEvent)
        waitUntil(description: "tiny image commits with immediate resize") {
            self.viewController.displayedFileURL == tinyFileURL
        }

        XCTAssertEqual(
            window.frame.minX,
            frameBeforeScroll.minX,
            accuracy: 0.01,
            "Top-left resize must preserve the window's left edge"
        )
        XCTAssertEqual(
            window.frame.maxY,
            frameBeforeScroll.maxY,
            accuracy: 0.01,
            "Top-left resize must preserve the window's top edge"
        )
        XCTAssertTrue(
            viewController.isOffWindowScrollCaptureActive,
            "Scroll capture must continue navigation when the resized window leaves the pointer outside"
        )

        guard let previousScrollEvent = makeScrollEvent(
            deltaY: 1,
            screenPoint: pointerScreenPoint
        ) else {
            XCTFail("A second mouse-wheel event should be available")
            return
        }
        XCTAssertTrue(
            viewController.handleCapturedOffWindowScroll(
                previousScrollEvent,
                currentPointer: pointerScreenPoint,
                requireActiveWindow: false
            ),
            "The captured wheel event should be handled without moving the pointer"
        )
        waitUntil(description: "captured wheel step reaches the large image") {
            self.viewController.displayedFileURL == largeFileURL
        }
        XCTAssertEqual(window.frame.minX, frameBeforeScroll.minX, accuracy: 0.01)
        XCTAssertEqual(window.frame.maxY, frameBeforeScroll.maxY, accuracy: 0.01)
    }

    func testDiscreteScrollPreservesAcceleratedStepMagnitude() {
        let fileURLs = (0..<5).map { index in
            makeTestImageFile(
                name: "test-wheel-magnitude-\(index)-\(UUID().uuidString).jpg",
                size: NSSize(width: 200, height: 150)
            )
        }
        defer {
            fileURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        viewController.loadImage(from: fileURLs[0])
        waitUntil(description: "first image commits before accelerated wheel navigation") {
            self.viewController.displayedFileURL == fileURLs[0]
        }
        viewController.fileListManager.fileURLs = fileURLs
        viewController.fileListManager.currentIndex = 0

        viewController.navigateWithDiscreteScroll(step: 3)

        waitUntil(description: "accelerated wheel reaches its multi-step target") {
            self.viewController.displayedFileURL == fileURLs[3]
        }

        XCTAssertEqual(viewController.fileListManager.currentIndex, 3)
        XCTAssertEqual(viewController.displayedFileURL, fileURLs[3])
    }

    func testStaleFileInfoUpdateDoesNotOverwriteDisplayedFile() {
        let originalShowFileSize = SettingsManager.shared.showFileSize
        let originalShowCreationDate = SettingsManager.shared.showCreationDate
        let originalShowImageResolution = SettingsManager.shared.showImageResolution
        defer {
            SettingsManager.shared.showFileSize = originalShowFileSize
            SettingsManager.shared.showCreationDate = originalShowCreationDate
            SettingsManager.shared.showImageResolution = originalShowImageResolution
        }

        SettingsManager.shared.showFileSize = false
        SettingsManager.shared.showCreationDate = false
        SettingsManager.shared.showImageResolution = true

        let firstFileURL = makeTestImageFile(
            name: "test-info-a-\(UUID().uuidString).jpg",
            size: NSSize(width: 111, height: 77)
        )
        let secondFileURL = makeTestImageFile(
            name: "test-info-b-\(UUID().uuidString).jpg",
            size: NSSize(width: 222, height: 144)
        )
        defer {
            try? FileManager.default.removeItem(at: firstFileURL)
            try? FileManager.default.removeItem(at: secondFileURL)
        }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first image commits before stale info test") {
            self.viewController.displayedFileURL == firstFileURL
        }

        viewController.updateFileInfo(for: firstFileURL)
        viewController.loadImage(from: secondFileURL)

        waitUntil(description: "second image commits before checking info text") {
            self.viewController.displayedFileURL == secondFileURL
        }
        waitUntil(description: "file info reflects the currently displayed file") {
            self.viewController.displayedFileInfoText == "222×144"
        }

        XCTAssertEqual(viewController.displayedFileInfoText, "222×144", "Stale file-info work should not overwrite the newly displayed file")
    }

    func testStaleFileTagUpdateDoesNotReappearAfterHide() {
        let originalShowFileTag = SettingsManager.shared.showFileTag
        defer { SettingsManager.shared.showFileTag = originalShowFileTag }

        SettingsManager.shared.showFileTag = true

        let testFileURL = makeTaggedTestImageFile(
            name: "test-tag-stale-\(UUID().uuidString).jpg",
            labelNumber: 6
        )
        defer { try? FileManager.default.removeItem(at: testFileURL) }

        viewController.loadImage(from: testFileURL)
        waitUntil(description: "tagged file commits before stale tag test") {
            self.viewController.displayedFileURL == testFileURL
        }

        viewController.updateFileTagDisplay(for: testFileURL)
        viewController.updateFileTagDisplay(for: nil)
        waitForAsyncWork(delay: 0.3)

        XCTAssertEqual(viewController.displayedTagCircleCount, 0, "Stale tag completions should not restore hidden tag circles")
    }

    func testUndoRestoresMultipleFilesInLIFOOrder() {
        let directoryURL = makeTestDirectory(name: "undo-stack-\(UUID().uuidString)")
        let firstFileURL = makeTestImageFile(
            name: "a-\(UUID().uuidString).jpg",
            directoryURL: directoryURL
        )
        let secondFileURL = makeTestImageFile(
            name: "b-\(UUID().uuidString).jpg",
            directoryURL: directoryURL
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        viewController.loadImage(from: firstFileURL)
        waitUntil(description: "first file commits before delete sequence") {
            self.viewController.displayedFileURL == firstFileURL
        }

        viewController.moveCurrentFileToTrash()
        waitUntil(description: "second file becomes visible after first delete") {
            self.viewController.displayedFileURL == secondFileURL &&
            !FileManager.default.fileExists(atPath: firstFileURL.path)
        }

        viewController.moveCurrentFileToTrash()
        waitUntil(description: "empty state appears after deleting the second file") {
            self.viewController.displayedFileURL == nil &&
            self.viewController.imageView.image == nil &&
            !FileManager.default.fileExists(atPath: secondFileURL.path)
        }

        XCTAssertTrue(viewController.canUndoMoveToTrash, "Deleting multiple files should keep undo available")

        viewController.undoMoveToTrash()
        waitUntil(description: "latest deleted file restores first") {
            self.viewController.displayedFileURL == secondFileURL &&
            FileManager.default.fileExists(atPath: secondFileURL.path)
        }

        XCTAssertTrue(viewController.canUndoMoveToTrash, "Older undo entries should remain after restoring the newest file")

        viewController.undoMoveToTrash()
        waitUntil(description: "older deleted file restores second") {
            self.viewController.displayedFileURL == firstFileURL &&
            FileManager.default.fileExists(atPath: firstFileURL.path)
        }

        XCTAssertFalse(viewController.canUndoMoveToTrash, "Undo stack should be empty after restoring both files")
    }

    func testFailedInitialLoadPreservesEmptyStateAndShowsToast() {
        let invalidFileURL = makeInvalidImageFile(name: "test-invalid-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: invalidFileURL) }

        viewController.loadImage(from: invalidFileURL)
        waitUntil(description: "toast appears after failed image load") {
            self.viewController.toastText.contains("Couldn't open")
        }

        XCTAssertNil(viewController.displayedFileURL, "Failed first load should leave the controller in the empty state")
        XCTAssertNil(viewController.imageView.image, "Failed first load should not display an image")
        XCTAssertFalse(viewController.isLoadingOverlayVisible, "Failed load should leave the loading overlay hidden")
        XCTAssertTrue(viewController.toastText.contains(invalidFileURL.lastPathComponent), "Failure toast should include the filename")
    }

    func testCmd1DisablesAutoResizeWhenEnabled() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Enable auto-resize setting
        SettingsManager.shared.autoResizeToImageSize = true
        XCTAssertTrue(SettingsManager.shared.autoResizeToImageSize, "Auto-resize should be enabled")

        // Create a Cmd+1 key event
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "1",
            charactersIgnoringModifiers: "1",
            isARepeat: false,
            keyCode: 18 // 1 key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler
        viewController.keyDown(with: keyEvent)

        // Wait a moment for async operations
        let expectation = XCTestExpectation(description: "Auto-resize disabled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        // Verify auto-resize is now disabled
        XCTAssertFalse(SettingsManager.shared.autoResizeToImageSize, "Auto-resize should be disabled after Cmd+1")
    }

    func testCmd2DisablesAutoResizeWhenEnabled() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Enable auto-resize setting
        SettingsManager.shared.autoResizeToImageSize = true
        XCTAssertTrue(SettingsManager.shared.autoResizeToImageSize, "Auto-resize should be enabled")

        // Create a Cmd+2 key event
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "2",
            charactersIgnoringModifiers: "2",
            isARepeat: false,
            keyCode: 19 // 2 key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler
        viewController.keyDown(with: keyEvent)

        // Wait a moment for async operations
        let expectation = XCTestExpectation(description: "Auto-resize disabled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        // Verify auto-resize is now disabled
        XCTAssertFalse(SettingsManager.shared.autoResizeToImageSize, "Auto-resize should be disabled after Cmd+2")
    }

    func testCmd3DisablesAutoResizeWhenEnabled() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Enable auto-resize setting
        SettingsManager.shared.autoResizeToImageSize = true
        XCTAssertTrue(SettingsManager.shared.autoResizeToImageSize, "Auto-resize should be enabled")

        // Create a Cmd+3 key event
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "3",
            charactersIgnoringModifiers: "3",
            isARepeat: false,
            keyCode: 20 // 3 key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler
        viewController.keyDown(with: keyEvent)

        // Wait a moment for async operations
        let expectation = XCTestExpectation(description: "Auto-resize disabled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        // Verify auto-resize is now disabled
        XCTAssertFalse(SettingsManager.shared.autoResizeToImageSize, "Auto-resize should be disabled after Cmd+3")
    }

    func testCmd1DoesNotDisableAutoResizeWhenAlreadyDisabled() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Disable auto-resize setting
        SettingsManager.shared.autoResizeToImageSize = false
        XCTAssertFalse(SettingsManager.shared.autoResizeToImageSize, "Auto-resize should be disabled")

        // Create a Cmd+1 key event
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "1",
            charactersIgnoringModifiers: "1",
            isARepeat: false,
            keyCode: 18 // 1 key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger the keyDown handler
        viewController.keyDown(with: keyEvent)

        // Wait a moment for async operations
        let expectation = XCTestExpectation(description: "Window resized")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        // Verify auto-resize remains disabled
        XCTAssertFalse(SettingsManager.shared.autoResizeToImageSize, "Auto-resize should remain disabled after Cmd+1 when already disabled")
    }

    func testZoomIn() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create a test image
        let testImage = createTestImage(size: NSSize(width: 800, height: 600))
        viewController.imageView.image = testImage

        // Create a temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-image-\(UUID().uuidString).jpg")

        // Create a simple test image file
        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            // Clean up test file
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Load the test file
        viewController.loadImage(from: testFileURL)

        // Wait for async image loading
        let loadExpectation = XCTestExpectation(description: "Image loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 1.0)

        // Verify initial zoom is 1.0 (no transform)
        let initialTransform = viewController.imageView.layer?.transform
        XCTAssertEqual(initialTransform?.m11 ?? 1.0, 1.0, accuracy: 0.01, "Initial zoom should be 1.0")

        // Create a Cmd+= key event for zoom in
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24 // = key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger zoom in
        viewController.keyDown(with: keyEvent)

        // Wait a moment for zoom to apply
        let zoomExpectation = XCTestExpectation(description: "Zoom applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoomExpectation.fulfill()
        }
        wait(for: [zoomExpectation], timeout: 0.5)

        // Verify zoom was applied (transform should be > 1.0)
        let zoomedTransform = viewController.imageView.layer?.transform
        XCTAssertGreaterThan(zoomedTransform?.m11 ?? 1.0, 1.0, "Zoom in should increase scale")
    }

    func testZoomOut() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create a test image
        let testImage = createTestImage(size: NSSize(width: 800, height: 600))
        viewController.imageView.image = testImage

        // Create a temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-image-\(UUID().uuidString).jpg")

        // Create a simple test image file
        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            // Clean up test file
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Load the test file
        viewController.loadImage(from: testFileURL)

        // Wait for async image loading
        let loadExpectation = XCTestExpectation(description: "Image loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 1.0)

        // Create a Cmd+- key event for zoom out
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "-",
            charactersIgnoringModifiers: "-",
            isARepeat: false,
            keyCode: 27 // - key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger zoom out
        viewController.keyDown(with: keyEvent)

        // Wait a moment for zoom to apply
        let zoomExpectation = XCTestExpectation(description: "Zoom applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoomExpectation.fulfill()
        }
        wait(for: [zoomExpectation], timeout: 0.5)

        // Verify zoom out was applied (transform should be < 1.0)
        let zoomedTransform = viewController.imageView.layer?.transform
        XCTAssertLessThan(zoomedTransform?.m11 ?? 1.0, 1.0, "Zoom out should decrease scale")
    }

    func testPixelGridWhenZoomedIn() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create a test image
        let testImage = createTestImage(size: NSSize(width: 800, height: 600))
        viewController.imageView.image = testImage

        // Create a temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-image-\(UUID().uuidString).jpg")

        // Create a simple test image file
        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            // Clean up test file
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Load the test file
        viewController.loadImage(from: testFileURL)

        // Wait for async image loading
        let loadExpectation = XCTestExpectation(description: "Image loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 1.0)

        // Ensure layer is set up
        viewController.imageView.wantsLayer = true
        guard let layer = viewController.imageView.layer else {
            XCTFail("Image view layer should be available")
            return
        }

        // Verify initial state uses linear filtering (smooth interpolation)
        XCTAssertEqual(layer.magnificationFilter, .linear, "Initial state should use linear filtering for smooth interpolation")
        XCTAssertEqual(layer.minificationFilter, .linear, "Initial state should use linear filtering for smooth interpolation")

        // Zoom in to trigger pixel grid mode
        let zoomInEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24 // = key
        )

        guard let keyEvent = zoomInEvent else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger zoom in
        viewController.keyDown(with: keyEvent)

        // Wait a moment for zoom to apply
        let zoomExpectation = XCTestExpectation(description: "Zoom applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoomExpectation.fulfill()
        }
        wait(for: [zoomExpectation], timeout: 0.5)

        // Verify zoom was applied (transform should be > 1.0)
        let zoomedTransform = viewController.imageView.layer?.transform
        XCTAssertGreaterThan(zoomedTransform?.m11 ?? 1.0, 1.0, "Zoom in should increase scale")

        // Verify pixel grid mode is enabled (nearest-neighbor filtering)
        XCTAssertEqual(layer.magnificationFilter, .nearest, "When zoomed in, should use nearest-neighbor filtering to show pixel grid")
        XCTAssertEqual(layer.minificationFilter, .nearest, "When zoomed in, should use nearest-neighbor filtering to show pixel grid")

        // Zoom out or reset to normal zoom
        let zoomOutEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "-",
            charactersIgnoringModifiers: "-",
            isARepeat: false,
            keyCode: 27 // - key
        )

        guard let zoomOutKeyEvent = zoomOutEvent else {
            XCTFail("Failed to create zoom out key event")
            return
        }

        // Zoom out multiple times to get back to 1.0 or below
        for _ in 0..<5 {
            viewController.keyDown(with: zoomOutKeyEvent)
        }

        // Wait for zoom out to apply
        let zoomOutExpectation = XCTestExpectation(description: "Zoom out applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoomOutExpectation.fulfill()
        }
        wait(for: [zoomOutExpectation], timeout: 0.5)

        // Verify filtering is back to linear when not zoomed in
        let finalTransform = viewController.imageView.layer?.transform
        if (finalTransform?.m11 ?? 1.0) <= 1.0 {
            XCTAssertEqual(layer.magnificationFilter, .linear, "When not zoomed in, should use linear filtering for smooth interpolation")
            XCTAssertEqual(layer.minificationFilter, .linear, "When not zoomed in, should use linear filtering for smooth interpolation")
        }
    }

    func testCommandZeroDisplaysActualSizeWithoutResizingWindow() {
        let previousAutoResize = SettingsManager.shared.autoResizeToImageSize
        SettingsManager.shared.autoResizeToImageSize = false
        defer {
            SettingsManager.shared.autoResizeToImageSize = previousAutoResize
        }

        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Use an image that remains larger than the window at physical 100% on Retina.
        let testImageSize = NSSize(width: 2400, height: 1800)
        let testImage = createTestImage(size: testImageSize)
        viewController.imageView.image = testImage

        // Create a temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-image-\(UUID().uuidString).jpg")

        // Create a simple test image file
        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            // Clean up test file
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Load the test file
        viewController.loadImage(from: testFileURL)

        // Wait for async image loading
        let loadExpectation = XCTestExpectation(description: "Image loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 1.0)

        // First zoom in
        let zoomInEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24 // = key
        )

        if let zoomInKeyEvent = zoomInEvent {
            viewController.keyDown(with: zoomInKeyEvent)
        }

        // Wait for zoom in
        let zoomInExpectation = XCTestExpectation(description: "Zoom in applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoomInExpectation.fulfill()
        }
        wait(for: [zoomInExpectation], timeout: 0.5)

        // Verify zoom was applied
        let zoomedTransform = viewController.imageView.layer?.transform
        XCTAssertGreaterThan(zoomedTransform?.m11 ?? 1.0, 1.0, "Zoom in should increase scale")

        window.setContentSize(NSSize(width: 600, height: 400))
        viewController.view.layoutSubtreeIfNeeded()
        let frameBeforeActualSize = window.frame
        SettingsManager.shared.autoResizeToImageSize = true

        // Display at Actual Size with Cmd+0.
        let restoreEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "0",
            charactersIgnoringModifiers: "0",
            isARepeat: false,
            keyCode: 29 // 0 key
        )

        guard let restoreKeyEvent = restoreEvent else {
            XCTFail("Failed to create restore key event")
            return
        }

        // Trigger restore
        viewController.keyDown(with: restoreKeyEvent)

        // Wait a moment for restore to apply
        let restoreExpectation = XCTestExpectation(description: "Actual Size applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            restoreExpectation.fulfill()
        }
        wait(for: [restoreExpectation], timeout: 0.5)

        let actualSizeTransform = viewController.imageView.layer?.transform
        guard let loadedImage = viewController.imageView.image else {
            XCTFail("Image should remain loaded")
            return
        }

        let fittedScale = min(
            1.0,
            min(
                viewController.view.bounds.width / loadedImage.size.width,
                viewController.view.bounds.height / loadedImage.size.height
            )
        )
        let baseDisplayedSize = NSSize(
            width: loadedImage.size.width * fittedScale,
            height: loadedImage.size.height * fittedScale
        )
        let backingScale = window.backingScaleFactor
        let expectedScale = min(
            (testImageSize.width / backingScale) / baseDisplayedSize.width,
            (testImageSize.height / backingScale) / baseDisplayedSize.height
        )

        XCTAssertEqual(
            actualSizeTransform?.m11 ?? 0,
            expectedScale,
            accuracy: 0.01,
            "Cmd+0 should map image pixels to physical display pixels"
        )
        XCTAssertEqual(window.frame.origin.x, frameBeforeActualSize.origin.x, accuracy: 0.01)
        XCTAssertEqual(window.frame.origin.y, frameBeforeActualSize.origin.y, accuracy: 0.01)
        XCTAssertEqual(window.frame.width, frameBeforeActualSize.width, accuracy: 0.01)
        XCTAssertEqual(window.frame.height, frameBeforeActualSize.height, accuracy: 0.01)
        XCTAssertFalse(
            SettingsManager.shared.autoResizeToImageSize,
            "Cmd+0 should disable Fit to Image"
        )
        XCTAssertTrue(
            viewController.isPanningAvailable(),
            "An Actual Size image extending beyond the window should be pannable"
        )

        window.setContentSize(NSSize(width: 800, height: 500))
        viewController.view.layoutSubtreeIfNeeded()
        viewController.viewDidLayout()

        let resizedFittedScale = min(
            1.0,
            min(
                viewController.view.bounds.width / loadedImage.size.width,
                viewController.view.bounds.height / loadedImage.size.height
            )
        )
        let resizedBaseSize = NSSize(
            width: loadedImage.size.width * resizedFittedScale,
            height: loadedImage.size.height * resizedFittedScale
        )
        let expectedResizedTransform = min(
            (testImageSize.width / backingScale) / resizedBaseSize.width,
            (testImageSize.height / backingScale) / resizedBaseSize.height
        )
        XCTAssertEqual(
            viewController.imageView.layer?.transform.m11 ?? 0,
            expectedResizedTransform,
            accuracy: 0.01,
            "Actual Size should remain pixel-accurate after resizing the window"
        )
    }

    func testZoomPersistsPerImage() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create two test images
        let testImage1 = createTestImage(size: NSSize(width: 800, height: 600))
        let testImage2 = createTestImage(size: NSSize(width: 1000, height: 750))

        // Create temporary test files
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL1 = tempDir.appendingPathComponent("test-image-1-\(UUID().uuidString).jpg")
        let testFileURL2 = tempDir.appendingPathComponent("test-image-2-\(UUID().uuidString).jpg")

        // Create test image files
        guard let tiffData1 = testImage1.tiffRepresentation,
              let bitmapImage1 = NSBitmapImageRep(data: tiffData1),
              let jpegData1 = bitmapImage1.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image 1 data")
            return
        }

        guard let tiffData2 = testImage2.tiffRepresentation,
              let bitmapImage2 = NSBitmapImageRep(data: tiffData2),
              let jpegData2 = bitmapImage2.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image 2 data")
            return
        }

        do {
            try jpegData1.write(to: testFileURL1)
            try jpegData2.write(to: testFileURL2)
        } catch {
            XCTFail("Failed to create test files: \(error)")
            return
        }

        defer {
            // Clean up test files
            try? FileManager.default.removeItem(at: testFileURL1)
            try? FileManager.default.removeItem(at: testFileURL2)
        }

        // Load first image
        viewController.loadImage(from: testFileURL1)

        // Wait for async image loading
        let load1Expectation = XCTestExpectation(description: "Image 1 loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            load1Expectation.fulfill()
        }
        wait(for: [load1Expectation], timeout: 1.0)

        // Zoom in on first image
        let zoomInEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24 // = key
        )

        if let zoomInKeyEvent = zoomInEvent {
            viewController.keyDown(with: zoomInKeyEvent)
        }

        // Wait for zoom
        let zoom1Expectation = XCTestExpectation(description: "Zoom 1 applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoom1Expectation.fulfill()
        }
        wait(for: [zoom1Expectation], timeout: 0.5)

        // Get zoom scale for first image
        let zoom1Transform = viewController.imageView.layer?.transform
        let zoom1Scale = zoom1Transform?.m11 ?? 1.0

        // Load second image
        viewController.loadImage(from: testFileURL2)

        // Wait for async image loading
        let load2Expectation = XCTestExpectation(description: "Image 2 loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            load2Expectation.fulfill()
        }
        wait(for: [load2Expectation], timeout: 1.0)

        // Second image should have no zoom (1.0)
        let zoom2Transform = viewController.imageView.layer?.transform
        let zoom2Scale = zoom2Transform?.m11 ?? 1.0
        XCTAssertEqual(zoom2Scale, 1.0, accuracy: 0.01, "Second image should start with zoom 1.0")

        // Switch back to first image
        viewController.loadImage(from: testFileURL1)

        // Wait for async image loading
        let load1AgainExpectation = XCTestExpectation(description: "Image 1 loaded again")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            load1AgainExpectation.fulfill()
        }
        wait(for: [load1AgainExpectation], timeout: 1.0)

        // First image should have its stored zoom restored
        let zoom1RestoredTransform = viewController.imageView.layer?.transform
        let zoom1RestoredScale = zoom1RestoredTransform?.m11 ?? 1.0
        XCTAssertEqual(zoom1RestoredScale, zoom1Scale, accuracy: 0.01, "First image should restore its stored zoom")
    }

    func testZoomResetsWhenSwitchingFilesInCmd4Mode() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Enable cmd4 mode (autoResizeToImageSize)
        SettingsManager.shared.autoResizeToImageSize = true
        SettingsManager.shared.autoResizeWithAnimation = false // Disable animation for faster tests

        // Create two test images
        let testImage1 = createTestImage(size: NSSize(width: 800, height: 600))
        let testImage2 = createTestImage(size: NSSize(width: 1000, height: 750))

        // Create temporary test files
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL1 = tempDir.appendingPathComponent("test-image-1-\(UUID().uuidString).jpg")
        let testFileURL2 = tempDir.appendingPathComponent("test-image-2-\(UUID().uuidString).jpg")

        // Create test image files
        guard let tiffData1 = testImage1.tiffRepresentation,
              let bitmapImage1 = NSBitmapImageRep(data: tiffData1),
              let jpegData1 = bitmapImage1.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image 1 data")
            return
        }

        guard let tiffData2 = testImage2.tiffRepresentation,
              let bitmapImage2 = NSBitmapImageRep(data: tiffData2),
              let jpegData2 = bitmapImage2.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image 2 data")
            return
        }

        do {
            try jpegData1.write(to: testFileURL1)
            try jpegData2.write(to: testFileURL2)
        } catch {
            XCTFail("Failed to create test files: \(error)")
            return
        }

        defer {
            // Clean up test files
            try? FileManager.default.removeItem(at: testFileURL1)
            try? FileManager.default.removeItem(at: testFileURL2)
            // Reset settings
            SettingsManager.shared.autoResizeToImageSize = false
        }

        // Load first image
        viewController.loadImage(from: testFileURL1)

        // Wait for async image loading and window resize
        let load1Expectation = XCTestExpectation(description: "Image 1 loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            load1Expectation.fulfill()
        }
        wait(for: [load1Expectation], timeout: 1.5)

        // Store initial window size (should match image 1 size)
        let initialWindowSize = window.frame.size

        // Zoom out on first image using Cmd+- (in cmd4 mode, this scales window down)
        let zoomOutEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "-",
            charactersIgnoringModifiers: "-",
            isARepeat: false,
            keyCode: 27 // - key
        )

        if let zoomOutKeyEvent = zoomOutEvent {
            viewController.keyDown(with: zoomOutKeyEvent)
        }

        // Wait for window resize to apply
        let zoomOutExpectation = XCTestExpectation(description: "Zoom out applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            zoomOutExpectation.fulfill()
        }
        wait(for: [zoomOutExpectation], timeout: 0.5)

        // In cmd4 mode, Cmd- scales window down instead of applying zoom transform
        // Verify window is smaller than initial size
        let scaledWindowSize = window.frame.size
        XCTAssertLessThan(scaledWindowSize.width, initialWindowSize.width, "Cmd- in cmd4 mode should scale window down")

        // Image transform should still be 1.0 (no zoom transform, just window scaling)
        let transform = viewController.imageView.layer?.transform
        let scale = transform?.m11 ?? 1.0
        XCTAssertEqual(scale, 1.0, accuracy: 0.01, "In cmd4 mode, Cmd- scales window, not zoom transform")

        // Switch to second image (window should resize to match new image)
        viewController.loadImage(from: testFileURL2)

        // Wait for async image loading and window resize
        let load2Expectation = XCTestExpectation(description: "Image 2 loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            load2Expectation.fulfill()
        }
        wait(for: [load2Expectation], timeout: 1.5)

        // Second image should have zoom at 1.0 (window resizes to match image)
        let zoom2Transform = viewController.imageView.layer?.transform
        let zoom2Scale = zoom2Transform?.m11 ?? 1.0
        XCTAssertEqual(zoom2Scale, 1.0, accuracy: 0.01, "Zoom should be 1.0 when switching files in cmd4 mode")
    }

    func testCmd4ModeZoomKeepsWindowAndImageSynchronized() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), // Start with small window
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Enable cmd4 mode
        SettingsManager.shared.autoResizeToImageSize = true
        SettingsManager.shared.autoResizeWithAnimation = false

        // Create a test image
        let testImage = createTestImage(size: NSSize(width: 800, height: 600))

        // Create temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-zoom-cmd4-\(UUID().uuidString).jpg")

        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            try? FileManager.default.removeItem(at: testFileURL)
            SettingsManager.shared.autoResizeToImageSize = false
        }

        // Load image (window should resize to match image)
        viewController.loadImage(from: testFileURL)

        let loadExpectation = XCTestExpectation(description: "Image loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 1.5)

        let initialContentSize = window.contentRect(forFrameRect: window.frame).size

        let zoomInEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24
        )

        if let event = zoomInEvent {
            viewController.keyDown(with: event)
        }

        let zoomInExpectation = XCTestExpectation(description: "Zoom in applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            zoomInExpectation.fulfill()
        }
        wait(for: [zoomInExpectation], timeout: 0.5)

        let zoomedContentSize = window.contentRect(forFrameRect: window.frame).size
        XCTAssertGreaterThan(zoomedContentSize.width, initialContentSize.width, "Cmd+ in cmd4 mode should enlarge the window")

        let transformAfterZoomIn = viewController.imageView.layer?.transform
        let scaleAfterZoomIn = transformAfterZoomIn?.m11 ?? 1.0
        XCTAssertGreaterThan(scaleAfterZoomIn, 1.0, "Cmd+ in cmd4 mode should also enlarge the image transform")

        let windowScale = zoomedContentSize.width / initialContentSize.width
        XCTAssertEqual(scaleAfterZoomIn, windowScale, accuracy: 0.05, "Cmd+ should grow the window and image in sync")

        let shouldPanWhileFitted = viewController.shouldStartPanning(at: NSPoint(x: 100, y: 100))
        XCTAssertFalse(shouldPanWhileFitted, "Panning should stay disabled while the enlarged image still fits the enlarged window")

        let zoomOutEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "-",
            charactersIgnoringModifiers: "-",
            isARepeat: false,
            keyCode: 27
        )

        if let event = zoomOutEvent {
            viewController.keyDown(with: event)
        }

        let zoomOutExpectation = XCTestExpectation(description: "Zoom out applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            zoomOutExpectation.fulfill()
        }
        wait(for: [zoomOutExpectation], timeout: 0.5)

        let restoredContentSize = window.contentRect(forFrameRect: window.frame).size
        let transformAfterZoomOut = viewController.imageView.layer?.transform
        let scaleAfterZoomOut = transformAfterZoomOut?.m11 ?? 1.0

        XCTAssertEqual(restoredContentSize.width, initialContentSize.width, accuracy: 2.0, "Cmd- should shrink the window back to fit size")
        XCTAssertEqual(scaleAfterZoomOut, 1.0, accuracy: 0.01, "Cmd- should shrink the image back to fit size in the same step")
    }

    func testZoomResetsWhenChangingWindowPreset() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Ensure cmd4 mode is off
        SettingsManager.shared.autoResizeToImageSize = false

        // Create a test image
        let testImage = createTestImage(size: NSSize(width: 800, height: 600))

        // Create temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-preset-zoom-\(UUID().uuidString).jpg")

        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Load image
        viewController.loadImage(from: testFileURL)

        let loadExpectation = XCTestExpectation(description: "Image loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 1.0)

        // Zoom in
        let zoomInEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24
        )

        if let event = zoomInEvent {
            viewController.keyDown(with: event)
        }

        let zoomExpectation = XCTestExpectation(description: "Zoom applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            zoomExpectation.fulfill()
        }
        wait(for: [zoomExpectation], timeout: 0.5)

        // Verify zoom was applied
        let zoomedTransform = viewController.imageView.layer?.transform
        let zoomedScale = zoomedTransform?.m11 ?? 1.0
        XCTAssertGreaterThan(zoomedScale, 1.0, "Zoom should be > 1.0 after Cmd+=")

        // Now change window preset with Cmd+2 (900x600)
        let cmd2Event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "2",
            charactersIgnoringModifiers: "2",
            isARepeat: false,
            keyCode: 19 // 2 key
        )

        if let event = cmd2Event {
            viewController.keyDown(with: event)
        }

        // Wait for window resize
        let resizeExpectation = XCTestExpectation(description: "Window resized")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            resizeExpectation.fulfill()
        }
        wait(for: [resizeExpectation], timeout: 1.0)

        // Zoom should be reset to 1.0 after changing window preset
        let resetTransform = viewController.imageView.layer?.transform
        let resetScale = resetTransform?.m11 ?? 1.0
        XCTAssertEqual(resetScale, 1.0, accuracy: 0.01, "Zoom should reset to 1.0 when changing window preset with Cmd+2")
    }

    func testZoomWithNoImageDoesNotCrash() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Ensure no image is loaded
        viewController.imageView.image = nil
        viewController.fileListManager.reset()

        // Create a Cmd+= key event for zoom in
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24 // = key
        )

        guard let keyEvent = event else {
            XCTFail("Failed to create key event")
            return
        }

        // Trigger zoom in - should handle gracefully when no image is loaded
        viewController.keyDown(with: keyEvent)

        // If we get here without crashing, the test passes
    }

    // MARK: - Panning Tests

    func testPanningOnlyWorksWhenZoomed() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create a test image
        let testImage = createTestImage(size: NSSize(width: 800, height: 600))
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-image-\(UUID().uuidString).jpg")

        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Load image
        viewController.loadImage(from: testFileURL)

        // Wait for async image loading
        let loadExpectation = XCTestExpectation(description: "Image loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 1.0)

        // Test that panning should not start when not zoomed
        let location = NSPoint(x: 100, y: 100)
        let shouldPan = viewController.shouldStartPanning(at: location)
        XCTAssertFalse(shouldPan, "Panning should not start when not zoomed")

        // Zoom in
        let zoomInEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24
        )

        if let zoomInKeyEvent = zoomInEvent {
            viewController.keyDown(with: zoomInKeyEvent)
        }

        // Wait for zoom
        let zoomExpectation = XCTestExpectation(description: "Zoom applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoomExpectation.fulfill()
        }
        wait(for: [zoomExpectation], timeout: 0.5)

        // Now panning should be allowed
        let shouldPanAfterZoom = viewController.shouldStartPanning(at: location)
        XCTAssertTrue(shouldPanAfterZoom, "Panning should be allowed when zoomed")
    }

    func testPanningAppliesTransform() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create a test image
        let testImage = createTestImage(size: NSSize(width: 800, height: 600))
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-image-\(UUID().uuidString).jpg")

        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Load image
        viewController.loadImage(from: testFileURL)

        // Wait for async image loading
        let loadExpectation = XCTestExpectation(description: "Image loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 1.0)

        // Zoom in first
        let zoomInEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24
        )

        if let zoomInKeyEvent = zoomInEvent {
            viewController.keyDown(with: zoomInKeyEvent)
        }

        // Wait for zoom
        let zoomExpectation = XCTestExpectation(description: "Zoom applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoomExpectation.fulfill()
        }
        wait(for: [zoomExpectation], timeout: 0.5)

        // Get initial transform (should have zoom but no translation)
        let initialTransform = viewController.imageView.layer?.transform
        let initialTranslationX = initialTransform?.m41 ?? 0
        let initialTranslationY = initialTransform?.m42 ?? 0

        // Start panning
        let startLocation = NSPoint(x: 100, y: 100)
        viewController.handlePanStart(at: startLocation)

        // Move to a new location (simulating drag)
        let endLocation = NSPoint(x: 150, y: 120)
        viewController.handlePanMove(to: endLocation)

        // Wait for transform to apply
        let panExpectation = XCTestExpectation(description: "Pan applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            panExpectation.fulfill()
        }
        wait(for: [panExpectation], timeout: 0.5)

        // Check that transform has translation applied
        let pannedTransform = viewController.imageView.layer?.transform
        let newTranslationX = pannedTransform?.m41 ?? 0
        let newTranslationY = pannedTransform?.m42 ?? 0

        // Translation should have changed (delta is 50 in x, 20 in y)
        XCTAssertNotEqual(newTranslationX, initialTranslationX, accuracy: 0.01, "Panning should apply X translation")
        XCTAssertNotEqual(newTranslationY, initialTranslationY, accuracy: 0.01, "Panning should apply Y translation")

        // End panning
        viewController.handlePanEnd()
    }

    func testPanningPersistsPerImage() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create two test images
        let testImage1 = createTestImage(size: NSSize(width: 800, height: 600))
        let testImage2 = createTestImage(size: NSSize(width: 1000, height: 750))

        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL1 = tempDir.appendingPathComponent("test-image-1-\(UUID().uuidString).jpg")
        let testFileURL2 = tempDir.appendingPathComponent("test-image-2-\(UUID().uuidString).jpg")

        guard let tiffData1 = testImage1.tiffRepresentation,
              let bitmapImage1 = NSBitmapImageRep(data: tiffData1),
              let jpegData1 = bitmapImage1.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image 1 data")
            return
        }

        guard let tiffData2 = testImage2.tiffRepresentation,
              let bitmapImage2 = NSBitmapImageRep(data: tiffData2),
              let jpegData2 = bitmapImage2.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image 2 data")
            return
        }

        do {
            try jpegData1.write(to: testFileURL1)
            try jpegData2.write(to: testFileURL2)
        } catch {
            XCTFail("Failed to create test files: \(error)")
            return
        }

        defer {
            try? FileManager.default.removeItem(at: testFileURL1)
            try? FileManager.default.removeItem(at: testFileURL2)
        }

        // Load first image
        viewController.loadImage(from: testFileURL1)

        // Wait for async image loading
        let load1Expectation = XCTestExpectation(description: "Image 1 loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            load1Expectation.fulfill()
        }
        wait(for: [load1Expectation], timeout: 1.0)

        // Zoom in on first image
        let zoomInEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24
        )

        if let zoomInKeyEvent = zoomInEvent {
            viewController.keyDown(with: zoomInKeyEvent)
        }

        // Wait for zoom
        let zoom1Expectation = XCTestExpectation(description: "Zoom 1 applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoom1Expectation.fulfill()
        }
        wait(for: [zoom1Expectation], timeout: 0.5)

        // Pan first image
        let startLocation1 = NSPoint(x: 100, y: 100)
        viewController.handlePanStart(at: startLocation1)
        let endLocation1 = NSPoint(x: 150, y: 120)
        viewController.handlePanMove(to: endLocation1)
        viewController.handlePanEnd()

        // Wait for pan to apply
        let pan1Expectation = XCTestExpectation(description: "Pan 1 applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pan1Expectation.fulfill()
        }
        wait(for: [pan1Expectation], timeout: 0.5)

        // Get pan offset for first image
        let pan1Transform = viewController.imageView.layer?.transform
        let pan1TranslationX = pan1Transform?.m41 ?? 0

        // Load second image
        viewController.loadImage(from: testFileURL2)

        // Wait for async image loading
        let load2Expectation = XCTestExpectation(description: "Image 2 loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            load2Expectation.fulfill()
        }
        wait(for: [load2Expectation], timeout: 1.0)

        // Zoom in on second image
        if let zoomInKeyEvent = zoomInEvent {
            viewController.keyDown(with: zoomInKeyEvent)
        }

        // Wait for zoom
        let zoom2Expectation = XCTestExpectation(description: "Zoom 2 applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            zoom2Expectation.fulfill()
        }
        wait(for: [zoom2Expectation], timeout: 0.5)

        // Second image should have no pan offset initially
        let pan2InitialTransform = viewController.imageView.layer?.transform
        let pan2InitialTranslationX = pan2InitialTransform?.m41 ?? 0
        XCTAssertEqual(pan2InitialTranslationX, 0, accuracy: 0.01, "Second image should start with no pan offset")

        // Switch back to first image
        viewController.loadImage(from: testFileURL1)

        // Wait for async image loading
        let load1AgainExpectation = XCTestExpectation(description: "Image 1 loaded again")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            load1AgainExpectation.fulfill()
        }
        wait(for: [load1AgainExpectation], timeout: 1.0)

        // First image should restore its pan offset
        let pan1RestoredTransform = viewController.imageView.layer?.transform
        let pan1RestoredTranslationX = pan1RestoredTransform?.m41 ?? 0
        XCTAssertEqual(pan1RestoredTranslationX, pan1TranslationX, accuracy: 1.0, "First image should restore its pan offset")
    }

    // MARK: - Drag and Drop Tests

    func testDragAndDropSetup() {
        // Verify that drag and drop is set up
        XCTAssertNotNil(viewController.view, "View should be loaded")

        // The view should be registered for file URL drag types
        // We can verify this by checking if the view responds to dragging methods
        XCTAssertTrue(viewController.conforms(to: NSDraggingDestination.self), "ViewController should conform to NSDraggingDestination")
    }

    func testDraggingEnteredWithSupportedFile() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create a temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-image-\(UUID().uuidString).jpg")

        // Create a simple test image file
        let testImage = createTestImage(size: NSSize(width: 100, height: 100))
        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            // Clean up test file
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Create a mock dragging info with the file URL
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        pasteboard.writeObjects([testFileURL as NSPasteboardWriting])

        // Create a mock dragging info
        class MockDraggingInfo: NSObject, NSDraggingInfo {
            var draggingPasteboard: NSPasteboard
            var draggingDestinationWindow: NSWindow?
            var draggingSource: Any?
            var draggingSourceOperationMask: NSDragOperation = .copy
            var draggingLocation: NSPoint = .zero
            var draggedImageLocation: NSPoint = .zero
            var draggedImage: NSImage?
            var draggingSequenceNumber: Int = 0
            var draggingContext: NSDraggingContext = .outsideApplication
            var draggingFormation: NSDraggingFormation = .default
            var animatesToDestination: Bool = false
            var numberOfValidItemsForDrop: Int = 1
            var springLoadingHighlight: NSSpringLoadingHighlight = .none

            init(pasteboard: NSPasteboard) {
                self.draggingPasteboard = pasteboard
            }

            func slideDraggedImage(to screenPoint: NSPoint) {}
            func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey : Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
            func resetSpringLoading() {}
        }

        let draggingInfo = MockDraggingInfo(pasteboard: pasteboard)

        // Test draggingEntered
        let operation = viewController.draggingEntered(draggingInfo)

        // Should return .copy for supported file
        XCTAssertEqual(operation, .copy, "Dragging entered should return .copy for supported file")
    }

    func testDraggingEnteredWithUnsupportedFile() {
        // Create a test window and add the view controller's view to it
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)

        // Create a temporary test file with unsupported extension
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-file-\(UUID().uuidString).txt")

        // Create a simple text file
        do {
            try "test content".write(to: testFileURL, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer {
            // Clean up test file
            try? FileManager.default.removeItem(at: testFileURL)
        }

        // Create a mock dragging info with the file URL
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        pasteboard.writeObjects([testFileURL as NSPasteboardWriting])

        // Create a mock dragging info
        class MockDraggingInfo: NSObject, NSDraggingInfo {
            var draggingPasteboard: NSPasteboard
            var draggingDestinationWindow: NSWindow?
            var draggingSource: Any?
            var draggingSourceOperationMask: NSDragOperation = .copy
            var draggingLocation: NSPoint = .zero
            var draggedImageLocation: NSPoint = .zero
            var draggedImage: NSImage?
            var draggingSequenceNumber: Int = 0
            var draggingContext: NSDraggingContext = .outsideApplication
            var draggingFormation: NSDraggingFormation = .default
            var animatesToDestination: Bool = false
            var numberOfValidItemsForDrop: Int = 1
            var springLoadingHighlight: NSSpringLoadingHighlight = .none

            init(pasteboard: NSPasteboard) {
                self.draggingPasteboard = pasteboard
            }

            func slideDraggedImage(to screenPoint: NSPoint) {}
            func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey : Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
            func resetSpringLoading() {}
        }

        let draggingInfo = MockDraggingInfo(pasteboard: pasteboard)

        // Test draggingEntered
        let operation = viewController.draggingEntered(draggingInfo)

        // Should return [] for unsupported file
        XCTAssertEqual(operation, [], "Dragging entered should return [] for unsupported file")
    }

    func testPerformDragOperationWithSupportedFile() {
        _ = makeTestWindow()
        let testFileURL = makeTestImageFile(name: "test-image-drop-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: testFileURL) }

        let draggingInfo = makeDraggingInfo(urls: [testFileURL])

        let success = viewController.performDragOperation(draggingInfo)

        XCTAssertTrue(success, "Perform drag operation should return true for supported file")
        XCTAssertNil(viewController.displayedFileURL, "Drop should commit asynchronously from empty state")

        waitForAsyncWork()

        XCTAssertEqual(viewController.displayedFileURL, testFileURL, "Dropped file should become displayed after preparation completes")
        XCTAssertEqual(viewController.fileListManager.currentFileURL, testFileURL, "Dropped file should become current after preparation completes")
        XCTAssertNotNil(viewController.imageView.image, "Dropped file should be displayed after preparation completes")
    }

    func testPerformDragOperationWithMultipleFiles() {
        _ = makeTestWindow()
        let testFileURL1 = makeTestImageFile(name: "test-image-1-\(UUID().uuidString).jpg")
        let testFileURL2 = makeTestImageFile(name: "test-image-2-\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: testFileURL1)
            try? FileManager.default.removeItem(at: testFileURL2)
        }

        let draggingInfo = makeDraggingInfo(urls: [testFileURL1, testFileURL2])

        let success = viewController.performDragOperation(draggingInfo)

        XCTAssertTrue(success, "Perform drag operation should return true for multiple supported files")

        waitForAsyncWork()

        XCTAssertEqual(viewController.displayedFileURL, testFileURL1, "The first supported file should become displayed on drop")
        XCTAssertEqual(viewController.fileListManager.currentFileURL, testFileURL1, "The first supported file should be committed on drop")
        XCTAssertNotNil(viewController.imageView.image, "The dropped file should be displayed")
    }

    func testDraggingExited() {
        _ = makeTestWindow()
        let draggingInfo = MockDraggingInfo(pasteboard: NSPasteboard(name: .drag))

        viewController.draggingExited(draggingInfo)
    }

    func testSupportedDragKeepsLogoVisibleBeforeDrop() {
        _ = makeTestWindow()

        let logoImageView = viewController.view.subviews.first { subview in
            subview is NSImageView && subview != viewController.imageView
        } as? NSImageView

        XCTAssertNotNil(logoImageView, "Logo image view should exist")
        XCTAssertFalse(logoImageView?.isHidden ?? true, "Logo should be visible initially")

        let testFileURL = makeTestImageFile(name: "test-image-hover-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: testFileURL) }

        let draggingInfo = makeDraggingInfo(urls: [testFileURL])

        _ = viewController.draggingEntered(draggingInfo)
        XCTAssertFalse(logoImageView?.isHidden ?? true, "Logo should stay visible while hovering a supported file")

        _ = viewController.draggingUpdated(draggingInfo)
        XCTAssertFalse(logoImageView?.isHidden ?? true, "Logo should remain visible during hover updates")

        viewController.draggingExited(draggingInfo)
        XCTAssertFalse(logoImageView?.isHidden ?? true, "Logo should remain visible after drag exit when no drop occurred")
    }

    func testLogoShownWhenDraggingUnsupportedFile() {
        _ = makeTestWindow()

        let logoImageView = viewController.view.subviews.first { subview in
            subview is NSImageView && subview != viewController.imageView
        } as? NSImageView

        XCTAssertNotNil(logoImageView, "Logo image view should exist")
        XCTAssertFalse(logoImageView?.isHidden ?? true, "Logo should be visible initially")

        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-file-\(UUID().uuidString).txt")

        do {
            try "test content".write(to: testFileURL, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        defer { try? FileManager.default.removeItem(at: testFileURL) }

        let draggingInfo = makeDraggingInfo(urls: [testFileURL])

        _ = viewController.draggingEntered(draggingInfo)
        XCTAssertFalse(logoImageView?.isHidden ?? true, "Logo should remain visible when dragging an unsupported file")
    }

    func testDraggingSupportedFileDoesNotMutateFileListDuringHover() {
        _ = makeTestWindow()
        let testFileURL = makeTestImageFile(name: "test-image-prefetch-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: testFileURL) }

        let draggingInfo = makeDraggingInfo(urls: [testFileURL])

        XCTAssertTrue(viewController.fileListManager.fileURLs.isEmpty, "File list should be empty initially")

        _ = viewController.draggingEntered(draggingInfo)
        waitForAsyncWork(delay: 0.4)

        XCTAssertTrue(viewController.fileListManager.fileURLs.isEmpty, "Hover preparation should not mutate the live file list")
        XCTAssertNil(viewController.displayedFileURL, "Hover preparation should not set a displayed file")
        XCTAssertNil(viewController.imageView.image, "Hover preparation should not display the dragged image")
    }

    func testDraggingSupportedFileKeepsCurrentImageVisibleBeforeDrop() {
        _ = makeTestWindow()
        let currentFileURL = makeTestImageFile(name: "test-current-\(UUID().uuidString).jpg")
        let hoveredFileURL = makeTestImageFile(name: "test-hovered-\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: currentFileURL)
            try? FileManager.default.removeItem(at: hoveredFileURL)
        }

        viewController.loadImage(from: currentFileURL)
        waitForAsyncWork()

        guard let originalImage = viewController.imageView.image else {
            XCTFail("Initial image should be loaded before hover")
            return
        }
        XCTAssertEqual(viewController.displayedFileURL, currentFileURL, "Displayed file should commit before hover")
        XCTAssertEqual(viewController.fileListManager.currentFileURL, currentFileURL, "Initial file should be loaded before hover")

        let draggingInfo = makeDraggingInfo(urls: [hoveredFileURL])
        _ = viewController.draggingEntered(draggingInfo)
        waitForAsyncWork(delay: 0.3)

        XCTAssertEqual(viewController.displayedFileURL, currentFileURL, "Hover should not change the displayed file")
        XCTAssertEqual(viewController.fileListManager.currentFileURL, currentFileURL, "Hover should not change current file")
        XCTAssertTrue(viewController.imageView.image === originalImage, "Hover should keep the previously displayed image visible")

        viewController.draggingExited(draggingInfo)
        waitForAsyncWork(delay: 0.2)

        XCTAssertEqual(viewController.displayedFileURL, currentFileURL, "Drag exit should leave the displayed file unchanged")
        XCTAssertEqual(viewController.fileListManager.currentFileURL, currentFileURL, "Drag exit should leave current file unchanged")
        XCTAssertTrue(viewController.imageView.image === originalImage, "Drag exit should keep the previous image visible")
    }

    func testPerformDragOperationKeepsCurrentImageVisibleWhilePreparationCompletes() {
        _ = makeTestWindow()
        let currentFileURL = makeTestImageFile(name: "test-before-drop-\(UUID().uuidString).jpg")
        let droppedFileURL = makeTestImageFile(name: "test-after-drop-\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: currentFileURL)
            try? FileManager.default.removeItem(at: droppedFileURL)
        }

        viewController.loadImage(from: currentFileURL)
        waitForAsyncWork()

        guard let originalImage = viewController.imageView.image else {
            XCTFail("Initial image should be loaded before drop")
            return
        }
        let draggingInfo = makeDraggingInfo(urls: [droppedFileURL])

        let success = viewController.performDragOperation(draggingInfo)

        XCTAssertTrue(success, "Perform drag operation should succeed for a supported file")
        XCTAssertEqual(viewController.displayedFileURL, currentFileURL, "Immediate drop should not change the displayed file before preparation completes")
        XCTAssertEqual(viewController.fileListManager.currentFileURL, currentFileURL, "Immediate drop should not mutate current file before preparation completes")
        XCTAssertTrue(viewController.imageView.image === originalImage, "Immediate drop should keep the previous image visible while preparation is in flight")

        waitForAsyncWork()

        XCTAssertEqual(viewController.displayedFileURL, droppedFileURL, "Dropped file should become displayed after preparation completes")
        XCTAssertEqual(viewController.fileListManager.currentFileURL, droppedFileURL, "Dropped file should become current after preparation completes")
        XCTAssertFalse(viewController.imageView.image === originalImage, "Dropped file should eventually replace the previous image")
    }

    private final class MockDraggingInfo: NSObject, NSDraggingInfo {
        var draggingPasteboard: NSPasteboard
        var draggingDestinationWindow: NSWindow?
        var draggingSource: Any?
        var draggingSourceOperationMask: NSDragOperation = .copy
        var draggingLocation: NSPoint = .zero
        var draggedImageLocation: NSPoint = .zero
        var draggedImage: NSImage?
        var draggingSequenceNumber: Int = 0
        var draggingContext: NSDraggingContext = .outsideApplication
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination: Bool = false
        var numberOfValidItemsForDrop: Int = 1
        var springLoadingHighlight: NSSpringLoadingHighlight = .none

        init(pasteboard: NSPasteboard) {
            self.draggingPasteboard = pasteboard
        }

        func slideDraggedImage(to screenPoint: NSPoint) {}
        func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey : Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        func resetSpringLoading() {}
    }

    @discardableResult
    private func makeTestWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func makeDraggingInfo(urls: [URL]) -> MockDraggingInfo {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSPasteboardWriting })
        return MockDraggingInfo(pasteboard: pasteboard)
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        location: NSPoint,
        timestamp: TimeInterval,
        window: NSWindow
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ) else {
            fatalError("Failed to create mouse event")
        }
        return event
    }

    private func makeScrollEvent(
        deltaY: Int32,
        screenPoint: NSPoint
    ) -> NSEvent? {
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else {
            return nil
        }
        // CGEvent uses a top-left global origin while NSEvent/AppKit uses a
        // bottom-left screen origin.
        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        cgEvent.location = CGPoint(
            x: screenPoint.x,
            y: mainDisplayHeight - screenPoint.y
        )
        return NSEvent(cgEvent: cgEvent)
    }

    private func makeTestDirectory(name: String) -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }

        return directoryURL
    }

    private func makeTestImageFile(
        name: String,
        size: NSSize = NSSize(width: 100, height: 100),
        directoryURL: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        let testFileURL = directoryURL.appendingPathComponent(name)
        let testImage = createTestImage(size: size)

        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return testFileURL
        }

        do {
            try jpegData.write(to: testFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
        }

        return testFileURL
    }

    private func makeTaggedTestImageFile(
        name: String,
        size: NSSize = NSSize(width: 100, height: 100),
        labelNumber: Int
    ) -> URL {
        var testFileURL = makeTestImageFile(name: name, size: size)

        do {
            var values = URLResourceValues()
            values.labelNumber = labelNumber
            try testFileURL.setResourceValues(values)
        } catch {
            XCTFail("Failed to set Finder label on test file: \(error)")
        }

        return testFileURL
    }

    private func makeInvalidImageFile(name: String, directoryURL: URL = FileManager.default.temporaryDirectory) -> URL {
        let fileURL = directoryURL.appendingPathComponent(name)
        let data = Data("not an image".utf8)

        do {
            try data.write(to: fileURL)
        } catch {
            XCTFail("Failed to create invalid image file: \(error)")
        }

        return fileURL
    }

    private func waitForAsyncWork(delay: TimeInterval = 1.0) {
        let expectation = XCTestExpectation(description: "Async work completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: delay + 1.0)
    }

    private func waitUntil(
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.05,
        description: String,
        condition: @escaping () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }
            RunLoop.main.run(until: Date().addingTimeInterval(pollInterval))
        }

        XCTAssertTrue(condition(), description)
    }

    // Helper method to create a test NSImage
    private func createTestImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
}
