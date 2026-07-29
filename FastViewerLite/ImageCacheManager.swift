//
//  ImageCacheManager.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa

/// Manages image caching and prefetching for fast navigation
class ImageCacheManager {
    
    /// Shared instance
    static let shared = ImageCacheManager()
    
    /// Cache for prefetched images
    private let imageCache: NSCache<NSString, NSImage>
    
    /// Cache for average colors
    private let averageColorCache: NSCache<NSString, NSColor>
    
    /// Operation queue for prefetching operations
    private let prefetchQueue: OperationQueue
    
    /// Dispatch queue for synchronizing prefetch requests
    private let prefetchSyncQueue = DispatchQueue(label: "com.fastviewer.prefetchsync")

    /// Protects the cache generation and makes generation checks/cache writes atomic.
    private let cacheStateLock = NSLock()
    private var cacheGeneration: UInt64 = 0
    private var cachedImageKeys: Set<NSString> = []
    private var cachedAverageColorKeys: Set<NSString> = []
    private var cachedImageCosts: [NSString: Int] = [:]
    
    /// Active prefetch work keyed by URL. Overlapping requests are retained.
    private var prefetchOperations: [String: Operation] = [:]

    /// Last navigation window applied to the rolling queue. A display commit often
    /// repeats the request already made when navigation started; treating it as a
    /// no-op prevents a second prefetch pass for the same position.
    private var activePrefetchRequest: PrefetchRequest?
    private var pendingPrefetchInput: PrefetchInput?
    private var prefetchReconciliationScheduled = false

    private struct PrefetchInput {
        let fileURLs: [URL]
        let currentIndex: Int
        let maxSize: Int
    }

    private struct PrefetchRequest: Equatable {
        let firstURL: URL
        let lastURL: URL
        let fileCount: Int
        let currentIndex: Int
        let maxSize: Int
        let prefetchBefore: Int
        let prefetchAfter: Int
    }
    
    /// Number of files to prefetch before current file
    var prefetchBefore: Int = 2
    
    /// Number of files to prefetch after current file
    var prefetchAfter: Int = 20
    
    /// Maximum cache size (count limit)
    private let maxCacheCount = 200
    
    private init() {
        // Initialize cache with count and memory limits
        imageCache = NSCache<NSString, NSImage>()
        imageCache.countLimit = maxCacheCount
        // Costs are supplied when objects are inserted, so this is a real decoded-memory limit.
        imageCache.totalCostLimit = 256 * 1024 * 1024
        
        // Initialize average color cache
        averageColorCache = NSCache<NSString, NSColor>()
        averageColorCache.countLimit = maxCacheCount
        // Colors are small (just NSColor objects), so no need for memory limit
        
        // Initialize prefetch queue with limited concurrency
        prefetchQueue = OperationQueue()
        prefetchQueue.name = "com.fastviewer.imageprefetch"
        // A single speculative decoder avoids competing with the foreground
        // decoder and prevents large neighboring PNG files from arriving in
        // CPU/memory bursts while the user scrolls.
        prefetchQueue.maxConcurrentOperationCount = 1
        prefetchQueue.qualityOfService = .utility // Lower priority than user-initiated operations
    }
    
    /// Gets a cached image for the given URL
    /// - Parameter url: The file URL
    /// - Returns: Cached image if available, nil otherwise
    func getCachedImage(for url: URL, maxSize: Int = 4000) -> NSImage? {
        return imageCache.object(forKey: Self.cacheKey(for: url, maxSize: maxSize))
    }
    
    /// Caches an image for the given URL
    /// - Parameters:
    ///   - image: The image to cache
    ///   - url: The file URL
    func cacheImage(_ image: NSImage, for url: URL, maxSize: Int = 4000) {
        cacheImage(image, for: url, maxSize: maxSize, ifGeneration: nil)
    }

