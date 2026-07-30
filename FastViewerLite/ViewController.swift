//
//  ViewController.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa
import ImageIO
import CoreGraphics

class ViewController: NSViewController, NSDraggingDestination, DraggingDestinationHandler, PanningHandler {

    /// A subtle adaptive gray for the empty canvas, kept close to the standard window color.
    internal static var emptyWindowBackgroundColor: NSColor {
        NSColor.windowBackgroundColor.blended(
            withFraction: 0.18,
            of: NSColor.underPageBackgroundColor
        ) ?? NSColor.windowBackgroundColor
    }

    internal var imageView: NSImageView!
    internal let fileListManager = FileListManager()
    private let imageLoader = ImageLoader.shared
    internal private(set) var displayedFileURL: URL?

    internal var hasDisplayedFile: Bool {
        return displayedFileURL != nil
    }

    internal var displayedFileInfoText: String {
        return fileInfoLabel?.stringValue ?? ""
    }

    internal var displayedTagCircleCount: Int {
        return fileTagCircles.count
    }

    internal var isLoadingOverlayVisible: Bool {
        return !(loadingOverlayView?.isHidden ?? true)
    }

    internal var toastText: String {
        return toastLabel?.stringValue ?? ""
    }

    // Logo image view (shown when no file is open)
    private var logoImageView: NonInteractiveImageView!

    // Stack container for logo and instruction label to center as a group
    private var logoStackView: NSStackView!

    // Instruction label below logo (shown when no file is open)
    private var instructionLabel: NSTextField!

    // File info pill view
    private var fileInfoPill: NSVisualEffectView!
    private var fileInfoLabel: NSTextField!
    private var fileInfoPillWidthConstraint: NSLayoutConstraint!
    private var fileInfoLabelLeadingConstraint: NSLayoutConstraint!

    // File name display view (for corner display)
    private var fileNamePill: NSVisualEffectView!
    private var fileNameLabel: NSTextField!
    private var fileNamePillWidthConstraint: NSLayoutConstraint!
    private var fileNamePillMinWidthConstraint: NSLayoutConstraint!

    // File tag circle views (can have multiple tags)
    private var fileTagCircles: [NSView] = []
    private var fileTagCircleContainer: NSView!
    private var fileTagCircleContainerWidthConstraint: NSLayoutConstraint!

    // Toast notification view (for undo feedback)
    private var toastView: NSVisualEffectView!
    private var toastLabel: NSTextField!

    // Loading UI is intentionally disabled; these remain for lightweight state checks.
    private var loadingOverlayView: NSVisualEffectView!
    private var loadingSpinner: NSProgressIndicator!


    // Transparency checker background view
    private var transparencyCheckerView: NSView!

    // Appearance observation
    private var appearanceObservation: NSKeyValueObservation?
    private var imageLinkMouseMonitor: Any?

    private struct DragPreparationState {
        let fileURL: URL
        let generation: Int
        var preparedImage: NSImage?
        var preparedFileList: FileListManager.PreparedFileList?
        var imagePreparationCompleted: Bool = false
        var fileListPreparationCompleted: Bool = false
        var dropPending: Bool = false
    }

    private var dragPreparationGeneration: Int = 0
    private var dragPreparationState: DragPreparationState?

    private enum FileListCommit {
        case keepCurrent
        case prepared(FileListManager.PreparedFileList)
        case currentIndex(Int)
        case singleFile(URL)
    }

    // Undo state for move to trash
    private struct UndoState {
        let originalFileURL: URL
        let trashFileURL: URL
        let directoryURL: URL
        let originalIndex: Int
    }
    private var undoStack: [UndoState] = []
    private var imageLoadGeneration: Int = 0
    private var currentImageLoadOperation: Operation?
    private var imageQualityLoadOperation: Operation?
    private var imageLinkDetectionDelay: DispatchWorkItem?
    private var imageLinkDetectionOperation: Operation?
    private var detectedImageLinks: [DetectedImageLink] = []
    private var pendingImageURL: URL?
    private var fileListPreparationGeneration: Int = 0
    private var preparedFileListForPendingDisplay: (
        fileURL: URL,
        generation: Int,
        prepared: FileListManager.PreparedFileList
    )?
    private var fileInfoGeneration: Int = 0
    private var fileTagGeneration: Int = 0
    // Zoom state per image
    private var imageZoomScales: [URL: CGFloat] = [:]
    private var imagePanOffsets: [URL: NSPoint] = [:]
    private var actualSizeImageURLs: Set<URL> = []
    private var originalImagePixelSizes: [URL: NSSize] = [:]
    private let zoomStep: CGFloat = 1.5 // 50% zoom per step
    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 10.0

    // Panning state
    private var isPanning: Bool = false
    private var panStartLocation: NSPoint = .zero
    private var panStartOffset: NSPoint = .zero
    private var cursorPushed: Bool = false
    private var openHandCursorPushed: Bool = false
    private var linkCursorPushed: Bool = false
    private var currentCursorType: CursorType = .default
    private var accumulatedNavigationScroll: CGFloat = 0
    private var lastScrollNavigationTime: TimeInterval = 0
    private let preciseScrollNavigationThreshold: CGFloat = 30
    private let scrollNavigationInterval: TimeInterval = 0.18

    private enum CursorType {
        case `default`
        case openHand
        case closedHand
    }

    override func loadView() {
        // Create draggable view programmatically for faster launch
        let newView = DraggableView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        newView.wantsLayer = true
        // Use the standard document-canvas background for the empty window.
        newView.layer?.backgroundColor = Self.emptyWindowBackgroundColor.cgColor
        // Set the view controller as the dragging delegate
        newView.draggingDelegate = self
        view = newView
    }

    func handleDoubleClick(_ event: NSEvent) {
        // Handle double-click in empty state to open file dialog
        // Check if we're in empty state (no file loaded)
        if displayedFileURL == nil && !isLoadingOverlayVisible {
            openFileDialog()
        }
    }

