//
//  ImageProcessingProtocol.swift
//  FastViewer
//
//  XPC Protocol for image processing operations
//  This protocol defines the interface between the main app and the XPC service
//

import Foundation

/// Protocol defining the XPC service interface for image processing operations
/// The main app communicates with the XPC service through this protocol
@objc protocol ImageProcessingProtocol {
    
    /// Loads an image from a file URL and returns it as Data
    /// - Parameters:
    ///   - fileURL: URL to the image file
    ///   - maxSize: Maximum pixel dimension for the image
    ///   - reply: Completion handler with image data (NSData from NSImage.tiffRepresentation)
    func loadImage(from fileURL: URL, maxSize: Int, reply: @escaping (Data?) -> Void)
    
    /// Loads an image asynchronously and caches it
    /// - Parameters:
    ///   - fileURL: URL to the image file
    ///   - maxSize: Maximum pixel dimension
    ///   - reply: Completion handler with image data
    func loadImageAsync(from fileURL: URL, maxSize: Int, reply: @escaping (Data?) -> Void)
    
    /// Calculates the average color of an image
    /// - Parameters:
    ///   - fileURL: URL to the image file
    ///   - reply: Completion handler with color data (archived NSColor)
    func calculateAverageColor(for fileURL: URL, reply: @escaping (Data?) -> Void)
    
    /// Prefetches images around the current index for fast navigation
    /// - Parameters:
    ///   - fileURLs: Array of all file URLs
    ///   - currentIndex: Current file index
    ///   - prefetchBefore: Number of files to prefetch before current
    ///   - prefetchAfter: Number of files to prefetch after current
    func prefetchImages(fileURLs: [URL], currentIndex: Int, prefetchBefore: Int, prefetchAfter: Int)
    
    /// Clears the image cache
    func clearCache()
    
    /// Gets cache statistics
    /// - Parameter reply: Completion handler with cache info (count, memory usage)
    func getCacheStats(reply: @escaping ([String: Any]) -> Void)
}
