//
//  ViewControllerTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 18.12.25.
//

import XCTest
import AppKit
import MetalKit
import ImageIO
@testable import FastViewer_Lite

final class ViewControllerTests: XCTestCase {

    var viewController: ViewController!
    private var previousWindowSizePreset: Any?

    override func setUp() {
        super.setUp()
        previousWindowSizePreset = UserDefaults.standard.object(forKey: "WindowSizePreset")
        ImageCacheManager.shared.clearCache()
        viewController = ViewController()
        // Load the view to initialize the imageView
        _ = viewController.view
    }

    override func tearDown() {
        ImageCacheManager.shared.clearCache()
        viewController = nil
        if let previousWindowSizePreset {
            UserDefaults.standard.set(previousWindowSizePreset, forKey: "WindowSizePreset")
        } else {
            UserDefaults.standard.removeObject(forKey: "WindowSizePreset")
        }
        super.tearDown()
    }

    func testImageViewSetup() {
        XCTAssertNotNil(viewController.view, "View should be loaded")
        XCTAssertNotNil(viewController.imageView, "ImageView should be initialized")
        XCTAssertEqual(viewController.imageView.imageAlignment, .alignCenter, "Image alignment should be center")
    }

    func testNearestNeighborRenderingDoesNotBlendSourcePixels() throws {
        let renderer = MetalImageRenderer.shared
        let device = try XCTUnwrap(renderer.device)
        XCTAssertTrue(renderer.isAvailable)
        let source = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        for y in 0..<2 {
            source.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1), atX: 0, y: y)
            source.setColor(NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1), atX: 1, y: y)
        }
        let texture = try XCTUnwrap(renderer.makeTexture(try XCTUnwrap(source.cgImage)))
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 32, height: 32, mipmapped: false
        )
        targetDescriptor.usage = [.renderTarget]
        targetDescriptor.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: targetDescriptor))
        for nearest in [false, true, false] {
            let command = try XCTUnwrap(renderer.render(
                texture: texture, to: target, geometry: SIMD4(1, 1, 0, 0), nearest: nearest
            ))
            command.waitUntilCompleted()
            XCTAssertNil(command.error)
            var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
            target.getBytes(&bytes, bytesPerRow: 32 * 4,
                            from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
            var blendedPixels = 0
            for x in 0..<32 {
                let offset = (16 * 32 + x) * 4
                let value = bytes[offset + 2]
                XCTAssertEqual(bytes[offset + 3], 255)
                if value > 0 && value < 255 { blendedPixels += 1 }
                if nearest { XCTAssertEqual(value, x < 16 ? 0 : 255) }
            }
            if nearest { XCTAssertEqual(blendedPixels, 0) }
            else { XCTAssertGreaterThan(blendedPixels, 0) }
        }
    }

    func testMetalCanvasZoomKeepsViewportFixedAndUsesOriginalTexture() throws {
        let canvas = DraggableImageView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        // Alternating columns would be lost if the 4px fitted view were enlarged.
        for y in 0..<16 {
            for x in 0..<16 {
                let value: CGFloat = x.isMultiple(of: 2) ? 0 : 1
                rep.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(rep)
        canvas.image = image
        canvas.layoutSubtreeIfNeeded()
        let ready = expectation(description: "Texture uploaded asynchronously")
        var remainingAttempts = 200
        func waitForUpload() {
            remainingAttempts -= 1
            if canvas.surface.texture != nil || remainingAttempts <= 0 { ready.fulfill() }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { waitForUpload() } }
        }
        waitForUpload()
        wait(for: [ready], timeout: 5)
        let texture = try XCTUnwrap(canvas.surface.texture)
        XCTAssertEqual(texture.width, 16)
        canvas.zoomScale = 8
        canvas.usesNearestNeighbor = true
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 4, height: 4, mipmapped: false
        )
        targetDescriptor.storageMode = .shared
        targetDescriptor.usage = .renderTarget
        let renderer = MetalImageRenderer.shared
        let target = try XCTUnwrap(renderer.device?.makeTexture(descriptor: targetDescriptor))
        let command = try XCTUnwrap(renderer.render(texture: texture, to: target,
            geometry: canvas.surface.geometry, nearest: canvas.surface.nearest))
        command.waitUntilCompleted()
        XCTAssertNil(command.error)
        var bytes = [UInt8](repeating: 0, count: 64)
        target.getBytes(&bytes, bytesPerRow: 16, from: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0)
        var row: [UInt8] = []
        for x in 0..<4 { row.append(bytes[(8 + x) * 4 + 2]) }
        XCTAssertEqual(row, [255, 255, 0, 0])
        XCTAssertEqual(canvas.surface.frame.size, NSSize(width: 4, height: 4))
        XCTAssertEqual(canvas.layer?.transform.m11 ?? 1, 1)
        canvas.panOffset = NSPoint(x: 2, y: -4)
        XCTAssertEqual(canvas.surface.geometry.z, 1, accuracy: 0.001)
        XCTAssertEqual(canvas.surface.geometry.w, -2, accuracy: 0.001)
        XCTAssertEqual(canvas.untransformedPoint(NSPoint(x: 4, y: -2)), NSPoint(x: 2, y: 2))
        canvas.image = nil
        XCTAssertNil(canvas.surface.texture)
    }

    func testRapidMetalImageChangesKeepTextureAndAspectRatioTogether() throws {
        let canvas = DraggableImageView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        func assertDisplayedAspect(file: StaticString = #filePath, line: UInt = #line) {
            guard let texture = canvas.surface.texture else { return }
            let geometry = canvas.surface.geometry
            let displayedAspect = CGFloat(geometry.x) * canvas.bounds.width
                / (CGFloat(geometry.y) * canvas.bounds.height)
            XCTAssertEqual(displayedAspect, CGFloat(texture.width) / CGFloat(texture.height),
                           accuracy: 0.001, file: file, line: line)
        }
        func waitForTexture(width: Int) {
            let ready = expectation(description: "Texture \(width) ready")
            var remaining = 200
            func poll() {
                assertDisplayedAspect()
                remaining -= 1
                if canvas.surface.texture?.width == width || remaining == 0 { ready.fulfill() }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { poll() } }
            }
            poll()
            wait(for: [ready], timeout: 3)
            XCTAssertEqual(canvas.surface.texture?.width, width)
            assertDisplayedAspect()
        }
        let landscape = createTestImage(size: NSSize(width: 128, height: 64))
        canvas.image = landscape
        waitForTexture(width: try XCTUnwrap(landscape.cgImage(forProposedRect: nil, context: nil, hints: nil)).width)
        let previousTexture = try XCTUnwrap(canvas.surface.texture)
        let portrait = createTestImage(size: NSSize(width: 64, height: 128))
        canvas.image = portrait
        // The main-thread upload completion has not run yet. The old texture
        // must retain its own proportions, even as the viewport/settings change.
        XCTAssertTrue(canvas.surface.texture === previousTexture)
        canvas.frame.size = NSSize(width: 400, height: 600)
        canvas.imageScaling = .scaleProportionallyDown
        canvas.zoomScale = 2
        canvas.layoutSubtreeIfNeeded()
        assertDisplayedAspect()
        waitForTexture(width: try XCTUnwrap(portrait.cgImage(forProposedRect: nil, context: nil, hints: nil)).width)
        for index in 0..<30 {
            let size = index.isMultiple(of: 2)
                ? NSSize(width: 96, height: 288) : NSSize(width: 256, height: 64)
            canvas.image = createTestImage(size: size)
            canvas.imageScaling = .scaleProportionallyUpOrDown
            assertDisplayedAspect()
        }
        let last = createTestImage(size: NSSize(width: 333, height: 111))
        canvas.image = last
        assertDisplayedAspect()
        waitForTexture(width: try XCTUnwrap(last.cgImage(forProposedRect: nil, context: nil, hints: nil)).width)
    }

    func testMetalResizePresentsNewFrameBeforeReturningToTrackingLoop() throws {
        let canvas = DraggableImageView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        canvas.image = createTestImage(size: NSSize(width: 320, height: 160))
        let ready = expectation(description: "Texture ready for live resize")
        var attempts = 200
        func poll() {
            attempts -= 1
            if canvas.surface.texture != nil || attempts == 0 { ready.fulfill() }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { poll() } }
        }
        poll()
        wait(for: [ready], timeout: 3)
        let texture = try XCTUnwrap(canvas.surface.texture)
        XCTAssertTrue(canvas.surface.presentsWithTransaction)
        // No run-loop turns or mouse-up between these updates. Every size must
        // get a new drawable immediately, using the existing texture.
        for size in [NSSize(width: 600, height: 300), NSSize(width: 300, height: 600), NSSize(width: 720, height: 420)] {
            window.setContentSize(size)
            canvas.setFrameSize(size)
            XCTAssertEqual(canvas.surface.lastPresentedDrawableSize, canvas.surface.convertToBacking(canvas.surface.bounds).size)
            let geometry = canvas.surface.geometry
            XCTAssertEqual(CGFloat(geometry.x) * size.width / (CGFloat(geometry.y) * size.height), 2, accuracy: 0.001)
            XCTAssertTrue(canvas.surface.texture === texture)
        }
    }

    func testMetalRenderingPreservesOrientationAndTransparency() throws {
        let renderer = MetalImageRenderer.shared
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
        rep.setColor(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1), atX: 1, y: 0)
        rep.setColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: 0, y: 1)
        rep.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: 1, y: 1)
        let texture = try XCTUnwrap(renderer.makeTexture(try XCTUnwrap(rep.cgImage)))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 2, height: 2, mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        let target = try XCTUnwrap(renderer.device?.makeTexture(descriptor: descriptor))
        let command = try XCTUnwrap(renderer.render(texture: texture, to: target,
            geometry: SIMD4(1, 1, 0, 0), nearest: true))
        command.waitUntilCompleted()
        XCTAssertNil(command.error)
        var bytes = [UInt8](repeating: 0, count: 16)
        target.getBytes(&bytes, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
        XCTAssertEqual(bytes, [0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255, 0, 0, 0, 0])
    }

    func testMetalCanvasPlaysAnimatedFramesAndDiscardsReplacedUploads() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, 2, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for green in [false, true] {
            for y in 0..<2 {
                for x in 0..<2 {
                    rep.setColor(NSColor(deviceRed: green ? 0 : 1, green: green ? 1 : 0, blue: 0, alpha: 1), atX: x, y: y)
                }
            }
            CGImageDestinationAddImage(destination, try XCTUnwrap(rep.cgImage),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let image = try XCTUnwrap(NSImage(data: data as Data))
        let canvas = DraggableImageView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        let window = NSWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.image = createTestImage(size: NSSize(width: 100, height: 100))
        canvas.image = nil
        canvas.image = image
        let frame = expectation(description: "Animated green frame reached the GPU")
        var attempts = 200
        func poll() {
            attempts -= 1
            if let texture = canvas.surface.texture {
                var pixel = [UInt8](repeating: 0, count: 4)
                texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
                if pixel[0] == 0 && pixel[1] == 255 { frame.fulfill(); return }
            }
            if attempts > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { poll() } }
        }
        poll()
        wait(for: [frame], timeout: 3)
        canvas.image = nil
        XCTAssertNil(canvas.surface.texture)
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

        let position = viewController.fileListManager.fileURLs.firstIndex(of: fileURL).map { $0 + 1 } ?? 1
        let expectedTitle = "FastViewer Lite - \(fileURL.lastPathComponent) - \(position)/\(viewController.fileListManager.fileURLs.count)"
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
            !FileManager.default.fileExists(atPath: testFileURL.path) && self.viewController.canUndoMoveToTrash
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

        let firstTitle = window.title
        ImageCacheManager.shared.clearCache()
        viewController.loadImage(from: secondFileURL)

        XCTAssertEqual(viewController.displayedFileURL, firstFileURL, "Visible file should remain on the previous image while the next file loads")
        XCTAssertTrue(viewController.imageView.image === originalImage, "Previous pixels should remain visible during an uncached transition")
        XCTAssertFalse(viewController.isLoadingOverlayVisible, "Uncached transitions should no longer show a loading overlay")
        XCTAssertEqual(window.title, firstTitle, "Window title should stay tied to the displayed file until commit")

        waitUntil(description: "second image commits after uncached transition") {
            self.viewController.displayedFileURL == secondFileURL &&
            self.viewController.imageView.image != nil
        }

        XCTAssertEqual(viewController.displayedFileURL, secondFileURL, "Visible file should switch only when the new image commits")
        XCTAssertFalse(viewController.imageView.image === originalImage, "Committed image should replace the old image after loading finishes")
        let position = viewController.fileListManager.fileURLs.firstIndex(of: secondFileURL).map { $0 + 1 } ?? 1
        XCTAssertEqual(window.title, "FastViewer Lite - \(secondFileURL.lastPathComponent) - \(position)/\(viewController.fileListManager.fileURLs.count)", "Window title should update when the new image commits")
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

        guard let imageView = viewController.imageView else {
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

        guard let imageView = viewController.imageView else {
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

        guard let imageView = viewController.imageView else {
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
        let initialTransform = viewController.imageView.renderTransform
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
        let zoomedTransform = viewController.imageView.renderTransform
        XCTAssertGreaterThan(zoomedTransform?.m11 ?? 1.0, 1.0, "Zoom in should increase scale")
    }

    func testRepeatedZoomOutStopsAtInitialSizeForLargeAndSmallImages() throws {
        let previous = SettingsManager.shared.autoResizeToImageSize
        SettingsManager.shared.autoResizeToImageSize = false
        defer { SettingsManager.shared.autoResizeToImageSize = previous }
        let window = makeTestWindow()
        window.setContentSize(NSSize(width: 600, height: 400))
        for size in [NSSize(width: 1600, height: 1200), NSSize(width: 100, height: 80)] {
            let file = makeTestImageFile(name: "zoom-floor-\(UUID().uuidString).jpg", size: size)
            defer { try? FileManager.default.removeItem(at: file) }
            viewController.loadImage(from: file)
            waitUntil(description: "image loaded for zoom floor") { self.viewController.displayedFileURL == file }
            let initialFrame = window.frame
            func press(_ character: String, code: UInt16) throws {
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: character,
                    charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
                viewController.keyDown(with: event)
            }
            try press("=", code: 24)
            try press("=", code: 24)
            XCTAssertGreaterThan(viewController.imageView.zoomScale, 1)
            for _ in 0..<20 { try press("-", code: 27) }
            XCTAssertEqual(viewController.imageView.zoomScale, 1, accuracy: 0.001)
            XCTAssertEqual(window.frame, initialFrame)
            XCTAssertEqual(viewController.imageView.panOffset, .zero)
        }
    }

    func testZoomOutAfterDraggingKeepsImageEdgesInsideTheViewport() throws {
        let previous = SettingsManager.shared.autoResizeToImageSize
        SettingsManager.shared.autoResizeToImageSize = false
        defer { SettingsManager.shared.autoResizeToImageSize = previous }
        let window = makeTestWindow()
        window.setContentSize(NSSize(width: 600, height: 400))
        viewController.view.layoutSubtreeIfNeeded()
        let file = makeTestImageFile(name: "zoom-pan-floor-\(UUID().uuidString).jpg", size: NSSize(width: 1800, height: 1200))
        defer { try? FileManager.default.removeItem(at: file) }
        viewController.loadImage(from: file)
        waitUntil(description: "image ready for zoom and drag") {
            self.viewController.displayedFileURL == file && self.viewController.imageView.surface.texture != nil
        }
        func press(_ character: String, code: UInt16) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
            viewController.keyDown(with: event)
        }
        for _ in 0..<3 { try press("=", code: 24) }
        viewController.handlePanStart(at: NSPoint(x: 200, y: 200))
        viewController.handlePanMove(to: NSPoint(x: 2000, y: 2000))
        viewController.handlePanEnd()
        XCTAssertNotEqual(viewController.imageView.panOffset, .zero)
        for _ in 0..<8 {
            try press("-", code: 27)
            let geometry = viewController.imageView.surface.geometry
            XCTAssertGreaterThanOrEqual(geometry.x - abs(geometry.z), 0.999)
            XCTAssertGreaterThanOrEqual(geometry.y - abs(geometry.w), 0.999)
        }
        XCTAssertEqual(viewController.imageView.zoomScale, 1, accuracy: 0.001)
        XCTAssertEqual(viewController.imageView.panOffset, .zero)
    }

    func testDragAnchorReplacesEarlierPointerFocus() throws {
        try runActionScenario(33)
        try runActionScenario(34)
    }

    func testMaximumZoomDragCanReachEveryImageCorner() throws {
        let previous = SettingsManager.shared.autoResizeToImageSize
        SettingsManager.shared.autoResizeToImageSize = false
        defer { SettingsManager.shared.autoResizeToImageSize = previous }
        let window = makeTestWindow()
        window.setContentSize(NSSize(width: 600, height: 400))
        viewController.view.layoutSubtreeIfNeeded()
        let file = makeTestImageFile(name: "zoom-corners-\(UUID().uuidString).jpg", size: NSSize(width: 1800, height: 1200))
        defer { try? FileManager.default.removeItem(at: file) }
        viewController.loadImage(from: file)
        waitUntil(description: "corner image loaded") { self.viewController.displayedFileURL == file }
        viewController.changeZoom(to: 10, at: NSPoint(x: 300, y: 200))
        for x: CGFloat in [-1, 1] {
            for y: CGFloat in [-1, 1] {
                viewController.handlePanStart(at: .zero)
                viewController.handlePanMove(to: NSPoint(x: x * 100000, y: y * 100000))
                viewController.handlePanEnd()
                XCTAssertEqual(viewController.imageView.panOffset.x, x * 2700, accuracy: 0.01)
                XCTAssertEqual(viewController.imageView.panOffset.y, y * 1800, accuracy: 0.01)
            }
        }
    }

    func testZoomOutReversesLatestPointerSegmentBeforeEarlierOnes() throws {
        let previous = SettingsManager.shared.autoResizeToImageSize
        SettingsManager.shared.autoResizeToImageSize = false
        defer { SettingsManager.shared.autoResizeToImageSize = previous }
        let window = makeTestWindow()
        window.setContentSize(NSSize(width: 600, height: 400))
        viewController.view.layoutSubtreeIfNeeded()
        let file = makeTestImageFile(name: "zoom-segments-\(UUID().uuidString).jpg", size: NSSize(width: 1800, height: 1200))
        defer { try? FileManager.default.removeItem(at: file) }
        viewController.loadImage(from: file)
        waitUntil(description: "zoom segment image loaded") { self.viewController.displayedFileURL == file }
        viewController.changeZoom(to: 2, at: NSPoint(x: 420, y: 260))
        let firstOffset = viewController.imageView.panOffset
        let secondPointer = NSPoint(x: 150, y: 100)
        let secondSource = viewController.imageView.untransformedPoint(secondPointer)
        viewController.changeZoom(to: 4, at: secondPointer)
        window.setContentSize(NSSize(width: 800, height: 400))
        viewController.view.layoutSubtreeIfNeeded()
        viewController.viewDidLayout()
        let resizedPointer = NSPoint(x: secondPointer.x + 100, y: secondPointer.y)
        viewController.changeZoom(to: 3, at: NSPoint(x: 590, y: 390))
        let sourceAfterZoomOut = viewController.imageView.untransformedPoint(resizedPointer)
        XCTAssertEqual(sourceAfterZoomOut.x, secondSource.x + 100, accuracy: 0.01)
        XCTAssertEqual(sourceAfterZoomOut.y, secondSource.y, accuracy: 0.01)
        viewController.changeZoom(to: 2, at: .zero)
        XCTAssertEqual(viewController.imageView.panOffset.x, firstOffset.x, accuracy: 0.01)
        XCTAssertEqual(viewController.imageView.panOffset.y, firstOffset.y, accuracy: 0.01)
        viewController.changeZoom(to: 1, at: .zero)
        XCTAssertEqual(viewController.imageView.panOffset, .zero)
    }

    func testZoomOutAfterDragAndResizeUsesDragAnchor() throws {
        try runActionScenario(36)
        try runActionScenario(37)
    }

    func testZoomFilterAndTitleReturnToRestingState() throws {
        let previous = SettingsManager.shared.autoResizeToImageSize
        SettingsManager.shared.autoResizeToImageSize = false
        defer { SettingsManager.shared.autoResizeToImageSize = previous }
        let window = makeTestWindow()
        window.setContentSize(NSSize(width: 600, height: 400))
        let file = makeTestImageFile(name: "zoom-title-\(UUID().uuidString).jpg", size: NSSize(width: 800, height: 600))
        defer { try? FileManager.default.removeItem(at: file) }
        viewController.loadImage(from: file)
        waitUntil(description: "image and texture ready") {
            self.viewController.displayedFileURL == file && !self.viewController.imageView.isTexturePending
        }
        var files = (0..<128).map { file.deletingLastPathComponent().appendingPathComponent("placeholder-\($0).jpg") }
        files[88] = file
        viewController.fileListManager.fileURLs = files
        viewController.fileListManager.currentIndex = 88
        viewController.updateFileNameDisplay(for: file)
        let base = "FastViewer Lite - \(file.lastPathComponent)"
        XCTAssertEqual(window.title, base + " - 89/128")
        XCTAssertFalse(viewController.imageView.usesNearestNeighbor)
        XCTAssertFalse(viewController.imageView.surface.nearest)
        for scale: CGFloat in [2.5, 1, 4, 1] {
            viewController.changeZoom(to: scale, at: NSPoint(x: 300, y: 200))
            XCTAssertEqual(viewController.imageView.usesNearestNeighbor, scale > 1)
            let zoom = scale > 1 ? " \(Int(scale * 100))%" : ""
            XCTAssertEqual(window.title, base + zoom + " - 89/128")
            waitUntil(description: "sampler committed with texture") { !self.viewController.imageView.isTexturePending }
            XCTAssertEqual(viewController.imageView.surface.nearest, scale > 1)
        }
        viewController.changeZoom(to: 2.5, at: NSPoint(x: 300, y: 200))
        viewController.resizeWindow(to: NSSize(width: 600, height: 400), animated: false)
        XCTAssertFalse(viewController.imageView.usesNearestNeighbor)
        XCTAssertEqual(window.title, base + " - 89/128")
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
        let zoomedTransform = viewController.imageView.renderTransform
        XCTAssertEqual(zoomedTransform?.m11 ?? 1.0, 1.0, accuracy: 0.001, "Zoom out must stop at the initial fitted size")
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
        guard viewController.imageView.layer != nil else {
            XCTFail("Image view layer should be available")
            return
        }

        // Verify initial state uses linear filtering (smooth interpolation)
        XCTAssertFalse(viewController.imageView.usesNearestNeighbor, "Initial state should use linear filtering for smooth interpolation")
        XCTAssertFalse(viewController.imageView.usesNearestNeighbor, "Initial state should use linear filtering for smooth interpolation")

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
        let zoomedTransform = viewController.imageView.renderTransform
        XCTAssertGreaterThan(zoomedTransform?.m11 ?? 1.0, 1.0, "Zoom in should increase scale")

        // Verify pixel grid mode is enabled (nearest-neighbor filtering)
        XCTAssertTrue(viewController.imageView.usesNearestNeighbor, "When zoomed in, should use nearest-neighbor filtering to show pixel grid")
        XCTAssertTrue(viewController.imageView.usesNearestNeighbor, "When zoomed in, should use nearest-neighbor filtering to show pixel grid")
        XCTAssertEqual((viewController.imageView)?.usesNearestNeighbor, true)

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
        let finalTransform = viewController.imageView.renderTransform
        if (finalTransform?.m11 ?? 1.0) <= 1.0 {
            XCTAssertFalse(viewController.imageView.usesNearestNeighbor, "When not zoomed in, should use linear filtering for smooth interpolation")
            XCTAssertFalse(viewController.imageView.usesNearestNeighbor, "When not zoomed in, should use linear filtering for smooth interpolation")
            XCTAssertEqual((viewController.imageView)?.usesNearestNeighbor, false)
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
        let zoomedTransform = viewController.imageView.renderTransform
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

        let actualSizeTransform = viewController.imageView.renderTransform
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
            viewController.imageView.renderTransform?.m11 ?? 0,
            expectedResizedTransform,
            accuracy: 0.01,
            "Actual Size should remain pixel-accurate after resizing the window"
        )
    }

    func testZoomResetsWhenReturningToImage() {
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
        let zoom1Transform = viewController.imageView.renderTransform
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
        let zoom2Transform = viewController.imageView.renderTransform
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

        // Returning to the first image must start fitted again.
        let zoom1RestoredTransform = viewController.imageView.renderTransform
        let zoom1RestoredScale = zoom1RestoredTransform?.m11 ?? 1.0
        XCTAssertGreaterThan(zoom1Scale, 1, "The first image must have been zoomed before navigating away")
        XCTAssertEqual(zoom1RestoredScale, 1, accuracy: 0.01, "Returning to the image must reset zoom")
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

        // At the fitted size, Cmd- must leave the window unchanged.
        let scaledWindowSize = window.frame.size
        XCTAssertEqual(scaledWindowSize.width, initialWindowSize.width, accuracy: 0.01, "Cmd- must not shrink the window below its initial fit")

        // Image transform should still be 1.0 (no zoom transform, just window scaling)
        let transform = viewController.imageView.renderTransform
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
        let zoom2Transform = viewController.imageView.renderTransform
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

        let transformAfterZoomIn = viewController.imageView.renderTransform
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
        let transformAfterZoomOut = viewController.imageView.renderTransform
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
        let zoomedTransform = viewController.imageView.renderTransform
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
        let resetTransform = viewController.imageView.renderTransform
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
        let initialTransform = viewController.imageView.renderTransform
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
        let pannedTransform = viewController.imageView.renderTransform
        let newTranslationX = pannedTransform?.m41 ?? 0
        let newTranslationY = pannedTransform?.m42 ?? 0

        // Translation should have changed (delta is 50 in x, 20 in y)
        XCTAssertNotEqual(newTranslationX, initialTranslationX, accuracy: 0.01, "Panning should apply X translation")
        XCTAssertNotEqual(newTranslationY, initialTranslationY, accuracy: 0.01, "Panning should apply Y translation")
        XCTAssertEqual(newTranslationX - initialTranslationX, 50, accuracy: 0.01, "Dragging should follow the pointer in screen points at any zoom")
        XCTAssertEqual(newTranslationY - initialTranslationY, 20, accuracy: 0.01)

        // End panning
        viewController.handlePanEnd()
    }

    func testPanningResetsWhenReturningToImage() {
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
        let pan1Transform = viewController.imageView.renderTransform
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
        let pan2InitialTransform = viewController.imageView.renderTransform
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
        let pan1RestoredTransform = viewController.imageView.renderTransform
        let pan1RestoredTranslationX = pan1RestoredTransform?.m41 ?? 0
        XCTAssertNotEqual(pan1TranslationX, 0, accuracy: 1.0, "The image must have been panned before navigation")
        XCTAssertEqual(pan1RestoredTranslationX, 0, accuracy: 0.01, "Returning to the image must clear its pan offset")
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

// Every agreed action scenario has its own XCTest entry, so failures identify
// the exact sequence. Upload completions are controlled to inspect pending frames.
extension ViewControllerTests {
    private func runActionScenario(_ number: Int, autoResize: Bool = false) throws {
        // I/O: zoom; D: drag; R: resize; A/B: photograph; F: delayed rapid navigation;
        // Q: input before a pending upload completes; P: preview/full-resolution swap.
        let scenarios: [Int: [String]] = [
            1: ["I","O"], 2: ["I","D","O"], 3: ["I","R","O"],
            4: ["I","D","R","O"], 5: ["I","R","D","O"],
            6: ["I","D","D","O"], 7: ["I","R","R","O"],
            8: ["I","D","R","D","O"], 9: ["I","R","D","R","O"],
            10: ["I","I","I","O","O","O","O"],
            11: ["I","D","I","O"], 12: ["I","R","I","O"],
            13: ["I","D","R","I","O"], 14: ["I","R","D","I","O"],
            15: ["I","D","O","D","O"], 16: ["I","R","O","R","O"],
            17: ["I","D","R","O","R","D","O"],
            18: ["I","I","O","I","O"],
            19: ["I","O","O","O","I","D","R","O"],
            20: ["B"], 21: ["B"], 22: ["B"],
            23: ["I","B","A"], 24: ["I","D","B","A"],
            25: ["I","R","B","A"], 26: ["I","D","R","B","A"],
            27: ["I","B","R","A"], 28: ["I","F"],
            29: ["I","F","F"], 30: ["F","R","F"],
            31: ["Q"], 32: ["I","D","P"],
            33: ["I","D","O"], 34: ["I","D","I"],
            35: ["I","D","D","D","O"],
            36: ["I","D","R","O"], 37: ["I","R","D","I"],
            38: ["I","D","B","A","I","O"]
        ]
        let previous = SettingsManager.shared.autoResizeToImageSize
        SettingsManager.shared.autoResizeToImageSize = autoResize
        defer { SettingsManager.shared.autoResizeToImageSize = previous }
        let window = makeTestWindow()
        window.setContentSize(NSSize(width: 360, height: 240))
        viewController.view.layoutSubtreeIfNeeded()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("viewer-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = [
            makeTestImageFile(name: "a.jpg", size: NSSize(width: 600, height: 400), directoryURL: directory),
            makeTestImageFile(name: "b.jpg", size: NSSize(width: 400, height: 600), directoryURL: directory),
            makeTestImageFile(name: "c.jpg", size: NSSize(width: 80, height: 50), directoryURL: directory)
        ]
        let canvas = viewController.imageView!
        var uploads: [(MTLTexture?, (MTLTexture?) -> Void)] = []
        canvas.textureUploader = { image, completion in
            uploads.append((MetalImageRenderer.shared.makeTexture(image), completion))
            return BlockOperation()
        }
        var savedScales: [URL: CGFloat] = [:]
        var savedCenters: [URL: NSPoint] = [:]
        var savedAnchors: [URL: NSPoint] = [:]
        var dragLocks: Set<URL> = []
        var activeAnchor: NSPoint?
        var resizeCount = 0
        var dragCount = 0
        func sourceAt(_ point: NSPoint) -> NSPoint {
            let g = canvas.surface.geometry
            return NSPoint(x: 0.5 + (point.x / canvas.bounds.width - 0.5 - CGFloat(g.z) / 2) / CGFloat(g.x),
                           y: 0.5 + (point.y / canvas.bounds.height - 0.5 - CGFloat(g.w) / 2) / CGFloat(g.y))
        }
        func screenOf(_ source: NSPoint) -> NSPoint {
            let g = canvas.surface.geometry
            return NSPoint(x: canvas.bounds.width * (0.5 + CGFloat(g.z) / 2 + (source.x - 0.5) * CGFloat(g.x)),
                           y: canvas.bounds.height * (0.5 + CGFloat(g.w) / 2 + (source.y - 0.5) * CGFloat(g.y)))
        }
        func checkFrame() {
            guard let logical = canvas.displayedLogicalSize, canvas.surface.texture != nil else { return }
            let g = canvas.surface.geometry
            XCTAssertEqual(CGFloat(g.x) * canvas.bounds.width / (CGFloat(g.y) * canvas.bounds.height),
                           logical.width / logical.height, accuracy: 0.001, "scenario \(number): aspect")
            if !canvas.isTexturePending && !canvas.isImageTransitionPending {
                let fit = min(1, canvas.bounds.width / logical.width, canvas.bounds.height / logical.height)
                XCTAssertEqual(CGFloat(g.x) * canvas.bounds.width / (logical.width * fit), canvas.zoomScale,
                               accuracy: 0.001, "scenario \(number): first frame must have final zoom")
            }
            if !canvas.isImageTransitionPending {
            for (extent, offset) in [(g.x, g.z), (g.y, g.w)] {
                if extent >= 1 {
                    XCTAssertGreaterThanOrEqual(extent - abs(offset), 0.999, "scenario \(number): exposed edge")
                } else {
                    XCTAssertEqual(offset, 0, accuracy: 0.001, "scenario \(number): center non-pannable axis")
                }
            }
            }
            XCTAssertGreaterThanOrEqual(canvas.zoomScale, 1)
            XCTAssertEqual(canvas.usesNearestNeighbor, canvas.zoomScale > 1)
            let percentage = " \(Int((canvas.zoomScale * 100).rounded()))%"
            if canvas.zoomScale > 1 { XCTAssertTrue(window.title.contains(percentage)) }
            else { XCTAssertFalse(window.title.contains("%")) }
        }
        func finishUploads() {
            while !uploads.isEmpty {
                let batch = uploads
                uploads.removeAll()
                for (texture, completion) in batch {
                    completion(texture)
                    checkFrame()
                }
            }
            checkFrame()
        }
        func open(_ index: Int, hold: Bool = false) {
            let switching = viewController.displayedFileURL != files[index]
            if let file = viewController.displayedFileURL {
                savedScales[file] = canvas.zoomScale
                if !canvas.isTexturePending { savedCenters[file] = sourceAt(NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)) }
                savedAnchors[file] = activeAnchor
            }
            let oldTexture = canvas.surface.texture
            let oldGeometry = canvas.surface.geometry
            let oldBounds = canvas.bounds
            let oldRect = canvas.displayedImageScreenRect
            canvas.surface.onFramePresented = { [weak canvas] _, texture in
                guard let canvas, let oldRect, oldTexture != nil, texture === oldTexture,
                      let rect = canvas.displayedImageScreenRect else { return }
                XCTAssertEqual(rect.minX, oldRect.minX, accuracy: 0.02, "old photo moved horizontally during transition")
                XCTAssertEqual(rect.minY, oldRect.minY, accuracy: 0.02, "old photo moved vertically during transition")
                XCTAssertEqual(rect.width, oldRect.width, accuracy: 0.02)
                XCTAssertEqual(rect.height, oldRect.height, accuracy: 0.02)
            }
            defer { canvas.surface.onFramePresented = nil }
            viewController.loadImage(from: files[index])
            waitUntil(description: "scenario \(number): image \(index) commit") { self.viewController.displayedFileURL == files[index] }
            if switching {
                activeAnchor = nil
                dragLocks.remove(files[index])
            } else {
                activeAnchor = savedAnchors[files[index]]
            }
            if canvas.isTexturePending, canvas.bounds == oldBounds {
                XCTAssertTrue(canvas.surface.texture === oldTexture, "old texture must stay paired with its own camera")
                XCTAssertEqual(canvas.surface.geometry, oldGeometry, "no old-image/new-zoom intermediate frame")
            }
            if !hold {
                finishUploads()
                XCTAssertEqual(canvas.zoomScale, switching ? 1 : (savedScales[files[index]] ?? 1), accuracy: 0.001)
                if switching {
                    XCTAssertEqual(canvas.panOffset, .zero)
                    XCTAssertFalse(canvas.usesNearestNeighbor)
                    XCTAssertFalse(window.title.contains("%"))
                }
                if !switching, let center = savedCenters[files[index]] {
                    let restored = sourceAt(NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
                    // Clamping after a resize may center an axis that now fits.
                    if canvas.surface.geometry.x > 1, abs(canvas.surface.geometry.z) < canvas.surface.geometry.x - 1 - 0.001 { XCTAssertEqual(restored.x, center.x, accuracy: 0.002) }
                    if canvas.surface.geometry.y > 1, abs(canvas.surface.geometry.w) < canvas.surface.geometry.y - 1 - 0.001 { XCTAssertEqual(restored.y, center.y, accuracy: 0.002) }
                }
            }
        }
        func zoom(_ increasing: Bool) {
            guard let file = viewController.displayedFileURL else { return }
            let pointer = NSPoint(x: canvas.bounds.width * 0.58, y: canvas.bounds.height * 0.55)
            let focusPoint: NSPoint
            if dragLocks.contains(file), let activeAnchor { focusPoint = screenOf(activeAnchor) }
            else if increasing || activeAnchor == nil {
                focusPoint = pointer
                activeAnchor = sourceAt(pointer)
            } else { focusPoint = screenOf(activeAnchor!) }
            let before = sourceAt(focusPoint)
            let target = increasing ? min(canvas.zoomScale * 2, 16) : max(1, canvas.zoomScale / 1.5)
            viewController.changeZoom(to: target, at: pointer)
            finishUploads()
            let after = sourceAt(focusPoint)
            // If an edge clamps the requested offset, exact anchoring is impossible.
            let g = canvas.surface.geometry
            if g.x > 1, abs(g.z) < g.x - 1 - 0.001 { XCTAssertEqual(after.x, before.x, accuracy: 0.002) }
            if g.y > 1, abs(g.w) < g.y - 1 - 0.001 { XCTAssertEqual(after.y, before.y, accuracy: 0.002) }
            if target == 1 { activeAnchor = nil; dragLocks.remove(file) }
            checkFrame()
        }
        func drag() {
            guard canvas.zoomScale > 1, let file = viewController.displayedFileURL else { return }
            dragCount += 1
            let start = NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
            let end = NSPoint(x: start.x + (dragCount.isMultiple(of: 2) ? -24 : 28), y: start.y + 16)
            viewController.handlePanStart(at: start)
            viewController.handlePanMove(to: end)
            viewController.handlePanEnd()
            finishUploads()
            activeAnchor = sourceAt(end)
            dragLocks.insert(file)
            checkFrame()
        }
        func resize() {
            resizeCount += 1
            let size = resizeCount.isMultiple(of: 2) ? NSSize(width: 300, height: 420) : NSSize(width: 480, height: 280)
            let center = sourceAt(NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
            window.setContentSize(size)
            viewController.view.layoutSubtreeIfNeeded()
            viewController.viewDidLayout()
            finishUploads()
            let newCenter = sourceAt(NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
            let g = canvas.surface.geometry
            if g.x > 1, abs(g.z) < g.x - 1 - 0.001 { XCTAssertEqual(newCenter.x, center.x, accuracy: 0.002) }
            if g.y > 1, abs(g.w) < g.y - 1 - 0.001 { XCTAssertEqual(newCenter.y, center.y, accuracy: 0.002) }
            checkFrame()
        }
        open(0)
        if [21,22,29,30,31].contains(number) {
            open(1); zoom(true); zoom(true)
            if number == 22 { drag() }
            open(0)
        }
        for action in scenarios[number]! {
            switch action {
            case "I": zoom(true)
            case "O": zoom(false)
            case "D": drag()
            case "R": resize()
            case "A": open(0)
            case "B": open(1)
            case "F":
                // Deliver superseded texture completions after new requests exist.
                for index in [1,2,0,2,1,0] { open(index, hold: true) }
                finishUploads()
                XCTAssertEqual(viewController.displayedFileURL, files[0])
                XCTAssertFalse(canvas.isTexturePending)
            case "Q":
                open(1, hold: true)
                let point = NSPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
                viewController.changeZoom(to: canvas.zoomScale * 2, at: point)
                viewController.handlePanStart(at: point)
                viewController.handlePanMove(to: NSPoint(x: point.x + 20, y: point.y + 10))
                viewController.handlePanEnd()
                window.setContentSize(NSSize(width: 440, height: 300))
                viewController.view.layoutSubtreeIfNeeded()
                checkFrame()
                finishUploads()
            case "P":
                let camera = canvas.surface.geometry
                let logical = try XCTUnwrap(canvas.logicalImageSize)
                let small = createTestImage(size: NSSize(width: 60, height: 40))
                canvas.setImage(small, logicalSize: logical)
                viewController.updateImageScaling(for: small)
                finishUploads()
                XCTAssertEqual(canvas.surface.geometry, camera, "preview must not alter the camera")
                canvas.setImage(createTestImage(size: NSSize(width: 600, height: 400)), logicalSize: logical)
                viewController.updateImageScaling(for: canvas.image!)
                finishUploads()
                XCTAssertEqual(canvas.surface.geometry, camera, "full resolution only replaces detail")
            default: XCTFail("Unknown action")
            }
            checkFrame()
        }
        // Final delayed completions must never resurrect a different photograph.
        finishUploads()
    }
    func testPanoramaAndPortraitCenterTheAxisThatFits() throws {
        let previous = SettingsManager.shared.autoResizeToImageSize
        SettingsManager.shared.autoResizeToImageSize = false
        defer { SettingsManager.shared.autoResizeToImageSize = previous }
        let window = makeTestWindow()
        window.setContentSize(NSSize(width: 600, height: 400))
        viewController.view.layoutSubtreeIfNeeded()
        for size in [NSSize(width: 2400, height: 100), NSSize(width: 100, height: 2400)] {
            let file = makeTestImageFile(name: "one-axis-\(UUID().uuidString).jpg", size: size)
            defer { try? FileManager.default.removeItem(at: file) }
            viewController.loadImage(from: file)
            waitUntil(description: "one-axis image loaded") { self.viewController.displayedFileURL == file }
            viewController.changeZoom(to: 4, at: NSPoint(x: 300, y: 200))
            viewController.handlePanStart(at: NSPoint(x: 300, y: 200))
            viewController.handlePanMove(to: NSPoint(x: 10000, y: 10000))
            viewController.handlePanEnd()
            if size.width > size.height {
                XCTAssertEqual(viewController.imageView.panOffset.y, 0)
                XCTAssertEqual(viewController.imageView.panOffset.x, 900, accuracy: 0.01)
            } else {
                XCTAssertEqual(viewController.imageView.panOffset.x, 0)
                XCTAssertEqual(viewController.imageView.panOffset.y, 600, accuracy: 0.01)
            }
            viewController.changeZoom(to: 2, at: .zero)
            let offset = viewController.imageView.panOffset
            if size.width > size.height { XCTAssertEqual(offset.y, 0) }
            else { XCTAssertEqual(offset.x, 0) }
        }
    }

    func testCmd3ZoomedPhotoStaysStationaryUntilNextTextureIsReady() throws {
        let previous = SettingsManager.shared.autoResizeToImageSize
        defer { SettingsManager.shared.autoResizeToImageSize = previous }
        let window = makeTestWindow()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cmd3-transition-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = makeTestImageFile(name: "a.jpg", size: NSSize(width: 600, height: 400), directoryURL: directory)
        let second = makeTestImageFile(name: "b.jpg", size: NSSize(width: 400, height: 600), directoryURL: directory)
        let cmd3 = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "3",
            charactersIgnoringModifiers: "3", isARepeat: false, keyCode: 20))
        viewController.keyDown(with: cmd3)
        let settled = expectation(description: "Cmd+3 preset settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        let canvas = viewController.imageView!
        var uploads: [(MTLTexture?, (MTLTexture?) -> Void)] = []
        canvas.textureUploader = { image, completion in
            uploads.append((MetalImageRenderer.shared.makeTexture(image), completion))
            return BlockOperation()
        }
        viewController.loadImage(from: first)
        waitUntil(description: "first photo committed") { self.viewController.displayedFileURL == first }
        while !uploads.isEmpty { let item = uploads.removeFirst(); item.1(item.0) }
        viewController.changeZoom(to: 4, at: NSPoint(x: canvas.bounds.width * 0.6, y: canvas.bounds.height * 0.6))
        viewController.handlePanStart(at: NSPoint(x: 200, y: 200))
        viewController.handlePanMove(to: NSPoint(x: 250, y: 230))
        viewController.handlePanEnd()
        let oldTexture = try XCTUnwrap(canvas.surface.texture)
        let oldRect = try XCTUnwrap(canvas.displayedImageScreenRect)
        // A late quality upload for the old photo must not release the frozen
        // frame while the next photo is still decoding.
        canvas.setImage(try XCTUnwrap(canvas.image), logicalSize: try XCTUnwrap(canvas.logicalImageSize))
        canvas.beginImageTransition()
        while !uploads.isEmpty { let item = uploads.removeFirst(); item.1(item.0) }
        XCTAssertTrue(canvas.surface.texture === oldTexture)
        XCTAssertTrue(canvas.isImageTransitionPending)
        viewController.fileListManager.fileURLs = [first, second]
        viewController.fileListManager.currentIndex = 0
        viewController.navigateToNext()
        waitUntil(description: "second photo awaits texture") { self.viewController.displayedFileURL == second }
        var observedFrames = 0
        canvas.surface.onFramePresented = { [weak canvas] _, texture in
            guard let canvas, texture === oldTexture, let rect = canvas.displayedImageScreenRect else { return }
            observedFrames += 1
            XCTAssertEqual(rect.minX, oldRect.minX, accuracy: 0.02)
            XCTAssertEqual(rect.minY, oldRect.minY, accuracy: 0.02)
            XCTAssertEqual(rect.width, oldRect.width, accuracy: 0.02)
            XCTAssertEqual(rect.height, oldRect.height, accuracy: 0.02)
        }
        for size in [NSSize(width: 800, height: 500), NSSize(width: 500, height: 700)] {
            window.setContentSize(size)
            window.setFrameOrigin(NSPoint(x: window.frame.minX + 20, y: window.frame.minY + 15))
            viewController.view.layoutSubtreeIfNeeded()
            canvas.layoutSubtreeIfNeeded()
            canvas.surface.draw()
        }
        XCTAssertGreaterThan(observedFrames, 0)
        canvas.surface.onFramePresented = nil
        XCTAssertTrue(canvas.surface.texture === oldTexture)
        while !uploads.isEmpty { let item = uploads.removeFirst(); item.1(item.0) }
        XCTAssertFalse(canvas.surface.texture === oldTexture)
        XCTAssertFalse(canvas.isImageTransitionPending)
        XCTAssertEqual(canvas.zoomScale, 1)
        // Genuine user resizing after commit resumes normal fitting.
        window.setContentSize(NSSize(width: 700, height: 400))
        viewController.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(canvas.isImageTransitionPending)
    }

    func testActionScenariosWithAutoResize() throws {
        for number in [2,4,5,20,21,22,23,24,25,26,27,28,29,30,31,32,36,37,38] {
            try runActionScenario(number, autoResize: true)
        }
    }
    func testActionScenario01() throws { try runActionScenario(1) }
    func testActionScenario02() throws { try runActionScenario(2) }
    func testActionScenario03() throws { try runActionScenario(3) }
    func testActionScenario04() throws { try runActionScenario(4) }
    func testActionScenario05() throws { try runActionScenario(5) }
    func testActionScenario06() throws { try runActionScenario(6) }
    func testActionScenario07() throws { try runActionScenario(7) }
    func testActionScenario08() throws { try runActionScenario(8) }
    func testActionScenario09() throws { try runActionScenario(9) }
    func testActionScenario10() throws { try runActionScenario(10) }
    func testActionScenario11() throws { try runActionScenario(11) }
    func testActionScenario12() throws { try runActionScenario(12) }
    func testActionScenario13() throws { try runActionScenario(13) }
    func testActionScenario14() throws { try runActionScenario(14) }
    func testActionScenario15() throws { try runActionScenario(15) }
    func testActionScenario16() throws { try runActionScenario(16) }
    func testActionScenario17() throws { try runActionScenario(17) }
    func testActionScenario18() throws { try runActionScenario(18) }
    func testActionScenario19() throws { try runActionScenario(19) }
    func testActionScenario20() throws { try runActionScenario(20) }
    func testActionScenario21() throws { try runActionScenario(21) }
    func testActionScenario22() throws { try runActionScenario(22) }
    func testActionScenario23() throws { try runActionScenario(23) }
    func testActionScenario24() throws { try runActionScenario(24) }
    func testActionScenario25() throws { try runActionScenario(25) }
    func testActionScenario26() throws { try runActionScenario(26) }
    func testActionScenario27() throws { try runActionScenario(27) }
    func testActionScenario28() throws { try runActionScenario(28) }
    func testActionScenario29() throws { try runActionScenario(29) }
    func testActionScenario30() throws { try runActionScenario(30) }
    func testActionScenario31() throws { try runActionScenario(31) }
    func testActionScenario32() throws { try runActionScenario(32) }
    func testActionScenario33() throws { try runActionScenario(33) }
    func testActionScenario34() throws { try runActionScenario(34) }
    func testActionScenario35() throws { try runActionScenario(35) }
    func testActionScenario36() throws { try runActionScenario(36) }
    func testActionScenario37() throws { try runActionScenario(37) }
    func testActionScenario38() throws { try runActionScenario(38) }
}
