//
//  SettingsViewController.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa

/// Settings window view controller following macOS layout guidelines
class SettingsViewController: NSViewController {
    
    // MARK: - UI Elements
    
    private var showFileSizeCheckbox: NSButton!
    private var showImageResolutionCheckbox: NSButton!
    private var autoResizeToImageSizeCheckbox: NSButton!
    private var windowResizeAnchorLabel: NSTextField!
    private var windowResizeAnchorPopup: NSPopUpButton!
    private var transparencyBackgroundLabel: NSTextField!
    private var transparencyBackgroundPopup: NSPopUpButton!
    private var separatorBox: NSBox!
    private var defaultAppsGroupTitle: NSTextField!
    private var defaultAppsGroupBox: NSBox!
    private var displayGroupTitle: NSTextField!
    private var displayGroupBox: NSBox!
    private var defaultAppsButton: NSButton!
    private var defaultAppsInfoLabel: NSTextField!
    
    // MARK: - Lifecycle
    
    override func loadView() {
        // Create view with proper size for settings window
        // Wider width for better center equalization (per macOS layout guidelines)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 385))
        view.wantsLayer = true
        self.view = view
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadCurrentValues()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        // Ensure the view can become first responder to receive keyboard events
        view.window?.makeFirstResponder(self)
        // Update menu states when settings window appears
        updateMenuStates()
        updateDefaultAppsButton()
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        // Handle Cmd+W to close settings window
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
        setupDefaultAppsGroup()
        setupDisplayGroup()
    }

