//
//  ImageProcessingService.swift
//  FastViewerService
//
//  XPC Service implementation for image processing
//  This service stays resident in memory to provide fast image loading
//

import Foundation
import Cocoa
import CoreImage
import ImageIO

/// XPC Service that handles image processing operations
/// This service stays in memory even after the main app quits, enabling faster subsequent launches
class ImageProcessingService: NSObject, ImageProcessingProtocol {
    
    /// Cache for prefetched images - stays in memory across app launches
    private let imageCache: NSCache<NSURL, NSImage>
    
    /// Cache for average colors
    private let averageColorCache: NSCache<NSURL, NSColor>
    
    /// Reused CIContext for optimal performance
    private let ciContext: CIContext
    
    /// Operation queue for prefetching
    private let prefetchQueue: OperationQueue
    
    /// Serial queue for cache synchronization
    private let prefetchSyncQueue: DispatchSerialQueue
    
    /// Track last prefetch request to avoid duplicates
    private var lastPrefetchIndex: Int?
    private var lastPrefetchURLs: [URL]?
    
    /// Maximum cache size
    private let maxCacheCount = 200
    
    override init() {
        // Initialize cache with count and memory limits
        imageCache = NSCache<NSURL, NSImage>()
        imageCache.countLimit = maxCacheCount
        imageCache.totalCostLimit = 500 * 1024 * 1024 // 500MB
        
        averageColorCache = NSCache<NSURL, NSColor>()
        averageColorCache.countLimit = maxCacheCount
        
        // Initialize CIContext for GPU-accelerated operations
        ciContext = CIContext(options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .useSoftwareRenderer: false
        ])
        
        // Initialize prefetch queue
        prefetchQueue = OperationQueue()
        prefetchQueue.maxConcurrentOperationCount = 4
        prefetchQueue.qualityOfService = .utility
        
        prefetchSyncQueue = DispatchQueue(label: "com.pleeg.FastViewer.ImageProcessingService.prefetch")
        
        super.init()
        
