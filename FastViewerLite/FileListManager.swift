//
//  FileListManager.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa

/// Manages the list of image files in a directory and the current file index
class FileListManager {

    /// Directory enumeration on a NAS can be expensive even when the image
    /// data itself is already cached. Keep the discovered list briefly so
    /// opening another image in the same folder does not repeat that request.
    private static let directoryListCacheTTL: TimeInterval = 60

    /// Prepared file list result that can be committed later without mutating live state during discovery.
    struct PreparedFileList {
        let fileURLs: [URL]
        let currentIndex: Int
    }

    /// Array of file URLs in the current directory
    var fileURLs: [URL] = []

    /// Current index in the file list
    var currentIndex: Int = 0

    private struct CachedDirectoryList {
        let createdAt: Date
        let fileURLs: [URL]
    }

    private var directoryListCache: [String: CachedDirectoryList] = [:]
    private let directoryListCacheLock = NSLock()

    /// Current file URL
    var currentFileURL: URL? {
        guard currentIndex >= 0 && currentIndex < fileURLs.count else {
            return nil
        }
        return fileURLs[currentIndex]
    }

    /// Whether there is a previous file
    var hasPrevious: Bool {
        return currentIndex > 0
    }

    /// Whether there is a next file
    var hasNext: Bool {
        return currentIndex < fileURLs.count - 1
    }

    /// Loads files from the same directory as the given file URL
    /// - Parameter fileURL: The file URL to use as reference
    /// - Returns: True if files were loaded successfully, false otherwise
    func loadFiles(fromDirectoryContaining fileURL: URL) -> Bool {
        guard let preparedFileList = prepareFiles(fromDirectoryContaining: fileURL) else {
            return false
        }

        applyPreparedFileList(preparedFileList)
        return true
    }

    /// Discovers files from the same directory as the given file URL without mutating live state.
    /// - Parameter fileURL: The file URL to use as reference
    /// - Returns: Prepared file list if discovery succeeded, nil otherwise
    func prepareFiles(fromDirectoryContaining fileURL: URL) -> PreparedFileList? {
        let directoryURL = fileURL.deletingLastPathComponent()

        let directoryCacheKey = directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        if let cachedURLs = cachedFileURLs(forKey: directoryCacheKey),
           let prepared = makePreparedFileList(cachedURLs, for: fileURL) {
            PerformanceLog.shared.event(
                "FILELIST",
                "cache-hit directory=\(directoryURL.path) count=\(cachedURLs.count)"
            )
            return prepared
        }

        // Start accessing security-scoped resources for both file and directory
        // This is critical for sandboxed apps when opening files via "Open with"
        let fileAccessing = fileURL.startAccessingSecurityScopedResource()
        let directoryAccessing = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if fileAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
            if directoryAccessing {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        // Detect Finder sort order and direction from .DS_Store before listing files
        let sortSettings = DSStoreReader.sortSettings(forDirectoryAt: directoryURL)
        let resourceKeys = resourceKeys(for: sortSettings.order)

        // Get all files in the directory. Some NAS implementations reject one
        // or more of the Finder metadata keys above even though directory
        // enumeration itself is supported. Retry with names only in that case.
        let fileURLs: [URL]
        if let enumeratedURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) {
            fileURLs = enumeratedURLs
        } else if let fallbackURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            PerformanceLog.shared.event(
                "FILELIST",
                "metadata-fallback directory=\(directoryURL.path)"
            )
            fileURLs = fallbackURLs
        } else {
            print("⚠️ Failed to load files from directory: \(directoryURL.path)")
            return nil
        }

        // Filter to only supported image formats and sort by Finder order
        // Use SettingsManager to get supported extensions (modular PNG support)
        let supportedExtensions = SettingsManager.shared.supportedExtensions
        let filtered = fileURLs.filter { url in
            let pathExtension = url.pathExtension.lowercased()
            return supportedExtensions.contains(pathExtension)
        }.map { directoryURL.appendingPathComponent($0.lastPathComponent) }
        var sortedFileURLs = sortFiles(filtered, by: sortSettings)

