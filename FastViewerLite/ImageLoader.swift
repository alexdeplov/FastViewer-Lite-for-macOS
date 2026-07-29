//
//  ImageLoader.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//
//  Minimum macOS Version: 12.0 (Monterey)
//  - Uses CGImageSource for fast thumbnail generation (performance-critical)
//  - Reuses CIContext instance for optimal performance
//  - Supports JPEG, PNG, WebP, AVIF, and HEIC formats
//  - Native WebP/AVIF support available since macOS 11.0+
//  - Native HEIC support available since macOS 10.13+

import Cocoa
import ImageIO
import CoreGraphics
import CoreImage

/// High-performance image loader using CGImageSource for fast image rendering
/// Supports JPEG, PNG (when enabled), WebP (when enabled), AVIF (when enabled), and HEIC (when enabled) formats
/// CGImageSource handles WebP and AVIF natively on macOS 11+, HEIC natively on macOS 10.13+
/// 
/// Performance optimizations (per PERFORMANCE_GUIDE.md):
/// - Uses CGImageSourceCreateThumbnailAtIndex for fast thumbnail generation
/// - Reuses CIContext instance to avoid creation overhead
/// - Uses autoreleasepool for efficient memory management
class ImageLoader {
    
    /// Shared instance for reusing CIContext
    static let shared = ImageLoader()
    
    /// Reused CIContext for optimal performance
    private let ciContext: CIContext

    /// Shared queue for async image loading requests.
    private let imageLoadingQueue: OperationQueue

    /// In-flight URL loads. Callers requesting the same file version and size share one decode.
    private let inFlightLock = NSLock()
    private var inFlightLoads: [String: InFlightLoad] = [:]

    private final class InFlightLoad {
        let group = DispatchGroup()
        var image: NSImage?

        init() {
            group.enter()
        }
    }
    
