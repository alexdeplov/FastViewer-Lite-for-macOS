//
//  DraggableImageView.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa
import MetalKit

/// Protocol for handling mouse interactions with the displayed image.
@objc protocol PanningHandler {
    @objc func shouldStartPanning(at location: NSPoint) -> Bool
    @objc func isPanningAvailable() -> Bool
    @objc func handlePanStart(at location: NSPoint)
    @objc func handlePanMove(to location: NSPoint)
    @objc func handlePanEnd()
    @objc func handleImageLinkClick(at location: NSPoint) -> Bool
    @objc func handlePrimaryImageClick(at location: NSPoint)
    @objc func handleCursorUpdate(at location: NSPoint)
    @objc func handleCursorExit()
    @objc func handleScroll(with event: NSEvent)
    @objc func handleMagnify(with event: NSEvent)
}

/// Metal image canvas with the viewer's mouse, zoom and drag interactions.
class DraggableImageView: NSView {

    /// feh keeps a left-button gesture in a "next or pan" state until pointer
    /// movement exceeds two pixels on either axis. A small, quick wobble is
    /// therefore still a click and advances the slideshow.
    private static let clickJitterOffset: CGFloat = 2
    private static let clickJitterTime: TimeInterval = 1
    private static let linkHoverBorderDashPattern: [CGFloat] = [6, 4]

    weak var draggingDelegate: DraggingDestinationHandler?
    weak var panningDelegate: PanningHandler?

    internal let surface = MetalImageSurface()
    private var textureUploadOperation: Operation?
    private var uploadGeneration = 0
    // Geometry must describe the texture on screen, which may still belong to
    // the previous image while the next asynchronous upload is in flight.
    private var displayedImageSize: NSSize?
    internal private(set) var logicalImageSize: NSSize?
    private var nextLogicalImageSize: NSSize?
    private var displayedGeneration = -1
    internal var displayedLogicalSize: NSSize? { displayedImageSize }
    internal var isTexturePending: Bool { image != nil && displayedGeneration != uploadGeneration }
    private struct Camera {
        let scaling: NSImageScaling
        let zoom: CGFloat
        let pan: NSPoint
        let nearest: Bool
    }
    private var displayedCamera: Camera?
    private var transitionScreenRect: NSRect?
    private var minimumTransitionGeneration: Int?
    private var windowMoveObserver: NSObjectProtocol?
    internal var isImageTransitionPending: Bool { minimumTransitionGeneration != nil }

    internal var displayedImageScreenRect: NSRect? {
        guard let window, surface.texture != nil else { return nil }
        let g = surface.geometry
        let size = NSSize(width: CGFloat(g.x) * bounds.width, height: CGFloat(g.y) * bounds.height)
        let rect = NSRect(x: bounds.midX + CGFloat(g.z) * bounds.width / 2 - size.width / 2,
                          y: bounds.midY + CGFloat(g.w) * bounds.height / 2 - size.height / 2,
                          width: size.width, height: size.height)
        return window.convertToScreen(convert(rect, to: nil))
    }

    func beginImageTransition() {
        if transitionScreenRect == nil { transitionScreenRect = displayedImageScreenRect }
        minimumTransitionGeneration = uploadGeneration + 1
    }

    func endImageTransition() {
        transitionScreenRect = nil
        minimumTransitionGeneration = nil
        updateGeometry()
    }
    internal var textureUploader: (CGImage, @escaping (MTLTexture?) -> Void) -> Operation = {
        MetalImageRenderer.shared.upload($0, completion: $1)
    }

    func setImage(_ image: NSImage, logicalSize: NSSize) {
        nextLogicalImageSize = logicalSize
        self.image = image
    }
    private var animationTimer: Timer?
    private var completedAnimationLoops = 0
    private var animatedRepresentation: NSBitmapImageRep? {
        image?.representations.compactMap { $0 as? NSBitmapImageRep }.first {
            ($0.value(forProperty: .frameCount) as? Int ?? 1) > 1
        }
    }