    /// Caches an image only if no cache clear occurred since the load started.
    func cacheImage(
        _ image: NSImage,
        for url: URL,
        maxSize: Int = 4000,
        ifGeneration generation: UInt64?
    ) {
        let key = Self.cacheKey(for: url, maxSize: maxSize)
        let cost = Self.decodedByteCost(of: image)

        cacheStateLock.lock()
        defer { cacheStateLock.unlock() }
        guard generation == nil || generation == cacheGeneration else { return }
        imageCache.setObject(image, forKey: key, cost: cost)
        cachedImageKeys.insert(key)
        cachedImageCosts[key] = cost
    }
    
    /// Gets a cached average color for the given URL
    /// - Parameter url: The file URL
    /// - Returns: Cached average color if available, nil otherwise
    func getCachedAverageColor(for url: URL) -> NSColor? {
        return averageColorCache.object(forKey: Self.averageColorCacheKey(for: url))
    }
    
    /// Caches an average color for the given URL
    /// - Parameters:
    ///   - color: The average color to cache
    ///   - url: The file URL
    func cacheAverageColor(_ color: NSColor, for url: URL) {
        cacheAverageColor(color, for: url, ifGeneration: nil)
    }

    /// Caches an average color only if the originating load still belongs to this generation.
    func cacheAverageColor(_ color: NSColor, for url: URL, ifGeneration generation: UInt64?) {
        let key = Self.averageColorCacheKey(for: url)

        cacheStateLock.lock()
        defer { cacheStateLock.unlock() }
        guard generation == nil || generation == cacheGeneration else { return }
        averageColorCache.setObject(color, forKey: key)
        cachedAverageColorKeys.insert(key)
    }

    /// Returns a token that can be used to reject results from work predating clearCache().
    func currentGeneration() -> UInt64 {
        cacheStateLock.lock()
        defer { cacheStateLock.unlock() }
        return cacheGeneration
    }
    
    /// Prefetches images around the current index
    /// Files are prioritized by distance from current position - closest files load first
    /// - Parameters:
    ///   - fileURLs: Array of all file URLs
    ///   - currentIndex: Current file index
    func prefetchImages(fileURLs: [URL], currentIndex: Int, maxSize: Int = 4000) {
        prefetchSyncQueue.async { [weak self] in
            guard let self else { return }
            self.pendingPrefetchInput = PrefetchInput(
                fileURLs: fileURLs,
                currentIndex: currentIndex,
                maxSize: maxSize
            )

            guard !self.prefetchReconciliationScheduled else { return }
            self.prefetchReconciliationScheduled = true
            self.prefetchSyncQueue.async { [weak self] in
                self?.reconcileLatestPrefetchInput()
            }
        }
    }