    private func setupDefaultAppsGroup() {
        defaultAppsGroupTitle = NSTextField(labelWithString: "Default Apps")
        defaultAppsGroupTitle.font = .systemFont(ofSize: 11, weight: .medium)
        defaultAppsGroupTitle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(defaultAppsGroupTitle)

        defaultAppsGroupBox = NSBox()
        defaultAppsGroupBox.boxType = .primary
        defaultAppsGroupBox.titlePosition = .noTitle
        defaultAppsGroupBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(defaultAppsGroupBox)

        let contentView = defaultAppsGroupBox.contentView!

        defaultAppsButton = NSButton(
            title: "Set FastViewer as Default",
            target: self,
            action: #selector(defaultAppsButtonClicked)
        )
        defaultAppsButton.translatesAutoresizingMaskIntoConstraints = false
        defaultAppsButton.bezelStyle = .rounded
        contentView.addSubview(defaultAppsButton)

        defaultAppsInfoLabel = NSTextField(labelWithString:
            "Use FastViewer to open JPEG, PNG, WebP, AVIF, HEIC, and HEIF files when you double-click them in Finder. You can restore the previously selected apps."
        )
        defaultAppsInfoLabel.font = .systemFont(ofSize: 10)
        defaultAppsInfoLabel.textColor = .secondaryLabelColor
        defaultAppsInfoLabel.lineBreakMode = .byWordWrapping
        defaultAppsInfoLabel.cell?.wraps = true
        defaultAppsInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(defaultAppsInfoLabel)

        NSLayoutConstraint.activate([
            defaultAppsGroupTitle.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            defaultAppsGroupTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),

            defaultAppsGroupBox.topAnchor.constraint(equalTo: defaultAppsGroupTitle.bottomAnchor, constant: 6),
            defaultAppsGroupBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            defaultAppsGroupBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            defaultAppsButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            defaultAppsButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            defaultAppsInfoLabel.topAnchor.constraint(equalTo: defaultAppsButton.bottomAnchor, constant: 10),
            defaultAppsInfoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            defaultAppsInfoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            defaultAppsInfoLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }
    
    private func setupDisplayGroup() {
        displayGroupTitle = NSTextField(labelWithString: "Display")
        displayGroupTitle.font = .systemFont(ofSize: 11, weight: .medium)
        displayGroupTitle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(displayGroupTitle)

        // Create group box for display settings
        displayGroupBox = NSBox()
        displayGroupBox.boxType = .primary
        displayGroupBox.titlePosition = .noTitle
        displayGroupBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(displayGroupBox)
        
        // Ensure contentView is set up
        let contentView = displayGroupBox.contentView!
        
        // Create checkbox for file size
        showFileSizeCheckbox = NSButton(checkboxWithTitle: "Show file size", target: self, action: #selector(showFileSizeChanged))
        showFileSizeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        showFileSizeCheckbox.controlSize = .regular
        // Prevent text wrapping
        showFileSizeCheckbox.lineBreakMode = .byTruncatingTail
        contentView.addSubview(showFileSizeCheckbox)
        
        // Create checkbox for image resolution
        showImageResolutionCheckbox = NSButton(checkboxWithTitle: "Show image resolution", target: self, action: #selector(showImageResolutionChanged))
        showImageResolutionCheckbox.translatesAutoresizingMaskIntoConstraints = false
        showImageResolutionCheckbox.controlSize = .regular
        // Prevent text wrapping
        showImageResolutionCheckbox.lineBreakMode = .byTruncatingTail
        contentView.addSubview(showImageResolutionCheckbox)
        
        // Create checkbox for auto-resize to image size
        autoResizeToImageSizeCheckbox = NSButton(checkboxWithTitle: "Auto-resize window to image size", target: self, action: #selector(autoResizeToImageSizeChanged))
        autoResizeToImageSizeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        autoResizeToImageSizeCheckbox.controlSize = .regular
        // Prevent text wrapping
        autoResizeToImageSizeCheckbox.lineBreakMode = .byTruncatingTail
        contentView.addSubview(autoResizeToImageSizeCheckbox)
        
        windowResizeAnchorLabel = NSTextField(labelWithString: "Resize anchor:")
        windowResizeAnchorLabel.alignment = .right
        windowResizeAnchorLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(windowResizeAnchorLabel)

        windowResizeAnchorPopup = NSPopUpButton()
        windowResizeAnchorPopup.translatesAutoresizingMaskIntoConstraints = false
        windowResizeAnchorPopup.controlSize = .regular
        windowResizeAnchorPopup.target = self
        windowResizeAnchorPopup.action = #selector(windowResizeAnchorChanged)
        windowResizeAnchorPopup.removeAllItems()
        for anchor in WindowResizeAnchor.allCases {
            windowResizeAnchorPopup.addItem(withTitle: anchor.displayName)
        }
        contentView.addSubview(windowResizeAnchorPopup)
        
        // Create horizontal separator
        separatorBox = NSBox()
        separatorBox.boxType = .separator
        separatorBox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separatorBox)
        
        // Create label for transparency background
        transparencyBackgroundLabel = NSTextField(labelWithString: "Show transparency as:")
        transparencyBackgroundLabel.alignment = .right
        transparencyBackgroundLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(transparencyBackgroundLabel)
        
        // Create popup button for transparency background
        transparencyBackgroundPopup = NSPopUpButton()
        transparencyBackgroundPopup.translatesAutoresizingMaskIntoConstraints = false
        transparencyBackgroundPopup.controlSize = .regular
        transparencyBackgroundPopup.target = self
        transparencyBackgroundPopup.action = #selector(transparencyBackgroundChanged)
        
        // Add menu items for each transparency option
        transparencyBackgroundPopup.removeAllItems()
        for background in TransparencyBackground.allCases {
            transparencyBackgroundPopup.addItem(withTitle: background.displayName)
        }
        
        contentView.addSubview(transparencyBackgroundPopup)
        
        // Set up constraints following macOS layout guidelines
        NSLayoutConstraint.activate([
            // Group box constraints (20pt margins from window edges, positioned below default apps)
            displayGroupTitle.topAnchor.constraint(equalTo: defaultAppsGroupBox.bottomAnchor, constant: 16),
            displayGroupTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),

            displayGroupBox.topAnchor.constraint(equalTo: displayGroupTitle.bottomAnchor, constant: 6),
            displayGroupBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            displayGroupBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            displayGroupBox.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            
            // Checkbox layout within group box
            // 16pt margins inside group box
            showFileSizeCheckbox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            showFileSizeCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            showImageResolutionCheckbox.topAnchor.constraint(equalTo: showFileSizeCheckbox.bottomAnchor, constant: 6),
            showImageResolutionCheckbox.leadingAnchor.constraint(equalTo: showFileSizeCheckbox.leadingAnchor),
            
            autoResizeToImageSizeCheckbox.topAnchor.constraint(equalTo: showImageResolutionCheckbox.bottomAnchor, constant: 6),
            autoResizeToImageSizeCheckbox.leadingAnchor.constraint(equalTo: showFileSizeCheckbox.leadingAnchor),
            
            windowResizeAnchorLabel.topAnchor.constraint(equalTo: autoResizeToImageSizeCheckbox.bottomAnchor, constant: 8),
            windowResizeAnchorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 36),
            windowResizeAnchorLabel.widthAnchor.constraint(equalToConstant: 110),

            windowResizeAnchorPopup.centerYAnchor.constraint(equalTo: windowResizeAnchorLabel.centerYAnchor),
            windowResizeAnchorPopup.leadingAnchor.constraint(equalTo: windowResizeAnchorLabel.trailingAnchor, constant: 6),
            windowResizeAnchorPopup.widthAnchor.constraint(equalToConstant: 130),

            // Separator constraints
            separatorBox.topAnchor.constraint(equalTo: windowResizeAnchorLabel.bottomAnchor, constant: 12),
            separatorBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            separatorBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            separatorBox.heightAnchor.constraint(equalToConstant: 1),
            
            // Transparency background label and popup
            transparencyBackgroundLabel.topAnchor.constraint(equalTo: separatorBox.bottomAnchor, constant: 12),
            transparencyBackgroundLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            transparencyBackgroundLabel.widthAnchor.constraint(equalToConstant: 130),
            
            transparencyBackgroundPopup.centerYAnchor.constraint(equalTo: transparencyBackgroundLabel.centerYAnchor),
            transparencyBackgroundPopup.leadingAnchor.constraint(equalTo: transparencyBackgroundLabel.trailingAnchor, constant: 6),
            transparencyBackgroundPopup.widthAnchor.constraint(equalToConstant: 150),
            
            transparencyBackgroundLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }
    
    // MARK: - Data Management
    
    /// Reloads current values from settings and updates UI
    /// Called when settings are changed from the menu bar or when settings window appears
    func loadCurrentValues() {
        // Load file size preference
        showFileSizeCheckbox.state = SettingsManager.shared.showFileSize ? .on : .off
        
        // Load image resolution preference
        showImageResolutionCheckbox.state = SettingsManager.shared.showImageResolution ? .on : .off
        
        // Load auto-resize to image size preference
        autoResizeToImageSizeCheckbox.state = SettingsManager.shared.autoResizeToImageSize ? .on : .off
        
        let currentResizeAnchor = SettingsManager.shared.windowResizeAnchor
        if let index = WindowResizeAnchor.allCases.firstIndex(of: currentResizeAnchor) {
            windowResizeAnchorPopup.selectItem(at: index)
        } else {
            windowResizeAnchorPopup.selectItem(at: 0)
        }
        
        // Update animation checkbox enabled state based on auto-resize setting
        updateAnimationCheckboxState()
        
        // Load transparency background preference
        let currentBackground = SettingsManager.shared.transparencyBackground
        if let index = TransparencyBackground.allCases.firstIndex(of: currentBackground) {
            transparencyBackgroundPopup.selectItem(at: index)
        } else {
            // Default to "checkers" if not found
            transparencyBackgroundPopup.selectItem(
                at: TransparencyBackground.allCases.firstIndex(of: .checkers) ?? 0
            )
        }
        
        updateDefaultAppsButton()
    }

    @objc private func defaultAppsButtonClicked() {
        let manager = DefaultFileAssociationManager.shared
        defaultAppsButton.title = "Updating…"
        defaultAppsButton.isEnabled = false

        let completion: (Result<Void, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateDefaultAppsButton()

                if case .failure(let error) = result {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Couldn’t Update Default Apps"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    if let window = self.view.window {
                        alert.beginSheetModal(for: window)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }

        switch manager.state {
        case .managedByFastViewer:
            manager.restorePreviousHandlers(completion: completion)
        case .available:
            manager.setAsDefaultHandler(completion: completion)
        case .alreadyDefault:
            updateDefaultAppsButton()
        }
    }

    private func updateDefaultAppsButton() {
        switch DefaultFileAssociationManager.shared.state {
        case .available:
            defaultAppsButton.title = "Set FastViewer as Default"
            defaultAppsButton.isEnabled = true
        case .managedByFastViewer:
            defaultAppsButton.title = "Restore Previous Default Apps"
            defaultAppsButton.isEnabled = true
        case .alreadyDefault:
            defaultAppsButton.title = "FastViewer Is Default"
            defaultAppsButton.isEnabled = false
        }
    }
    
    @objc private func showFileSizeChanged() {
        let isEnabled = showFileSizeCheckbox.state == .on
        SettingsManager.shared.showFileSize = isEnabled
        
        // Update menu states
        updateMenuStates()
        
        // Update file info pill visibility and content immediately if there's an active view controller
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let viewController = appDelegate.viewController {
            viewController.updateFileInfoPillVisibility()
            if let currentFileURL = viewController.fileListManager.currentFileURL {
                viewController.updateFileInfo(for: currentFileURL)
            }
        }
    }
    
    @objc private func showImageResolutionChanged() {
        let isEnabled = showImageResolutionCheckbox.state == .on
        SettingsManager.shared.showImageResolution = isEnabled
        
        // Update menu states
        updateMenuStates()
        
        // Update file info pill visibility and content immediately if there's an active view controller
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let viewController = appDelegate.viewController {
            viewController.updateFileInfoPillVisibility()
            if let currentFileURL = viewController.fileListManager.currentFileURL {
                viewController.updateFileInfo(for: currentFileURL)
            }
        }
    }
    
    @objc private func autoResizeToImageSizeChanged() {
        let isEnabled = autoResizeToImageSizeCheckbox.state == .on
        SettingsManager.shared.autoResizeToImageSize = isEnabled
        
        // Update animation checkbox enabled state based on auto-resize setting
        updateAnimationCheckboxState()
        
        // Update menu states
        updateMenuStates()
        
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let viewController = appDelegate.viewController {
            viewController.refreshBackgroundForCurrentImage()
            if isEnabled {
                if viewController.imageView.image != nil {
                    viewController.autoResizeToImageSizeIfEnabled()
                }
            }
        }
    }
    
    @objc private func transparencyBackgroundChanged() {
        let selectedIndex = transparencyBackgroundPopup.indexOfSelectedItem
        guard selectedIndex >= 0 && selectedIndex < TransparencyBackground.allCases.count else {
            return
        }
        
        let selectedBackground = TransparencyBackground.allCases[selectedIndex]
        SettingsManager.shared.transparencyBackground = selectedBackground
        
        // Update menu states
        updateMenuStates()
        
        // Update transparency background display immediately if there's an active view controller
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let viewController = appDelegate.viewController {
            viewController.updateTransparencyCheckerVisibility()
            viewController.refreshBackgroundForCurrentImage()
        }
    }
    
    /// Updates the enabled state of the animation checkbox based on auto-resize setting
    private func updateAnimationCheckboxState() {
        let autoResizeEnabled = SettingsManager.shared.autoResizeToImageSize
        windowResizeAnchorLabel.isEnabled = autoResizeEnabled
        windowResizeAnchorPopup.isEnabled = autoResizeEnabled
    }

    @objc private func windowResizeAnchorChanged() {
        let selectedIndex = windowResizeAnchorPopup.indexOfSelectedItem
        guard selectedIndex >= 0 && selectedIndex < WindowResizeAnchor.allCases.count else {
            return
        }

        SettingsManager.shared.windowResizeAnchor = WindowResizeAnchor.allCases[selectedIndex]
    }
    
    /// Updates menu item states to reflect current settings
    private func updateMenuStates() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.updateMenuStates()
    }
    
}
