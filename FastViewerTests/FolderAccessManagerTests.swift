//
//  FolderAccessManagerTests.swift
//  FastViewerTests
//
//  Created by Alexander Deplov on 23.12.25.
//
//  Tests for FolderAccessManager functionality

import XCTest
@testable import FastViewer_Lite

final class FolderAccessManagerTests: XCTestCase {
    
    var sut: FolderAccessManager!
    var tempDirectory: URL!
    var tempFile: URL!
    
    override func setUp() {
        super.setUp()
        sut = FolderAccessManager.shared
        
        // Create a temporary directory for testing
        let tempPath = NSTemporaryDirectory()
        tempDirectory = URL(fileURLWithPath: tempPath)
            .appendingPathComponent("FolderAccessManagerTests_\(UUID().uuidString)")
        
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Create a test file in the temp directory
        tempFile = tempDirectory.appendingPathComponent("test_image.jpg")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(), attributes: nil)
    }
    
    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        sut.clearAccessCache()
        super.tearDown()
    }
    
    // MARK: - Singleton Tests
    
    func testSharedInstanceExists() {
        // Then
        XCTAssertNotNil(FolderAccessManager.shared)
    }
    
    func testSharedInstanceIsSingleton() {
        // Given
        let instance1 = FolderAccessManager.shared
        let instance2 = FolderAccessManager.shared
        
        // Then
        XCTAssertTrue(instance1 === instance2, "Shared instance should be singleton")
    }
    
    // MARK: - hasAccessToDirectory Tests
    
    func testHasAccessToDirectoryReturnsTrueForTempDirectory() {
        // Given - temp directory created in setUp
        
        // When
        let hasAccess = sut.hasAccessToDirectory(tempDirectory)
        
        // Then
        XCTAssertTrue(hasAccess, "Should have access to temp directory")
    }
    
    func testHasAccessToDirectoryContainingFile() {
        // Given - temp file created in setUp
        
        // When
        let hasAccess = sut.hasAccessToDirectory(containing: tempFile)
        
        // Then
        XCTAssertTrue(hasAccess, "Should have access to directory containing temp file")
    }
    
    func testHasAccessToDirectoryCachesResult() {
        // Given
        _ = sut.hasAccessToDirectory(tempDirectory) // First call
        
        // When - Second call should use cache
        let hasAccess = sut.hasAccessToDirectory(tempDirectory)
        
        // Then
        XCTAssertTrue(hasAccess, "Cached result should be true")
    }
    
    func testHasAccessToDirectoryReturnsFalseForNonExistentDirectory() {
        // Given
        let nonExistentDir = URL(fileURLWithPath: "/nonexistent_directory_12345")
        
        // When
        let hasAccess = sut.hasAccessToDirectory(nonExistentDir)
        
        // Then
        XCTAssertFalse(hasAccess, "Should not have access to non-existent directory")
    }
    
    // MARK: - clearAccessCache Tests
    
    func testClearAccessCacheClearsCache() {
        // Given
        _ = sut.hasAccessToDirectory(tempDirectory) // Populate cache
        
        // When
        sut.clearAccessCache()
        
        // Then - directory should still be accessible, but cache is cleared
        // We can't easily test the internal state, but we can verify the method doesn't crash
        // and the access check still works
        XCTAssertTrue(sut.hasAccessToDirectory(tempDirectory))
    }
    
    // MARK: - accessDirectory Tests
    
    func testAccessDirectoryWithExistingAccess() {
        // Given
        let expectation = XCTestExpectation(description: "Access directory completion called")
        
        // When
        sut.accessDirectory(tempDirectory, requestIfNeeded: false) { granted in
            // Then
            XCTAssertTrue(granted, "Should be granted for accessible directory")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testAccessDirectoryWithoutRequestForInaccessible() {
        // Given
        let inaccessibleDir = URL(fileURLWithPath: "/nonexistent_directory_12345")
        let expectation = XCTestExpectation(description: "Access directory completion called")
        
        // When
        sut.accessDirectory(inaccessibleDir, requestIfNeeded: false) { granted in
            // Then
            XCTAssertFalse(granted, "Should not be granted for inaccessible directory without request")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Directory Path Tests
    
    func testDeleteLastPathComponentGetsCorrectDirectory() {
        // Given
        let fileURL = URL(fileURLWithPath: "/Users/test/Documents/image.jpg")
        
        // When
        let directoryURL = fileURL.deletingLastPathComponent()
        
        // Then
        XCTAssertEqual(directoryURL.path, "/Users/test/Documents")
    }
    
    func testMultipleFilesInSameDirectoryShareAccess() {
        // Given
        let file1 = tempDirectory.appendingPathComponent("image1.jpg")
        let file2 = tempDirectory.appendingPathComponent("image2.jpg")
        FileManager.default.createFile(atPath: file1.path, contents: Data(), attributes: nil)
        FileManager.default.createFile(atPath: file2.path, contents: Data(), attributes: nil)
        
        // When
        let hasAccess1 = sut.hasAccessToDirectory(containing: file1)
        let hasAccess2 = sut.hasAccessToDirectory(containing: file2)
        
        // Then
        XCTAssertTrue(hasAccess1, "Should have access for file1's directory")
        XCTAssertTrue(hasAccess2, "Should have access for file2's directory (same as file1)")
    }
}