    private init() {
        // Create and reuse CIContext instance for optimal performance
        // Using GPU acceleration by default
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: NSNull()
        ])
        self.imageLoadingQueue = OperationQueue()
        self.imageLoadingQueue.name = "com.fastviewer.imageLoading"
        self.imageLoadingQueue.qualityOfService = .userInitiated
        self.imageLoadingQueue.maxConcurrentOperationCount = 2
    }
    
    /// Loads an image from file URL using optimized CGImageSource thumbnail generation
    /// - Parameters:
    ///   - fileURL: URL to the image file
    ///   - maxSize: Maximum pixel dimension for thumbnail (defaults to 4000 for Retina displays)
    /// - Returns: NSImage if successful, nil otherwise
    func loadImage(
        from fileURL: URL,
        maxSize: Int = 4000,
        allowsAnimatedImage: Bool = true,
        shouldCancel: () -> Bool = { false }
    ) -> NSImage? {
        guard !shouldCancel() else { return nil }

        let startedAt = ProcessInfo.processInfo.systemUptime
        PerformanceLog.shared.event(
            "DECODE",
            "begin file=\(fileURL.lastPathComponent) maxSize=\(maxSize) animated=\(allowsAnimatedImage)"
        )
        let loadKey = "\(ImageCacheManager.cacheKey(for: fileURL, maxSize: maxSize))|\(allowsAnimatedImage)"
        inFlightLock.lock()
        if let existingLoad = inFlightLoads[loadKey] {
            inFlightLock.unlock()
            PerformanceLog.shared.event("DECODE", "wait-inflight file=\(fileURL.lastPathComponent)")
            while existingLoad.group.wait(timeout: .now() + .milliseconds(20)) == .timedOut {
                if shouldCancel() {
                    PerformanceLog.shared.event("DECODE", "cancel-wait file=\(fileURL.lastPathComponent)")
                    return nil
                }
            }
            inFlightLock.lock()
            let image = existingLoad.image
            inFlightLock.unlock()
            PerformanceLog.shared.event(
                "DECODE",
                String(
                    format: "reuse-inflight file=%@ duration=%.1fms",
                    fileURL.lastPathComponent,
                    (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                )
            )
            return shouldCancel() ? nil : image
        }

        let newLoad = InFlightLoad()
        inFlightLoads[loadKey] = newLoad
        inFlightLock.unlock()

        let image = loadImageUncoalesced(
            from: fileURL,
            maxSize: maxSize,
            allowsAnimatedImage: allowsAnimatedImage,
            shouldCancel: shouldCancel
        )

        inFlightLock.lock()
        newLoad.image = image
        inFlightLoads.removeValue(forKey: loadKey)
        newLoad.group.leave()
        inFlightLock.unlock()
        PerformanceLog.shared.event(
            "DECODE",
            String(
                format: "end file=%@ success=%d duration=%.1fms",
                fileURL.lastPathComponent,
                image == nil ? 0 : 1,
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
        )
        return image
    }

    private func loadImageUncoalesced(
        from fileURL: URL,
        maxSize: Int,
        allowsAnimatedImage: Bool,
        shouldCancel: () -> Bool
    ) -> NSImage? {
        // Try to access security-scoped resource if needed (for sandboxed apps)
        // Returns true if access was granted, false if not needed or failed
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Let ImageIO read static images directly from the file. Creating Data for
        // every prefetched image copies the complete compressed file into memory and
        // causes visible I/O/decode bursts when the prefetch window reaches a group
        // of large PNG/WebP files.
        return autoreleasepool {
            guard !shouldCancel(),
                  let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                return nil
            }

            // Animated images need their original encoded data so NSImage can retain
            // every frame. Static images stay on the URL-backed fast path.
            if CGImageSourceGetCount(source) > 1 {
                guard allowsAnimatedImage else {
                    return nil
                }
                guard !shouldCancel(),
                      let imageData = try? Data(contentsOf: fileURL),
                      !shouldCancel() else {
                    return nil
                }
                return NSImage(data: imageData)
            }

            return createThumbnail(
                from: source,
                maxSize: maxSize,
                shouldCancel: shouldCancel
            )
        }
    }
    
    /// Loads an image from file path using optimized CGImageSource thumbnail generation
    /// - Parameters:
    ///   - filePath: Path to the image file
    ///   - maxSize: Maximum pixel dimension for thumbnail (defaults to 4000 for Retina displays)
    /// - Returns: NSImage if successful, nil otherwise
    func loadImage(from filePath: String, maxSize: Int = 4000) -> NSImage? {
        let fileURL = URL(fileURLWithPath: filePath)
        return loadImage(from: fileURL, maxSize: maxSize)
    }
    
    /// Loads an image from data using optimized CGImageSource thumbnail generation
    /// - Parameters:
    ///   - imageData: Image data
    ///   - maxSize: Maximum pixel dimension for thumbnail
    /// - Returns: NSImage if successful, nil otherwise
    func loadImage(
        from imageData: Data,
        maxSize: Int = 4000,
        shouldCancel: () -> Bool = { false }
    ) -> NSImage? {
        // Use autoreleasepool to manage memory efficiently
        return autoreleasepool {
            guard !shouldCancel() else { return nil }

            // Create image source from data
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
                return nil
            }

            // Animated images (e.g. animated WebP/GIF): return NSImage(data:) to
            // preserve all frames. The thumbnail API only extracts a single frame.
            if CGImageSourceGetCount(source) > 1 {
                guard !shouldCancel() else { return nil }
                let image = NSImage(data: imageData)
                return shouldCancel() ? nil : image
            }

            return createThumbnail(
                from: source,
                maxSize: maxSize,
                shouldCancel: shouldCancel
            )
        }
    }

    private func createThumbnail(
        from source: CGImageSource,
        maxSize: Int,
        shouldCancel: () -> Bool
    ) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ]

        guard !shouldCancel(),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
              ),
              !shouldCancel() else {
            return nil
        }

        return NSImage(
            cgImage: thumbnail,
            size: NSSize(width: thumbnail.width, height: thumbnail.height)
        )
    }
    
    /// Loads an image asynchronously on a background queue
    /// Checks cache first, then loads from disk if not cached
    /// - Parameters:
    ///   - fileURL: URL to the image file
    ///   - maxSize: Maximum pixel dimension for thumbnail
    ///   - completion: Completion handler called on main queue with NSImage or nil
    @discardableResult
    func loadImageAsync(
        from fileURL: URL,
        maxSize: Int = 4000,
        completion: @escaping (NSImage?) -> Void
    ) -> Operation? {
        // Check cache first for instant loading
        if let cachedImage = ImageCacheManager.shared.getCachedImage(for: fileURL, maxSize: maxSize) {
            completion(cachedImage)
            return nil
        }
        
        // Load from disk if not cached
        // Use a dedicated queue with userInitiated QoS to avoid priority inversion
        // The queue's QoS will be inherited by all operations running on it
        // Note: CGImageSource may use internal threads with lower QoS, which can cause
        // priority inversion warnings. This is often unavoidable when using system frameworks.
        let cacheGeneration = ImageCacheManager.shared.currentGeneration()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            // Load image - this runs on a queue with userInitiated QoS
            // CGImageSource operations may still use internal threads, but we've done
            // our best to ensure the operation runs at the correct priority
            let image = self?.loadImage(
                from: fileURL,
                maxSize: maxSize,
                shouldCancel: { operation.isCancelled }
            )

            guard !operation.isCancelled else { return }

            // Calculate cost and insert off-main. NSCache may release older decoded
            // images while inserting, which must not pause scrolling.
            if let image = image {
                ImageCacheManager.shared.cacheImage(
                    image,
                    for: fileURL,
                    maxSize: maxSize,
                    ifGeneration: cacheGeneration
                )
            }

            DispatchQueue.main.async {
                guard !operation.isCancelled else { return }
                completion(image)
            }
        }
        imageLoadingQueue.addOperation(operation)
        return operation
    }
    
    /// Loads an image asynchronously on a background queue from file path
    /// - Parameters:
    ///   - filePath: Path to the image file
    ///   - maxSize: Maximum pixel dimension for thumbnail
    ///   - completion: Completion handler called on main queue with NSImage or nil
    @discardableResult
    func loadImageAsync(
        from filePath: String,
        maxSize: Int = 4000,
        completion: @escaping (NSImage?) -> Void
    ) -> Operation? {
        let fileURL = URL(fileURLWithPath: filePath)
        return loadImageAsync(from: fileURL, maxSize: maxSize, completion: completion)
    }
    
    /// Calculates the average color of an image using the fastest algorithm (CIAreaAverage filter)
    /// This uses GPU acceleration via Core Image for optimal performance
    /// - Parameter image: The image to analyze
    /// - Returns: The average color as NSColor, or nil if calculation fails
    func calculateAverageColor(of image: NSImage) -> NSColor? {
        // Use autoreleasepool to manage memory efficiently
        return autoreleasepool {
            // Convert NSImage to CGImage
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            
            // Create CIImage from CGImage
            let ciImage = CIImage(cgImage: cgImage)
            let extent = ciImage.extent
            
            // Use CIAreaAverage filter - this is the fastest algorithm as it uses GPU acceleration
            guard let areaAverageFilter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]) else {
                return nil
            }
            
            guard let outputImage = areaAverageFilter.outputImage else {
                return nil
            }
            
            // Render the output to a 1x1 pixel bitmap to get the average color
            // Reuse the existing CIContext for optimal performance
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
            
            // Extract RGBA components and create NSColor
            let red = CGFloat(bitmapData[0]) / 255.0
            let green = CGFloat(bitmapData[1]) / 255.0
            let blue = CGFloat(bitmapData[2]) / 255.0
            let alpha = CGFloat(bitmapData[3]) / 255.0
            
            return NSColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    }
    
    /// Calculates the average color of an image from file URL
    /// - Parameter fileURL: URL to the image file
    /// - Returns: The average color as NSColor, or nil if calculation fails
    func calculateAverageColor(from fileURL: URL) -> NSColor? {
        // Try to access security-scoped resource if needed
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Load image first
        guard let image = loadImage(from: fileURL) else {
            return nil
        }
        
        return calculateAverageColor(of: image)
    }
}
