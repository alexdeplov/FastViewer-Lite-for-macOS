//
//  SettingsManager.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Foundation

/// File name display location options
enum FileNameDisplayLocation: String, CaseIterable {
    case inTitle = "inTitle"
    case inCorner = "inCorner"
    case off = "off"
    
    var displayName: String {
        switch self {
        case .inTitle:
            return "in the title"
        case .inCorner:
            return "in the corner"
        case .off:
            return "off"
        }
    }
}

/// Transparency background display options
enum TransparencyBackground: String, CaseIterable {
    case solidColor = "solidColor"
    case checkers = "checkers"
    
    var displayName: String {
        switch self {
        case .solidColor:
            return "Solid color"
        case .checkers:
            return "Checkers"
        }
    }
}

/// Anchor used when the window is automatically resized for a new image.
enum WindowResizeAnchor: String, CaseIterable {
    case center = "center"
    case topLeft = "topLeft"

    var displayName: String {
        switch self {
        case .center:
            return "Center"
        case .topLeft:
            return "Top Left"
        }
    }
}

/// Manages application settings and preferences
class SettingsManager {
    
    /// Shared instance
    static let shared = SettingsManager()
    
    /// UserDefaults key for PNG support preference
    private let pngSupportEnabledKey = "PNGSupportEnabled"
    
    /// UserDefaults key for WebP support preference
    private let webpSupportEnabledKey = "WebPSupportEnabled"
    
    /// UserDefaults key for AVIF support preference
    private let avifSupportEnabledKey = "AVIFSupportEnabled"
    
    /// UserDefaults key for HEIC support preference
    private let heicSupportEnabledKey = "HEICSupportEnabled"
    
    /// UserDefaults key for file size display preference
    private let showFileSizeKey = "ShowFileSize"
    
    /// UserDefaults key for image resolution display preference
    private let showImageResolutionKey = "ShowImageResolution"
    
    /// UserDefaults key for creation date display preference
    private let showCreationDateKey = "ShowCreationDate"
    
    /// UserDefaults key for auto-resize to image size preference
    private let autoResizeToImageSizeKey = "AutoResizeToImageSize"
    
    /// UserDefaults key for auto-resize animation preference
    private let autoResizeWithAnimationKey = "AutoResizeWithAnimation"

    /// UserDefaults key for the anchor used while auto-resizing the window
    private let windowResizeAnchorKey = "WindowResizeAnchor"
    
    /// UserDefaults key for file name display location preference
    private let fileNameDisplayLocationKey = "FileNameDisplayLocation"
    
    /// UserDefaults key for file tag display preference
    private let showFileTagKey = "ShowFileTag"
    
    /// UserDefaults key for transparency background preference
    private let transparencyBackgroundKey = "TransparencyBackground"
    
    /// UserDefaults key for showing file position counter in title
    private let showFilePositionKey = "ShowFilePosition"
    
    private init() {
        UserDefaults.standard.register(defaults: [
            autoResizeToImageSizeKey: true
        ])
    }
    
    /// Whether PNG support is enabled
    /// Defaults to true (enabled by default)
    var isPNGSupportEnabled: Bool {
        get {
            // Check UserDefaults, default to true if not set
            if UserDefaults.standard.object(forKey: pngSupportEnabledKey) == nil {
                return true // Default to enabled
            }
            return UserDefaults.standard.bool(forKey: pngSupportEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: pngSupportEnabledKey)
        }
    }
    
    /// Whether WebP support is enabled
    /// Defaults to true (enabled by default)
    var isWebPSupportEnabled: Bool {
        get {
            // Check UserDefaults, default to true if not set
            if UserDefaults.standard.object(forKey: webpSupportEnabledKey) == nil {
                return true // Default to enabled
            }
            return UserDefaults.standard.bool(forKey: webpSupportEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: webpSupportEnabledKey)
        }
    }
    
    /// Whether AVIF support is enabled
    /// Defaults to true (enabled by default)
    var isAVIFSupportEnabled: Bool {
        get {
            // Check UserDefaults, default to true if not set
            if UserDefaults.standard.object(forKey: avifSupportEnabledKey) == nil {
                return true // Default to enabled
            }
            return UserDefaults.standard.bool(forKey: avifSupportEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: avifSupportEnabledKey)
        }
    }
    
