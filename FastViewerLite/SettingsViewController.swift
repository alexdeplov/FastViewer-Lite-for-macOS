//
//  SettingsViewController.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import Cocoa

/// Settings window view controller following macOS layout guidelines
class SettingsViewController: NSViewController {

    static let preferredContentSize = NSSize(width: 440, height: 323)

    private enum Layout {
        static let windowTop: CGFloat = 14
        static let windowSide: CGFloat = 20
        static let windowBottom: CGFloat = 20
        static let groupInset: CGFloat = 0
        static let controlSpacing: CGFloat = 6
        static let sectionSpacing: CGFloat = 14
        static let separatorSpacing: CGFloat = 12
        static let descriptionSpacing: CGFloat = 4
        static let sectionLabelWidth: CGFloat = 105
    }
    
    // MARK: - UI Elements
    
    private var showFileSizeCheckbox: NSButton!
    private var showImageResolutionCheckbox: NSButton!
    private var autoResizeToImageSizeCheckbox: NSButton!
    private var windowResizeAnchorLabel: NSTextField!
    private var windowResizeAnchorButtons: [NSButton] = []
    private var transparencyBackgroundLabel: NSTextField!
    private var transparencyBackgroundButtons: [NSButton] = []
    private var defaultAppsGroupBox: NSBox!
    private var displayGroupBox: NSBox!
    private var defaultAppsSeparator: NSBox!
    private var defaultAppsButton: NSButton!
    private var defaultAppsInfoLabel: NSTextField!
    
    // MARK: - Lifecycle
    
    override func loadView() {
        let rootView = NSView(frame: NSRect(origin: .zero, size: Self.preferredContentSize))
        NSLayoutConstraint.activate([
            rootView.widthAnchor.constraint(equalToConstant: Self.preferredContentSize.width),
            rootView.heightAnchor.constraint(equalToConstant: Self.preferredContentSize.height)
        ])
        view = rootView
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
        defaultAppsGroupBox = makeContainer(identifier: "defaultAppsContainer")
        view.addSubview(defaultAppsGroupBox)

        let contentView = defaultAppsGroupBox.contentView!

        let imageFilesLabel = makeSectionLabel("Image files:")
        contentView.addSubview(imageFilesLabel)

        defaultAppsButton = NSButton(
            title: "Set FastViewer as Default",
            target: self,
            action: #selector(defaultAppsButtonClicked)
        )
        defaultAppsButton.translatesAutoresizingMaskIntoConstraints = false
        defaultAppsButton.bezelStyle = .rounded
        defaultAppsButton.controlSize = .regular
        contentView.addSubview(defaultAppsButton)

        defaultAppsInfoLabel = NSTextField(labelWithString:
            "Use FastViewer to open JPEG, PNG, WebP, AVIF, HEIC, and HEIF files from Finder. You can switch back to the previous apps or Preview."
        )
        defaultAppsInfoLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        defaultAppsInfoLabel.textColor = .secondaryLabelColor
        defaultAppsInfoLabel.lineBreakMode = .byWordWrapping
        defaultAppsInfoLabel.cell?.wraps = true
        defaultAppsInfoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        defaultAppsInfoLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        defaultAppsInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(defaultAppsInfoLabel)

        defaultAppsSeparator = makeSeparator()
        view.addSubview(defaultAppsSeparator)

        NSLayoutConstraint.activate([
            defaultAppsGroupBox.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: Layout.windowTop
            ),
            defaultAppsGroupBox.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Layout.windowSide
            ),
            defaultAppsGroupBox.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Layout.windowSide
            ),

            imageFilesLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Layout.groupInset
            ),
            imageFilesLabel.widthAnchor.constraint(equalToConstant: Layout.sectionLabelWidth),
            imageFilesLabel.firstBaselineAnchor.constraint(
                equalTo: defaultAppsButton.firstBaselineAnchor
            ),

            defaultAppsButton.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: Layout.groupInset
            ),
            defaultAppsButton.leadingAnchor.constraint(
                equalTo: imageFilesLabel.trailingAnchor,
                constant: Layout.controlSpacing
            ),

            defaultAppsInfoLabel.topAnchor.constraint(
                equalTo: defaultAppsButton.bottomAnchor,
                constant: Layout.descriptionSpacing
            ),
            defaultAppsInfoLabel.leadingAnchor.constraint(equalTo: defaultAppsButton.leadingAnchor),
            defaultAppsInfoLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Layout.groupInset
            ),
            defaultAppsInfoLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -Layout.groupInset
            ),

            defaultAppsSeparator.topAnchor.constraint(
                equalTo: defaultAppsGroupBox.bottomAnchor,
                constant: Layout.separatorSpacing
            ),
            defaultAppsSeparator.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Layout.windowSide
            ),
            defaultAppsSeparator.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Layout.windowSide
            ),
            defaultAppsSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
    
    private func setupDisplayGroup() {
        displayGroupBox = makeContainer(identifier: "displayContainer")
        view.addSubview(displayGroupBox)
        
        let contentView = displayGroupBox.contentView!

        let fileInfoLabel = makeSectionLabel("File info:")
        contentView.addSubview(fileInfoLabel)

        showFileSizeCheckbox = NSButton(checkboxWithTitle: "Show file size", target: self, action: #selector(showFileSizeChanged))
        showFileSizeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        showFileSizeCheckbox.controlSize = .regular
        showFileSizeCheckbox.lineBreakMode = .byTruncatingTail
        contentView.addSubview(showFileSizeCheckbox)
        
        showImageResolutionCheckbox = NSButton(checkboxWithTitle: "Show image resolution", target: self, action: #selector(showImageResolutionChanged))
        showImageResolutionCheckbox.translatesAutoresizingMaskIntoConstraints = false
        showImageResolutionCheckbox.controlSize = .regular
        showImageResolutionCheckbox.lineBreakMode = .byTruncatingTail
        contentView.addSubview(showImageResolutionCheckbox)

        let fileInfoSeparator = makeSeparator()
        contentView.addSubview(fileInfoSeparator)

        let windowLabel = makeSectionLabel("Window:")
        contentView.addSubview(windowLabel)

        autoResizeToImageSizeCheckbox = NSButton(checkboxWithTitle: "Auto-resize window to image size", target: self, action: #selector(autoResizeToImageSizeChanged))
        autoResizeToImageSizeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        autoResizeToImageSizeCheckbox.controlSize = .regular
        autoResizeToImageSizeCheckbox.lineBreakMode = .byTruncatingTail
        contentView.addSubview(autoResizeToImageSizeCheckbox)
        
        windowResizeAnchorLabel = NSTextField(labelWithString: "Resize from:")
        windowResizeAnchorLabel.alignment = .right
        windowResizeAnchorLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(windowResizeAnchorLabel)

        windowResizeAnchorButtons = WindowResizeAnchor.allCases.enumerated().map { index, anchor in
            let button = NSButton(
                radioButtonWithTitle: anchor.displayName,
                target: self,
                action: #selector(windowResizeAnchorChanged(_:))
            )
            button.controlSize = .regular
            button.tag = index
            button.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(button)
            return button
        }

        let centerAnchorButton = windowResizeAnchorButtons[0]
        let topLeftAnchorButton = windowResizeAnchorButtons[1]

        let windowSeparator = makeSeparator()
        contentView.addSubview(windowSeparator)

        transparencyBackgroundLabel = makeSectionLabel("Transparency:")
        contentView.addSubview(transparencyBackgroundLabel)

        transparencyBackgroundButtons = TransparencyBackground.allCases.enumerated().map {
            index, background in
            let button = NSButton(
                radioButtonWithTitle: background.displayName,
                target: self,
                action: #selector(transparencyBackgroundChanged(_:))
            )
            button.controlSize = .regular
            button.tag = index
            button.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(button)
            return button
        }

        let solidColorButton = transparencyBackgroundButtons[0]
        let checkersButton = transparencyBackgroundButtons[1]
        
        NSLayoutConstraint.activate([
            displayGroupBox.topAnchor.constraint(
                equalTo: defaultAppsSeparator.bottomAnchor,
                constant: Layout.separatorSpacing
            ),
            displayGroupBox.leadingAnchor.constraint(equalTo: defaultAppsGroupBox.leadingAnchor),
            displayGroupBox.trailingAnchor.constraint(equalTo: defaultAppsGroupBox.trailingAnchor),
            displayGroupBox.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -Layout.windowBottom
            ),

            fileInfoLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Layout.groupInset
            ),
            fileInfoLabel.widthAnchor.constraint(equalToConstant: Layout.sectionLabelWidth),
            fileInfoLabel.firstBaselineAnchor.constraint(
                equalTo: showFileSizeCheckbox.firstBaselineAnchor
            ),

            showFileSizeCheckbox.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: Layout.groupInset
            ),
            showFileSizeCheckbox.leadingAnchor.constraint(
                equalTo: fileInfoLabel.trailingAnchor,
                constant: Layout.controlSpacing
            ),
            
            showImageResolutionCheckbox.topAnchor.constraint(
                equalTo: showFileSizeCheckbox.bottomAnchor,
                constant: Layout.controlSpacing
            ),
            showImageResolutionCheckbox.leadingAnchor.constraint(equalTo: showFileSizeCheckbox.leadingAnchor),

            fileInfoSeparator.topAnchor.constraint(
                equalTo: showImageResolutionCheckbox.bottomAnchor,
                constant: Layout.separatorSpacing
            ),
            fileInfoSeparator.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: Layout.groupInset
            ),
            fileInfoSeparator.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -Layout.groupInset
            ),
            fileInfoSeparator.heightAnchor.constraint(equalToConstant: 1),

            windowLabel.leadingAnchor.constraint(equalTo: fileInfoLabel.leadingAnchor),
            windowLabel.widthAnchor.constraint(equalTo: fileInfoLabel.widthAnchor),
            windowLabel.firstBaselineAnchor.constraint(
                equalTo: autoResizeToImageSizeCheckbox.firstBaselineAnchor
            ),

            autoResizeToImageSizeCheckbox.topAnchor.constraint(
                equalTo: fileInfoSeparator.bottomAnchor,
                constant: Layout.separatorSpacing
            ),
            autoResizeToImageSizeCheckbox.leadingAnchor.constraint(equalTo: showFileSizeCheckbox.leadingAnchor),

            windowResizeAnchorLabel.leadingAnchor.constraint(equalTo: fileInfoLabel.leadingAnchor),
            windowResizeAnchorLabel.widthAnchor.constraint(equalTo: fileInfoLabel.widthAnchor),
            windowResizeAnchorLabel.firstBaselineAnchor.constraint(
                equalTo: centerAnchorButton.firstBaselineAnchor
            ),

            centerAnchorButton.topAnchor.constraint(
                equalTo: autoResizeToImageSizeCheckbox.bottomAnchor,
                constant: Layout.sectionSpacing
            ),
            centerAnchorButton.leadingAnchor.constraint(
                equalTo: windowResizeAnchorLabel.trailingAnchor,
                constant: Layout.controlSpacing
            ),

            topLeftAnchorButton.topAnchor.constraint(
                equalTo: centerAnchorButton.bottomAnchor,
                constant: Layout.controlSpacing
            ),
            topLeftAnchorButton.leadingAnchor.constraint(equalTo: centerAnchorButton.leadingAnchor),

            windowSeparator.topAnchor.constraint(
                equalTo: topLeftAnchorButton.bottomAnchor,
                constant: Layout.separatorSpacing
            ),
            windowSeparator.leadingAnchor.constraint(equalTo: fileInfoSeparator.leadingAnchor),
            windowSeparator.trailingAnchor.constraint(equalTo: fileInfoSeparator.trailingAnchor),
            windowSeparator.heightAnchor.constraint(equalToConstant: 1),

            transparencyBackgroundLabel.leadingAnchor.constraint(equalTo: fileInfoLabel.leadingAnchor),
            transparencyBackgroundLabel.widthAnchor.constraint(equalTo: fileInfoLabel.widthAnchor),
            transparencyBackgroundLabel.firstBaselineAnchor.constraint(
                equalTo: solidColorButton.firstBaselineAnchor
            ),

            solidColorButton.topAnchor.constraint(
                equalTo: windowSeparator.bottomAnchor,
                constant: Layout.separatorSpacing
            ),
            solidColorButton.leadingAnchor.constraint(equalTo: showFileSizeCheckbox.leadingAnchor),

            checkersButton.topAnchor.constraint(
                equalTo: solidColorButton.bottomAnchor,
                constant: Layout.controlSpacing
            ),
            checkersButton.leadingAnchor.constraint(equalTo: solidColorButton.leadingAnchor),
            checkersButton.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -Layout.groupInset
            )
        ])
    }

    private func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    private func makeContainer(identifier: String) -> NSBox {
        let container = NSBox()
        container.boxType = .custom
        container.titlePosition = .noTitle
        container.contentViewMargins = .zero
        container.isTransparent = true
        container.identifier = NSUserInterfaceItemIdentifier(identifier)
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
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
        let selectedIndex = WindowResizeAnchor.allCases.firstIndex(of: currentResizeAnchor) ?? 0
        for (index, button) in windowResizeAnchorButtons.enumerated() {
            button.state = index == selectedIndex ? .on : .off
        }
        
        updateResizeAnchorState()
        
        // Load transparency background preference
        let currentBackground = SettingsManager.shared.transparencyBackground
        let selectedBackgroundIndex = TransparencyBackground.allCases.firstIndex(
            of: currentBackground
        ) ?? TransparencyBackground.allCases.firstIndex(of: .checkers) ?? 0
        for (index, button) in transparencyBackgroundButtons.enumerated() {
            button.state = index == selectedBackgroundIndex ? .on : .off
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
            manager.restoreDefaultHandlers(completion: completion)
        }
    }

    private func updateDefaultAppsButton() {
        switch DefaultFileAssociationManager.shared.state {
        case .available:
            defaultAppsButton.title = "Set FastViewer as Default"
            defaultAppsButton.isEnabled = true
        case .managedByFastViewer:
            defaultAppsButton.title = "Restore Previous Apps"
            defaultAppsButton.isEnabled = true
        case .alreadyDefault:
            defaultAppsButton.title = "Restore Default Apps"
            defaultAppsButton.isEnabled = true
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
        
        updateResizeAnchorState()
        
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
    
    @objc private func transparencyBackgroundChanged(_ sender: NSButton) {
        let selectedIndex = sender.tag
        guard selectedIndex >= 0 && selectedIndex < TransparencyBackground.allCases.count else {
            return
        }

        for (index, button) in transparencyBackgroundButtons.enumerated() {
            button.state = index == selectedIndex ? .on : .off
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
    
    private func updateResizeAnchorState() {
        let autoResizeEnabled = SettingsManager.shared.autoResizeToImageSize
        windowResizeAnchorLabel.isEnabled = autoResizeEnabled
        windowResizeAnchorLabel.textColor = autoResizeEnabled
            ? .labelColor
            : .disabledControlTextColor
        windowResizeAnchorButtons.forEach { $0.isEnabled = autoResizeEnabled }
    }

    @objc private func windowResizeAnchorChanged(_ sender: NSButton) {
        let selectedIndex = sender.tag
        guard selectedIndex >= 0 && selectedIndex < WindowResizeAnchor.allCases.count else {
            return
        }

        for (index, button) in windowResizeAnchorButtons.enumerated() {
            button.state = index == selectedIndex ? .on : .off
        }
        SettingsManager.shared.windowResizeAnchor = WindowResizeAnchor.allCases[selectedIndex]
    }
    
    /// Updates menu item states to reflect current settings
    private func updateMenuStates() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.updateMenuStates()
    }
    
}