        print("🚀 FastViewer XPC Service initialized - Image processing core is now resident in memory")
    }
    
    // MARK: - ImageProcessingProtocol Implementation
    
    func loadImage(from fileURL: URL, maxSize: Int, reply: @escaping (Data?) -> Void) {
        // Check cache first
        if let cachedImage = imageCache.object(forKey: fileURL as NSURL) {
            reply(cachedImage.tiffRepresentation)
            return
        }
        
        // Load image using optimized CGImageSource
        guard let image = loadImageInternal(from: fileURL, maxSize: maxSize) else {
            reply(nil)
            return
        }
        
        // Cache the loaded image
        imageCache.setObject(image, forKey: fileURL as NSURL)
        
        // Return as data
        reply(image.tiffRepresentation)
    }
    
    func loadImageAsync(from fileURL: URL, maxSize: Int, reply: @escaping (Data?) -> Void) {
        // Check cache first for instant response
        if let cachedImage = imageCache.object(forKey: fileURL as NSURL) {
            reply(cachedImage.tiffRepresentation)
            return
        }
        
        // Load asynchronously
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                reply(nil)
                return
            }
            
            guard let image = self.loadImageInternal(from: fileURL, maxSize: maxSize) else {
                reply(nil)
                return
            }
            
            // Cache the loaded image
            self.imageCache.setObject(image, forKey: fileURL as NSURL)
            
            reply(image.tiffRepresentation)
        }
    }
    
    func calculateAverageColor(for fileURL: URL, reply: @escaping (Data?) -> Void) {
        // Check cache first
        if let cachedColor = averageColorCache.object(forKey: fileURL as NSURL) {
            if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: cachedColor, requiringSecureCoding: false) {
                reply(colorData)
                return
            }
        }
        
        // Access security-scoped resource
        let didStartAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Load image first
        guard let image = loadImageInternal(from: fileURL, maxSize: 4000) else {
            reply(nil)
            return
        }
        
        // Calculate average color
        guard let color = calculateAverageColorInternal(of: image) else {
            reply(nil)
            return
        }
        
        // Cache the color
        averageColorCache.setObject(color, forKey: fileURL as NSURL)
        
        // Archive and return
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            reply(colorData)
        } else {
            reply(nil)
        }
    }
    
    func prefetchImages(fileURLs: [URL], currentIndex: Int, prefetchBefore: Int, prefetchAfter: Int) {
        // Check for duplicate requests
        prefetchSyncQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Skip if same request
            if self.lastPrefetchIndex == currentIndex && self.lastPrefetchURLs == fileURLs {
                return
            }
            
            self.lastPrefetchIndex = currentIndex
            self.lastPrefetchURLs = fileURLs
            
            // Cancel existing operations
            self.prefetchQueue.cancelAllOperations()
            
            // Determine which files to prefetch
            var indicesToPrefetch: [Int] = []
            
            for offset in 1...max(prefetchBefore, prefetchAfter) {
                // Files before current
                if offset <= prefetchBefore {
                    let beforeIndex = currentIndex - offset
                    if beforeIndex >= 0 && beforeIndex < fileURLs.count {
                        if self.imageCache.object(forKey: fileURLs[beforeIndex] as NSURL) == nil {
                            indicesToPrefetch.append(beforeIndex)
                        }
                    }
                }
                
                // Files after current
                if offset <= prefetchAfter {
                    let afterIndex = currentIndex + offset
                    if afterIndex >= 0 && afterIndex < fileURLs.count {
                        if self.imageCache.object(forKey: fileURLs[afterIndex] as NSURL) == nil {
                            indicesToPrefetch.append(afterIndex)
                        }
                    }
                }
            }
            
            // Sort by distance from current (closest first)
            indicesToPrefetch.sort { abs($0 - currentIndex) < abs($1 - currentIndex) }
            
            // Create prefetch operations
            for index in indicesToPrefetch {
                let fileURL = fileURLs[index]
                let distance = abs(index - currentIndex)
                
                let operation = BlockOperation { [weak self] in
                    guard let self = self else { return }
                    
                    // Load image
                    if let image = self.loadImageInternal(from: fileURL, maxSize: 4000) {
                        self.imageCache.setObject(image, forKey: fileURL as NSURL)
                    }
                }
                
                // Set QoS based on distance
                if distance <= 2 {
                    operation.qualityOfService = .userInitiated
                } else if distance <= 5 {
                    operation.qualityOfService = .default
                } else {
                    operation.qualityOfService = .utility
                }
                
                self.prefetchQueue.addOperation(operation)
            }
        }
    }
    
    func clearCache() {
        imageCache.removeAllObjects()
        averageColorCache.removeAllObjects()
        prefetchQueue.cancelAllOperations()
        
        prefetchSyncQueue.async { [weak self] in
            self?.lastPrefetchIndex = nil
            self?.lastPrefetchURLs = nil
        }
        
        print("🗑️ XPC Service cache cleared")
    }
    
    func getCacheStats(reply: @escaping ([String: Any]) -> Void) {
        let stats: [String: Any] = [
            "cacheCount": imageCache.countLimit,
            "memoryCostLimit": imageCache.totalCostLimit,
            "prefetchQueueOperations": prefetchQueue.operationCount
        ]
        reply(stats)
    }
    
    // MARK: - Internal Image Loading
    
    /// Internal method to load image from URL using CGImageSource
    private func loadImageInternal(from fileURL: URL, maxSize: Int) -> NSImage? {
        return autoreleasepool {
            // Try to access security-scoped resource
            let didStartAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // Create image source
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                return nil
            }
            
            // Configure thumbnail options
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize
            ]
            
            // Create thumbnail
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                return nil
            }
            
            return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        }
    }
    
    /// Internal method to calculate average color
    private func calculateAverageColorInternal(of image: NSImage) -> NSColor? {
        return autoreleasepool {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            
            let inputImage = CIImage(cgImage: cgImage)
            
            // Apply area average filter
            guard let filter = CIFilter(name: "CIAreaAverage") else {
                return nil
            }
            
            filter.setValue(inputImage, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: 0, y: 0, z: CGFloat(cgImage.width), w: CGFloat(cgImage.height)),
                          forKey: kCIInputExtentKey)
            
            guard let outputImage = filter.outputImage else {
                return nil
            }
            
            // Render to 1x1 pixel
            var bitmapData = [UInt8](repeating: 0, count: 4)
            let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            
            ciContext.render(
                outputImage,
                toBitmap: &bitmapData,
                rowBytes: 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            
            let red = CGFloat(bitmapData[0]) / 255.0
            let green = CGFloat(bitmapData[1]) / 255.0
            let blue = CGFloat(bitmapData[2]) / 255.0
            let alpha = CGFloat(bitmapData[3]) / 255.0
            
            return NSColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    }
}

/// XPC Service delegate that creates and provides the service object
class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure the XPC connection
        newConnection.exportedInterface = NSXPCInterface(with: ImageProcessingProtocol.self)
        newConnection.exportedObject = ImageProcessingService()
        
        newConnection.resume()
        
        print("✅ XPC Service accepted new connection from main app")
        return true
    }
}