    /// Whether HEIC support is enabled
    /// Defaults to true (enabled by default)
    var isHEICSupportEnabled: Bool {
        get {
            // Check UserDefaults, default to true if not set
            if UserDefaults.standard.object(forKey: heicSupportEnabledKey) == nil {
                return true // Default to enabled
            }
            return UserDefaults.standard.bool(forKey: heicSupportEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: heicSupportEnabledKey)
        }
    }
    
    /// Returns array of supported file extensions based on current settings
    var supportedExtensions: [String] {
        var extensions = ["jpg", "jpeg"] // JPEG always supported
        if isPNGSupportEnabled {
            extensions.append("png")
        }
        if isWebPSupportEnabled {
            extensions.append("webp")
        }
        if isAVIFSupportEnabled {
            extensions.append("avif")
        }
        if isHEICSupportEnabled {
            extensions.append(contentsOf: ["heic", "heif"])
        }
        return extensions
    }
    
    /// Checks if a file extension is supported based on current settings
    /// - Parameter extension: File extension (case-insensitive)
    /// - Returns: True if the extension is supported
    func isExtensionSupported(_ extension: String) -> Bool {
        let lowercased = `extension`.lowercased()
        return supportedExtensions.contains(lowercased)
    }
    
    /// Whether file size should be shown in the file info pill
    /// Defaults to false (hidden by default)
    var showFileSize: Bool {
        get {
            return UserDefaults.standard.bool(forKey: showFileSizeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showFileSizeKey)
        }
    }
    
    /// Whether image resolution should be shown in the file info pill
    /// Defaults to false (hidden by default)
    var showImageResolution: Bool {
        get {
            return UserDefaults.standard.bool(forKey: showImageResolutionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showImageResolutionKey)
        }
    }
    
    /// Whether creation date should be shown in the file info pill
    /// Defaults to false (hidden by default)
    var showCreationDate: Bool {
        get {
            return UserDefaults.standard.bool(forKey: showCreationDateKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showCreationDateKey)
        }
    }
    
    /// Whether the file info pill should be shown
    /// Returns true if any display option is enabled
    var showFileInfoPill: Bool {
        return showFileSize || showImageResolution
    }
    
    /// Whether window should automatically resize to match image size when changing images
    /// Defaults to true (enabled by default)
    var autoResizeToImageSize: Bool {
        get {
            return UserDefaults.standard.bool(forKey: autoResizeToImageSizeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoResizeToImageSizeKey)
        }
    }
    
    /// Whether auto-resize should use animation
    /// Defaults to false (not animated by default)
    var autoResizeWithAnimation: Bool {
        get {
            return UserDefaults.standard.bool(forKey: autoResizeWithAnimationKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoResizeWithAnimationKey)
        }
    }

    /// Anchor used when resizing the window to match the current image.
    /// Defaults to the top-left corner.
    var windowResizeAnchor: WindowResizeAnchor {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: windowResizeAnchorKey),
               let anchor = WindowResizeAnchor(rawValue: rawValue) {
                return anchor
            }
            return .topLeft
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: windowResizeAnchorKey)
        }
    }
    
    /// Where to display the file name
    /// Defaults to .inTitle
    var fileNameDisplayLocation: FileNameDisplayLocation {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: fileNameDisplayLocationKey),
               let location = FileNameDisplayLocation(rawValue: rawValue) {
                return location
            }
            return .inTitle
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: fileNameDisplayLocationKey)
        }
    }
    
    /// Whether file tag should be shown as a colored circle
    /// Defaults to false (hidden by default)
    var showFileTag: Bool {
        get {
            // Check UserDefaults, default to false if not set (hidden by default)
            if UserDefaults.standard.object(forKey: showFileTagKey) == nil {
                return false // Default to hidden
            }
            return UserDefaults.standard.bool(forKey: showFileTagKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showFileTagKey)
        }
    }
    
    /// How to display transparency in images
    /// Defaults to .checkers
    var transparencyBackground: TransparencyBackground {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: transparencyBackgroundKey),
               let background = TransparencyBackground(rawValue: rawValue) {
                return background
            }
            return .checkers
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: transparencyBackgroundKey)
        }
    }
    
    /// Whether to show file position counter in title (e.g., "3 / 47")
    /// Defaults to true (shown by default)
    var showFilePosition: Bool {
        get {
            // Check UserDefaults, default to true if not set
            if UserDefaults.standard.object(forKey: showFilePositionKey) == nil {
                return true // Default to showing
            }
            return UserDefaults.standard.bool(forKey: showFilePositionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showFilePositionKey)
        }
    }
}
