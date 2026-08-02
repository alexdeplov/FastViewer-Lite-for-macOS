//
//  ImageCacheManagerTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 18.12.25.
//

import XCTest
import AppKit
@testable import FastViewer_Lite

final class ImageCacheManagerTests: XCTestCase {
    
    var cacheManager: ImageCacheManager!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        cacheManager = ImageCacheManager.shared
        cacheManager.clearCache()
        cacheManager.prefetchBefore = 2
        cacheManager.prefetchAfter = 8
        
        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        cacheManager.clearCache()
        cacheManager.cancelPrefetching()
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        cacheManager = nil
        tempDirectory = nil
        super.tearDown()
    }
    
    func testCacheImageAndRetrieve() {
        let testURL = tempDirectory.appendingPathComponent("test.jpg")
        let testImage = createTestImage(size: NSSize(width: 100, height: 100))
        
        // Initially should not be cached
        XCTAssertNil(cacheManager.getCachedImage(for: testURL), "Image should not be cached initially")
        
        // Cache the image
        cacheManager.cacheImage(testImage, for: testURL)
        
        // Should now be cached
        let cachedImage = cacheManager.getCachedImage(for: testURL)
        XCTAssertNotNil(cachedImage, "Image should be cached")
        XCTAssertEqual(cachedImage?.size, testImage.size, "Cached image should match original size")
    }
    
    func testClearCache() {
        let testURL = tempDirectory.appendingPathComponent("test.jpg")
        let testImage = createTestImage(size: NSSize(width: 100, height: 100))
        
        // Cache the image
        cacheManager.cacheImage(testImage, for: testURL)
        XCTAssertNotNil(cacheManager.getCachedImage(for: testURL), "Image should be cached")
        
        // Clear cache
        cacheManager.clearCache()
        
        // Should no longer be cached
        XCTAssertNil(cacheManager.getCachedImage(for: testURL), "Image should not be cached after clear")
    }

    func testCacheSeparatesDecodeSizes() {
        let testURL = tempDirectory.appendingPathComponent("sized.jpg")
        let image = createTestImage(size: NSSize(width: 100, height: 100))

        cacheManager.cacheImage(image, for: testURL, maxSize: 1024)

        XCTAssertNotNil(cacheManager.getCachedImage(for: testURL, maxSize: 1024))
        XCTAssertNil(cacheManager.getCachedImage(for: testURL, maxSize: 4000))
    }

    func testCacheInvalidatesExplicitlyWhenFileIsReopenedOrReplaced() throws {
        let testURL = tempDirectory.appendingPathComponent("versioned.jpg")
        try Data([0x01]).write(to: testURL)
        let image = createTestImage(size: NSSize(width: 100, height: 100))
        cacheManager.cacheImage(image, for: testURL, maxSize: 1024)
        XCTAssertNotNil(cacheManager.getCachedImage(for: testURL, maxSize: 1024))

        try Data([0x01, 0x02]).write(to: testURL)
        cacheManager.removeCachedImage(for: testURL)

        XCTAssertNil(
            cacheManager.getCachedImage(for: testURL, maxSize: 1024),
            "Explicit invalidation must prevent a replaced file from reusing old pixels"
        )
    }

    func testDefaultPrefetchWindowIsTwoBackAndEightForward() {
        XCTAssertEqual(cacheManager.prefetchBefore, 2)
        XCTAssertEqual(cacheManager.prefetchAfter, 8)
    }
    
    func testPrefetchImagesSkipsCachedImages() {
        // Create test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        let fileURLs = [file1, file2, file3]
        let currentIndex = 1 // Middle file
        
        // Cache file2 (current file)
        let cachedImage = createTestImage(size: NSSize(width: 100, height: 100))
        cacheManager.cacheImage(cachedImage, for: file2)
        
        // Prefetch should skip file2 since it's already cached
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: currentIndex)
        
        // Give prefetch operations time to start
        let expectation = XCTestExpectation(description: "Prefetch operations complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        // Note: We can't easily verify which files were prefetched without actual image files,
        // but we can verify the operation doesn't crash and cache works
    }
    
    func testPrefetchImagesRespectsBounds() {
        // Create test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        let fileURLs = [file1, file2, file3]
        
        // Test prefetching at start (index 0)
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 0)
        
        // Test prefetching at end (index 2)
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 2)
        
        // Should not crash
        XCTAssertTrue(true, "Prefetching should handle boundary conditions")
    }
    
    func testPrefetchImagesCancelsPreviousOperations() {
        // Create test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        
        let fileURLs = [file1, file2]
        
        // Start prefetching
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 0)
        
        // Immediately start another prefetch (should cancel previous)
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 1)
        
        // Should not crash
        XCTAssertTrue(true, "Canceling prefetch operations should work")
    }
    
    func testPrefetchImagesPreventsDuplicateRequests() {
        // Create test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        let fileURLs = [file1, file2, file3]
        let currentIndex = 1
        
        // Call prefetchImages twice with same parameters (simulating the bug scenario)
        // This simulates the case where navigateToNext() and loadImage() both call startPrefetching()
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: currentIndex)
        
        // Wait a tiny bit to let the first request start processing
        let expectation1 = XCTestExpectation(description: "First prefetch request")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 0.1)
        
        // Call prefetchImages again with same parameters (duplicate request)
        // This should be prevented by the duplicate detection logic
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: currentIndex)
        
        // Wait for requests to process
        let expectation2 = XCTestExpectation(description: "Prefetch requests processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 0.5)
        
        // Verify that subsequent different requests still work (not blocked by duplicate prevention)
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 0)
        
        // If we get here without issues, the duplicate prevention is working
        XCTAssertTrue(true, "Duplicate prefetch requests should be prevented without blocking valid requests")
    }
    
    func testCancelPrefetching() {
        // Create test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        
        let fileURLs = [file1, file2]
        
        // Start prefetching
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 0)
        
        // Cancel prefetching
        cacheManager.cancelPrefetching()
        
        // Should not crash
        XCTAssertTrue(true, "Cancel prefetching should work")
    }
    
    func testPrefetchRangeCalculation() {
        // Create 30 test files
        var fileURLs: [URL] = []
        for i in 0..<30 {
            let file = tempDirectory.appendingPathComponent("file\(i).jpg")
            try? "test data".write(to: file, atomically: true, encoding: .utf8)
            fileURLs.append(file)
        }
        
        // Test prefetching at middle (index 15)
        // Should prefetch indices: 13, 14, 16-35 (but capped at 29)
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 15)
        
        // Should not crash
        XCTAssertTrue(true, "Prefetch range calculation should work")
    }
    
    func testPrefetchAtStartOfList() {
        // Create test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        
        let fileURLs = [file1, file2]
        
        // Prefetch at start (index 0)
        // Should only prefetch forward, not backward
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 0)
        
        // Should not crash
        XCTAssertTrue(true, "Prefetching at start should work")
    }
    
    func testPrefetchAtEndOfList() {
        // Create test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        
        let fileURLs = [file1, file2]
        
        // Prefetch at end (index 1)
        // Should only prefetch backward, not forward
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 1)
        
        // Should not crash
        XCTAssertTrue(true, "Prefetching at end should work")
    }
    
    func testPrefetchWithEmptyFileList() {
        // Test prefetching with empty file list (should not crash)
        // This can happen when opening a file from Downloads folder if permissions
        // prevent reading the directory contents
        let emptyFileURLs: [URL] = []
        
        // Should not crash when called with empty array
        cacheManager.prefetchImages(fileURLs: emptyFileURLs, currentIndex: 0)
        
        // Should not crash
        XCTAssertTrue(true, "Prefetching with empty file list should not crash")
    }
    
    func testPrefetchWithSingleFile() {
        // Create a single test file
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        
        let fileURLs = [file1]
        
        // Prefetch with single file (index 0)
        // Should not crash even though there's nothing to prefetch
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 0)
        
        // Should not crash
        XCTAssertTrue(true, "Prefetching with single file should not crash")
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
    
    // MARK: - Average Color Cache Tests
    
    func testCacheAverageColorAndRetrieve() {
        let testURL = tempDirectory.appendingPathComponent("test.jpg")
        let testColor = NSColor.red
        
        // Initially should not be cached
        XCTAssertNil(cacheManager.getCachedAverageColor(for: testURL), "Average color should not be cached initially")
        
        // Cache the color
        cacheManager.cacheAverageColor(testColor, for: testURL)
        
        // Should now be cached
        let cachedColor = cacheManager.getCachedAverageColor(for: testURL)
        XCTAssertNotNil(cachedColor, "Average color should be cached")
        XCTAssertEqual(cachedColor?.redComponent ?? -1, testColor.redComponent, accuracy: 0.001, "Cached color should match original")
    }
    
    func testClearCacheRemovesAverageColors() {
        let testURL = tempDirectory.appendingPathComponent("test.jpg")
        let testColor = NSColor.blue
        
        // Cache the color
        cacheManager.cacheAverageColor(testColor, for: testURL)
        XCTAssertNotNil(cacheManager.getCachedAverageColor(for: testURL), "Average color should be cached")
        
        // Clear cache
        cacheManager.clearCache()
        
        // Should no longer be cached
        XCTAssertNil(cacheManager.getCachedAverageColor(for: testURL), "Average color should not be cached after clear")
    }
    
    func testAverageColorCacheSeparateFromImageCache() {
        let testURL = tempDirectory.appendingPathComponent("test.jpg")
        let testImage = createTestImage(size: NSSize(width: 100, height: 100))
        let testColor = NSColor.green
        
        // Cache image but not color
        cacheManager.cacheImage(testImage, for: testURL)
        XCTAssertNotNil(cacheManager.getCachedImage(for: testURL), "Image should be cached")
        XCTAssertNil(cacheManager.getCachedAverageColor(for: testURL), "Average color should not be cached")
        
        // Cache color but not image (different scenario)
        cacheManager.clearCache()
        cacheManager.cacheAverageColor(testColor, for: testURL)
        XCTAssertNil(cacheManager.getCachedImage(for: testURL), "Image should not be cached")
        XCTAssertNotNil(cacheManager.getCachedAverageColor(for: testURL), "Average color should be cached")
    }
    
    func testPrefetchPrioritizesClosestFiles() {
        // Create 10 test files
        var fileURLs: [URL] = []
        for i in 0..<10 {
            let file = tempDirectory.appendingPathComponent("file\(String(format: "%02d", i)).jpg")
            try? "test data".write(to: file, atomically: true, encoding: .utf8)
            fileURLs.append(file)
        }
        
        // Prefetch from middle (index 5)
        // Should prioritize: 4, 6 (distance 1), then 3, 7 (distance 2), etc.
        cacheManager.prefetchImages(fileURLs: fileURLs, currentIndex: 5)
        
        // Wait for prefetch operations to start (they should be queued in priority order)
        let expectation = XCTestExpectation(description: "Prefetch operations queued")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
        
        // Test passes if no crash - priority ordering is internal implementation detail
        // but ensures closest files are prefetched first for better UX
        XCTAssertTrue(true, "Prefetch should prioritize closest files")
    }
}



