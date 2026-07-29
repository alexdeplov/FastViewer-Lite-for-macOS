//
//  FileListManagerTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 18.12.25.
//

import XCTest
@testable import FastViewer_Lite

final class FileListManagerTests: XCTestCase {
    
    var fileListManager: FileListManager!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        fileListManager = FileListManager()
        
        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        fileListManager = nil
        tempDirectory = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertEqual(fileListManager.fileURLs.count, 0, "File list should be empty initially")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0 initially")
        XCTAssertNil(fileListManager.currentFileURL, "Current file URL should be nil initially")
        XCTAssertFalse(fileListManager.hasPrevious, "Should not have previous file initially")
        XCTAssertFalse(fileListManager.hasNext, "Should not have next file initially")
    }
    
    func testLoadFilesWithSingleFile() {
        // Create a test file
        let testFile = tempDirectory.appendingPathComponent("test.jpg")
        try? "test data".write(to: testFile, atomically: true, encoding: .utf8)
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: testFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 1, "Should have one file")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0")
        XCTAssertEqual(fileListManager.currentFileURL, testFile, "Current file should be the test file")
        XCTAssertFalse(fileListManager.hasPrevious, "Should not have previous file")
        XCTAssertFalse(fileListManager.hasNext, "Should not have next file")
    }
    
    func testLoadFilesWithMultipleFiles() {
        // Create multiple test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: file2)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 3, "Should have three files")
        XCTAssertEqual(fileListManager.currentIndex, 1, "Current index should be 1 (file2)")
        XCTAssertEqual(fileListManager.currentFileURL, file2, "Current file should be file2")
        XCTAssertTrue(fileListManager.hasPrevious, "Should have previous file")
        XCTAssertTrue(fileListManager.hasNext, "Should have next file")
    }
    
    func testLoadFilesFiltersUnsupportedFormats() {
        // Create files with different extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let pngFile = tempDirectory.appendingPathComponent("test.png")
        let txtFile = tempDirectory.appendingPathComponent("test.txt")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: pngFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: txtFile, atomically: true, encoding: .utf8)
        
        // Ensure PNG support is disabled
        SettingsManager.shared.isPNGSupportEnabled = false
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 1, "Should only have JPEG file")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertFalse(fileListManager.fileURLs.contains(pngFile), "Should not contain PNG file when disabled")
        XCTAssertFalse(fileListManager.fileURLs.contains(txtFile), "Should not contain TXT file")
    }
    
    func testLoadFilesIncludesPNGWhenEnabled() {
        // Create files with different extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let pngFile = tempDirectory.appendingPathComponent("test.png")
        let txtFile = tempDirectory.appendingPathComponent("test.txt")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: pngFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: txtFile, atomically: true, encoding: .utf8)
        
        // Enable PNG support
        SettingsManager.shared.isPNGSupportEnabled = true
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 2, "Should have JPEG and PNG files")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertTrue(fileListManager.fileURLs.contains(pngFile), "Should contain PNG file when enabled")
        XCTAssertFalse(fileListManager.fileURLs.contains(txtFile), "Should not contain TXT file")
    }
    
    func testLoadFilesExcludesPNGWhenDisabled() {
        // Create files with different extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let pngFile = tempDirectory.appendingPathComponent("test.png")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: pngFile, atomically: true, encoding: .utf8)
        
        // Disable PNG support
        SettingsManager.shared.isPNGSupportEnabled = false
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 1, "Should only have JPEG file")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertFalse(fileListManager.fileURLs.contains(pngFile), "Should not contain PNG file when disabled")
    }
    
    func testLoadFilesFiltersWebPWhenDisabled() {
        // Create files with different extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let webpFile = tempDirectory.appendingPathComponent("test.webp")
        let txtFile = tempDirectory.appendingPathComponent("test.txt")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: webpFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: txtFile, atomically: true, encoding: .utf8)
        
        // Ensure WebP support is disabled
        SettingsManager.shared.isWebPSupportEnabled = false
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 1, "Should only have JPEG file")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertFalse(fileListManager.fileURLs.contains(webpFile), "Should not contain WebP file when disabled")
        XCTAssertFalse(fileListManager.fileURLs.contains(txtFile), "Should not contain TXT file")
    }
    
    func testLoadFilesIncludesWebPWhenEnabled() {
        // Create files with different extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let webpFile = tempDirectory.appendingPathComponent("test.webp")
        let txtFile = tempDirectory.appendingPathComponent("test.txt")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: webpFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: txtFile, atomically: true, encoding: .utf8)
        
        // Enable WebP support
        SettingsManager.shared.isWebPSupportEnabled = true
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 2, "Should have JPEG and WebP files")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertTrue(fileListManager.fileURLs.contains(webpFile), "Should contain WebP file when enabled")
        XCTAssertFalse(fileListManager.fileURLs.contains(txtFile), "Should not contain TXT file")
    }
    
    func testLoadFilesExcludesWebPWhenDisabled() {
        // Create files with different extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let webpFile = tempDirectory.appendingPathComponent("test.webp")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: webpFile, atomically: true, encoding: .utf8)
        
        // Disable WebP support
        SettingsManager.shared.isWebPSupportEnabled = false
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 1, "Should only have JPEG file")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertFalse(fileListManager.fileURLs.contains(webpFile), "Should not contain WebP file when disabled")
    }
    
    func testLoadFilesWithPNGAndWebPWhenBothEnabled() {
        // Create files with different extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let pngFile = tempDirectory.appendingPathComponent("test.png")
        let webpFile = tempDirectory.appendingPathComponent("test.webp")
        let txtFile = tempDirectory.appendingPathComponent("test.txt")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: pngFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: webpFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: txtFile, atomically: true, encoding: .utf8)
        
        // Enable both PNG and WebP support
        SettingsManager.shared.isPNGSupportEnabled = true
        SettingsManager.shared.isWebPSupportEnabled = true
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 3, "Should have JPEG, PNG, and WebP files")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertTrue(fileListManager.fileURLs.contains(pngFile), "Should contain PNG file when enabled")
        XCTAssertTrue(fileListManager.fileURLs.contains(webpFile), "Should contain WebP file when enabled")
        XCTAssertFalse(fileListManager.fileURLs.contains(txtFile), "Should not contain TXT file")
    }
    
    func testLoadFilesModularFormatSupport() {
        // Create files with different extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let pngFile = tempDirectory.appendingPathComponent("test.png")
        let webpFile = tempDirectory.appendingPathComponent("test.webp")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: pngFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: webpFile, atomically: true, encoding: .utf8)
        
        // Enable PNG but disable WebP
        SettingsManager.shared.isPNGSupportEnabled = true
        SettingsManager.shared.isWebPSupportEnabled = false
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 2, "Should have JPEG and PNG files")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertTrue(fileListManager.fileURLs.contains(pngFile), "Should contain PNG file when enabled")
        XCTAssertFalse(fileListManager.fileURLs.contains(webpFile), "Should not contain WebP file when disabled")
        
        // Now enable WebP but disable PNG
        SettingsManager.shared.isPNGSupportEnabled = false
        SettingsManager.shared.isWebPSupportEnabled = true
        
        let success2 = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success2, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 2, "Should have JPEG and WebP files")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertFalse(fileListManager.fileURLs.contains(pngFile), "Should not contain PNG file when disabled")
        XCTAssertTrue(fileListManager.fileURLs.contains(webpFile), "Should contain WebP file when enabled")
    }
    
    func testLoadFilesSortsAlphabetically() {
        // Create files in non-alphabetical order
        let fileZ = tempDirectory.appendingPathComponent("z.jpg")
        let fileA = tempDirectory.appendingPathComponent("a.jpg")
        let fileM = tempDirectory.appendingPathComponent("m.jpg")
        
        try? "test data".write(to: fileZ, atomically: true, encoding: .utf8)
        try? "test data".write(to: fileA, atomically: true, encoding: .utf8)
        try? "test data".write(to: fileM, atomically: true, encoding: .utf8)
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: fileM)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 3, "Should have three files")
        XCTAssertEqual(fileListManager.fileURLs[0].lastPathComponent, "a.jpg", "First file should be a.jpg")
        XCTAssertEqual(fileListManager.fileURLs[1].lastPathComponent, "m.jpg", "Second file should be m.jpg")
        XCTAssertEqual(fileListManager.currentIndex, 1, "Current index should be 1 (m.jpg)")
    }
    
    func testMoveToNext() {
        // Create multiple test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        fileListManager.loadFiles(fromDirectoryContaining: file1)
        
        // Move to next
        let nextURL = fileListManager.moveToNext()
        
        XCTAssertEqual(nextURL, file2, "Should return file2")
        XCTAssertEqual(fileListManager.currentIndex, 1, "Current index should be 1")
        XCTAssertEqual(fileListManager.currentFileURL, file2, "Current file should be file2")
        XCTAssertTrue(fileListManager.hasPrevious, "Should have previous file")
        XCTAssertTrue(fileListManager.hasNext, "Should have next file")
        
        // Move to next again
        let nextURL2 = fileListManager.moveToNext()
        
        XCTAssertEqual(nextURL2, file3, "Should return file3")
        XCTAssertEqual(fileListManager.currentIndex, 2, "Current index should be 2")
        XCTAssertEqual(fileListManager.currentFileURL, file3, "Current file should be file3")
        XCTAssertTrue(fileListManager.hasPrevious, "Should have previous file")
        XCTAssertFalse(fileListManager.hasNext, "Should not have next file")
        
        // Try to move beyond last file - should loop to first
        let nextURL3 = fileListManager.moveToNext()
        
        XCTAssertNotNil(nextURL3, "Should loop to first file instead of returning nil")
        XCTAssertEqual(nextURL3, file1, "Should return file1 (looped)")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0 (looped to start)")
    }
    
    func testMoveToPrevious() {
        // Create multiple test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        fileListManager.loadFiles(fromDirectoryContaining: file3)
        
        // Move to previous
        let previousURL = fileListManager.moveToPrevious()
        
        XCTAssertEqual(previousURL, file2, "Should return file2")
        XCTAssertEqual(fileListManager.currentIndex, 1, "Current index should be 1")
        XCTAssertEqual(fileListManager.currentFileURL, file2, "Current file should be file2")
        XCTAssertTrue(fileListManager.hasPrevious, "Should have previous file")
        XCTAssertTrue(fileListManager.hasNext, "Should have next file")
        
        // Move to previous again
        let previousURL2 = fileListManager.moveToPrevious()
        
        XCTAssertEqual(previousURL2, file1, "Should return file1")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0")
        XCTAssertEqual(fileListManager.currentFileURL, file1, "Current file should be file1")
        XCTAssertFalse(fileListManager.hasPrevious, "Should not have previous file")
        XCTAssertTrue(fileListManager.hasNext, "Should have next file")
        
        // Try to move before first file - should loop to last
        let previousURL3 = fileListManager.moveToPrevious()
        
        XCTAssertNotNil(previousURL3, "Should loop to last file instead of returning nil")
        XCTAssertEqual(previousURL3, file3, "Should return file3 (looped)")
        XCTAssertEqual(fileListManager.currentIndex, 2, "Current index should be 2 (looped to end)")
    }
    
    func testReset() {
        // Create a test file
        let testFile = tempDirectory.appendingPathComponent("test.jpg")
        try? "test data".write(to: testFile, atomically: true, encoding: .utf8)
        
        fileListManager.loadFiles(fromDirectoryContaining: testFile)
        
        XCTAssertEqual(fileListManager.fileURLs.count, 1, "Should have one file")
        
        fileListManager.reset()
        
        XCTAssertEqual(fileListManager.fileURLs.count, 0, "File list should be empty after reset")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0 after reset")
        XCTAssertNil(fileListManager.currentFileURL, "Current file URL should be nil after reset")
    }
    
    func testLoadFilesWithNonexistentFile() {
        let nonexistentFile = tempDirectory.appendingPathComponent("nonexistent.jpg")
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: nonexistentFile)
        
        // Should still succeed (directory exists), but file won't be in list
        XCTAssertTrue(success, "Should succeed even if file doesn't exist")
        XCTAssertEqual(fileListManager.fileURLs.count, 0, "Should have no files")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0")
    }
    
    func testLoadFilesWithJPEGExtension() {
        // Test both .jpg and .jpeg extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let jpegFile = tempDirectory.appendingPathComponent("test.jpeg")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: jpegFile, atomically: true, encoding: .utf8)
        
        let success = fileListManager.loadFiles(fromDirectoryContaining: jpgFile)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 2, "Should have both JPEG files")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain .jpg file")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpegFile), "Should contain .jpeg file")
    }
    
    func testLoopingFromLastToFirst() {
        // Create multiple test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        fileListManager.loadFiles(fromDirectoryContaining: file3)
        
        // Should be at last file (index 2)
        XCTAssertEqual(fileListManager.currentIndex, 2, "Should start at last file")
        
        // Move to next - should loop to first
        let nextURL = fileListManager.moveToNext()
        
        XCTAssertNotNil(nextURL, "Should not return nil")
        XCTAssertEqual(nextURL, file1, "Should loop to first file")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0")
    }
    
    func testLoopingFromFirstToLast() {
        // Create multiple test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        fileListManager.loadFiles(fromDirectoryContaining: file1)
        
        // Should be at first file (index 0)
        XCTAssertEqual(fileListManager.currentIndex, 0, "Should start at first file")
        
        // Move to previous - should loop to last
        let previousURL = fileListManager.moveToPrevious()
        
        XCTAssertNotNil(previousURL, "Should not return nil")
        XCTAssertEqual(previousURL, file3, "Should loop to last file")
        XCTAssertEqual(fileListManager.currentIndex, 2, "Current index should be 2")
    }
    
    func testLoopingWithSingleFile() {
        // Create a single test file
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        
        fileListManager.loadFiles(fromDirectoryContaining: file1)
        
        // Should be at index 0
        XCTAssertEqual(fileListManager.currentIndex, 0, "Should be at index 0")
        
        // Move to next - should stay at same file (looping)
        let nextURL = fileListManager.moveToNext()
        
        XCTAssertNotNil(nextURL, "Should not return nil")
        XCTAssertEqual(nextURL, file1, "Should return same file")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should still be 0")
        
        // Move to previous - should stay at same file (looping)
        let previousURL = fileListManager.moveToPrevious()
        
        XCTAssertNotNil(previousURL, "Should not return nil")
        XCTAssertEqual(previousURL, file1, "Should return same file")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should still be 0")
    }
    
    func testLoopingWithEmptyList() {
        // Don't load any files
        fileListManager.reset()
        
        XCTAssertEqual(fileListManager.fileURLs.count, 0, "Should have no files")
        
        // Move to next - should return nil
        let nextURL = fileListManager.moveToNext()
        
        XCTAssertNil(nextURL, "Should return nil when list is empty")
        
        // Move to previous - should return nil
        let previousURL = fileListManager.moveToPrevious()
        
        XCTAssertNil(previousURL, "Should return nil when list is empty")
    }
    
    func testReloadFilesFromDirectory() {
        // Create multiple test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        // Load files initially
        fileListManager.loadFiles(fromDirectoryContaining: file2)
        XCTAssertEqual(fileListManager.fileURLs.count, 3, "Should have three files")
        XCTAssertEqual(fileListManager.currentIndex, 1, "Current index should be 1")
        
        // Reload from directory - should reset index to 0
        let success = fileListManager.reloadFiles(fromDirectory: tempDirectory)
        
        XCTAssertTrue(success, "Should successfully reload files")
        XCTAssertEqual(fileListManager.fileURLs.count, 3, "Should still have three files")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be reset to 0")
        XCTAssertTrue(fileListManager.fileURLs.contains(file1), "Should contain file1")
        XCTAssertTrue(fileListManager.fileURLs.contains(file2), "Should contain file2")
        XCTAssertTrue(fileListManager.fileURLs.contains(file3), "Should contain file3")
    }
    
    func testReloadFilesFromEmptyDirectory() {
        // Reload from empty directory
        let success = fileListManager.reloadFiles(fromDirectory: tempDirectory)
        
        XCTAssertTrue(success, "Should successfully reload files")
        XCTAssertEqual(fileListManager.fileURLs.count, 0, "Should have no files")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0")
    }
    
    func testReloadFilesFiltersUnsupportedFormats() {
        // Create files with different extensions
        let jpgFile = tempDirectory.appendingPathComponent("test.jpg")
        let pngFile = tempDirectory.appendingPathComponent("test.png")
        let txtFile = tempDirectory.appendingPathComponent("test.txt")
        
        try? "test data".write(to: jpgFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: pngFile, atomically: true, encoding: .utf8)
        try? "test data".write(to: txtFile, atomically: true, encoding: .utf8)
        
        // Disable PNG support
        SettingsManager.shared.isPNGSupportEnabled = false
        
        // Reload from directory
        let success = fileListManager.reloadFiles(fromDirectory: tempDirectory)
        
        XCTAssertTrue(success, "Should successfully reload files")
        XCTAssertEqual(fileListManager.fileURLs.count, 1, "Should only have JPEG file")
        XCTAssertTrue(fileListManager.fileURLs.contains(jpgFile), "Should contain JPEG file")
        XCTAssertFalse(fileListManager.fileURLs.contains(pngFile), "Should not contain PNG file when disabled")
        XCTAssertFalse(fileListManager.fileURLs.contains(txtFile), "Should not contain TXT file")
    }
    
    /// Test that verifies navigation works after loading the first file
    /// This test addresses the issue where arrow keys don't work when opening the first image
    func testNavigationAfterLoadingFirstFile() {
        // Create multiple test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        // Load files starting from the first file (simulating first image open)
        let success = fileListManager.loadFiles(fromDirectoryContaining: file1)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 3, "Should have three files")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0 (first file)")
        XCTAssertEqual(fileListManager.currentFileURL, file1, "Current file should be file1")
        
        // Verify navigation works - move to next
        let nextURL = fileListManager.moveToNext()
        XCTAssertNotNil(nextURL, "Should be able to navigate to next file")
        XCTAssertEqual(nextURL, file2, "Next file should be file2")
        XCTAssertEqual(fileListManager.currentIndex, 1, "Current index should be 1")
        XCTAssertTrue(fileListManager.hasPrevious, "Should have previous file")
        XCTAssertTrue(fileListManager.hasNext, "Should have next file")
        
        // Verify navigation works - move to previous
        let previousURL = fileListManager.moveToPrevious()
        XCTAssertNotNil(previousURL, "Should be able to navigate to previous file")
        XCTAssertEqual(previousURL, file1, "Previous file should be file1")
        XCTAssertEqual(fileListManager.currentIndex, 0, "Current index should be 0")
        XCTAssertFalse(fileListManager.hasPrevious, "Should not have previous file (at first)")
        XCTAssertTrue(fileListManager.hasNext, "Should have next file")
    }
    
    /// Test that verifies file list is populated even when loading from middle file
    func testFileListPopulatedWhenLoadingMiddleFile() {
        // Create multiple test files
        let file1 = tempDirectory.appendingPathComponent("a.jpg")
        let file2 = tempDirectory.appendingPathComponent("b.jpg")
        let file3 = tempDirectory.appendingPathComponent("c.jpg")
        
        try? "test data".write(to: file1, atomically: true, encoding: .utf8)
        try? "test data".write(to: file2, atomically: true, encoding: .utf8)
        try? "test data".write(to: file3, atomically: true, encoding: .utf8)
        
        // Load files starting from the middle file
        let success = fileListManager.loadFiles(fromDirectoryContaining: file2)
        
        XCTAssertTrue(success, "Should successfully load files")
        XCTAssertEqual(fileListManager.fileURLs.count, 3, "Should have three files")
        XCTAssertEqual(fileListManager.currentIndex, 1, "Current index should be 1 (middle file)")
        XCTAssertEqual(fileListManager.currentFileURL, file2, "Current file should be file2")
        
        // Verify both directions work
        XCTAssertTrue(fileListManager.hasPrevious, "Should have previous file")
        XCTAssertTrue(fileListManager.hasNext, "Should have next file")
        
        // Test navigation in both directions
        let nextURL = fileListManager.moveToNext()
        XCTAssertEqual(nextURL, file3, "Next file should be file3")
        
        let previousURL = fileListManager.moveToPrevious()
        XCTAssertEqual(previousURL, file2, "Previous file should be file2")
        
        let previousURL2 = fileListManager.moveToPrevious()
        XCTAssertEqual(previousURL2, file1, "Previous file should be file1")
    }
}