        // Keep the opened item even if the NAS returned incomplete metadata or
        // the file was created while the directory was being enumerated.
        if !sortedFileURLs.contains(where: {
            $0.resolvingSymlinksInPath().standardizedFileURL.path ==
                fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        }) {
            sortedFileURLs.append(fileURL)
            sortedFileURLs = sortFiles(sortedFileURLs, by: sortSettings)
        }
        PerformanceLog.shared.event(
            "FILELIST",
            "directory=\(directoryURL.path) discovered=\(fileURLs.count) supported=\(sortedFileURLs.count) order=\(sortSettings.order) ascending=\(sortSettings.ascending ? 1 : 0)"
        )
        PerformanceLog.shared.snapshotDirectory(directoryURL, reason: "prepare")

        storeCachedFileURLs(sortedFileURLs, forKey: directoryCacheKey)

        // Find the index of the current file
        return makePreparedFileList(sortedFileURLs, for: fileURL)

    }

    /// Applies a previously prepared file list to live navigation state.
    /// - Parameter preparedFileList: Prepared file list state to commit
    func applyPreparedFileList(_ preparedFileList: PreparedFileList) {
        fileURLs = preparedFileList.fileURLs
        currentIndex = preparedFileList.currentIndex
    }

    /// Falls back to tracking only a single file when directory enumeration is unavailable.
    /// - Parameter fileURL: The file URL to make current
    func setSingleFile(_ fileURL: URL) {
        fileURLs = [fileURL]
        currentIndex = 0
    }

    /// Moves to the previous file with looping support
    /// If at the first file, loops to the last file
    /// - Returns: The URL of the previous file, or nil if list is empty
    @discardableResult
    func moveToPrevious() -> URL? {
        guard !fileURLs.isEmpty else {
            return nil
        }

        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            // Loop to last file
            currentIndex = fileURLs.count - 1
        }

        return currentFileURL
    }

    /// Moves to the next file with looping support
    /// If at the last file, loops to the first file
    /// - Returns: The URL of the next file, or nil if list is empty
    @discardableResult
    func moveToNext() -> URL? {
        guard !fileURLs.isEmpty else {
            return nil
        }

        if currentIndex < fileURLs.count - 1 {
            currentIndex += 1
        } else {
            // Loop to first file
            currentIndex = 0
        }

        return currentFileURL
    }

    /// Resets the file list
    func reset() {
        fileURLs = []
        currentIndex = 0
    }

    /// Invalidates the cached enumeration for a directory after a file
    /// operation changes its contents.
    func invalidateDirectoryCache(for directoryURL: URL) {
        let key = directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        directoryListCacheLock.lock()
        directoryListCache.removeValue(forKey: key)
        directoryListCacheLock.unlock()
    }

    /// Reloads files from the given directory URL
    /// - Parameter directoryURL: The directory URL to load files from
    /// - Returns: True if files were loaded successfully, false otherwise
    func reloadFiles(fromDirectory directoryURL: URL) -> Bool {
        invalidateDirectoryCache(for: directoryURL)
        // Start accessing security-scoped resource for directory
        // This is critical for sandboxed apps
        let directoryAccessing = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if directoryAccessing {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        // Detect Finder sort order and direction from .DS_Store before listing files
        let sortSettings = DSStoreReader.sortSettings(forDirectoryAt: directoryURL)
        let resourceKeys = resourceKeys(for: sortSettings.order)

        // Get all files in the directory
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            // Log error for debugging (can be removed in production if desired)
            print("⚠️ Failed to reload files from directory: \(directoryURL.path)")
            return false
        }

        // Filter to only supported image formats and sort by Finder order
        let supportedExtensions = SettingsManager.shared.supportedExtensions
        let filtered = fileURLs.filter { url in
            let pathExtension = url.pathExtension.lowercased()
            return supportedExtensions.contains(pathExtension)
        }.map { directoryURL.appendingPathComponent($0.lastPathComponent) }
        self.fileURLs = sortFiles(filtered, by: sortSettings)

        // Reset index to 0 (caller should adjust if needed)
        currentIndex = 0
        return true
    }

    // MARK: - Sorting

    private func makePreparedFileList(_ fileURLs: [URL], for fileURL: URL) -> PreparedFileList? {
        let requestedPath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard let index = fileURLs.firstIndex(where: {
            $0.resolvingSymlinksInPath().standardizedFileURL.path == requestedPath
        }) else {
            return nil
        }
        return PreparedFileList(fileURLs: fileURLs, currentIndex: index)
    }

    private func cachedFileURLs(forKey key: String) -> [URL]? {
        directoryListCacheLock.lock()
        defer { directoryListCacheLock.unlock() }

        guard let cached = directoryListCache[key] else {
            return nil
        }
        guard Date().timeIntervalSince(cached.createdAt) < Self.directoryListCacheTTL else {
            directoryListCache.removeValue(forKey: key)
            return nil
        }
        return cached.fileURLs
    }

    private func storeCachedFileURLs(_ fileURLs: [URL], forKey key: String) {
        directoryListCacheLock.lock()
        directoryListCache[key] = CachedDirectoryList(createdAt: Date(), fileURLs: fileURLs)
        directoryListCacheLock.unlock()
    }

    /// Returns the URLResourceKeys needed for the given sort order
    private func resourceKeys(for sortOrder: FinderSortOrder) -> [URLResourceKey] {
        // Do not request metadata that is not used by the selected sort.
        // In particular, .isRegularFileKey can make a NAS enumerate every item
        // one by one and leave the UI at its temporary 1/1 state for seconds.
        var keys: [URLResourceKey] = []
        switch sortOrder {
        case .name:
            break
        case .dateModified:
            keys.append(.contentModificationDateKey)
        case .dateCreated:
            keys.append(.creationDateKey)
        case .dateAdded:
            keys.append(.addedToDirectoryDateKey)
        case .size:
            keys.append(.fileSizeKey)
        case .kind:
            break // sort by extension string
        }
        return keys
    }

    /// Sorts files according to the given Finder sort settings (column + direction)
    private func sortFiles(_ files: [URL], by settings: FinderSortSettings) -> [URL] {
        let asc = settings.ascending

        switch settings.order {
        case .name:
            return files.sorted {
                let result = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                if result == .orderedSame {
                    return $0.path < $1.path
                }
                return asc ? result == .orderedAscending : result == .orderedDescending
            }

        case .dateModified:
            let values = files.map {
                ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
            }
            return values.sorted {
                $0.1 == $1.1 ? $0.0.path < $1.0.path : (asc ? $0.1 < $1.1 : $0.1 > $1.1)
            }.map(\.0)

        case .dateCreated:
            let values = files.map {
                ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast)
            }
            return values.sorted {
                $0.1 == $1.1 ? $0.0.path < $1.0.path : (asc ? $0.1 < $1.1 : $0.1 > $1.1)
            }.map(\.0)

        case .dateAdded:
            let values = files.map {
                ($0, (try? $0.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? .distantPast)
            }
            return values.sorted {
                $0.1 == $1.1 ? $0.0.path < $1.0.path : (asc ? $0.1 < $1.1 : $0.1 > $1.1)
            }.map(\.0)

        case .size:
            let values = files.map {
                ($0, (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            return values.sorted {
                $0.1 == $1.1 ? $0.0.path < $1.0.path : (asc ? $0.1 < $1.1 : $0.1 > $1.1)
            }.map(\.0)

        case .kind:
            return files.sorted {
                let ext0 = $0.pathExtension.lowercased()
                let ext1 = $1.pathExtension.lowercased()
                if ext0 != ext1 {
                    let result = ext0.localizedStandardCompare(ext1)
                    return asc ? result == .orderedAscending : result == .orderedDescending
                }
                let nameResult = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                if nameResult == .orderedSame {
                    return $0.path < $1.path
                }
                return asc ? nameResult == .orderedAscending : nameResult == .orderedDescending
            }
        }
    }
}