    /// Applies only the newest cursor received before this reconciliation turn.
    /// Rapid wheel events therefore collapse into one rolling-window update.
    private func reconcileLatestPrefetchInput() {
        guard let input = pendingPrefetchInput else {
            prefetchReconciliationScheduled = false
            return
        }
        pendingPrefetchInput = nil
        prefetchReconciliationScheduled = false

        let fileURLs = input.fileURLs
        let currentIndex = input.currentIndex
        let maxSize = input.maxSize
        let generation = currentGeneration()
            
        // Guard against empty file list
        guard !fileURLs.isEmpty,
              currentIndex >= 0,
              currentIndex < fileURLs.count else {
            cancelAllPrefetchOperations()
            return
        }

        let request = PrefetchRequest(
            firstURL: fileURLs[0],
            lastURL: fileURLs[fileURLs.count - 1],
            fileCount: fileURLs.count,
            currentIndex: currentIndex,
            maxSize: maxSize,
            prefetchBefore: prefetchBefore,
            prefetchAfter: prefetchAfter
        )
            // Calculate prefetch range
            let startIndex = max(0, currentIndex - self.prefetchBefore)
            let endIndex = min(fileURLs.count - 1, currentIndex + self.prefetchAfter)
            
            // Guard against invalid range (startIndex > endIndex)
            guard startIndex <= endIndex else { return }
            
            // Collect indices to prefetch (excluding current).
            var indicesToPrefetch: [Int] = []
            for index in startIndex...endIndex {
                // Skip current file (it's being loaded separately)
                if index == currentIndex {
                    continue
                }
                
                indicesToPrefetch.append(index)
            }
            
            // Sort by distance from current index (closest first)
            // This ensures next/previous images are prefetched with highest priority
            indicesToPrefetch.sort { abs($0 - currentIndex) < abs($1 - currentIndex) }
            PerformanceLog.shared.event(
                "PREFETCH",
                "window=\(startIndex)...\(endIndex) queuedCandidates=\(indicesToPrefetch.count) generation=\(generation)"
            )
            
            let desiredKeys = Set(indicesToPrefetch.map {
                Self.cacheKey(for: fileURLs[$0], maxSize: maxSize) as String
            })

            if request == self.activePrefetchRequest,
               indicesToPrefetch.allSatisfy({
                   let fileURL = fileURLs[$0]
                   let key = Self.cacheKey(for: fileURL, maxSize: maxSize) as String
                   return self.prefetchOperations[key] != nil ||
                       self.getCachedImage(for: fileURL, maxSize: maxSize) != nil
               }) {
                PerformanceLog.shared.event(
                    "PREFETCH",
                    "retain-window index=\(currentIndex) count=\(fileURLs.count)"
                )
                return
            }
            self.activePrefetchRequest = request

            // Cancel only work that has moved outside the current prefetch window.
            let staleKeys = self.prefetchOperations.keys.filter { !desiredKeys.contains($0) }
            for key in staleKeys {
                self.prefetchOperations.removeValue(forKey: key)?.cancel()
            }

            // Existing operations are the overlapping part of one rolling range,
            // not an old batch. Re-prioritize them for the new cursor so a file that
            // just became adjacent can move ahead of previously distant work.
            for index in indicesToPrefetch {
                let operationKey = Self.cacheKey(
                    for: fileURLs[index],
                    maxSize: maxSize
                ) as String
                if let operation = self.prefetchOperations[operationKey] {
                    self.configurePriority(
                        of: operation,
                        distance: abs(index - currentIndex)
                    )
                }
            }

            // Add only missing work in priority order; overlapping operations survive.
            for index in indicesToPrefetch {
                let fileURL = fileURLs[index]
                let operationKey = Self.cacheKey(for: fileURL, maxSize: maxSize) as String
                let distance = abs(index - currentIndex)

                if self.getCachedImage(for: fileURL, maxSize: maxSize) != nil ||
                    self.prefetchOperations[operationKey] != nil {
                    continue
                }
                
                // Create prefetch operation
                let operation = BlockOperation()
                operation.addExecutionBlock { [weak self, weak operation] in
                    guard let self = self, let operation = operation else { return }
                    let startedAt = ProcessInfo.processInfo.systemUptime
                    PerformanceLog.shared.event(
                        "PREFETCH",
                        "begin file=\(fileURL.lastPathComponent) distance=\(distance)"
                    )
                    defer {
                        PerformanceLog.shared.event(
                            "PREFETCH",
                            String(
                                format: "end file=%@ cancelled=%d duration=%.1fms",
                                fileURL.lastPathComponent,
                                operation.isCancelled ? 1 : 0,
                                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                            )
                        )
                        self.prefetchSyncQueue.async { [weak self, weak operation] in
                            guard let self, let operation,
                                  self.prefetchOperations[operationKey] === operation else { return }
                            self.prefetchOperations.removeValue(forKey: operationKey)
                        }
                    }
                    guard !operation.isCancelled,
                          generation == self.currentGeneration() else { return }

                    // Use autoreleasepool to prevent memory buildup
                    autoreleasepool {
                        // Load image using ImageLoader
                        if let image = ImageLoader.shared.loadImage(
                            from: fileURL,
                            maxSize: maxSize,
                            allowsAnimatedImage: false,
                            shouldCancel: { operation.isCancelled || generation != self.currentGeneration() }
                        ), !operation.isCancelled, generation == self.currentGeneration() {
                            self.cacheImage(
                                image,
                                for: fileURL,
                                maxSize: maxSize,
                                ifGeneration: generation
                            )
                        }
                    }

                }
                
                self.configurePriority(of: operation, distance: distance)
                
            prefetchOperations[operationKey] = operation
            prefetchQueue.addOperation(operation)
        }
    }
    
