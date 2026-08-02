//
//  ImageLoaderTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 18.12.25.
//

import XCTest
import AppKit
import ImageIO
@testable import FastViewer_Lite

final class ImageLoaderTests: XCTestCase {
    
    var imageLoader: ImageLoader!
    
    override func setUp() {
        super.setUp()
        imageLoader = ImageLoader.shared
    }
    
    override func tearDown() {
        imageLoader = nil
        super.tearDown()
    }
    
    func testImageLoaderSingleton() {
        let loader1 = ImageLoader.shared
        let loader2 = ImageLoader.shared
        XCTAssertTrue(loader1 === loader2, "ImageLoader should be a singleton")
    }
    
    func testLoadImageFromInvalidPath() {
        let invalidPath = "/nonexistent/path/image.jpg"
        let image = imageLoader.loadImage(from: invalidPath)
        XCTAssertNil(image, "Should return nil for invalid file path")
    }
    
    func testLoadImageFromInvalidData() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        let image = imageLoader.loadImage(from: invalidData)
        XCTAssertNil(image, "Should return nil for invalid image data")
    }
    
    func testLoadImageAsyncWithInvalidPath() {
        let expectation = XCTestExpectation(description: "Async load completes")
        let invalidPath = "/nonexistent/path/image.jpg"
        
        imageLoader.loadImageAsync(from: invalidPath) { image in
            XCTAssertNil(image, "Should return nil for invalid file path")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testLoadImageAsyncCompletesOnMainQueue() {
        let expectation = XCTestExpectation(description: "Async load completes on main queue")
        let invalidPath = "/nonexistent/path/image.jpg"
        
        imageLoader.loadImageAsync(from: invalidPath) { image in
            XCTAssertTrue(Thread.isMainThread, "Completion handler should be called on main thread")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }

    func testStaticPrefetchReportsAnimatedImageWithoutDecodingIt() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "com.compuserve.gif" as CFString,
            2,
            nil
        ) else {
            XCTFail("Could not create GIF destination")
            return
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let pixels: [[UInt8]] = [
            [255, 0, 0, 255],
            [0, 0, 255, 255]
        ]
        for pixel in pixels {
            guard let provider = CGDataProvider(
                data: Data(pixel) as CFData
            ), let image = CGImage(
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.last.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ) else {
                XCTFail("Could not create GIF frame")
                return
            }
            CGImageDestinationAddImage(destination, image, nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: fileURL)

        var reportedAnimatedImage = false
        let image = imageLoader.loadImage(
            from: fileURL,
            allowsAnimatedImage: false,
            onUnsupportedAnimatedImage: {
                reportedAnimatedImage = true
            }
        )

        XCTAssertNil(image)
        XCTAssertTrue(reportedAnimatedImage)
    }
    
    // Note: To test with actual JPEG files, you would need to add test images to the test bundle
    // This test demonstrates the structure but requires actual image files
    func testLoadImageWithValidJPEG() {
        // This test would require a test JPEG file in the test bundle
        // For now, we'll skip it but show the structure
        // Uncomment and add a test image to test this:
        /*
        guard let testImagePath = Bundle(for: type(of: self)).path(forResource: "test", ofType: "jpg") else {
            XCTSkip("Test image not found in bundle")
            return
        }
        
        let image = imageLoader.loadImage(from: testImagePath)
        XCTAssertNotNil(image, "Should load valid JPEG image")
        XCTAssertGreaterThan(image!.size.width, 0, "Image should have valid width")
        XCTAssertGreaterThan(image!.size.height, 0, "Image should have valid height")
        */
    }
    
    // MARK: - Average Color Calculation Tests
    
    func testCalculateAverageColorWithNilImage() {
        // Create an invalid NSImage (no CGImage representation)
        let invalidImage = NSImage(size: NSSize(width: 100, height: 100))
        let color = imageLoader.calculateAverageColor(of: invalidImage)
        XCTAssertNil(color, "Should return nil for image without CGImage representation")
    }
    
    func testCalculateAverageColorWithSolidColorImage() {
        // Create a solid red image
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        
        let averageColor = imageLoader.calculateAverageColor(of: image)
        XCTAssertNotNil(averageColor, "Should calculate average color for solid color image")
        
        // Check that the color is approximately red (allowing for some floating point precision)
        if let color = averageColor {
            let red = color.redComponent
            let green = color.greenComponent
            let blue = color.blueComponent
            
            // Red should be dominant (close to 1.0)
            XCTAssertGreaterThan(red, 0.9, "Red component should be close to 1.0 for red image")
            // Green and blue should be close to 0
            XCTAssertLessThan(green, 0.1, "Green component should be close to 0 for red image")
            XCTAssertLessThan(blue, 0.1, "Blue component should be close to 0 for red image")
        }
    }
    
    func testCalculateAverageColorWithSolidBlueImage() {
        // Create a solid blue image
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        
        let averageColor = imageLoader.calculateAverageColor(of: image)
        XCTAssertNotNil(averageColor, "Should calculate average color for solid blue image")
        
        // Check that the color is approximately blue
        if let color = averageColor {
            let red = color.redComponent
            let green = color.greenComponent
            let blue = color.blueComponent
            
            // Blue should be dominant (close to 1.0)
            XCTAssertGreaterThan(blue, 0.9, "Blue component should be close to 1.0 for blue image")
            // Red and green should be close to 0
            XCTAssertLessThan(red, 0.1, "Red component should be close to 0 for blue image")
            XCTAssertLessThan(green, 0.1, "Green component should be close to 0 for blue image")
        }
    }
    
    func testCalculateAverageColorWithGradientImage() {
        // Create a gradient image (black to white)
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)
        image.lockFocus()
        
        let gradient = NSGradient(colors: [NSColor.black, NSColor.white])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 0)
        
        image.unlockFocus()
        
        let averageColor = imageLoader.calculateAverageColor(of: image)
        XCTAssertNotNil(averageColor, "Should calculate average color for gradient image")
        
        // For a black-to-white gradient, the average should be approximately gray (0.5, 0.5, 0.5)
        if let color = averageColor {
            let red = color.redComponent
            let green = color.greenComponent
            let blue = color.blueComponent
            
            // All components should be approximately 0.5 (gray)
            // Allow some tolerance for gradient calculation
            XCTAssertGreaterThan(red, 0.3, "Red component should be around 0.5 for black-white gradient")
            XCTAssertLessThan(red, 0.7, "Red component should be around 0.5 for black-white gradient")
            XCTAssertGreaterThan(green, 0.3, "Green component should be around 0.5 for black-white gradient")
            XCTAssertLessThan(green, 0.7, "Green component should be around 0.5 for black-white gradient")
            XCTAssertGreaterThan(blue, 0.3, "Blue component should be around 0.5 for black-white gradient")
            XCTAssertLessThan(blue, 0.7, "Blue component should be around 0.5 for black-white gradient")
        }
    }
    
    func testCalculateAverageColorFromInvalidURL() {
        let invalidURL = URL(fileURLWithPath: "/nonexistent/path/image.jpg")
        let color = imageLoader.calculateAverageColor(from: invalidURL)
        XCTAssertNil(color, "Should return nil for invalid file URL")
    }
    
    func testCalculateAverageColorPerformance() {
        // Create a test image
        let size = NSSize(width: 2000, height: 2000)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        
        // Measure performance of average color calculation
        measure {
            _ = imageLoader.calculateAverageColor(of: image)
        }
    }
}





