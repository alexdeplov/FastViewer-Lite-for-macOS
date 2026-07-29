//
//  XPCImageLoader.swift
//  FastViewer
//
//  XPC Client wrapper for image loading operations
//  This class communicates with the XPC service to leverage persistent image processing
//

import Foundation
import Cocoa

/// XPC Client that communicates with the FastViewerService for image processing
/// Maintains same API as ImageLoader for backward compatibility
class XPCImageLoader {
    
    /// Shared instance
    static let shared = XPCImageLoader()
    
    /// XPC connection to the service
    private var connection: NSXPCConnection?
    
    /// Lock for thread-safe connection access
    private let connectionLock = NSLock()
    
    private init() {
        setupConnection()
    }
    
    deinit {
        connection?.invalidate()
    }
    
    /// Sets up the XPC connection to the service
    private func setupConnection() {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        
        // Create connection to the XPC service
        let newConnection = NSXPCConnection(serviceName: "com.pleeg.FastViewer.FastViewerService")
        
        // Set up the interface
        newConnection.remoteObjectInterface = NSXPCInterface(with: ImageProcessingProtocol.self)
        
        // Set up interruption and invalidation handlers
        newConnection.interruptionHandler = { [weak self] in
            print("⚠️ XPC connection interrupted - will reconnect")
            self?.setupConnection()
        }
        
        newConnection.invalidationHandler = {
            print("❌ XPC connection invalidated")
        }
        
        // Resume the connection
        newConnection.resume()
        
        self.connection = newConnection
        
        print("🔗 XPC connection established to FastViewerService")
    }
    
    /// Gets the remote proxy object for the service
    private func getRemoteProxy() -> ImageProcessingProtocol? {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        
        guard let connection = connection else {
            print("❌ No XPC connection available")
            return nil
        }
        
        return connection.remoteObjectProxyWithErrorHandler { error in
            print("❌ XPC Error: \(error)")
        } as? ImageProcessingProtocol
    }
    
    // MARK: - Public API (Compatible with ImageLoader)
    
    /// Loads an image from a file URL
    /// - Parameters:
    ///   - fileURL: URL to the image file
    ///   - maxSize: Maximum pixel dimension for thumbnail
    /// - Returns: NSImage if successful, nil otherwise
    func loadImage(from fileURL: URL, maxSize: Int = 4000) -> NSImage? {
        // Use semaphore for synchronous operation
        let semaphore = DispatchSemaphore(value: 0)
        var resultImage: NSImage?
        
        guard let proxy = getRemoteProxy() else {
            print("❌ Failed to get XPC proxy")
            return nil
        }
        
        proxy.loadImage(from: fileURL, maxSize: maxSize) { imageData in
            if let data = imageData {
                resultImage = NSImage(data: data)
            }
            semaphore.signal()
        }
        
        // Wait for response (with timeout)
        let timeout = DispatchTime.now() + .seconds(10)
        if semaphore.wait(timeout: timeout) == .timedOut {
            print("⏱️ XPC call timed out for \(fileURL.lastPathComponent)")
            return nil
        }
        
        return resultImage
    }
    
    /// Loads an image from a file path
    func loadImage(from filePath: String, maxSize: Int = 4000) -> NSImage? {
        let fileURL = URL(fileURLWithPath: filePath)
        return loadImage(from: fileURL, maxSize: maxSize)
    }
    
    /// Loads an image asynchronously
    /// - Parameters:
    ///   - fileURL: URL to the image file
    ///   - maxSize: Maximum pixel dimension
    ///   - completion: Completion handler with NSImage or nil
    func loadImageAsync(from fileURL: URL, maxSize: Int = 4000, completion: @escaping (NSImage?) -> Void) {
        guard let proxy = getRemoteProxy() else {
            print("❌ Failed to get XPC proxy")
            completion(nil)
            return
        }
        
        proxy.loadImageAsync(from: fileURL, maxSize: maxSize) { imageData in
            DispatchQueue.main.async {
                if let data = imageData {
                    completion(NSImage(data: data))
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    /// Loads an image asynchronously from file path
    func loadImageAsync(from filePath: String, maxSize: Int = 4000, completion: @escaping (NSImage?) -> Void) {
        let fileURL = URL(fileURLWithPath: filePath)
        loadImageAsync(from: fileURL, maxSize: maxSize, completion: completion)
    }
    
    /// Calculates the average color of an image
    /// - Parameter fileURL: URL to the image file
    /// - Returns: The average color as NSColor, or nil if calculation fails
    func calculateAverageColor(for fileURL: URL) -> NSColor? {
        let semaphore = DispatchSemaphore(value: 0)
        var resultColor: NSColor?
        
        guard let proxy = getRemoteProxy() else {
            print("❌ Failed to get XPC proxy")
            return nil
        }
        
        proxy.calculateAverageColor(for: fileURL) { colorData in
            if let data = colorData,
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                resultColor = color
            }
            semaphore.signal()
        }
        
        let timeout = DispatchTime.now() + .seconds(5)
        if semaphore.wait(timeout: timeout) == .timedOut {
            print("⏱️ XPC color calculation timed out")
            return nil
        }
        
        return resultColor
    }
    
    /// Prefetches images around the current index
    /// - Parameters:
    ///   - fileURLs: Array of all file URLs
    ///   - currentIndex: Current file index
    ///   - prefetchBefore: Number of files to prefetch before
    ///   - prefetchAfter: Number of files to prefetch after
    func prefetchImages(fileURLs: [URL], currentIndex: Int, prefetchBefore: Int = 2, prefetchAfter: Int = 20) {
        guard let proxy = getRemoteProxy() else {
            print("❌ Failed to get XPC proxy for prefetch")
            return
        }
        
        proxy.prefetchImages(fileURLs: fileURLs, currentIndex: currentIndex, 
                           prefetchBefore: prefetchBefore, prefetchAfter: prefetchAfter)
    }
    
    /// Clears the image cache
    func clearCache() {
        guard let proxy = getRemoteProxy() else {
            print("❌ Failed to get XPC proxy for cache clear")
            return
        }
        
        proxy.clearCache()
    }
    
    /// Gets cache statistics
    func getCacheStats(completion: @escaping ([String: Any]) -> Void) {
        guard let proxy = getRemoteProxy() else {
            print("❌ Failed to get XPC proxy for stats")
            completion([:])
            return
        }
        
        proxy.getCacheStats { stats in
            DispatchQueue.main.async {
                completion(stats)
            }
        }
    }
}