    var image: NSImage? {
        didSet {
            logicalImageSize = nextLogicalImageSize ?? image?.size
            nextLogicalImageSize = nil
            animationTimer?.invalidate()
            textureUploadOperation?.cancel()
            completedAnimationLoops = 0
            uploadGeneration += 1
            guard let image else {
                transitionScreenRect = nil
                minimumTransitionGeneration = nil
                displayedImageSize = nil
                displayedCamera = nil
                surface.texture = nil
                return
            }
            if let rep = animatedRepresentation {
                rep.setProperty(.currentFrame, withValue: 0)
            }
            uploadImage(image)
            updateGeometry()
        }
    }
    var imageScaling: NSImageScaling = .scaleProportionallyUpOrDown {
        didSet { updateGeometry() }
    }
    var imageAlignment: NSImageAlignment = .alignCenter
    var animates = true {
        didSet {
            animationTimer?.invalidate()
            if animates { scheduleAnimationFrame() }
        }
    }
    var usesNearestNeighbor = false {
        didSet { updateGeometry() }
    }
    var zoomScale: CGFloat = 1 { didSet { updateGeometry() } }
    var panOffset: NSPoint = .zero { didSet { updateGeometry() } }
    private var geometryUpdateDepth = 0
    private var pendingResizeDraw = false

    func performGeometryUpdates(_ updates: () -> Void) {
        geometryUpdateDepth += 1
        updates()
        geometryUpdateDepth -= 1
        if geometryUpdateDepth == 0 {
            updateGeometry()
            if pendingResizeDraw {
                pendingResizeDraw = false
                drawResizedFrame()
            }
        }
    }

    /// The same transform is used by the shader, link hit-testing and overlays.
    var renderTransform: CATransform3D? {
        var transform = CATransform3DMakeScale(zoomScale, zoomScale, 1)
        transform = CATransform3DTranslate(transform, panOffset.x / zoomScale, panOffset.y / zoomScale, 0)
        return transform
    }

    func untransformedPoint(_ point: NSPoint) -> NSPoint {
        NSPoint(x: (point.x - bounds.midX - panOffset.x) / zoomScale + bounds.midX,
                y: (point.y - bounds.midY - panOffset.y) / zoomScale + bounds.midY)
    }