    /// Shows the open file dialog to select an image file
    private func openFileDialog() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return
        }
        appDelegate.presentOpenFilePanel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupTransparencyCheckerView()
        setupImageView()
        setupLogoImageView()
        setupInstructionLabel()
        setupLogoStackView()
        setupFileInfoPill()
        setupFileNamePill()
        setupFileTagCircle()
        setupLoadingOverlay()
        setupToastNotification()
        setupAppearanceObserver()
        setupDragAndDrop()
        setupImageLinkMouseMonitor()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Ensure view controller becomes first responder to receive keyboard events
        view.window?.makeFirstResponder(self)
    }

    deinit {
        cancelImageLinkDetection()
        if let imageLinkMouseMonitor {
            NSEvent.removeMonitor(imageLinkMouseMonitor)
        }
        appearanceObservation?.invalidate()
    }

    /// Intercepts link clicks before AppKit dispatches them through the view
    /// hierarchy. Mouse tracking can reach the image view while an overlapping
    /// view still consumes mouseDown, so responder-only handling is insufficient.
    private func setupImageLinkMouseMonitor() {
        imageLinkMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self,
                  event.window === self.view.window,
                  self.imageView.image != nil else {
                return event
            }

            let location = self.imageView.convert(event.locationInWindow, from: nil)
            guard self.imageView.bounds.contains(location),
                  self.handleImageLinkClick(at: location) else {
                return event
            }

            // Consuming the event prevents the same click from also navigating or
            // starting a pan gesture after the browser receives the URL.
            return nil
        }
    }

    /// Sets up observer for view appearance changes
    private func setupAppearanceObserver() {
        // Observe the view's effectiveAppearance property
        // This triggers when the view's appearance changes (e.g., when moved to different display)
        appearanceObservation = view.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateBackgroundForCurrentAppearance()
            }
        }
    }

    /// Updates background color based on current appearance
    private func updateBackgroundForCurrentAppearance() {
        updateCheckerPatternForAppearance()
        refreshBackgroundForCurrentImage()
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        // Handle Cmd+1, Cmd+2, Cmd+3, Cmd+4 for window sizing
        if event.modifierFlags.contains(.command) {
            // Handle Cmd+H to hide the application
            if let characters = event.charactersIgnoringModifiers, characters == "h" {
                NSApplication.shared.hide(nil)
                return
            }

            // Handle Cmd+M to minimize the current window
            if let characters = event.charactersIgnoringModifiers, characters == "m" {
                view.window?.performMiniaturize(nil)
                return
            }

            // Handle Cmd+Enter (Return key) to open current file in Finder
            if event.keyCode == 36 { // Return key
                openCurrentFileInFinder()
                return
            }

            // Handle Cmd+Backspace to move current file to Trash
            if event.keyCode == 51 { // Backspace/Delete key
                moveCurrentFileToTrash()
                return
            }

            // Handle Cmd+Z to undo move to trash
            if let characters = event.charactersIgnoringModifiers, characters == "z" {
                undoMoveToTrash()
                return
            }

            // Handle Cmd+0 to display the image at its actual pixel size
            if let characters = event.charactersIgnoringModifiers, characters == "0" {
                displayImageAtActualSize()
                return
            }

            // Handle Cmd+= or Cmd++ for zoom in
            // Key code 24 is = key, which becomes + when Shift is pressed
            if event.keyCode == 24 {
                if let characters = event.charactersIgnoringModifiers, characters == "=" || characters == "+" {
                    zoomIn()
                    return
                }
            }

            // Handle Cmd+- for zoom out
            // Key code 27 is - key
            if event.keyCode == 27 {
                if let characters = event.charactersIgnoringModifiers, characters == "-" {
                    zoomOut()
                    return
                }
            }

            if let characters = event.charactersIgnoringModifiers {
                switch characters {
                case "1":
                    // If auto-resize is enabled, disable it when user manually sets size
                    if SettingsManager.shared.autoResizeToImageSize {
                        SettingsManager.shared.autoResizeToImageSize = false
                        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                            appDelegate.updateMenuStates()
                            appDelegate.updateSettingsWindowUI()
                        }
                    }
                    resizeWindow(to: NSSize(width: 600, height: 400), animated: true)
                    return
                case "2":
                    // If auto-resize is enabled, disable it when user manually sets size
                    if SettingsManager.shared.autoResizeToImageSize {
                        SettingsManager.shared.autoResizeToImageSize = false
                        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                            appDelegate.updateMenuStates()
                            appDelegate.updateSettingsWindowUI()
                        }
                    }
                    resizeWindow(to: NSSize(width: 900, height: 600), animated: true)
                    return
                case "3":
                    // If auto-resize is enabled, disable it when user manually sets size
                    if SettingsManager.shared.autoResizeToImageSize {
                        SettingsManager.shared.autoResizeToImageSize = false
                        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                            appDelegate.updateMenuStates()
                            appDelegate.updateSettingsWindowUI()
                        }
                    }
                    resizeWindowToAlmostMaximized(animated: true)
                    return
                case "4":
                    // Simply call the AppDelegate's toggle method so behavior is consistent
                    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                        appDelegate.resizeWindowToImage()
                    }
                    return
                default:
                    break
                }
            }
        }

        switch event.keyCode {
        case 123: // Left arrow key
            navigateToPrevious()
        case 124: // Right arrow key
            navigateToNext()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Window Resizing

    /// Restores the window to its initial state (no file loaded)
    /// Preserves undo state so Cmd+Z can restore the file if it was moved to trash
    internal func restoreInitialState() {
        clearDragPreparation()
        cancelPendingImageTransition()
        cancelImageLinkDetection()
        invalidateMetadataRequests()
        displayedFileURL = nil
        imageView.image = nil

        // Reset file list manager
        fileListManager.reset()

        showEmptyStateUI()

        // Keep menu command availability in sync with the current image/file state
        updateAppMenuStates()

        // Reset window to initial size (600x400)
        resizeWindow(to: NSSize(width: 600, height: 400), animated: true)
    }

    private func showEmptyStateUI() {
        hideLoadingOverlay()
        transparencyCheckerView?.isHidden = true
        logoImageView?.isHidden = false
        instructionLabel?.isHidden = false
        updateFileNameDisplay(for: nil)
        fileInfoPill?.isHidden = true
        fileInfoLabel?.stringValue = ""
        hideFileTagDisplay()

        useEmptyWindowBackground()
    }

    /// Resizes the window to the specified size with optional animation
    /// Resets zoom to initial state (1.0)
    /// - Parameters:
    ///   - size: The target size for the window
    ///   - animated: Whether to animate the resize
    internal func resizeWindow(to size: NSSize, animated: Bool) {
        guard let window = view.window else { return }

        // Reset zoom to 1.0 when changing window preset
        resetZoomToInitial()

        let currentFrame = window.frame
        let newOrigin: NSPoint
        switch SettingsManager.shared.windowResizeAnchor {
        case .topLeft:
            newOrigin = NSPoint(
                x: currentFrame.minX,
                y: currentFrame.maxY - size.height
            )
        case .center:
            newOrigin = NSPoint(
                x: currentFrame.midX - size.width / 2,
                y: currentFrame.midY - size.height / 2
            )
        }
        let newFrame = NSRect(origin: newOrigin, size: size)

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                window.animator().setFrame(newFrame, display: true)
            }, completionHandler: { [weak self] in
                // Update image scaling after resize completes
                if let image = self?.imageView.image {
                    self?.updateImageScaling(for: image)
                }
            })
        } else {
            window.setFrame(newFrame, display: true)
            if let image = imageView.image {
                updateImageScaling(for: image)
            }
        }
    }

    /// Resizes the window to almost maximized size (90% of screen size) with optional animation
    /// Resets zoom to initial state (1.0)
    /// - Parameter animated: Whether to animate the resize
    internal func resizeWindowToAlmostMaximized(animated: Bool) {
        guard let window = view.window,
              let screen = window.screen ?? NSScreen.main else { return }

        // Reset zoom to 1.0 when changing window preset
        resetZoomToInitial()

        let screenFrame = screen.visibleFrame
        let margin: CGFloat = 40 // 20 points margin on each side
        let targetSize = NSSize(
            width: screenFrame.width - margin * 2,
            height: screenFrame.height - margin * 2
        )

        let newOrigin: NSPoint
        switch SettingsManager.shared.windowResizeAnchor {
        case .topLeft:
            let currentFrame = window.frame
            newOrigin = NSPoint(
                x: currentFrame.minX,
                y: currentFrame.maxY - targetSize.height
            )
        case .center:
            newOrigin = NSPoint(
                x: screenFrame.midX - targetSize.width / 2,
                y: screenFrame.midY - targetSize.height / 2
            )
        }
        let newFrame = NSRect(origin: newOrigin, size: targetSize)

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                window.animator().setFrame(newFrame, display: true)
            }, completionHandler: { [weak self] in
                // Update image scaling after resize completes
                if let image = self?.imageView.image {
                    self?.updateImageScaling(for: image)
                }
            })
        } else {
            window.setFrame(newFrame, display: true)
            if let image = imageView.image {
                updateImageScaling(for: image)
            }
        }
    }

    /// Resizes the window to match the current image size exactly at 100% scale with optional animation
    /// Sets image scale to 100% and resizes window to match image size exactly, without any gaps
    /// If image is larger than screen, scales it down proportionally to fit
    /// - Parameter animated: Whether to animate the resize
    /// - Parameter completion: Optional completion handler called after resize completes
    internal func resizeWindowToImageSize(
        animated: Bool,
        keepingScreenPointVisible screenPoint: NSPoint? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard let window = view.window,
              let image = imageView.image else {
            // No image loaded, do nothing
            return
        }

        // Reset zoom to 1.0 when resizing to image size (Cmd+4)
        resetZoomToInitial()

        // Get actual pixel dimensions from the CGImage representation
        // The NSImage.size property might be incorrect if the image was created with pixel dimensions
        // We need to get the actual pixel size and convert to points for accurate 100% scale
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Fallback to NSImage.size if we can't get CGImage
            let imageSize = image.size
            let desiredContentRect = NSRect(origin: .zero, size: imageSize)
            let newWindowFrame = window.frameRect(forContentRect: desiredContentRect)
            resizeWindow(
                to: newWindowFrame,
                animated: animated,
                image: image,
                keepingScreenPointVisible: screenPoint
            )
            return
        }

        // Get pixel dimensions from CGImage
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)

        // Get the screen's backing scale factor for the window's screen
        guard let screen = window.screen ?? NSScreen.main else { return }
        let scaleFactor = screen.backingScaleFactor

        // Convert pixels to points for 100% scale display
        // On Retina (2x): 1 point = 2 pixels, so 2000 pixels = 1000 points
        // On non-Retina (1x): 1 point = 1 pixel, so 2000 pixels = 2000 points
        // Formula: points = pixels / scaleFactor
        var imageSizeInPoints = NSSize(
            width: pixelWidth / scaleFactor,
            height: pixelHeight / scaleFactor
        )

        // Get current content rect to calculate title bar height
        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        let currentWindowFrame = window.frame
        let titleBarHeight = currentWindowFrame.height - currentContentRect.height

        // Get available screen size (visible frame)
        let screenFrame = screen.visibleFrame
        let maxContentWidth = screenFrame.width
        let maxContentHeight = screenFrame.height - titleBarHeight

        // Check if image exceeds screen size and scale down proportionally if needed
        if imageSizeInPoints.width > maxContentWidth || imageSizeInPoints.height > maxContentHeight {
            // Calculate scale factor to fit within screen while maintaining aspect ratio
            let widthScale = maxContentWidth / imageSizeInPoints.width
            let heightScale = maxContentHeight / imageSizeInPoints.height
            let scale = min(widthScale, heightScale)

            // Scale down proportionally
            imageSizeInPoints.width = imageSizeInPoints.width * scale
            imageSizeInPoints.height = imageSizeInPoints.height * scale
        }

        // Calculate new window size: content size + title bar
        let newWindowSize = NSSize(
            width: imageSizeInPoints.width,
            height: imageSizeInPoints.height + titleBarHeight
        )

        // Create the new window frame
        let newWindowFrame = NSRect(origin: .zero, size: newWindowSize)

        resizeWindow(
            to: newWindowFrame,
            animated: animated,
            image: image,
            keepingScreenPointVisible: screenPoint,
            completion: completion
        )
    }

    /// Helper method to resize window and set image scaling
    private func resizeWindow(
        to newWindowFrame: NSRect,
        animated: Bool,
        image: NSImage,
        keepingScreenPointVisible screenPoint: NSPoint? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard let window = view.window else { return }

        guard let screen = window.screen ?? NSScreen.main else { return }
        let newOrigin: NSPoint

        switch SettingsManager.shared.windowResizeAnchor {
        case .center:
            let screenFrame = screen.visibleFrame
            newOrigin = NSPoint(
                x: screenFrame.origin.x + (screenFrame.width - newWindowFrame.width) / 2,
                y: screenFrame.origin.y + (screenFrame.height - newWindowFrame.height) / 2
            )
        case .topLeft:
            let currentFrame = window.frame
            newOrigin = NSPoint(
                x: currentFrame.minX,
                y: currentFrame.maxY - newWindowFrame.height
            )
        }

        var newFrame = NSRect(origin: newOrigin, size: newWindowFrame.size)
        if let screenPoint {
            newFrame = frameKeepingScrollPointerVisible(
                newFrame,
                screenPoint: screenPoint,
                window: window,
                screen: screen
            )
        }

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                // Set image scaling to fit the content size exactly
                // Use scaleProportionallyDown to ensure it fits without scaling up
                self.imageView.imageScaling = .scaleProportionallyDown
                window.animator().setFrame(newFrame, display: true)
            }, completionHandler: {
                // If completion handler is provided, let it handle updateImageScaling
                // Otherwise, update scaling here
                if completion == nil {
                    // Ensure scaling is correct after animation completes
                    // The window size should match the image size (or scaled down version)
                    if let image = self.imageView.image {
                        self.updateImageScaling(for: image)
                    }
                }
                // Call completion handler after animation
                completion?()
            })
        } else {
            // Set image scaling to fit the content size exactly
            imageView.imageScaling = .scaleProportionallyDown
            window.setFrame(newFrame, display: true)
            // If completion handler is provided, let it handle updateImageScaling
            // Otherwise, update scaling here
            if completion == nil {
                // Update scaling after resize to ensure it's correct
                updateImageScaling(for: image)
            }
            // Call completion handler immediately for non-animated case
            completion?()
        }
    }

    /// Moves a resized window only as much as needed to keep subsequent wheel
    /// events over its content view. This is used exclusively for mouse-scroll
    /// navigation; normal Cmd+4 resizing still follows the configured anchor.
    private func frameKeepingScrollPointerVisible(
        _ frame: NSRect,
        screenPoint: NSPoint,
        window: NSWindow,
        screen: NSScreen
    ) -> NSRect {
        var adjustedFrame = frame
        let contentRect = window.contentRect(forFrameRect: adjustedFrame)
        let margin = min(4, min(contentRect.width / 4, contentRect.height / 4))
        let safeContentRect = contentRect.insetBy(dx: margin, dy: margin)

        if screenPoint.x < safeContentRect.minX {
            adjustedFrame.origin.x += screenPoint.x - safeContentRect.minX
        } else if screenPoint.x > safeContentRect.maxX {
            adjustedFrame.origin.x += screenPoint.x - safeContentRect.maxX
        }

        if screenPoint.y < safeContentRect.minY {
            adjustedFrame.origin.y += screenPoint.y - safeContentRect.minY
        } else if screenPoint.y > safeContentRect.maxY {
            adjustedFrame.origin.y += screenPoint.y - safeContentRect.maxY
        }

        let visibleFrame = screen.visibleFrame
        adjustedFrame.origin.x = min(
            max(adjustedFrame.origin.x, visibleFrame.minX),
            visibleFrame.maxX - adjustedFrame.width
        )
        adjustedFrame.origin.y = min(
            max(adjustedFrame.origin.y, visibleFrame.minY),
            visibleFrame.maxY - adjustedFrame.height
        )
        return adjustedFrame
    }

    /// Sets up the transparency checker pattern background view
    private func setupTransparencyCheckerView() {
        transparencyCheckerView = NSView()
        transparencyCheckerView.translatesAutoresizingMaskIntoConstraints = false
        transparencyCheckerView.wantsLayer = true

        // Apply initial checker pattern based on current appearance
        updateCheckerPatternForAppearance()

        view.addSubview(transparencyCheckerView)

        NSLayoutConstraint.activate([
            transparencyCheckerView.topAnchor.constraint(equalTo: view.topAnchor),
            transparencyCheckerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transparencyCheckerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transparencyCheckerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Initially hidden
        transparencyCheckerView.isHidden = true
    }

    /// Updates the checker pattern colors based on current appearance (light/dark mode)
    private func updateCheckerPatternForAppearance() {
        guard let checkerView = transparencyCheckerView else { return }

        let appearance = view.effectiveAppearance
        let isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Create checker pattern with appearance-appropriate colors
        let checkerSize: CGFloat = 10
        let lightColor: NSColor
        let darkColor: NSColor

        if isDarkMode {
            // Dark mode: subtle darker checker colors
            lightColor = NSColor(white: 0.32, alpha: 1.0)
            darkColor = NSColor(white: 0.27, alpha: 1.0)
        } else {
            // Light mode: subtle lighter checker colors
            lightColor = NSColor(white: 0.88, alpha: 1.0)
            darkColor = NSColor(white: 0.82, alpha: 1.0)
        }

        // Create the checker pattern image
        let patternSize = NSSize(width: checkerSize * 2, height: checkerSize * 2)
        let patternImage = NSImage(size: patternSize, flipped: false) { rect in
            // Draw light background
            lightColor.setFill()
            rect.fill()

            // Draw dark squares
            darkColor.setFill()
            NSRect(x: 0, y: 0, width: checkerSize, height: checkerSize).fill()
            NSRect(x: checkerSize, y: checkerSize, width: checkerSize, height: checkerSize).fill()

            return true
        }

        // Set the pattern as background color
        let patternColor = NSColor(patternImage: patternImage)
        checkerView.layer?.backgroundColor = patternColor.cgColor
    }

    private func setupImageView() {
        // Create draggable image view programmatically
        let draggableImageView = DraggableImageView()
        draggableImageView.draggingDelegate = self
        draggableImageView.panningDelegate = self
        imageView = draggableImageView
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // Scale image to fit within the view bounds proportionally
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        // Enable layer for zoom transforms
        imageView.wantsLayer = true
        // Enable animation playback for animated images (WebP, GIF)
        // No effect on static images
        imageView.animates = true
        // Prevent image view from resizing based on image content
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Set the anchor point to the center (0.5, 0.5) after constraints are active
        // This ensures zoom happens from the center of the view
        // We'll update the position in viewDidLayout or when applying transforms
    }

    /// Sets up the logo image view centered on screen (shown when no file is open)
    private func setupLogoImageView() {
        logoImageView = NonInteractiveImageView()
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.imageScaling = .scaleProportionallyUpOrDown
        logoImageView.imageAlignment = .alignCenter
        logoImageView.imageFrameStyle = .none

        // Load logo image from assets
        if let logoImage = NSImage(named: "logo") {
            logoImageView.image = logoImage
        }

        // Set reasonable size constraints (logo will maintain aspect ratio)
        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 100),
            logoImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 100)
        ])

        // Initially show logo (no file is open at startup)
        logoImageView.isHidden = false
    }

    /// Sets up the instruction label below the logo
    private func setupInstructionLabel() {
        instructionLabel = NSTextField(labelWithString: "Double-click an image in Finder to open, or drop it here")
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.alignment = .center
        instructionLabel.isEditable = false
        instructionLabel.isSelectable = false
        instructionLabel.isBezeled = false
        instructionLabel.drawsBackground = false

        // Initially show instruction label (no file is open at startup)
        instructionLabel.isHidden = false
    }

    /// Sets up a stack view to center the logo and instruction label together
    private func setupLogoStackView() {
        logoStackView = NSStackView(views: [logoImageView, instructionLabel])
        logoStackView.orientation = .vertical
        logoStackView.alignment = .centerX
        logoStackView.distribution = .gravityAreas
        logoStackView.spacing = 12
        logoStackView.translatesAutoresizingMaskIntoConstraints = false

        // Keep the empty-state artwork behind the image view so a dropped image
        // is always rendered above it, including while the drop is being committed.
        view.addSubview(logoStackView, positioned: .below, relativeTo: imageView)

        NSLayoutConstraint.activate([
            logoStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logoStackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            logoStackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40)
        ])
    }

    /// Loads and displays an image from file URL
    /// - Parameter fileURL: URL to the image file
    func loadImage(from fileURL: URL) {
        PerformanceLog.shared.event("OPEN", "file=\(fileURL.lastPathComponent)")
        clearDragPreparation()
        ImageCacheManager.shared.removeCachedImage(for: fileURL)
        fileListPreparationGeneration += 1
        let preparationGeneration = fileListPreparationGeneration
        preparedFileListForPendingDisplay = nil

        // Start the visible decode immediately. Directory discovery can be much
        // slower on large, network, or cloud-backed folders and must not delay it.
        displayImage(from: fileURL, fileListCommit: .singleFile(fileURL))
        prepareFileListInBackground(for: fileURL, generation: preparationGeneration)

        DispatchQueue.main.async { [weak self] in
            self?.view.window?.makeFirstResponder(self)
        }
    }

    private func prepareFileListInBackground(for fileURL: URL, generation: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let startedAt = ProcessInfo.processInfo.systemUptime
            let prepared = self.fileListManager.prepareFiles(fromDirectoryContaining: fileURL)
            PerformanceLog.shared.event(
                "FILELIST",
                String(
                    format: "prepared file=%@ count=%d duration=%.1fms",
                    fileURL.lastPathComponent,
                    prepared?.fileURLs.count ?? 0,
                    (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                )
            )

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      generation == self.fileListPreparationGeneration,
                      self.pendingImageURL == fileURL || self.displayedFileURL == fileURL else {
                    return
                }

                guard let prepared else {
                    return
                }

                if self.displayedFileURL == fileURL {
                    self.fileListManager.applyPreparedFileList(prepared)
                    self.startPrefetching()
                    self.updateWindowTitle(with: fileURL)
                } else {
                    self.preparedFileListForPendingDisplay = (fileURL, generation, prepared)
                }
            }
        }
    }

    private func postUndoStateChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("UndoStateChanged"), object: nil)
    }

    private func cancelPendingImageTransition() {
        imageLoadGeneration += 1
        currentImageLoadOperation?.cancel()
        currentImageLoadOperation = nil
        imageQualityLoadOperation?.cancel()
        imageQualityLoadOperation = nil
        pendingImageURL = nil
        hideLoadingOverlay()
    }

    private func cancelImageLinkDetection() {
        imageLinkDetectionDelay?.cancel()
        imageLinkDetectionDelay = nil
        imageLinkDetectionOperation?.cancel()
        imageLinkDetectionOperation = nil
        detectedImageLinks = []
        (imageView as? DraggableImageView)?.hideLinkHoverBorder()
        clearLinkCursor()
    }

    private func invalidateMetadataRequests() {
        fileInfoGeneration += 1
        fileTagGeneration += 1
    }

    /// Starts prefetching images around the current file position
    private func startPrefetching(at index: Int? = nil) {
        let fileURLs = fileListManager.fileURLs
        let currentIndex = index ?? fileListManager.currentIndex
        PerformanceLog.shared.event(
            "PREFETCH",
            "request index=\(currentIndex) count=\(fileURLs.count) maxSize=\(preferredDecodeMaxSize())"
        )

        // Prefetch images around current position
        ImageCacheManager.shared.prefetchImages(
            fileURLs: fileURLs,
            currentIndex: currentIndex,
            maxSize: preferredDecodeMaxSize()
        )
    }

    /// Updates prefetching with current settings (called when settings change)
    func updatePrefetching() {
        // Only update if we have files loaded
        guard !fileListManager.fileURLs.isEmpty else {
            return
        }
        startPrefetching()
    }

    /// Displays an image from file URL without reloading the file list
    /// - Parameter fileURL: URL to the image file
    private func displayImage(
        from fileURL: URL,
        fileListCommit: FileListCommit = .keepCurrent,
        preferredImage: NSImage? = nil,
        keepingScrollPointerAt screenPoint: NSPoint? = nil
    ) {
        // Navigation starts a new two-second quiet period immediately, even if
        // decoding the replacement image has not completed yet.
        cancelImageLinkDetection()

        if pendingImageURL == fileURL {
            PerformanceLog.shared.event("DISPLAY", "duplicate file=\(fileURL.lastPathComponent)")
            #if DEBUG
            NSLog("[ScrollDiagnostic] duplicate pending request ignored: %@", fileURL.lastPathComponent)
            #endif
            return
        }

        currentImageLoadOperation?.cancel()
        currentImageLoadOperation = nil
        imageQualityLoadOperation?.cancel()
        imageQualityLoadOperation = nil
        pendingImageURL = nil
        imageLoadGeneration += 1
        let generation = imageLoadGeneration
        let decodeMaxSize = preferredDecodeMaxSize()
        let requestStartedAt = ProcessInfo.processInfo.systemUptime

        // Move the rolling prefetch cursor when navigation is requested, not after
        // the foreground decode commits. This keeps the range ahead of fast input.
        if case .currentIndex(let targetIndex) = fileListCommit {
            startPrefetching(at: targetIndex)
        }

        if let image = preferredImage ?? ImageCacheManager.shared.getCachedImage(
            for: fileURL,
            maxSize: decodeMaxSize
        ) {
            PerformanceLog.shared.event(
                "DISPLAY",
                "cache-hit file=\(fileURL.lastPathComponent) maxSize=\(decodeMaxSize)"
            )
            commitDisplayedImage(
                image,
                for: fileURL,
                generation: generation,
                fileListCommit: fileListCommit,
                keepingScrollPointerAt: screenPoint
            )
            return
        }

        showLoadingOverlay()
        pendingImageURL = fileURL
        PerformanceLog.shared.event(
            "DISPLAY",
            "decode-request file=\(fileURL.lastPathComponent) generation=\(generation) maxSize=\(decodeMaxSize)"
        )
        #if DEBUG
        NSLog("[ScrollDiagnostic] load requested: %@", fileURL.lastPathComponent)
        #endif

        currentImageLoadOperation = imageLoader.loadImageAsync(
            from: fileURL,
            maxSize: decodeMaxSize
        ) { [weak self] image in
            guard let self = self else { return }
            guard generation == self.imageLoadGeneration else { return }
            self.currentImageLoadOperation = nil
            self.pendingImageURL = nil

            guard let image = image else {
                self.handleFailedImageTransition(for: fileURL, generation: generation)
                return
            }
            PerformanceLog.shared.event(
                "DISPLAY",
                String(
                    format: "decode-complete file=%@ generation=%d duration=%.1fms",
                    fileURL.lastPathComponent,
                    generation,
                    (ProcessInfo.processInfo.systemUptime - requestStartedAt) * 1_000
                )
            )

            self.commitDisplayedImage(
                image,
                for: fileURL,
                generation: generation,
                fileListCommit: fileListCommit,
                keepingScrollPointerAt: screenPoint
            )
        }
    }

    private func commitDisplayedImage(
        _ image: NSImage,
        for fileURL: URL,
        generation: Int,
        fileListCommit: FileListCommit,
        keepingScrollPointerAt screenPoint: NSPoint?
    ) {
        guard generation == imageLoadGeneration else {
            return
        }

        applyFileListCommit(fileListCommit)
        if let prepared = preparedFileListForPendingDisplay,
           prepared.fileURL == fileURL,
           prepared.generation == fileListPreparationGeneration {
            fileListManager.applyPreparedFileList(prepared.prepared)
            preparedFileListForPendingDisplay = nil
        }
        displayedFileURL = fileURL
        cancelImageLinkDetection()
        PerformanceLog.shared.event(
            "DISPLAY",
            "commit file=\(fileURL.lastPathComponent) index=\(fileListManager.currentIndex)/\(fileListManager.fileURLs.count)"
        )
        #if DEBUG
        NSLog(
            "[ScrollDiagnostic] displayed index=%ld/%ld file=%@",
            fileListManager.currentIndex,
            fileListManager.fileURLs.count,
            fileURL.lastPathComponent
        )
        #endif

        prepareViewForDisplayedImage(at: fileURL)

        hideLoadingOverlay()
        presentLoadedImage(
            image,
            for: fileURL,
            keepingScrollPointerAt: screenPoint
        )
        scheduleImageLinkDetection(for: fileURL, image: image)

        if !fileListManager.fileURLs.isEmpty {
            startPrefetching()
        }

    }

    private func preferredDecodeMaxSize(zoomScale: CGFloat = 1) -> Int {
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let longestSide = max(imageView?.bounds.width ?? view.bounds.width,
                              imageView?.bounds.height ?? view.bounds.height)
        let requestedPixels = longestSide * scale * max(zoomScale, 1)
        return min(12_000, max(1_024, Int(requestedPixels.rounded(.up))))
    }

    /// Replaces the display with a larger decode only when zoom/window size needs it.
    /// The current pixels remain visible while the quality upgrade runs.
    private func requestSharperImageIfNeeded() {
        guard let fileURL = displayedFileURL,
              let image = imageView.image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let targetSize = preferredDecodeMaxSize(zoomScale: getCurrentZoomScale())
        guard max(cgImage.width, cgImage.height) < targetSize else {
            return
        }

        imageQualityLoadOperation?.cancel()
        imageQualityLoadOperation = imageLoader.loadImageAsync(
            from: fileURL,
            maxSize: targetSize
        ) { [weak self] sharperImage in
            guard let self,
                  self.displayedFileURL == fileURL,
                  let sharperImage else {
                return
            }
            self.imageQualityLoadOperation = nil
            self.imageView.image = sharperImage
            self.updateImageScaling(for: sharperImage)
            self.imageView.needsDisplay = true
        }
    }

    private func handleFailedImageTransition(for fileURL: URL, generation: Int) {
        guard generation == imageLoadGeneration else {
            return
        }

        hideLoadingOverlay()
        #if DEBUG
        NSLog("[ScrollDiagnostic] load failed: %@", fileURL.lastPathComponent)
        #endif

        if displayedFileURL == nil && imageView.image == nil {
            showEmptyStateUI()
            updateAppMenuStates()
        }

        showToast(message: "Couldn't open \(fileURL.lastPathComponent)")
    }

    private func applyFileListCommit(_ fileListCommit: FileListCommit) {
        switch fileListCommit {
        case .keepCurrent:
            break
        case .prepared(let preparedFileList):
            fileListManager.applyPreparedFileList(preparedFileList)
        case .currentIndex(let index):
            guard index >= 0 && index < fileListManager.fileURLs.count else {
                fileListManager.reset()
                return
            }
            fileListManager.currentIndex = index
        case .singleFile(let fileURL):
            fileListManager.setSingleFile(fileURL)
        }
    }

    private func prepareViewForDisplayedImage(at fileURL: URL) {
        invalidateMetadataRequests()

        // Reset cursor state when loading new image
        if openHandCursorPushed {
            NSCursor.pop()
            openHandCursorPushed = false
        }
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        isPanning = false

        updateFileNameDisplay(for: fileURL)

        if SettingsManager.shared.showFileInfoPill {
            updateFileInfo(for: fileURL)
        } else {
            fileInfoPill?.isHidden = true
        }

        hideFileTagDisplay()

        logoImageView?.isHidden = true
        instructionLabel?.isHidden = true
        useDefaultWindowBackground()
    }

    private func presentLoadedImage(
        _ image: NSImage,
        for fileURL: URL,
        keepingScrollPointerAt screenPoint: NSPoint?
    ) {
        // Set image without changing its size property to prevent window resizing
        // Adjust scaling based on image size vs view size
        // Note: Zoom scale will be applied in updateImageScaling if stored
        imageView.image = image
        updateAppMenuStates()
        imageView.needsDisplay = true
        logoImageView?.isHidden = true
        instructionLabel?.isHidden = true

        // Auto-resize window to image size if setting is enabled
        if SettingsManager.shared.autoResizeToImageSize {
            let currentFileURL = fileURL
            resizeWindowToImageSize(
                animated: false,
                keepingScreenPointVisible: screenPoint
            ) {
                self.resetZoomForFile(currentFileURL)
                self.updateImageScaling(for: image)
                self.refreshBackgroundForCurrentImage()
            }
        } else {
            updateImageScaling(for: image)
            refreshBackgroundForCurrentImage()
        }

        updateTransparencyCheckerVisibility()
    }

    /// Waits until the image has remained unchanged for two seconds, then performs
    /// on-device OCR away from the main thread. Every navigation invalidates both
    /// the delay and any in-flight result.
    private func scheduleImageLinkDetection(for fileURL: URL, image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let generation = imageLoadGeneration
        let delayedWork = DispatchWorkItem { [weak self] in
            guard let self,
                  self.displayedFileURL == fileURL,
                  self.imageLoadGeneration == generation else {
                return
            }

            self.imageLinkDetectionDelay = nil
            self.imageLinkDetectionOperation = ImageLinkDetector.shared.detectLinks(in: cgImage) {
                [weak self] links in
                guard let self,
                      self.displayedFileURL == fileURL,
                      self.imageLoadGeneration == generation else {
                    return
                }

                self.imageLinkDetectionOperation = nil
                self.detectedImageLinks = links
                self.refreshCursorForCurrentMouseLocation()
            }
        }

        imageLinkDetectionDelay = delayedWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: delayedWork)
    }

    /// Navigates to the previous file in the directory
    private func navigateToPrevious() {
        guard let currentIndex = currentVisibleFileIndex(), !fileListManager.fileURLs.isEmpty else {
            return
        }

        let previousIndex = currentIndex > 0 ? currentIndex - 1 : fileListManager.fileURLs.count - 1
        guard previousIndex >= 0, previousIndex < fileListManager.fileURLs.count else {
            return
        }

        displayImage(
            from: fileListManager.fileURLs[previousIndex],
            fileListCommit: .currentIndex(previousIndex)
        )
    }

    /// Navigates to the next file in the directory
    internal func navigateToNext() {
        guard let currentIndex = currentVisibleFileIndex(), !fileListManager.fileURLs.isEmpty else {
            return
        }

        let nextIndex = currentIndex < fileListManager.fileURLs.count - 1 ? currentIndex + 1 : 0
        displayImage(
            from: fileListManager.fileURLs[nextIndex],
            fileListCommit: .currentIndex(nextIndex)
        )
    }

    /// Moves the navigation cursor immediately. Foreground loading is latest-wins:
    /// a newer wheel target cancels the obsolete request instead of waiting for an
    /// intermediate image to commit and making scrolling appear frozen.
    internal func navigateWithDiscreteScroll(
        step: Int,
        keepingPointerAt screenPoint: NSPoint? = nil
    ) {
        guard step != 0,
              let currentIndex = currentVisibleFileIndex(),
              !fileListManager.fileURLs.isEmpty else {
            return
        }

        let fileCount = fileListManager.fileURLs.count
        let targetIndex = ((currentIndex + step) % fileCount + fileCount) % fileCount
        displayImage(
            from: fileListManager.fileURLs[targetIndex],
            fileListCommit: .currentIndex(targetIndex),
            keepingScrollPointerAt: screenPoint
        )
    }

    private func currentVisibleFileIndex() -> Int? {
        // During rapid navigation, advance from the file already requested rather
        // than repeatedly advancing from the last image that finished decoding.
        // Otherwise all wheel events received while a load is pending target the
        // same next URL and are discarded as duplicate requests.
        if let pendingImageURL,
           let index = fileListManager.fileURLs.firstIndex(of: pendingImageURL) {
            return index
        }

        if let displayedFileURL,
           let index = fileListManager.fileURLs.firstIndex(of: displayedFileURL) {
            return index
        }

        guard !fileListManager.fileURLs.isEmpty else {
            return nil
        }

        return min(max(fileListManager.currentIndex, 0), fileListManager.fileURLs.count - 1)
    }

    private func handleDisplayedFileRemoval(
        from directoryURL: URL,
        removedIndex: Int,
        wasLastFile: Bool,
        wasOnlyFile: Bool
    ) {
        _ = fileListManager.reloadFiles(fromDirectory: directoryURL)

        guard !wasOnlyFile, !fileListManager.fileURLs.isEmpty else {
            restoreInitialState()
            return
        }

        let targetIndex = wasLastFile
            ? fileListManager.fileURLs.count - 1
            : min(removedIndex, fileListManager.fileURLs.count - 1)
        guard targetIndex >= 0, targetIndex < fileListManager.fileURLs.count else {
            restoreInitialState()
            return
        }

        displayImage(
            from: fileListManager.fileURLs[targetIndex],
            fileListCommit: .currentIndex(targetIndex)
        )
    }

    /// Opens the current file in Finder
    internal func openCurrentFileInFinder() {
        guard let fileURL = displayedFileURL else {
            return
        }

        // Use NSWorkspace to reveal the file in Finder
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Requests an immediate menu state refresh in AppDelegate.
    private func updateAppMenuStates() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return
        }
        appDelegate.updateMenuStates()
    }

    /// Opens the native macOS print panel for the currently displayed image
    internal func printCurrentImage() {
        guard let image = imageView.image else {
            NSSound.beep()
            return
        }

        guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else {
            NSSound.beep()
            return
        }

        // Force one-page output and fit oversized images to the printable area.
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let pageSize = printInfo.imageablePageBounds.size
        let printableImageView = NSImageView(frame: NSRect(origin: .zero, size: pageSize))
        printableImageView.image = image
        printableImageView.imageScaling = .scaleProportionallyDown
        printableImageView.imageAlignment = .alignCenter

        let printOperation = NSPrintOperation(view: printableImageView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.run()
    }

    /// Moves the current file to Trash
    internal func moveCurrentFileToTrash() {
        guard let fileURL = displayedFileURL,
              let currentIndex = currentVisibleFileIndex() else {
            return
        }

        cancelPendingImageTransition()

        // Store the current index and directory for navigation after deletion
        let directoryURL = fileURL.deletingLastPathComponent()
        let wasLastFile = currentIndex == fileListManager.fileURLs.count - 1
        let wasOnlyFile = fileListManager.fileURLs.count == 1

        // Move file to trash asynchronously to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Start accessing security-scoped resource if needed
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                // Move file to trash and get the trash URL for undo
                // trashItem uses an inout parameter to return the resulting URL
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: &resultingURL)

                // Get the trash URL from the resulting parameter
                guard let trashFileURL = resultingURL as URL? else {
                    DispatchQueue.main.async {
                        self.handleDisplayedFileRemoval(
                            from: directoryURL,
                            removedIndex: currentIndex,
                            wasLastFile: wasLastFile,
                            wasOnlyFile: wasOnlyFile
                        )
                    }
                    return
                }

                // Store undo state on main thread before updating UI
                // Capture values needed for undo state to ensure proper closure capture
                let capturedFileURL = fileURL
                let capturedDirectoryURL = directoryURL
                let capturedCurrentIndex = currentIndex
                let capturedTrashFileURL = trashFileURL

                DispatchQueue.main.async {
                    self.undoStack.append(UndoState(
                        originalFileURL: capturedFileURL,
                        trashFileURL: capturedTrashFileURL,
                        directoryURL: capturedDirectoryURL,
                        originalIndex: capturedCurrentIndex
                    ))
                    self.postUndoStateChanged()

                    // Show toast notification to inform user about undo
                    self.showToast(message: "Moved to Trash. Press ⌘Z to undo")
                }

                DispatchQueue.main.async {
                    self.handleDisplayedFileRemoval(
                        from: directoryURL,
                        removedIndex: currentIndex,
                        wasLastFile: wasLastFile,
                        wasOnlyFile: wasOnlyFile
                    )
                }
            } catch {
                // Show error alert on main thread
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Move File to Trash"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    /// Returns whether undo is available (a file was moved to trash)
    internal var canUndoMoveToTrash: Bool {
        return !undoStack.isEmpty
    }

    /// Undoes the last move to trash operation
    internal func undoMoveToTrash() {
        guard !undoStack.isEmpty else {
            return
        }

        cancelPendingImageTransition()

        let undo = undoStack.removeLast()
        postUndoStateChanged()

        // Restore file from trash asynchronously to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Start accessing security-scoped resource if needed
            let accessing = undo.trashFileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    undo.trashFileURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                // Check if file still exists in trash
                guard FileManager.default.fileExists(atPath: undo.trashFileURL.path) else {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Cannot Undo"
                        alert.informativeText = "The file is no longer available in Trash."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    return
                }

                // Check if original location is available (not overwriting existing file)
                if FileManager.default.fileExists(atPath: undo.originalFileURL.path) {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Cannot Undo"
                        alert.informativeText = "A file already exists at the original location."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    return
                }

                // Restore file from trash to original location
                try FileManager.default.moveItem(at: undo.trashFileURL, to: undo.originalFileURL)

                DispatchQueue.main.async {
                    _ = self.fileListManager.reloadFiles(fromDirectory: undo.directoryURL)

                    if let index = self.fileListManager.fileURLs.firstIndex(of: undo.originalFileURL) {
                        self.displayImage(
                            from: undo.originalFileURL,
                            fileListCommit: .currentIndex(index)
                        )
                    } else {
                        self.displayImage(
                            from: undo.originalFileURL,
                            fileListCommit: .singleFile(undo.originalFileURL)
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Restore File"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    /// Updates the window title. The file name is always visible.
    /// - Parameter fileURL: URL to the image file (optional - if nil, shows just "FastViewer")
    private func updateWindowTitle(with fileURL: URL?) {
        guard let fileURL = fileURL else {
            view.window?.title = "FastViewer Lite"
            return
        }

        let filename = fileURL.lastPathComponent
        view.window?.title = "FastViewer Lite — \(filename)"
    }

    /// Updates the title and keeps the obsolete corner pill hidden.
    func updateFileNameDisplay(for fileURL: URL?) {
        guard let fileURL = fileURL else {
            // No file selected - hide the file name pill
            fileNamePill.isHidden = true
            updateWindowTitle(with: nil)
            return
        }

        updateWindowTitle(with: fileURL)
        fileNamePill.isHidden = true

        // Update pill visibility based on window size after updating widths
        updatePillVisibilityForWindowSize()
    }

    /// Updates image scaling based on image size relative to view size
    /// If image is smaller than view, keep it at original size (centered)
    /// If image is larger than view, scale it down to fit
    /// If view size exactly matches image size, show at 100% scale
    /// Also applies stored zoom scale if available
    /// - Parameter image: The image to check
    internal func updateImageScaling(for image: NSImage) {
        let imageSize = image.size
        // Use view's bounds (imageView fills the entire view)
        let viewSize = view.bounds.size

        // If view hasn't been laid out yet, use default scaling
        guard viewSize.width > 0 && viewSize.height > 0 else {
            imageView.imageScaling = .scaleProportionallyUpOrDown
            resetZoomTransform()
            return
        }

        // Get stored zoom scale for current image and window size
        let zoomScale = getCurrentZoomScale()

        // Apply zoom transform if zoom scale is not 1.0
        if zoomScale != 1.0 {
            applyZoomTransform(scale: zoomScale)
            // When zoomed, use scaleProportionallyDown to maintain image quality
            imageView.imageScaling = .scaleProportionallyDown
        } else {
            // Reset transform when zoom is 1.0
            resetZoomTransform()

            // Check if view size exactly matches image size (within 1 point tolerance for floating point precision)
            let sizeTolerance: CGFloat = 1.0
            let widthMatches = abs(imageSize.width - viewSize.width) < sizeTolerance
            let heightMatches = abs(imageSize.height - viewSize.height) < sizeTolerance

            if widthMatches && heightMatches {
                // View size exactly matches image size - show at 100% scale
                // .scaleProportionallyDown won't scale up, so it displays at original size
                imageView.imageScaling = .scaleProportionallyDown
            } else if imageSize.width < viewSize.width && imageSize.height < viewSize.height {
                // Image is smaller than view - keep at original size (centered)
                // .scaleProportionallyDown only scales down, never up, so smaller images stay at original size
                imageView.imageScaling = .scaleProportionallyDown
            } else {
                // Image is larger than or equal to view - scale to fit proportionally
                imageView.imageScaling = .scaleProportionallyUpOrDown
            }
        }

        if let fileURL = displayedFileURL,
           actualSizeImageURLs.contains(fileURL) {
            let currentOffset = imagePanOffsets[fileURL] ?? .zero
            let constrainedOffset = constrainPanOffset(
                currentOffset,
                zoomScale: zoomScale
            )
            if constrainedOffset != currentOffset {
                imagePanOffsets[fileURL] = constrainedOffset
                applyZoomTransform(scale: zoomScale)
            }
        }

        // Update cursor when image scaling changes
        refreshCursorForCurrentMouseLocation()
        refreshBackgroundForCurrentImage()
    }

    // MARK: - Zoom Functionality

    /// Gets the current zoom scale for the displayed image
    /// - Returns: Current zoom scale (defaults to 1.0 if not set)
    private func getCurrentZoomScale() -> CGFloat {
        guard let fileURL = displayedFileURL else {
            return 1.0
        }
        if actualSizeImageURLs.contains(fileURL),
           let image = imageView.image {
            return actualSizeZoomScale(for: image, fileURL: fileURL)
        }
        return imageZoomScales[fileURL] ?? 1.0
    }

    /// Stores the zoom scale for the current image and window size
    /// - Parameter scale: The zoom scale to store
    private func storeZoomScale(_ scale: CGFloat) {
        guard let fileURL = displayedFileURL else {
            return
        }
        actualSizeImageURLs.remove(fileURL)
        imageZoomScales[fileURL] = scale
    }

    /// Returns the transform needed for one image pixel to occupy one physical display pixel.
    private func actualSizeZoomScale(for image: NSImage, fileURL: URL) -> CGFloat {
        guard let baseSize = getBaseDisplayedImageSize(for: image),
              baseSize.width > 0,
              baseSize.height > 0 else {
            return 1.0
        }

        let pixelSize = originalImagePixelSizes[fileURL]
            ?? readOriginalPixelSize(for: fileURL, fallbackImage: image)
        originalImagePixelSizes[fileURL] = pixelSize

        let backingScale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1.0
        let actualSizeInPoints = NSSize(
            width: pixelSize.width / backingScale,
            height: pixelSize.height / backingScale
        )

        let widthScale = actualSizeInPoints.width / baseSize.width
        let heightScale = actualSizeInPoints.height / baseSize.height
        return max(0.0001, min(widthScale, heightScale))
    }

    /// Keeps the normal zoom limit while ensuring Actual Size and zooming beyond it remain possible.
    private func maximumStandardZoomScale(for image: NSImage) -> CGFloat {
        guard let fileURL = displayedFileURL else { return maxZoom }
        return max(
            maxZoom,
            actualSizeZoomScale(for: image, fileURL: fileURL) * maxZoom
        )
    }

    private func readOriginalPixelSize(for fileURL: URL, fallbackImage image: NSImage) -> NSSize {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
           let width = pixelDimension(properties[kCGImagePropertyPixelWidth]),
           let height = pixelDimension(properties[kCGImagePropertyPixelHeight]),
           width > 0,
           height > 0 {
            let orientation = pixelDimension(properties[kCGImagePropertyOrientation]) ?? 1
            if [5, 6, 7, 8].contains(Int(orientation)) {
                return NSSize(width: height, height: width)
            }
            return NSSize(width: width, height: height)
        }

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
    }

    private func pixelDimension(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(number.doubleValue)
        }
        if let integer = value as? Int {
            return CGFloat(integer)
        }
        return nil
    }

    /// Resets the zoom scale to 1.0 for a specific file URL and current window size
    /// Also clears the pan offset
    /// - Parameter fileURL: The file URL to reset zoom for
    private func resetZoomForFile(_ fileURL: URL) {
        actualSizeImageURLs.remove(fileURL)
        imageZoomScales[fileURL] = 1.0
        imagePanOffsets[fileURL] = .zero
    }

    /// Resets zoom to initial state (1.0) for the current file
    /// Clears all zoom/pan states for this file across all window sizes
    /// Called when Cmd+1, Cmd+2, Cmd+3, Cmd+4 change window size
    private func resetZoomToInitial() {
        guard let fileURL = displayedFileURL else { return }

        // Clear zoom/pan state for this file
        actualSizeImageURLs.remove(fileURL)
        imageZoomScales.removeValue(forKey: fileURL)
        imagePanOffsets.removeValue(forKey: fileURL)

        // Reset the zoom transform visually
        resetZoomTransform()

        // Update cursor
        refreshCursorForCurrentMouseLocation()
    }

    /// Gets the current pan offset for the displayed image
    /// - Returns: Current pan offset (defaults to .zero if not set)
    private func getCurrentPanOffset() -> NSPoint {
        guard let fileURL = displayedFileURL else {
            return .zero
        }
        return imagePanOffsets[fileURL] ?? .zero
    }

    /// Stores the pan offset for the current image and window size
    /// - Parameter offset: The pan offset to store
    private func storePanOffset(_ offset: NSPoint) {
        guard let fileURL = displayedFileURL else {
            return
        }
        imagePanOffsets[fileURL] = offset
    }

    /// Applies a zoom transform to the image view, centered on the window's center
    /// Also applies pan offset if available
    /// - Parameter scale: The zoom scale to apply
    private func applyZoomTransform(scale: CGFloat) {
        // Ensure image view has a layer (should already be set in setupImageView)
        imageView.wantsLayer = true
        guard let layer = imageView.layer else { return }

        // Set the anchor point to center (0.5, 0.5) to ensure zoom happens from the center
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // Because Auto Layout is used, we must re-center the anchor point
        // to the middle of the view bounds so the transform doesn't "jump"
        let x = imageView.bounds.midX
        let y = imageView.bounds.midY
        layer.position = CGPoint(x: x, y: y)

        // When zoomed in (scale > 1.0), use nearest-neighbor filtering to show pixel grid
        // When zoomed out or at normal size, use linear filtering for smooth interpolation
        let isActualSize = displayedFileURL.map(actualSizeImageURLs.contains) ?? false
        if scale > 1.0 || isActualSize {
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
        } else {
            layer.magnificationFilter = .linear
            layer.minificationFilter = .linear
        }

        // Get pan offset if zoomed
        let panOffset = scale != 1.0 ? getCurrentPanOffset() : .zero

        // Apply scale transform from the center, then translate for panning
        var transform = CATransform3DMakeScale(scale, scale, 1.0)
        if panOffset != .zero {
            transform = CATransform3DTranslate(transform, panOffset.x, panOffset.y, 0)
        }
        layer.transform = transform
    }

    /// Resets the zoom transform to identity
    private func resetZoomTransform() {
        guard let layer = imageView.layer else { return }

        // Reset transform to identity
        layer.transform = CATransform3DIdentity

        // Reset anchor point and position to defaults
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let x = imageView.bounds.midX
        let y = imageView.bounds.midY
        layer.position = CGPoint(x: x, y: y)

        // Reset to smooth interpolation when not zoomed
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear

        // Clear pan offset when resetting zoom
        if let fileURL = displayedFileURL {
            imagePanOffsets[fileURL] = .zero
        }
    }

    /// Zooms in on the current image
    /// In cmd4 mode: increases image and window size together until the window hits the display cap
    private func zoomIn() {
        guard let image = imageView.image else { return }

        // In cmd4 mode, apply a synchronized window + image zoom step
        if SettingsManager.shared.autoResizeToImageSize {
            zoomInCmd4Mode(image: image)
            return
        }

        // Standard mode: just apply zoom transform
        let currentZoom = getCurrentZoomScale()
        let newZoom = min(
            currentZoom * zoomStep,
            maximumStandardZoomScale(for: image)
        )

        if newZoom != currentZoom {
            storeZoomScale(newZoom)
            updateImageScaling(for: image)
            // Update cursor when zoom changes
            refreshCursorForCurrentMouseLocation()
        }
    }

    /// Zooms out on the current image
    /// In cmd4 mode: shrinks image and window together until the window reaches the fit size
    private func zoomOut() {
        guard let image = imageView.image else { return }

        // In cmd4 mode, apply a synchronized window + image zoom step
        if SettingsManager.shared.autoResizeToImageSize {
            zoomOutCmd4Mode(image: image)
            return
        }

        // Standard mode: just apply zoom transform
        let currentZoom = getCurrentZoomScale()
        let newZoom = max(currentZoom / zoomStep, minZoom)

        if newZoom != currentZoom {
            storeZoomScale(newZoom)
            updateImageScaling(for: image)
            // Update cursor when zoom changes
            refreshCursorForCurrentMouseLocation()
        }
    }

    // MARK: - Cmd4 Mode Zoom Helpers

    /// Gets the maximum (100%) image size in points, capped to screen size
    /// - Returns: The size the window should be at 100% scale (or screen-capped if image is larger)
    private func getMaxImageSizeInPoints() -> NSSize? {
        guard let window = view.window,
              let image = imageView.image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let screen = window.screen ?? NSScreen.main else {
            return nil
        }

        let scaleFactor = screen.backingScaleFactor
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)

        // Convert pixels to points for 100% scale
        var imageSizeInPoints = NSSize(
            width: pixelWidth / scaleFactor,
            height: pixelHeight / scaleFactor
        )

        // Get title bar height
        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        let titleBarHeight = window.frame.height - currentContentRect.height

        // Get available screen size
        let screenFrame = screen.visibleFrame
        let maxContentWidth = screenFrame.width
        let maxContentHeight = screenFrame.height - titleBarHeight

        // Cap to screen size if needed
        if imageSizeInPoints.width > maxContentWidth || imageSizeInPoints.height > maxContentHeight {
            let widthScale = maxContentWidth / imageSizeInPoints.width
            let heightScale = maxContentHeight / imageSizeInPoints.height
            let scale = min(widthScale, heightScale)
            imageSizeInPoints.width *= scale
            imageSizeInPoints.height *= scale
        }

        return imageSizeInPoints
    }

    /// Gets the current window content size
    private func getCurrentContentSize() -> NSSize? {
        guard let window = view.window else { return nil }
        let contentRect = window.contentRect(forFrameRect: window.frame)
        return contentRect.size
    }

    /// Calculates the current window scale relative to the cmd4 fit-to-image size (1.0 = fitted)
    private func getWindowScaleRelativeToImage() -> CGFloat {
        guard let maxSize = getMaxImageSizeInPoints(),
              let currentSize = getCurrentContentSize() else {
            return 1.0
        }

        let widthScale = currentSize.width / maxSize.width
        let heightScale = currentSize.height / maxSize.height
        return min(widthScale, heightScale)
    }

    /// Calculates the effective visible image scale in cmd4 mode.
    /// Below fit size the window controls the visible scale; above fit size the transform does.
    private func getCurrentCmd4EffectiveScale() -> CGFloat {
        let windowScale = getWindowScaleRelativeToImage()
        let transformScale = getCurrentZoomScale()
        return min(windowScale, 1.0) * transformScale
    }

    /// Returns the largest window scale cmd4 mode can use before zoom must continue in the image transform.
    private func getMaxWindowScaleRelativeToImageFit() -> CGFloat {
        guard let window = view.window,
              let screen = window.screen ?? NSScreen.main,
              let maxSize = getMaxImageSizeInPoints() else { return 1.0 }

        let contentRect = window.contentRect(forFrameRect: window.frame)
        let titleBarHeight = window.frame.height - contentRect.height
        let screenFrame = screen.visibleFrame
        let maxContentWidth = screenFrame.width
        let maxContentHeight = screenFrame.height - titleBarHeight

        let widthScale = maxContentWidth / maxSize.width
        let heightScale = maxContentHeight / maxSize.height
        return max(min(widthScale, heightScale), 1.0)
    }

    /// Maps an effective cmd4 zoom target to the matching window scale.
    private func getWindowScaleForCmd4EffectiveScale(_ effectiveScale: CGFloat, maxWindowScale: CGFloat) -> CGFloat {
        if effectiveScale <= 1.0 {
            return effectiveScale
        }

        return min(effectiveScale, maxWindowScale)
    }

    /// Maps an effective cmd4 zoom target to the CATransform scale stored for the image.
    private func getTransformScaleForCmd4EffectiveScale(_ effectiveScale: CGFloat, windowScale: CGFloat) -> CGFloat {
        if windowScale < 1.0 {
            return 1.0
        }

        return effectiveScale
    }

    /// Resizes the window to a scale relative to the cmd4 fit size.
    private func resizeWindowToCmd4Scale(_ windowScale: CGFloat, animated: Bool, image: NSImage) {
        guard let window = view.window,
              let screen = window.screen ?? NSScreen.main,
              let fitSize = getMaxImageSizeInPoints() else { return }

        let contentRect = window.contentRect(forFrameRect: window.frame)
        let titleBarHeight = window.frame.height - contentRect.height
        let maxContentWidth = screen.visibleFrame.width
        let maxContentHeight = screen.visibleFrame.height - titleBarHeight
        let minWindowSize: CGFloat = 100

        var newContentSize = NSSize(
            width: fitSize.width * windowScale,
            height: fitSize.height * windowScale
        )
        newContentSize.width = min(max(newContentSize.width, minWindowSize), maxContentWidth)
        newContentSize.height = min(max(newContentSize.height, minWindowSize), maxContentHeight)

        let newWindowSize = NSSize(
            width: newContentSize.width,
            height: newContentSize.height + titleBarHeight
        )

        let newOrigin: NSPoint
        switch SettingsManager.shared.windowResizeAnchor {
        case .topLeft:
            let currentFrame = window.frame
            newOrigin = NSPoint(
                x: currentFrame.minX,
                y: currentFrame.maxY - newWindowSize.height
            )
        case .center:
            let screenFrame = screen.visibleFrame
            newOrigin = NSPoint(
                x: screenFrame.midX - newWindowSize.width / 2,
                y: screenFrame.midY - newWindowSize.height / 2
            )
        }

        let newFrame = NSRect(origin: newOrigin, size: newWindowSize)

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.allowsImplicitAnimation = true
                window.animator().setFrame(newFrame, display: true)
            }, completionHandler: {
                if let image = self.imageView.image {
                    self.updateImageScaling(for: image)
                }
                self.refreshCursorForCurrentMouseLocation()
            })
        } else {
            window.setFrame(newFrame, display: true)
            if let image = imageView.image {
                updateImageScaling(for: image)
            }
            refreshCursorForCurrentMouseLocation()
        }
    }

    /// Applies one synchronized cmd4 zoom step.
    /// The window tracks the visible image size until it hits the display cap.
    private func zoomCmd4Mode(image: NSImage, factor: CGFloat) {
        let tolerance: CGFloat = 0.001
        let currentEffectiveScale = getCurrentCmd4EffectiveScale()
        let targetEffectiveScale = min(max(currentEffectiveScale * factor, minZoom), maxZoom)

        if abs(targetEffectiveScale - currentEffectiveScale) < tolerance {
            return
        }

        let maxWindowScale = getMaxWindowScaleRelativeToImageFit()
        let currentWindowScale = getWindowScaleRelativeToImage()
        let targetWindowScale = getWindowScaleForCmd4EffectiveScale(
            targetEffectiveScale,
            maxWindowScale: maxWindowScale
        )
        let targetTransformScale = getTransformScaleForCmd4EffectiveScale(
            targetEffectiveScale,
            windowScale: targetWindowScale
        )

        storeZoomScale(targetTransformScale)

        if abs(targetWindowScale - currentWindowScale) < tolerance {
            updateImageScaling(for: image)
            refreshCursorForCurrentMouseLocation()
            return
        }

        resizeWindowToCmd4Scale(targetWindowScale, animated: true, image: image)
    }

    /// Zoom in for cmd4 mode by increasing the effective visible scale.
    private func zoomInCmd4Mode(image: NSImage) {
        zoomCmd4Mode(image: image, factor: zoomStep)
    }

    /// Zoom out for cmd4 mode by decreasing the effective visible scale.
    private func zoomOutCmd4Mode(image: NSImage) {
        zoomCmd4Mode(image: image, factor: 1.0 / zoomStep)
    }

    /// Displays the current image pixel-for-pixel without changing the window frame.
    internal func displayImageAtActualSize() {
        guard let image = imageView.image,
              let fileURL = displayedFileURL else { return }

        if SettingsManager.shared.autoResizeToImageSize {
            SettingsManager.shared.autoResizeToImageSize = false
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.updateMenuStates()
                appDelegate.updateSettingsWindowUI()
            }
        }

        originalImagePixelSizes[fileURL] = readOriginalPixelSize(
            for: fileURL,
            fallbackImage: image
        )
        actualSizeImageURLs.insert(fileURL)
        imageZoomScales.removeValue(forKey: fileURL)
        imagePanOffsets[fileURL] = .zero

        updateImageScaling(for: image)
        requestSharperImageIfNeeded()
        refreshCursorForCurrentMouseLocation()
    }

    /// Recomputes Actual Size when a window moves between displays with different scale factors.
    internal func refreshImageScalingForBackingScaleChange() {
        guard let fileURL = displayedFileURL,
              actualSizeImageURLs.contains(fileURL),
              let image = imageView.image else { return }

        updateImageScaling(for: image)
        requestSharperImageIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        // Update layer position when view layout changes (important for anchor point)
        if let layer = imageView.layer, layer.anchorPoint == CGPoint(x: 0.5, y: 0.5) {
            let x = imageView.bounds.midX
            let y = imageView.bounds.midY
            layer.position = CGPoint(x: x, y: y)
        }

        // Update scaling when view size changes (e.g., window resize)
        // Note: When window size changes, we need to check if there's a stored zoom for the new size
        if let image = imageView.image {
            updateImageScaling(for: image)
            requestSharperImageIfNeeded()
        }
        // Update pill visibility based on window size and current file
        updatePillVisibilityForWindowSize()
        // Ensure file name pill is hidden if no file is selected
        if displayedFileURL == nil {
            fileNamePill.isHidden = true
        }
    }

    /// Updates the remaining file-info pill visibility based on window size.
    private func updatePillVisibilityForWindowSize() {
        guard view.bounds.width > 0 else { return }
        fileNamePill?.isHidden = true

        guard displayedFileURL != nil else {
            fileInfoPill?.isHidden = true
            return
        }

        let viewWidth = view.bounds.width
        let shouldShowFileInfoPill = SettingsManager.shared.showFileInfoPill
        let fileInfoPillWidth = shouldShowFileInfoPill && fileInfoPill != nil ? fileInfoPillWidthConstraint.constant : 0
        let leftPadding: CGFloat = 16
        let rightPadding: CGFloat = 16
        let requiredWidth = leftPadding + fileInfoPillWidth + rightPadding
        fileInfoPill.isHidden = !shouldShowFileInfoPill || requiredWidth > viewWidth
    }

    /// Loads and displays an image from file path
    /// - Parameter filePath: Path to the image file
    func loadImage(from filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        loadImage(from: fileURL)
    }

    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }

    // MARK: - File Info Pill

    /// Sets up the file info pill view at the bottom left corner
    private func setupFileInfoPill() {
        // Create visual effect view with material surface
        fileInfoPill = NSVisualEffectView()
        fileInfoPill.material = .hudWindow
        fileInfoPill.blendingMode = .withinWindow
        fileInfoPill.state = .active
        fileInfoPill.translatesAutoresizingMaskIntoConstraints = false

        // Make it pill-shaped with rounded corners
        fileInfoPill.wantsLayer = true
        fileInfoPill.layer?.cornerRadius = 12

        // Create label for file info
        fileInfoLabel = NSTextField(labelWithString: "")
        fileInfoLabel.font = .systemFont(ofSize: 11, weight: .medium)
        fileInfoLabel.textColor = .labelColor
        fileInfoLabel.alignment = .left
        fileInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        fileInfoLabel.lineBreakMode = .byClipping
        fileInfoLabel.cell?.wraps = false

        fileInfoPill.addSubview(fileInfoLabel)
        view.addSubview(fileInfoPill, positioned: .above, relativeTo: imageView)

        // Layout constraints
        fileInfoPillWidthConstraint = fileInfoPill.widthAnchor.constraint(equalToConstant: 200)

        NSLayoutConstraint.activate([
            // Pill constraints - bottom left corner with padding
            fileInfoPill.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fileInfoPill.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            fileInfoPill.heightAnchor.constraint(equalToConstant: 24),
            fileInfoPillWidthConstraint,

            // Label constraints - trailing anchor with 15pt padding
            fileInfoLabel.trailingAnchor.constraint(equalTo: fileInfoPill.trailingAnchor, constant: -15),
            fileInfoLabel.centerYAnchor.constraint(equalTo: fileInfoPill.centerYAnchor)
        ])

        // Label leading constraint - will be updated when circle is set up
        // Default: 15pt from leading edge (when circle is hidden)
        fileInfoLabelLeadingConstraint = fileInfoLabel.leadingAnchor.constraint(equalTo: fileInfoPill.leadingAnchor, constant: 15)
        fileInfoLabelLeadingConstraint.isActive = true

        // Initially hide/show based on whether any option is enabled
        fileInfoPill.isHidden = !SettingsManager.shared.showFileInfoPill
    }

    /// Sets up the file name pill view at the bottom right corner
    private func setupFileNamePill() {
        // Create visual effect view with material surface
        fileNamePill = NSVisualEffectView()
        fileNamePill.material = .hudWindow
        fileNamePill.blendingMode = .withinWindow
        fileNamePill.state = .active
        fileNamePill.translatesAutoresizingMaskIntoConstraints = false

        // Make it pill-shaped with rounded corners
        fileNamePill.wantsLayer = true
        fileNamePill.layer?.cornerRadius = 12

        // Create label for file name
        fileNameLabel = NSTextField(labelWithString: "")
        fileNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        fileNameLabel.textColor = .labelColor
        fileNameLabel.alignment = .left
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.cell?.wraps = false

        fileNamePill.addSubview(fileNameLabel)
        view.addSubview(fileNamePill, positioned: .above, relativeTo: imageView)

        // Layout constraints
        // Set a maximum width for the pill (will truncate middle if filename is too long)
        fileNamePillWidthConstraint = fileNamePill.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        // Set minimum width of 150pt
        fileNamePillMinWidthConstraint = fileNamePill.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)

        NSLayoutConstraint.activate([
            // Pill constraints - bottom right corner with padding
            fileNamePill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            fileNamePill.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            fileNamePill.heightAnchor.constraint(equalToConstant: 24),
            fileNamePillWidthConstraint,
            fileNamePillMinWidthConstraint,

            // Label constraints - 15pt padding inside pill on both sides
            fileNameLabel.leadingAnchor.constraint(equalTo: fileNamePill.leadingAnchor, constant: 15),
            fileNameLabel.trailingAnchor.constraint(equalTo: fileNamePill.trailingAnchor, constant: -15),
            fileNameLabel.centerYAnchor.constraint(equalTo: fileNamePill.centerYAnchor)
        ])

        // Initially hide (will be shown/hidden based on setting)
        fileNamePill.isHidden = true
    }

    /// Sets up the file tag circle container view
    private func setupFileTagCircle() {
        // Create a container view for tag circles (can hold multiple circles)
        fileTagCircleContainer = NSView()
        fileTagCircleContainer.translatesAutoresizingMaskIntoConstraints = false
        fileTagCircleContainer.wantsLayer = true

        // Add container as subview of the pill (inside the pill)
        fileInfoPill.addSubview(fileTagCircleContainer)

        // Position: inside the pill, with spacing from leading edge
        fileTagCircleContainerWidthConstraint = fileTagCircleContainer.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            fileTagCircleContainer.leadingAnchor.constraint(equalTo: fileInfoPill.leadingAnchor, constant: 8),
            fileTagCircleContainer.centerYAnchor.constraint(equalTo: fileInfoPill.centerYAnchor),
            fileTagCircleContainer.heightAnchor.constraint(equalToConstant: 12),
            fileTagCircleContainerWidthConstraint
        ])

        // Initially hide (will be shown/hidden based on setting and file tags)
        fileTagCircleContainer.isHidden = true
    }

    private func setupLoadingOverlay() {
        loadingOverlayView = nil
        loadingSpinner = nil
    }

    private func showLoadingOverlay() {
        // Spinner intentionally removed from the UI.
    }

    private func hideLoadingOverlay() {
        // Spinner intentionally removed from the UI.
    }

    /// Sets up the toast notification view for displaying temporary messages (e.g., undo feedback)
    private func setupToastNotification() {
        // Create visual effect view with material surface
        toastView = NSVisualEffectView()
        toastView.material = .hudWindow
        toastView.blendingMode = .withinWindow
        toastView.state = .active
        toastView.translatesAutoresizingMaskIntoConstraints = false

        // Make it pill-shaped with rounded corners
        toastView.wantsLayer = true
        toastView.layer?.cornerRadius = 12

        // Create label for toast message
        toastLabel = NSTextField(labelWithString: "")
        toastLabel.font = .systemFont(ofSize: 13, weight: .medium)
        toastLabel.textColor = .labelColor
        toastLabel.alignment = .center
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.lineBreakMode = .byClipping
        toastLabel.cell?.wraps = false

        toastView.addSubview(toastLabel)
        view.addSubview(toastView, positioned: .above, relativeTo: imageView)

        // Layout constraints - centered both horizontally and vertically
        NSLayoutConstraint.activate([
            toastView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            toastView.heightAnchor.constraint(equalToConstant: 40),
            toastView.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),

            toastLabel.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 20),
            toastLabel.trailingAnchor.constraint(equalTo: toastView.trailingAnchor, constant: -20),
            toastLabel.centerYAnchor.constraint(equalTo: toastView.centerYAnchor)
        ])

        // Initially hide the toast
        toastView.alphaValue = 0
    }

    /// Shows a toast notification with the given message
    /// The toast automatically dismisses after 3 seconds
    /// - Parameter message: The message to display
    private func showToast(message: String) {
        toastLabel.stringValue = message

        // Cancel any existing hide animation
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideToast), object: nil)

        // Animate the toast fading in
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toastView.animator().alphaValue = 1.0
        }, completionHandler: {
            // Auto-hide after 3 seconds
            self.perform(#selector(self.hideToast), with: nil, afterDelay: 3.0)
        })
    }

    /// Hides the toast notification with animation
    @objc private func hideToast() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            toastView.animator().alphaValue = 0
        })
    }


    /// Recalculates the file info pill width based on current label text and circle visibility
    private func recalculateFileInfoPillWidth() {
        guard let label = fileInfoLabel, fileInfoPill != nil else { return }

        let infoText = label.stringValue
        guard !infoText.isEmpty else { return }

        // Calculate exact text width
        let font = label.font ?? .systemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedString = NSAttributedString(string: infoText, attributes: attributes)
        let textSize = attributedString.size()
        let labelWidth = textSize.width

        // Calculate pill width accounting for circles if visible
        let isCircleVisible = !(fileTagCircleContainer?.isHidden ?? true)
        let circleWidth = fileTagCircleContainerWidthConstraint?.constant ?? 0
        let leadingPadding: CGFloat = isCircleVisible ? (8 + circleWidth + 6) : 15 // Circle space or default padding
        let trailingPadding: CGFloat = 15
        let pillWidth = labelWidth + leadingPadding + trailingPadding
        fileInfoPillWidthConstraint.constant = pillWidth

        // Update pill visibility based on window size
        updatePillVisibilityForWindowSize()
    }

    private func hideFileTagDisplay() {
        guard let container = fileTagCircleContainer else { return }

        for circle in fileTagCircles {
            circle.removeFromSuperview()
        }
        fileTagCircles.removeAll()
        container.isHidden = true
        fileTagCircleContainerWidthConstraint.constant = 0

        if fileInfoLabel != nil, fileInfoPill != nil {
            fileInfoLabelLeadingConstraint.isActive = false
            fileInfoLabelLeadingConstraint = fileInfoLabel.leadingAnchor.constraint(equalTo: fileInfoPill.leadingAnchor, constant: 15)
            fileInfoLabelLeadingConstraint.isActive = true
        }
    }

    /// File-tag display was removed; retain the entry point for compatibility.
    func updateFileTagDisplay(for fileURL: URL?) {
        fileTagGeneration += 1
        hideFileTagDisplay()
    }

    /// Returns color for a tag name (maps tag names to macOS default colors)
    private func colorForTagName(_ tagName: String) -> NSColor? {
        // macOS default tag names and colors
        let lowercased = tagName.lowercased()
        switch lowercased {
        case "gray", "grey":
            return NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.55, alpha: 1.0)
        case "green":
            return NSColor(calibratedRed: 0.48, green: 0.84, blue: 0.32, alpha: 1.0)
        case "purple":
            return NSColor(calibratedRed: 0.70, green: 0.42, blue: 0.93, alpha: 1.0)
        case "blue":
            return NSColor(calibratedRed: 0.24, green: 0.56, blue: 0.95, alpha: 1.0)
        case "yellow":
            return NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.24, alpha: 1.0)
        case "red":
            return NSColor(calibratedRed: 0.96, green: 0.32, blue: 0.32, alpha: 1.0)
        case "orange":
            return NSColor(calibratedRed: 0.98, green: 0.63, blue: 0.24, alpha: 1.0)
        default:
            // For custom tag names, try to derive from label number or use a default color
            return nil
        }
    }

    /// Returns color for a label number (legacy support)
    private func colorForLabelNumber(_ labelNum: Int) -> NSColor? {
        switch labelNum {
        case 1: // Gray
            return NSColor(calibratedRed: 0.55, green: 0.55, blue: 0.55, alpha: 1.0)
        case 2: // Green
            return NSColor(calibratedRed: 0.48, green: 0.84, blue: 0.32, alpha: 1.0)
        case 3: // Purple
            return NSColor(calibratedRed: 0.70, green: 0.42, blue: 0.93, alpha: 1.0)
        case 4: // Blue
            return NSColor(calibratedRed: 0.24, green: 0.56, blue: 0.95, alpha: 1.0)
        case  5: // Yellow
            return NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.24, alpha: 1.0)
        case 6: // Red
            return NSColor(calibratedRed: 0.96, green: 0.32, blue: 0.32, alpha: 1.0)
        case 7: // Orange
            return NSColor(calibratedRed: 0.98, green: 0.63, blue: 0.24, alpha: 1.0)
        default:
            return nil
        }
    }

    /// Updates file info pill visibility based on settings
    /// Pill is shown if any display option is enabled and a file is open
    func updateFileInfoPillVisibility() {
        guard let fileInfoPill = fileInfoPill else { return }

        // Hide pill if no file is open
        guard let currentFileURL = displayedFileURL else {
            fileInfoPill.isHidden = true
            return
        }

        // Show pill if any option is enabled
        fileInfoPill.isHidden = !SettingsManager.shared.showFileInfoPill

        // If any option is enabled and we have a current file, update the info
        if SettingsManager.shared.showFileInfoPill {
            updateFileInfo(for: currentFileURL)
        }

        // Update pill visibility based on window size after updating settings
        updatePillVisibilityForWindowSize()
    }

    /// Updates the transparency checker pattern visibility based on settings and current image
    func updateTransparencyCheckerVisibility() {
        guard let checkerView = transparencyCheckerView else { return }

        // Hide if setting is not set to checkers
        guard SettingsManager.shared.transparencyBackground == .checkers else {
            checkerView.isHidden = true
            return
        }

        // Hide if no image is displayed
        guard let image = imageView.image else {
            checkerView.isHidden = true
            return
        }

        // Show checker only if image has transparency
        checkerView.isHidden = !imageHasTransparency(image)
    }

    /// Checks if an image has an alpha channel (transparency)
    private func imageHasTransparency(_ image: NSImage) -> Bool {
        // Get the best representation to check for alpha
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Try to get from representations
            for rep in image.representations {
                if let bitmapRep = rep as? NSBitmapImageRep {
                    return bitmapRep.hasAlpha
                }
            }
            return false
        }

        // Check if the CGImage has an alpha channel
        let alphaInfo = cgImage.alphaInfo
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        case .premultipliedFirst, .premultipliedLast, .first, .last, .alphaOnly:
            return true
        @unknown default:
            return false
        }
    }

    /// Updates the file info pill with enabled display options
    /// Only reads file attributes if at least one option is enabled (for performance)
    /// - Parameter fileURL: URL to the file
    func updateFileInfo(for fileURL: URL) {
        fileInfoGeneration += 1
        let generation = fileInfoGeneration

        // Skip file attribute reading if all options are disabled (performance optimization)
        guard SettingsManager.shared.showFileInfoPill else {
            fileInfoPill?.isHidden = true
            return
        }

        // Get file attributes asynchronously to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            var fileSize: Int64 = 0
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                fileSize = (attributes[.size] as? Int64) ?? 0
            } catch {
                // If we can't get attributes, fileSize will remain 0
            }

            // Format file size (only if setting is enabled)
            var formattedSize: String? = nil
            if SettingsManager.shared.showFileSize {
                formattedSize = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }

            // Get image resolution from file metadata (if setting is enabled)
            var resolutionString: String? = nil
            if SettingsManager.shared.showImageResolution {
                // Read actual image dimensions from file metadata using CGImageSource
                // This gives us the original resolution, not the thumbnail size
                if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                   let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {

                    // Handle both Int and NSNumber types for width/height
                    var width: Int? = nil
                    var height: Int? = nil

                    if let widthValue = imageProperties[kCGImagePropertyPixelWidth] {
                        if let intValue = widthValue as? Int {
                            width = intValue
                        } else if let numberValue = widthValue as? NSNumber {
                            width = numberValue.intValue
                        }
                    }

                    if let heightValue = imageProperties[kCGImagePropertyPixelHeight] {
                        if let intValue = heightValue as? Int {
                            height = intValue
                        } else if let numberValue = heightValue as? NSNumber {
                            height = numberValue.intValue
                        }
                    }

                    if let w = width, let h = height, w > 0 && h > 0 {
                        resolutionString = "\(w)×\(h)"
                    }
                }
            }

            // Update UI on main thread
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.fileInfoGeneration == generation,
                      self.displayedFileURL == fileURL,
                      SettingsManager.shared.showFileInfoPill else {
                    return
                }

                // Build info string - only include enabled options
                var infoComponents: [String] = []

                // Add file size if enabled
                if let size = formattedSize {
                    infoComponents.append(size)
                }

                // Add resolution if enabled
                if let resolution = resolutionString {
                    infoComponents.append(resolution)
                }

                // Only show pill if at least one option is enabled
                if !infoComponents.isEmpty {
                    let infoText = infoComponents.joined(separator: " • ")
                    self.fileInfoLabel.stringValue = infoText
                    self.fileInfoPill.isHidden = false

                    // Recalculate pill width (accounts for circle visibility)
                    self.recalculateFileInfoPillWidth()
                } else {
                    // Hide pill if no options are enabled
                    self.fileInfoPill.isHidden = true
                }
            }
        }
    }

    /// Checks whether the window content size currently matches the image-fit size
    /// Used to decide if Cmd+4 should toggle off or re-apply the fit
    /// - Returns: true if the window is already at the image-fit size (within tolerance)
    internal func isWindowAtImageFitSize() -> Bool {
        guard let maxSize = getMaxImageSizeInPoints(),
              let currentSize = getCurrentContentSize() else {
            return false
        }
        let tolerance: CGFloat = 2.0
        return abs(currentSize.width - maxSize.width) < tolerance &&
               abs(currentSize.height - maxSize.height) < tolerance
    }

    /// Auto-resizes window to image size if the setting is enabled
    /// Called when the setting is toggled and an image is already loaded
    func autoResizeToImageSizeIfEnabled() {
        guard SettingsManager.shared.autoResizeToImageSize,
              imageView.image != nil else {
            return
        }
        resizeWindowToImageSize(animated: false)
    }

    // MARK: - Appearance Management

    /// Keeps the empty canvas distinct while preserving the normal image background.
    internal func refreshBackgroundForCurrentImage() {
        assert(Thread.isMainThread, "refreshBackgroundForCurrentImage must be called on main thread")
        if displayedFileURL == nil {
            useEmptyWindowBackground()
        } else {
            useDefaultWindowBackground()
        }
    }

    private func useEmptyWindowBackground() {
        let appearance = view.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let emptyColor = Self.emptyWindowBackgroundColor
            self.view.window?.backgroundColor = emptyColor
            if self.view.layer?.backgroundColor != emptyColor.cgColor {
                self.updateBackgroundColor(emptyColor)
            }
        }
    }

    private func useDefaultWindowBackground() {
        let appearance = view.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let defaultColor = NSColor.windowBackgroundColor
            self.view.window?.backgroundColor = defaultColor
            if self.view.layer?.backgroundColor != defaultColor.cgColor {
                self.updateBackgroundColor(defaultColor)
            }
        }
    }

    /// Updates the view background color (called when appearance changes)
    /// - Parameter color: The new background color to apply
    func updateBackgroundColor(_ color: NSColor) {
        // Ensure we're on the main thread
        assert(Thread.isMainThread, "updateBackgroundColor must be called on main thread")

        // Update the layer background color immediately
        // The color should be resolved within performAsCurrentDrawingAppearance context
        view.layer?.backgroundColor = color.cgColor

        // Force view to update its appearance and redraw
        view.needsDisplay = true
        view.displayIfNeeded()
    }

    // MARK: - Drag and Drop Support

    /// Sets up drag and drop support for the view
    private func setupDragAndDrop() {
        // Drag and drop is handled by DraggableImageView which forwards to this view controller
        // The imageView is set up in setupImageView() with the dragging delegate
        // Also register on the main view as a fallback
        view.registerForDraggedTypes([.fileURL])
    }

    // MARK: - NSDraggingDestination

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let firstImageURL = supportedDraggedImageURLs(from: sender.draggingPasteboard).first else {
            clearDragPreparation()
            return []
        }

        beginDragPreparation(for: firstImageURL)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingEntered(sender)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let firstImageURL = supportedDraggedImageURLs(from: sender.draggingPasteboard).first else {
            clearDragPreparation()
            return false
        }

        beginDragPreparation(for: firstImageURL, dropPending: true)
        commitPreparedDropIfReady()
        return true
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        clearDragPreparation()
    }

    private func supportedDraggedImageURLs(from pasteboard: NSPasteboard) -> [URL] {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            return []
        }

        let supportedExtensions = SettingsManager.shared.supportedExtensions
        return urls.filter { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }
    }

    private func clearDragPreparation() {
        dragPreparationGeneration += 1
        dragPreparationState = nil
    }

    private func beginDragPreparation(for fileURL: URL, dropPending: Bool = false) {
        if var existingState = dragPreparationState, existingState.fileURL == fileURL {
            if dropPending && !existingState.dropPending {
                existingState.dropPending = true
                dragPreparationState = existingState
            }
            return
        }

        dragPreparationGeneration += 1
        let generation = dragPreparationGeneration
        dragPreparationState = DragPreparationState(
            fileURL: fileURL,
            generation: generation,
            dropPending: dropPending
        )

        ImageCacheManager.shared.removeCachedImage(for: fileURL)
        prepareDraggedImage(for: fileURL, generation: generation)
        prepareDraggedFileList(for: fileURL, generation: generation)
    }

    private func prepareDraggedImage(for fileURL: URL, generation: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let cachedImage = ImageCacheManager.shared.getCachedImage(for: fileURL)
            let image = cachedImage ?? ImageLoader.shared.loadImage(from: fileURL)

            if let image = image {
                ImageCacheManager.shared.cacheImage(image, for: fileURL)
            }

            DispatchQueue.main.async { [weak self] in
                self?.completeDraggedImagePreparation(
                    for: fileURL,
                    generation: generation,
                    image: image
                )
            }
        }
    }

    private func prepareDraggedFileList(for fileURL: URL, generation: Int) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let preparedFileList = self.fileListManager.prepareFiles(fromDirectoryContaining: fileURL)

            DispatchQueue.main.async { [weak self] in
                self?.completeDraggedFileListPreparation(
                    for: fileURL,
                    generation: generation,
                    preparedFileList: preparedFileList
                )
            }
        }
    }

    private func completeDraggedImagePreparation(
        for fileURL: URL,
        generation: Int,
        image: NSImage?
    ) {
        guard var state = dragPreparationState,
              state.generation == generation,
              state.fileURL == fileURL else {
            return
        }

        state.preparedImage = image
        state.imagePreparationCompleted = true
        dragPreparationState = state

        if state.dropPending {
            commitPreparedDropIfReady()
        }
    }

    private func completeDraggedFileListPreparation(
        for fileURL: URL,
        generation: Int,
        preparedFileList: FileListManager.PreparedFileList?
    ) {
        guard var state = dragPreparationState,
              state.generation == generation,
              state.fileURL == fileURL else {
            return
        }

        state.preparedFileList = preparedFileList
        state.fileListPreparationCompleted = true
        dragPreparationState = state

        if state.dropPending {
            commitPreparedDropIfReady()
        }
    }

    private func commitPreparedDropIfReady() {
        guard let state = dragPreparationState, state.dropPending else {
            return
        }

        guard state.imagePreparationCompleted, state.fileListPreparationCompleted else {
            return
        }

        guard let preparedImage = state.preparedImage else {
            clearDragPreparation()
            return
        }

        let fileListCommit: FileListCommit = state.preparedFileList.map { .prepared($0) } ?? .singleFile(state.fileURL)
        clearDragPreparation()
        displayImage(
            from: state.fileURL,
            fileListCommit: fileListCommit,
            preferredImage: preparedImage
        )

        DispatchQueue.main.async { [weak self] in
            self?.view.window?.makeFirstResponder(self)
        }
    }

    // MARK: - PanningHandler

    /// Calculates the image size after NSImageView fitting and before the zoom transform.
    private func getBaseDisplayedImageSize(for image: NSImage) -> NSSize? {
        let viewSize = view.bounds.size
        let imageSize = image.size
        guard viewSize.width > 0,
              viewSize.height > 0,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }

        let widthScale = viewSize.width / imageSize.width
        let heightScale = viewSize.height / imageSize.height
        let fittedScale = min(1.0, min(widthScale, heightScale))

        return NSSize(
            width: imageSize.width * fittedScale,
            height: imageSize.height * fittedScale
        )
    }

    /// Calculates the current displayed image size after view fitting and zoom transform.
    private func getDisplayedImageSize(for zoomScale: CGFloat) -> NSSize? {
        guard let image = imageView.image,
              let baseSize = getBaseDisplayedImageSize(for: image) else {
            return nil
        }
        return NSSize(
            width: baseSize.width * zoomScale,
            height: baseSize.height * zoomScale
        )
    }

    /// Returns whether the current image extends beyond the view and can actually be panned.
    private func canPanCurrentImage() -> Bool {
        guard let displayedImageSize = getDisplayedImageSize(for: getCurrentZoomScale()) else {
            return false
        }

        let viewSize = view.bounds.size
        let tolerance: CGFloat = 1.0
        return displayedImageSize.width > viewSize.width + tolerance ||
               displayedImageSize.height > viewSize.height + tolerance
    }

    /// Determines if panning should start (only when image is zoomed)
    func shouldStartPanning(at location: NSPoint) -> Bool {
        return canPanCurrentImage()
    }

    /// Returns whether panning is available (image is zoomed in)
    func isPanningAvailable() -> Bool {
        return canPanCurrentImage()
    }


    /// Updates cursor based on zoom and panning state
    func handleCursorUpdate(at location: NSPoint) {
        // Don't change cursor if we're actively panning (closed hand is already shown)
        if isPanning {
            return
        }

        if let hit = imageLinkHit(at: location) {
            (imageView as? DraggableImageView)?.showLinkHoverBorder(
                in: hit.bounds,
                displayScale: getCurrentZoomScale()
            )
            if openHandCursorPushed {
                NSCursor.pop()
                openHandCursorPushed = false
            }
            if !linkCursorPushed {
                NSCursor.pointingHand.push()
                linkCursorPushed = true
            }
            return
        }

        (imageView as? DraggableImageView)?.hideLinkHoverBorder()
        clearLinkCursor()

        // If panning is available (zoomed), show open hand cursor
        if isPanningAvailable() {
            if !openHandCursorPushed {
                // Pop any existing cursor first to avoid cursor stack issues
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
                NSCursor.openHand.push()
                openHandCursorPushed = true
            }
        } else {
            // Not zoomed, reset cursor
            if openHandCursorPushed {
                NSCursor.pop()
                openHandCursorPushed = false
            }
            if cursorPushed {
                NSCursor.pop()
                cursorPushed = false
            }
        }
    }

    func handleCursorExit() {
        (imageView as? DraggableImageView)?.hideLinkHoverBorder()
        clearLinkCursor()
        if openHandCursorPushed {
            NSCursor.pop()
            openHandCursorPushed = false
        }
    }

    private func clearLinkCursor() {
        if linkCursorPushed {
            NSCursor.pop()
            linkCursorPushed = false
        }
    }

    private func refreshCursorForCurrentMouseLocation() {
        guard let window = view.window else { return }
        let location = imageView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard imageView.bounds.contains(location) else {
            handleCursorExit()
            return
        }
        handleCursorUpdate(at: location)
    }

    /// Converts the pointer through the image view's layer transform so link
    /// hit-testing stays aligned while the image is zoomed or panned.
    private struct ImageLinkHit {
        let link: DetectedImageLink
        let bounds: CGRect
    }

    private func imageLink(at location: NSPoint) -> DetectedImageLink? {
        imageLinkHit(at: location)?.link
    }

    private func imageLinkHit(at location: NSPoint) -> ImageLinkHit? {
        guard !detectedImageLinks.isEmpty,
              let displayedSize = getDisplayedImageSize(for: 1.0) else {
            return nil
        }

        let untransformedLocation: CGPoint
        if let layer = imageView.layer, let superlayer = layer.superlayer {
            untransformedLocation = layer.convert(location, from: superlayer)
        } else {
            untransformedLocation = location
        }

        let imageRect = CGRect(
            x: imageView.bounds.midX - displayedSize.width / 2,
            y: imageView.bounds.midY - displayedSize.height / 2,
            width: displayedSize.width,
            height: displayedSize.height
        )
        guard imageRect.contains(untransformedLocation) else {
            return nil
        }

        for link in detectedImageLinks {
            let bounds = CGRect(
                x: imageRect.minX + link.normalizedBounds.minX * imageRect.width,
                y: imageRect.minY + link.normalizedBounds.minY * imageRect.height,
                width: link.normalizedBounds.width * imageRect.width,
                height: link.normalizedBounds.height * imageRect.height
            ).insetBy(dx: -2, dy: -2)
            if bounds.contains(untransformedLocation) {
                return ImageLinkHit(link: link, bounds: bounds)
            }
        }
        return nil
    }

    /// Handles the start of a pan gesture
    func handlePanStart(at location: NSPoint) {
        guard imageView.image != nil else { return }

        (imageView as? DraggableImageView)?.hideLinkHoverBorder()
        clearLinkCursor()

        // Pop open hand cursor if it was shown
        if openHandCursorPushed {
            NSCursor.pop()
            openHandCursorPushed = false
        }

        isPanning = true
        panStartLocation = location
        panStartOffset = getCurrentPanOffset()

        // Change cursor to closed hand (grabbing) when panning starts
        NSCursor.closedHand.push()
        cursorPushed = true
    }

    /// Handles panning movement
    func handlePanMove(to location: NSPoint) {
        guard isPanning, imageView.image != nil else { return }

        // Calculate the delta from the start location
        let deltaX = location.x - panStartLocation.x
        let deltaY = location.y - panStartLocation.y

        // Calculate new pan offset
        var newOffset = NSPoint(
            x: panStartOffset.x + deltaX,
            y: panStartOffset.y + deltaY
        )

        // Constrain panning to keep image within reasonable bounds
        newOffset = constrainPanOffset(newOffset, zoomScale: getCurrentZoomScale())

        // Store and apply the new offset
        storePanOffset(newOffset)
        applyZoomTransform(scale: getCurrentZoomScale())
    }

    /// Handles the end of a pan gesture
    func handlePanEnd() {
        isPanning = false

        // Reset cursor to default when panning ends
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }

        refreshCursorForCurrentMouseLocation()
    }

    /// Matches feh's default left-click action in slideshow mode.
    func handleImageLinkClick(at location: NSPoint) -> Bool {
        guard let link = imageLink(at: location) else {
            return false
        }
        openImageLink(link.url)
        return true
    }

    func handlePrimaryImageClick(at location: NSPoint) {
        guard displayedFileURL != nil else { return }
        if handleImageLinkClick(at: location) {
            return
        }
        navigateToNext()
    }

    private func openImageLink(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            showToast(message: "Couldn't open \(url.absoluteString)")
        }
    }

    /// Handles mouse-wheel navigation and trackpad panning/navigation.
    func handleScroll(with event: NSEvent) {
        guard imageView.image != nil else { return }
        PerformanceLog.shared.event(
            "SCROLL",
            String(
                format: "dx=%.2f dy=%.2f precise=%d phase=%ld momentum=%ld zoom=%.3f",
                event.scrollingDeltaX,
                event.scrollingDeltaY,
                event.hasPreciseScrollingDeltas ? 1 : 0,
                event.phase.rawValue,
                event.momentumPhase.rawValue,
                getCurrentZoomScale()
            )
        )

        // Keep two-finger panning for zoomed images. A mouse wheel still navigates
        // between files, even while the current image is zoomed.
        if event.hasPreciseScrollingDeltas && isPanningAvailable() {
            panImage(with: event)
            return
        }

        if navigateWithScroll(event) {
            // Draw the cache hit now, but let AppKit commit the backing layer at the
            // normal event-loop boundary. Forcing a Core Animation flush from every
            // wheel callback can disturb the current event-tracking sequence.
            imageView.displayIfNeeded()
        }
    }

    private func panImage(with event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        let deltaY = -event.scrollingDeltaY

        let currentOffset = getCurrentPanOffset()
        var newOffset = NSPoint(
            x: currentOffset.x + deltaX,
            y: currentOffset.y + deltaY
        )

        newOffset = constrainPanOffset(newOffset, zoomScale: getCurrentZoomScale())
        storePanOffset(newOffset)
        applyZoomTransform(scale: getCurrentZoomScale())
    }

    private func navigateWithScroll(_ event: NSEvent) -> Bool {
        let verticalDelta = event.scrollingDeltaY
        guard abs(verticalDelta) > abs(event.scrollingDeltaX), verticalDelta != 0 else {
            return false
        }

        if event.phase == .began {
            accumulatedNavigationScroll = 0
        }

        if event.hasPreciseScrollingDeltas {
            accumulatedNavigationScroll += verticalDelta
            guard abs(accumulatedNavigationScroll) >= preciseScrollNavigationThreshold else {
                return false
            }

            let now = event.timestamp
            guard now - lastScrollNavigationTime >= scrollNavigationInterval else {
                return false
            }
            lastScrollNavigationTime = now
        } else {
            // Some accelerated mouse wheels report non-precise events whose deltas
            // grow from fractions to double digits during one physical spin. Delta
            // magnitude must not become a jump across unprefetched files: event
            // frequency already carries the wheel's acceleration.
            accumulatedNavigationScroll = verticalDelta
        }

        if accumulatedNavigationScroll < 0 {
            let steps = 1
            PerformanceLog.shared.event(
                "NAV",
                "next accumulated=\(accumulatedNavigationScroll) steps=\(steps)"
            )
            let screenPoint = event.window?.convertPoint(
                toScreen: event.locationInWindow
            ) ?? event.locationInWindow
            navigateWithDiscreteScroll(step: steps, keepingPointerAt: screenPoint)
        } else {
            let steps = 1
            PerformanceLog.shared.event(
                "NAV",
                "previous accumulated=\(accumulatedNavigationScroll) steps=\(steps)"
            )
            let screenPoint = event.window?.convertPoint(
                toScreen: event.locationInWindow
            ) ?? event.locationInWindow
            navigateWithDiscreteScroll(step: -steps, keepingPointerAt: screenPoint)
        }

        accumulatedNavigationScroll = 0
        return true
    }

    /// Handles a magnification/trackpad event for pinch-to-zoom
    func handleMagnify(with event: NSEvent) {
        guard let image = imageView.image else { return }

        let magnification = event.magnification
        let currentZoom = getCurrentZoomScale()

        // Apply magnification: event.magnification is the delta (e.g., 0.1 for 10% increase)
        // newScale = currentScale * (1 + magnification)
        let newZoom = min(
            max(currentZoom * (1 + magnification), minZoom),
            maximumStandardZoomScale(for: image)
        )

        if newZoom != currentZoom {
            storeZoomScale(newZoom)
            updateImageScaling(for: image)
            // Update cursor when zoom changes
            refreshCursorForCurrentMouseLocation()
        }
    }

    /// Constrains pan offset to keep the image within reasonable bounds
    /// - Parameters:
    ///   - offset: The desired pan offset
    ///   - zoomScale: The current zoom scale
    /// - Returns: The constrained pan offset
    private func constrainPanOffset(_ offset: NSPoint, zoomScale: CGFloat) -> NSPoint {
        guard imageView.image != nil else { return offset }

        let viewSize = view.bounds.size
        guard viewSize.width > 0 && viewSize.height > 0 else { return offset }

        guard let displayedImageSize = getDisplayedImageSize(for: zoomScale) else {
            return offset
        }

        let scaledWidth = displayedImageSize.width
        let scaledHeight = displayedImageSize.height

        // Calculate maximum allowed offset based on image and view size
        // The image can be panned until its edges align with the view edges
        let edgeBasedMaxOffsetX = max(0, (scaledWidth - viewSize.width) / 2)
        let edgeBasedMaxOffsetY = max(0, (scaledHeight - viewSize.height) / 2)

        // Limit panning to half the view size in each direction
        // This ensures the image center can't go beyond the view center
        let halfViewWidth = viewSize.width / 2
        let halfViewHeight = viewSize.height / 2

        // Use the smaller of the two constraints
        let maxOffsetX = min(edgeBasedMaxOffsetX, halfViewWidth)
        let maxOffsetY = min(edgeBasedMaxOffsetY, halfViewHeight)

        // Constrain the offset
        let constrainedX = max(-maxOffsetX, min(maxOffsetX, offset.x))
        let constrainedY = max(-maxOffsetY, min(maxOffsetY, offset.y))

        return NSPoint(x: constrainedX, y: constrainedY)
    }
}