    /// Clears the image cache
    func clearCache() {
        prefetchSyncQueue.sync {
            cancelAllPrefetchOperations()
        }

        cacheStateLock.lock()
        cacheGeneration &+= 1
        imageCache.removeAllObjects()
        averageColorCache.removeAllObjects()
        cachedImageKeys.removeAll()
        cachedAverageColorKeys.removeAll()
        cachedImageCosts.removeAll()
        cacheStateLock.unlock()

    }
    
    /// Cancels all prefetch operations
    func cancelPrefetching() {
        prefetchSyncQueue.async { [weak self] in
            self?.cancelAllPrefetchOperations()
        }
    }

    private func cancelAllPrefetchOperations() {
        activePrefetchRequest = nil
        pendingPrefetchInput = nil
        for operation in prefetchOperations.values {
            operation.cancel()
        }
        prefetchOperations.removeAll()
        prefetchQueue.cancelAllOperations()
    }

    private func configurePriority(of operation: Operation, distance: Int) {
        if distance <= 2 {
            operation.queuePriority = .veryHigh
            operation.qualityOfService = .userInitiated
        } else if distance <= 5 {
            operation.queuePriority = .high
            operation.qualityOfService = .default
        } else {
            operation.queuePriority = .normal
            operation.qualityOfService = .utility
        }
    }

    /// Invalidates a file explicitly when it is opened again or replaced.
    func removeCachedImage(for url: URL) {
        let imageKeys: [NSString]
        let colorKey = Self.averageColorCacheKey(for: url)
        cacheStateLock.lock()
        let prefix = url.standardizedFileURL.absoluteString + "|"
        imageKeys = cachedImageKeys.filter { ($0 as String).hasPrefix(prefix) }
        for key in imageKeys {
            imageCache.removeObject(forKey: key)
            cachedImageKeys.remove(key)
            cachedImageCosts.removeValue(forKey: key)
        }
        averageColorCache.removeObject(forKey: colorKey)
        cachedAverageColorKeys.remove(colorKey)
        cacheStateLock.unlock()
    }

    /// Fast session key that never performs filesystem I/O on the main thread.
    /// Explicit invalidation handles files reopened at the same URL.
    static func cacheKey(for url: URL, maxSize: Int = 4000) -> NSString {
        return "\(url.standardizedFileURL.absoluteString)|\(maxSize)|\(fileVersion(for: url))" as NSString
    }

    private static func averageColorCacheKey(for url: URL) -> NSString {
        return "\(url.standardizedFileURL.absoluteString)|color|\(fileVersion(for: url))" as NSString
    }

    private static func fileVersion(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "missing"
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        return "\(size)-\(modified.bitPattern)"
    }

    private static func decodedByteCost(of image: NSImage) -> Int {
        let frameCount = image.representations.compactMap { representation -> Int? in
            guard let bitmap = representation as? NSBitmapImageRep else { return nil }
            return bitmap.value(forProperty: .frameCount) as? Int
        }.max() ?? 1

        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            let width = max(1, Int(image.size.width.rounded(.up)))
            let height = max(1, Int(image.size.height.rounded(.up)))
            let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
            let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
            let (animatedBytes, animatedOverflow) = bytes.multipliedReportingOverflow(by: frameCount)
            return pixelOverflow || byteOverflow || animatedOverflow ? Int.max : animatedBytes
        }

        let (singleFrameCost, frameOverflow) = cgImage.bytesPerRow.multipliedReportingOverflow(
            by: cgImage.height
        )
        let (totalCost, totalOverflow) = singleFrameCost.multipliedReportingOverflow(by: frameCount)
        return frameOverflow || totalOverflow ? Int.max : totalCost
    }
}