    private func setupSurface() {
        surface.prepareFrame = { [weak self] in
            guard let self, self.isImageTransitionPending else { return }
            self.updateGeometry()
        }
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)
    }

    override func layout() {
        super.layout()
        surface.frame = bounds
        updateGeometry()
        drawResizedFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        surface.frame = bounds
        updateGeometry()
        // Live resizing runs in AppKit's tracking loop. A deferred needsDisplay
        // can wait until mouse-up, so render the new size before returning.
        drawResizedFrame()
    }

    private func drawResizedFrame() {
        guard geometryUpdateDepth == 0 else {
            pendingResizeDraw = true
            return
        }
        guard window != nil, surface.texture != nil,
              bounds.width > 0, bounds.height > 0 else { return }
        surface.drawableSize = surface.convertToBacking(surface.bounds).size
        surface.draw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowMoveObserver { NotificationCenter.default.removeObserver(windowMoveObserver) }
        windowMoveObserver = nil
        if let window {
            windowMoveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { [weak self] _ in
                guard let self, self.isImageTransitionPending else { return }
                self.surface.draw()
            }
        }
        animationTimer?.invalidate()
        if window != nil { scheduleAnimationFrame() }
    }

    private func updateGeometry() {
        guard geometryUpdateDepth == 0 else { return }
        if let rect = transitionScreenRect, let window, bounds.width > 0, bounds.height > 0 {
            // Keep the old image stationary on screen, even when the next
            // photo's window frame is already resizing or moving.
            let local = convert(window.convertFromScreen(rect), from: nil)
            surface.geometry = SIMD4(Float(local.width / bounds.width), Float(local.height / bounds.height),
                                     Float(2 * (local.midX - bounds.midX) / bounds.width),
                                     Float(2 * (local.midY - bounds.midY) / bounds.height))
            return
        }
        guard let imageSize = displayedImageSize, imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        if displayedGeneration == uploadGeneration {
            displayedCamera = Camera(scaling: imageScaling, zoom: zoomScale, pan: panOffset, nearest: usesNearestNeighbor)
        }
        guard let camera = displayedCamera else { return }
        var fit = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        if camera.scaling == .scaleProportionallyDown { fit = min(1, fit) }
        if camera.scaling == .scaleNone { fit = 1 }
        let width = imageSize.width * fit * camera.zoom
        let height = imageSize.height * fit * camera.zoom
        let maxX = max(0, (width - bounds.width) / 2)
        let maxY = max(0, (height - bounds.height) / 2)
        let pan = NSPoint(x: min(max(camera.pan.x, -maxX), maxX),
                          y: min(max(camera.pan.y, -maxY), maxY))
        surface.nearest = camera.nearest
        surface.geometry = SIMD4(Float(width / bounds.width), Float(height / bounds.height),
                                 Float(2 * pan.x / bounds.width),
                                 Float(2 * pan.y / bounds.height))
        updateHoverLayer()
    }

    private func uploadImage(_ image: NSImage) {
        let generation = uploadGeneration
        let imageSize = logicalImageSize ?? image.size
        let cgImage = animatedRepresentation?.cgImage
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard let cgImage else { return }
        let startedAt = ProcessInfo.processInfo.systemUptime
        textureUploadOperation = textureUploader(cgImage) { [weak self] texture in
            guard let self, self.uploadGeneration == generation, let texture else { return }
            if let minimum = self.minimumTransitionGeneration, generation < minimum { return }
            // Commit both on the main thread before the next draw can run.
            self.transitionScreenRect = nil
            self.minimumTransitionGeneration = nil
            self.displayedGeneration = generation
            self.displayedImageSize = imageSize
            self.surface.texture = texture
            self.updateGeometry()
            PerformanceLog.shared.event("METAL", String(format: "texture-ready pixels=%dx%d duration=%.1fms",
                cgImage.width, cgImage.height, (ProcessInfo.processInfo.systemUptime - startedAt) * 1000))
            self.scheduleAnimationFrame()
        }
    }

    private func scheduleAnimationFrame() {
        animationTimer?.invalidate()
        guard animates, window != nil, let rep = animatedRepresentation else { return }
        let duration = max(0.02, rep.value(forProperty: .currentFrameDuration) as? Double ?? 0.1)
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            guard let self, let image = self.image, let rep = self.animatedRepresentation else { return }
            let count = rep.value(forProperty: .frameCount) as? Int ?? 1
            let frame = ((rep.value(forProperty: .currentFrame) as? Int ?? 0) + 1) % count
            if frame == 0 {
                self.completedAnimationLoops += 1
                let loops = rep.value(forProperty: .loopCount) as? Int ?? 0
                if loops > 0 && self.completedAnimationLoops >= loops { return }
            }
            rep.setProperty(.currentFrame, withValue: frame)
            self.uploadImage(image)
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private var primaryMouseDownLocation: NSPoint?
    private var primaryMouseDownTimestamp: TimeInterval = 0
    private var primaryMouseGestureBecameDrag = false
    private var primaryMousePanStarted = false
    private var linkHoverBorderRect: CGRect?
    private var linkHoverBorderDisplayScale: CGFloat = 1

    internal var isLinkHoverBorderVisible: Bool {
        linkHoverBorderRect != nil
    }

    internal var linkHoverBorderBounds: CGRect? {
        linkHoverBorderRect
    }

    internal var linkHoverBorderDashPattern: [NSNumber]? {
        guard isLinkHoverBorderVisible else { return nil }
        let safeScale = max(linkHoverBorderDisplayScale, 0.01)
        return Self.linkHoverBorderDashPattern.map {
            NSNumber(value: Double($0 / safeScale))
        }
    }

    internal var linkHoverBorderColor: NSColor {
        .systemGray
    }

    deinit {
        if let windowMoveObserver { NotificationCenter.default.removeObserver(windowMoveObserver) }
        animationTimer?.invalidate()
        textureUploadOperation?.cancel()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL])
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        setupMouseTracking()
        setupSurface()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        setupMouseTracking()
        setupSurface()
    }
    
    private func setupMouseTracking() {
        // Enable mouse tracking to show cursor changes when hovering
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    /// Shows a lightweight URL affordance without modifying the source image.
    /// A shape layer above the Metal surface follows the image geometry.
    func showLinkHoverBorder(in bounds: CGRect, displayScale: CGFloat) {
        let oldRect = linkHoverBorderRect
        let safeScale = max(displayScale, 0.01)
        guard oldRect != bounds || linkHoverBorderDisplayScale != safeScale else {
            return
        }

        linkHoverBorderRect = bounds
        linkHoverBorderDisplayScale = safeScale
        updateHoverLayer()
    }

    func hideLinkHoverBorder() {
        guard linkHoverBorderRect != nil else { return }
        linkHoverBorderRect = nil
        updateHoverLayer()
    }

    private let hoverLayer = CAShapeLayer()

    private func updateHoverLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let rect = linkHoverBorderRect else {
            hoverLayer.removeFromSuperlayer()
            return
        }
        let transformed = CGRect(
            x: bounds.midX + (rect.minX - bounds.midX) * zoomScale + panOffset.x,
            y: bounds.midY + (rect.minY - bounds.midY) * zoomScale + panOffset.y,
            width: rect.width * zoomScale, height: rect.height * zoomScale
        )
        hoverLayer.path = CGPath(roundedRect: transformed, cornerWidth: 3, cornerHeight: 3, transform: nil)
        hoverLayer.fillColor = nil
        hoverLayer.strokeColor = linkHoverBorderColor.cgColor
        hoverLayer.lineWidth = 2
        hoverLayer.lineDashPattern = [6, 4]
        surface.layer?.addSublayer(hoverLayer)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove old tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }
        // Add new tracking area
        setupMouseTracking()
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingDelegate?.draggingEntered(sender) ?? []
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingDelegate?.draggingUpdated(sender) ?? []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return draggingDelegate?.performDragOperation(sender) ?? false
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        draggingDelegate?.draggingExited?(sender)
    }
    
    // MARK: - Mouse Event Handling for Panning

    override func mouseDown(with event: NSEvent) {
        guard image != nil,
              panningDelegate != nil,
              event.modifierFlags.intersection([.control, .shift, .option, .command]).isEmpty else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)

        // Open detected links immediately, before the click can enter the
        // slideshow/panning state machine.
        if panningDelegate?.handleImageLinkClick(at: location) == true {
            resetPrimaryMouseGesture()
            return
        }

        primaryMouseDownLocation = location
        primaryMouseDownTimestamp = event.timestamp
        primaryMouseGestureBecameDrag = false
        primaryMousePanStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownLocation = primaryMouseDownLocation,
              let panningDelegate = panningDelegate else {
            super.mouseDragged(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let horizontalMovement = abs(location.x - mouseDownLocation.x)
        let verticalMovement = abs(location.y - mouseDownLocation.y)
        let elapsedTime = event.timestamp - primaryMouseDownTimestamp

        if !primaryMouseGestureBecameDrag,
           horizontalMovement > Self.clickJitterOffset ||
           verticalMovement > Self.clickJitterOffset ||
           elapsedTime > Self.clickJitterTime {
            primaryMouseGestureBecameDrag = true

            if panningDelegate.shouldStartPanning(at: mouseDownLocation) {
                panningDelegate.handlePanStart(at: mouseDownLocation)
                primaryMousePanStarted = true
            }
        }

        if primaryMousePanStarted {
            panningDelegate.handlePanMove(to: location)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard primaryMouseDownLocation != nil,
              let panningDelegate = panningDelegate else {
            super.mouseUp(with: event)
            return
        }

        if primaryMousePanStarted {
            panningDelegate.handlePanEnd()
        }

        if !primaryMouseGestureBecameDrag {
            // Use the mouse-down point for hit-testing. A tiny movement between
            // press and release is still a click, and must not lose a narrow link.
            panningDelegate.handlePrimaryImageClick(at: primaryMouseDownLocation!)
        }

        resetPrimaryMouseGesture()
    }

    private func resetPrimaryMouseGesture() {
        primaryMouseDownLocation = nil
        primaryMouseDownTimestamp = 0
        primaryMouseGestureBecameDrag = false
        primaryMousePanStarted = false
    }

    override func mouseEntered(with event: NSEvent) {
        // Update cursor when mouse enters (show open hand if zoomed)
        panningDelegate?.handleCursorUpdate(at: convert(event.locationInWindow, from: nil))
        super.mouseEntered(with: event)
    }
    
    override func mouseExited(with event: NSEvent) {
        // End panning if user exits the view while dragging
        if primaryMousePanStarted {
            panningDelegate?.handlePanEnd()
            primaryMousePanStarted = false
        }
        // Reset cursor when mouse exits
        panningDelegate?.handleCursorExit()
        super.mouseExited(with: event)
    }
    
    override func mouseMoved(with event: NSEvent) {
        // Update cursor as mouse moves (in case zoom state changes)
        // Only update if mouse is actually over the view
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            panningDelegate?.handleCursorUpdate(at: location)
        }
        super.mouseMoved(with: event)
    }
    
    override func scrollWheel(with event: NSEvent) {
        PerformanceLog.shared.event(
            "EVENT-ROUTE",
            "image-view window=\(event.windowNumber) dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY) delegate=\(panningDelegate == nil ? 0 : 1) hidden=\(isHidden ? 1 : 0) alpha=\(alphaValue) frame=\(NSStringFromRect(frame)) bounds=\(NSStringFromRect(bounds)) visible=\(NSStringFromRect(visibleRect))"
        )
        // Always forward scrolling. The view controller decides whether the event
        // should pan a zoomed image or navigate between images.
        if let panningDelegate = panningDelegate {
            panningDelegate.handleScroll(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
    
    override func magnify(with event: NSEvent) {
        // Forward magnification event to panning delegate for trackpad pinch-to-zoom
        // Unlike panning, zooming should work at any zoom level (not just when already zoomed)
        if let panningDelegate = panningDelegate {
            panningDelegate.handleMagnify(with: event)
        } else {
            super.magnify(with: event)
        }
    }
}
