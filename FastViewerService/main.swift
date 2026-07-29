//
//  main.swift
//  FastViewerService
//
//  Entry point for the XPC service
//

import Foundation

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate

print("🎯 FastViewer XPC Service starting...")
listener.resume()

// Keep service running
RunLoop.main.run()
