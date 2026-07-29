//
//  main.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Initialize delegate - NSApplication.run() ensures we're on main thread
// Use MainActor.assumeIsolated to satisfy Swift 6 concurrency requirements
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
}

app.run()








