//
//  AboutViewController.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa

/// About window view controller following macOS Human Interface Guidelines
class AboutViewController: NSViewController {
    
    // MARK: - UI Elements
    
    private var appIconImageView: NSImageView!
    private var appNameLabel: NSTextField!
    private var versionLabel: NSTextField!
    private var copyrightLabel: NSTextField!
    private var pleeqButton: NSButton!
    
    // MARK: - Lifecycle
    
    override func loadView() {
        // Create view with proper size for About window
        // Standard macOS About window size: ~400x240 (increased to accommodate button)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        view.wantsLayer = true
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadAppInfo()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        // Ensure the view can become first responder to receive keyboard events
        view.window?.makeFirstResponder(self)
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        // Handle Escape or Cmd+W to close About window
        if event.keyCode == 53 { // Escape key
            view.window?.performClose(nil)
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
            view.window?.performClose(nil)
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "m" {
            view.window?.performMiniaturize(nil)
            return
        }
        super.keyDown(with: event)
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        // Create app icon image view
        appIconImageView = NSImageView()
        appIconImageView.translatesAutoresizingMaskIntoConstraints = false
        appIconImageView.imageScaling = .scaleProportionallyUpOrDown
        appIconImageView.imageAlignment = .alignCenter
        appIconImageView.imageFrameStyle = .none
        
        // Load bundled app icon - use NSApplication's applicationIconImage which properly loads from bundle
        appIconImageView.image = NSApplication.shared.applicationIconImage
        
        view.addSubview(appIconImageView)
        
        // Create app name label
        appNameLabel = NSTextField(labelWithString: "")
        appNameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        appNameLabel.textColor = .labelColor
        appNameLabel.alignment = .center
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(appNameLabel)
        
        // Create version label
        versionLabel = NSTextField(labelWithString: "")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(versionLabel)
        
        // Create copyright label
        copyrightLabel = NSTextField(labelWithString: "")
        copyrightLabel.font = .systemFont(ofSize: 10)
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.alignment = .center
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false
        copyrightLabel.lineBreakMode = .byWordWrapping
        copyrightLabel.cell?.wraps = true
        view.addSubview(copyrightLabel)
        
        // Create Pleeq Software button
        pleeqButton = NSButton(title: "Pleeq Software", target: self, action: #selector(openPleeqWebsite))
        pleeqButton.bezelStyle = .rounded
        pleeqButton.controlSize = .regular
        pleeqButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pleeqButton)
        
        // Set up constraints following macOS Human Interface Guidelines
        // About windows typically have centered content with proper spacing
        NSLayoutConstraint.activate([
            // App icon: centered horizontally, top of window with padding
            appIconImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
            appIconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            appIconImageView.widthAnchor.constraint(equalToConstant: 64),
            appIconImageView.heightAnchor.constraint(equalToConstant: 64),
            
            // App name: below icon with spacing
            appNameLabel.topAnchor.constraint(equalTo: appIconImageView.bottomAnchor, constant: 12),
            appNameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            appNameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            appNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            // Version: below app name with spacing
            versionLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            versionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            versionLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            // Copyright: below version with spacing
            copyrightLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 8),
            copyrightLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            copyrightLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            copyrightLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            // Pleeq Software button: below copyright with spacing, bottom of window
            pleeqButton.topAnchor.constraint(equalTo: copyrightLabel.bottomAnchor, constant: 12),
            pleeqButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pleeqButton.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])
    }
    
    // MARK: - Data Loading
    
    /// Loads app information from Bundle
    private func loadAppInfo() {
        let bundle = Bundle.main
        
        // Get app name
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FastViewer Lite"
        appNameLabel.stringValue = appName
        
        // Get version
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        versionLabel.stringValue = "Version \(version) (\(build))"
        
        // Get copyright
        let copyright = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        if let copyright = copyright, !copyright.isEmpty {
            copyrightLabel.stringValue = copyright
        } else {
            // Fallback copyright
            let currentYear = Calendar.current.component(.year, from: Date())
            copyrightLabel.stringValue = "Copyright © \(currentYear) FastViewer Lite. All rights reserved."
        }
    }
    
    // MARK: - Actions
    
    /// Opens Pleeq Software website in default browser
    @objc private func openPleeqWebsite() {
        guard let url = URL(string: "https://pleeq.com/") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
