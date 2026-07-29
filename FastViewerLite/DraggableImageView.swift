//
//  DraggableImageView.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa

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

/// A custom NSImageView that forwards drag and drop events to its view controller
class DraggableImageView: NSImageView {

    /// feh keeps a left-button gesture in a "next or pan" state until pointer
    /// movement exceeds two pixels on either axis. A small, quick wobble is
    /// therefore still a click and advances the slideshow.
    private static let clickJitterOffset: CGFloat = 2
    private static let clickJitterTime: TimeInterval = 1

    weak var draggingDelegate: DraggingDestinationHandler?
    weak var panningDelegate: PanningHandler?

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
        return [
            NSNumber(value: 5.0 / Double(safeScale)),
            NSNumber(value: 3.0 / Double(safeScale))
        ]
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL])
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        setupMouseTracking()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        setupMouseTracking()
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
    /// The border is drawn after NSImageView's content so image compositing cannot
    /// cover it, and the image view's zoom/pan transform keeps it aligned.
    func showLinkHoverBorder(in bounds: CGRect, displayScale: CGFloat) {
        let oldRect = linkHoverBorderRect
        let safeScale = max(displayScale, 0.01)
        guard oldRect != bounds || linkHoverBorderDisplayScale != safeScale else {
            return
        }

        linkHoverBorderRect = bounds
        linkHoverBorderDisplayScale = safeScale
        let dirtyRect = oldRect.map { $0.union(bounds) } ?? bounds
        setNeedsDisplay(dirtyRect.insetBy(dx: -6 / safeScale, dy: -6 / safeScale))
    }

    func hideLinkHoverBorder() {
        guard let oldRect = linkHoverBorderRect else { return }
        linkHoverBorderRect = nil
        let safeScale = max(linkHoverBorderDisplayScale, 0.01)
        setNeedsDisplay(oldRect.insetBy(dx: -6 / safeScale, dy: -6 / safeScale))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let borderRect = linkHoverBorderRect else { return }
        let safeScale = max(linkHoverBorderDisplayScale, 0.01)
        let dashPattern: [CGFloat] = [5 / safeScale, 3 / safeScale]
        let borderPath = NSBezierPath(
            roundedRect: borderRect,
            xRadius: 3 / safeScale,
            yRadius: 3 / safeScale
        )
        borderPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        borderPath.lineCapStyle = .round
        borderPath.lineJoinStyle = .round

        NSGraphicsContext.saveGraphicsState()

        // The dark dashed halo separates the blue affordance from bright or
        // similarly colored image content without obscuring the URL itself.
        borderPath.lineWidth = 4 / safeScale
        NSColor(calibratedWhite: 0, alpha: 0.7).setStroke()
        borderPath.stroke()

        borderPath.lineWidth = 2 / safeScale
        NSColor.linkColor.setStroke()
        borderPath.stroke()

        NSGraphicsContext.restoreGraphicsState()
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
