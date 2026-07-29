//
//  NonInteractiveImageView.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa

/// An NSImageView that forwards all drag events to its parent view
/// This allows drag and drop to work anywhere in the window, including on top of the logo
class NonInteractiveImageView: NSImageView {
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupNonInteractive()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupNonInteractive()
    }
    
    private func setupNonInteractive() {
        // Register for drag types so macOS knows this view can accept drops
        // We'll forward all events to the parent view
        registerForDraggedTypes([.fileURL])
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return self so we receive drag events, but we'll forward them to parent
        // This ensures macOS shows the correct drop cursor
        return self
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Don't accept first mouse events for clicks
        return false
    }
    
    // MARK: - Drag and Drop Forwarding
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Forward to parent DraggableView, which will forward to its delegate
        if let parentView = superview as? DraggableView {
            return parentView.draggingEntered(sender)
        }
        return []
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Forward to parent DraggableView, which will forward to its delegate
        if let parentView = superview as? DraggableView {
            return parentView.draggingUpdated(sender)
        }
        return []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Forward to parent DraggableView, which will forward to its delegate
        if let parentView = superview as? DraggableView {
            return parentView.performDragOperation(sender)
        }
        return false
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        // Forward to parent DraggableView, which will forward to its delegate
        if let parentView = superview as? DraggableView {
            parentView.draggingExited(sender)
        }
    }
}
