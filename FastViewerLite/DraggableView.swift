//
//  DraggableView.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa

/// Protocol that wraps NSDraggingDestination with required methods
@objc protocol DraggingDestinationHandler {
    @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation
    @objc func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation
    @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool
    @objc optional func draggingExited(_ sender: NSDraggingInfo?)
    @objc optional func handleDoubleClick(_ event: NSEvent)
}

/// A custom NSView that forwards drag and drop events to its view controller
class DraggableView: NSView {
    
    weak var draggingDelegate: DraggingDestinationHandler?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.fileURL])
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
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
    
    override func mouseDown(with event: NSEvent) {
        // Forward double-clicks to the delegate (view controller)
        if event.clickCount == 2 {
            draggingDelegate?.handleDoubleClick?(event)
        } else {
            super.mouseDown(with: event)
        }
    }
}





