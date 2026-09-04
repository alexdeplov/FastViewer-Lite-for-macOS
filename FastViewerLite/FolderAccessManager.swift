//
//  FolderAccessManager.swift
//  FastViewer
//
//  Created by Alexander Deplov on 23.12.25.
//
//  Manages security-scoped bookmarks for folder access in sandboxed apps.
//  This is critical for enabling navigation between sibling images when
//  opening files via "Open with" from Finder.

import Cocoa

/// Manages folder access permissions for sandboxed apps
/// Stores security-scoped bookmarks to maintain folder access across sessions
class FolderAccessManager {
    
    // MARK: - Singleton
    
    static let shared = FolderAccessManager()
    
    private init() {}
    
    // MARK: - Properties
    
    /// Currently active security-scoped URL for folder access
    private var activeDirectoryURL: URL?
    
    /// Whether we're currently accessing a security-scoped resource
    private var isAccessingSecurityScopedResource = false
    
    /// Cache of directory URLs that we've confirmed access to
    private var accessedDirectories: Set<String> = []
    
    // MARK: - Public Methods
    
    /// Checks if we have access to the directory containing the given file
    /// - Parameter fileURL: The file URL to check directory access for
    /// - Returns: True if we have access to the directory, false otherwise
    func hasAccessToDirectory(containing fileURL: URL) -> Bool {
        let directoryURL = fileURL.deletingLastPathComponent()
        return hasAccessToDirectory(directoryURL)
    }
    
    /// Checks if we have access to a directory
    /// - Parameter directoryURL: The directory URL to check
    /// - Returns: True if we have access, false otherwise
    func hasAccessToDirectory(_ directoryURL: URL) -> Bool {
        // Check if we've already confirmed access to this directory
        if accessedDirectories.contains(directoryURL.path) {
            return true
        }
        
        // Try to read directory contents to verify access
        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            // If successful, cache this directory
            accessedDirectories.insert(directoryURL.path)
            return true
        } catch {
            return false
        }
    }
    
    /// Requests access to the directory containing a file via NSOpenPanel
    /// - Parameters:
    ///   - fileURL: The file URL whose directory we need access to
    ///   - completion: Called with true if access was granted, false otherwise
    func requestAccessToDirectory(containing fileURL: URL, completion: @escaping (Bool) -> Void) {
        let directoryURL = fileURL.deletingLastPathComponent()
        requestAccessToDirectory(directoryURL, completion: completion)
    }
    
    /// Requests access to a directory via NSOpenPanel
    /// - Parameters:
    ///   - directoryURL: The directory URL we need access to
    ///   - completion: Called with true if access was granted, false otherwise
    func requestAccessToDirectory(_ directoryURL: URL, completion: @escaping (Bool) -> Void) {
        // Must run on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            // First, check if we already have access
            if self.hasAccessToDirectory(directoryURL) {
                completion(true)
                return
            }
            
            // Show open panel to request folder access
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "FastViewer Lite needs access to this folder to browse images.\nPlease select the folder and click 'Grant Access'."
            panel.prompt = "Grant Access"
            
            // Set the directory as the starting location
            panel.directoryURL = directoryURL
            
            panel.begin { response in
                if response == .OK, let selectedURL = panel.url {
                    // User granted access - start accessing security-scoped resource
                    let accessing = selectedURL.startAccessingSecurityScopedResource()
                    
                    // Verify we can now read the directory
                    var canRead = false
                    do {
                        _ = try FileManager.default.contentsOfDirectory(
                            at: selectedURL,
                            includingPropertiesForKeys: nil,
                            options: [.skipsHiddenFiles]
                        )
                        canRead = true
                        
                        // Store the active directory for later cleanup
                        // Note: We keep the security-scoped resource active so we can
                        // continue accessing files in the directory
                        if accessing {
                            self.stopAccessingCurrentDirectory()
                            self.activeDirectoryURL = selectedURL
                            self.isAccessingSecurityScopedResource = true
                        }
                        
                        // Cache this directory as accessible
                        self.accessedDirectories.insert(selectedURL.path)
                        // Also add the requested directory path (they might be the same)
                        self.accessedDirectories.insert(directoryURL.path)
                        
                    } catch {
                        // Failed to read directory even after granting access
                        if accessing {
                            selectedURL.stopAccessingSecurityScopedResource()
                        }
                        canRead = false
                    }
                    
                    completion(canRead)
                } else {
                    // User cancelled or denied access
                    completion(false)
                }
            }
        }
    }
    
    /// Stops accessing the currently active security-scoped directory
    func stopAccessingCurrentDirectory() {
        if isAccessingSecurityScopedResource, let url = activeDirectoryURL {
            url.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedResource = false
            activeDirectoryURL = nil
        }
    }
    
    /// Clears all cached directory access information
    /// Call this when the app terminates or when you want to reset access state
    func clearAccessCache() {
        accessedDirectories.removeAll()
        stopAccessingCurrentDirectory()
    }
    
    /// Attempts to access a directory and its contents
    /// This is a convenience method that combines checking and requesting access
    /// - Parameters:
    ///   - directoryURL: The directory URL to access
    ///   - requestIfNeeded: If true, will show an open panel if access is not available
    ///   - completion: Called with true if access is available/granted, false otherwise
    func accessDirectory(_ directoryURL: URL, requestIfNeeded: Bool, completion: @escaping (Bool) -> Void) {
        if hasAccessToDirectory(directoryURL) {
            completion(true)
            return
        }
        
        if requestIfNeeded {
            requestAccessToDirectory(directoryURL, completion: completion)
        } else {
            completion(false)
        }
    }
}



