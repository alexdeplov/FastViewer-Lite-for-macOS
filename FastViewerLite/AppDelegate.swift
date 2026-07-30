//
//  AppDelegate.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//
//  Minimum macOS Version: 12.0 (Monterey)
//  - Uses UniformTypeIdentifiers framework (available since macOS 11.0)
//  - All APIs used are compatible with macOS 12.0+

import Cocoa
import UniformTypeIdentifiers
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private static let hasPresentedInitialSettingsKey = "HasPresentedInitialSettings"
    private static let topLeftWindowInset: CGFloat = 20
    
    var window: NSWindow?
    var viewController: ViewController?
    var settingsWindow: NSWindow?
    var settingsViewController: SettingsViewController?
    var aboutWindow: NSWindow?
    var aboutViewController: AboutViewController?
    var keyboardShortcutsWindow: NSWindow?
    var keyboardShortcutsViewController: KeyboardShortcutsViewController?
    private var openFilePanel: NSOpenPanel?
    private var appearanceObservation: NSKeyValueObservation?
    
    // Menu item references for direct state updates
    private var showFileSizeMenuItem: NSMenuItem?
    private var showImageResolutionMenuItem: NSMenuItem?
    private var autoResizeMenuItem: NSMenuItem?
    private var actualSizeMenuItem: NSMenuItem?
    private var printMenuItem: NSMenuItem?
    private var showInFinderMenuItem: NSMenuItem?
    private var moveToTrashMenuItem: NSMenuItem?
    
    // Window size menu items
    private var resizeSmallMenuItem: NSMenuItem?
    private var resizeMediumMenuItem: NSMenuItem?
    private var resizeLargeMenuItem: NSMenuItem?
    private var resizeToImageMenuItem: NSMenuItem?
    
    override init() {
        super.init()
        setupAppearanceObserver()
    }
    
    deinit {
        appearanceObservation?.invalidate()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        PerformanceLog.shared.start()
        PerformanceLog.shared.event("APP", "didFinishLaunching")
        // Set activation policy to ensure app appears in dock
        NSApp.setActivationPolicy(.regular)
        
        // Create window programmatically for faster launch
        ensureWindow()
        
        // Set up menu for opening files
        setupMenu()
        
        // Activate app to bring window to front
        NSApp.activate(ignoringOtherApps: true)
        
        // Handle files opened at launch (e.g., via "Open with")
        if let fileURL = aNotification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? URL {
            viewController?.loadImage(from: fileURL)
        }

        presentSettingsOnFirstLaunchIfNeeded()
    }

    private func presentSettingsOnFirstLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.hasPresentedInitialSettingsKey) else {
            return
        }

        // Persist before presenting so an interrupted launch cannot create an
        // endless first-run loop.
        defaults.set(true, forKey: Self.hasPresentedInitialSettingsKey)
        DispatchQueue.main.async { [weak self] in
            self?.showSettings()
        }
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Ensure app delegate is set
        NSApp.delegate = self
    }
    
    private func ensureWindow() {
        // Reuse existing window if it exists
        if let existingWindow = window {
            // If window is visible, just bring it to front
            if existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
            } else {
                // Window exists but is closed, reopen it
                existingWindow.makeKeyAndOrderFront(nil)
            }
            return
        }
        
        // Create new window only if none exists
        createWindow()
    }
    
    private func createWindow() {
        // Create window with optimal size
        let windowRect = NSRect(x: 0, y: 0, width: 600, height: 400)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        
        let newWindow = NSWindow(
            contentRect: windowRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "FastViewer Lite"
        if SettingsManager.shared.windowResizeAnchor == .topLeft,
           let screen = NSScreen.main {
            newWindow.setFrameTopLeftPoint(
                Self.topLeftWindowPoint(in: screen.visibleFrame)
            )
        } else {
            newWindow.center()
        }
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false
        // Disable window opening animation for instant appearance
        newWindow.animationBehavior = .none
        // Prevent window from auto-resizing based on content
        newWindow.styleMask.insert(.resizable)
        // Disable tab bar support to prevent "Show Tab Bar" menu item
        if #available(macOS 10.13, *) {
            newWindow.tabbingMode = .disallowed
        }
        
        // Create view controller (it will create its own view in loadView)
        let newViewController = ViewController()
        newWindow.contentViewController = newViewController
        
        // Prevent content view from resizing window
        if let contentView = newWindow.contentView {
            contentView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            contentView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            contentView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            contentView.setContentHuggingPriority(.defaultLow, for: .vertical)
        }
        
        // Store references
        window = newWindow
        viewController = newViewController
        
        // Set initial appearance-based background
        updateWindowAppearance()
        
        // Make window visible and bring to front
        newWindow.makeKeyAndOrderFront(nil)
        
        // Ensure view controller becomes first responder to receive keyboard events
        DispatchQueue.main.async {
            // AppKit may cascade a newly shown window when another FastViewer
            // window is already on screen. Re-apply the requested launch anchor
            // after ordering the window so every new instance starts in the
            // exact same top-left position.
            if SettingsManager.shared.windowResizeAnchor == .topLeft,
               let screen = newWindow.screen ?? NSScreen.main {
                newWindow.setFrameTopLeftPoint(
                    Self.topLeftWindowPoint(in: screen.visibleFrame)
                )
            }
            newWindow.makeFirstResponder(newViewController)
        }
    }

    internal static func topLeftWindowPoint(in visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.minX + topLeftWindowInset,
            y: visibleFrame.maxY - topLeftWindowInset
        )
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When dock icon is clicked and no windows are visible, show an empty window
        if !flag {
            ensureWindow()
        }
        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        
        if closingWindow == settingsWindow {
            // Settings window closed - keep reference for reuse
            return
        }
        
        if closingWindow == aboutWindow {
            // About window closed - keep reference for reuse
            return
        }
        
        if closingWindow == keyboardShortcutsWindow {
            // Keyboard shortcuts window closed - keep reference for reuse
            return
        }
        
        // Main window closed - reset view controller to empty state
        // This ensures that when window is reopened (e.g., via dock click), it shows empty window
        if closingWindow == window {
            viewController?.restoreInitialState()
        }
        
        // Keep window reference even when closed, so we can reuse it
        // The window will be reopened when a new file is opened or dock icon is clicked
        // References are only cleared when app terminates
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure view controller becomes first responder when window becomes key
        // This ensures keyboard shortcuts work even when no file is open
        guard let window = notification.object as? NSWindow,
              window == self.window,
              let viewController = window.contentViewController as? ViewController else {
            return
        }
        DispatchQueue.main.async {
            window.makeFirstResponder(viewController)
        }
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        viewController?.refreshImageScalingForBackingScaleChange()
    }
    
    private func setupMenu() {
        let mainMenu = NSMenu()
        
        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        // Add About menu item (first item in app menu, following macOS conventions)
        let aboutMenuItem = NSMenuItem(title: "About FastViewer Lite", action: #selector(showAbout), keyEquivalent: "")
        aboutMenuItem.target = self
        aboutMenuItem.image = nil // Remove any SF icon that macOS might add
        appMenu.addItem(aboutMenuItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Add Settings menu item with Cmd+, shortcut
        let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        appMenu.addItem(settingsMenuItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        appMenu.addItem(NSMenuItem(title: "Quit FastViewer Lite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        mainMenu.addItem(appMenuItem)
        
        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        
        let openMenuItem = NSMenuItem(title: "Open...", action: #selector(openFile), keyEquivalent: "o")
        openMenuItem.target = self
        fileMenu.addItem(openMenuItem)
        
        printMenuItem = NSMenuItem(title: "Print...", action: #selector(printCurrentImage), keyEquivalent: "p")
        printMenuItem?.target = self
        printMenuItem?.isEnabled = false
        if let item = printMenuItem {
            fileMenu.addItem(item)
        }
        
        fileMenu.addItem(NSMenuItem.separator())
        
        // Show in Finder (Cmd+Enter)
        showInFinderMenuItem = NSMenuItem(title: "Show in Finder", action: #selector(showInFinder), keyEquivalent: "\u{0003}") // Enter key
        showInFinderMenuItem?.keyEquivalentModifierMask = .command
        showInFinderMenuItem?.target = self
        showInFinderMenuItem?.isEnabled = true
        if let item = showInFinderMenuItem {
            fileMenu.addItem(item)
        }
        
        // Move to Trash (Cmd+Backspace)
        moveToTrashMenuItem = NSMenuItem(title: "Move to Trash", action: #selector(moveToTrash), keyEquivalent: "\u{8}") // Backspace character
        moveToTrashMenuItem?.keyEquivalentModifierMask = .command
        moveToTrashMenuItem?.target = self
        moveToTrashMenuItem?.isEnabled = true
        if let item = moveToTrashMenuItem {
            fileMenu.addItem(item)
        }
        
        mainMenu.addItem(fileMenuItem)
        
        // View menu (Display settings)
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        
        // File info display options
        showFileSizeMenuItem = NSMenuItem(title: "Show File Size", action: #selector(toggleShowFileSize), keyEquivalent: "")
        showFileSizeMenuItem?.target = self
        showFileSizeMenuItem?.isEnabled = true
        showFileSizeMenuItem?.state = SettingsManager.shared.showFileSize ? .on : .off
        if let item = showFileSizeMenuItem {
            viewMenu.addItem(item)
        }
        
        showImageResolutionMenuItem = NSMenuItem(title: "Show Image Resolution", action: #selector(toggleShowImageResolution), keyEquivalent: "")
        showImageResolutionMenuItem?.target = self
        showImageResolutionMenuItem?.isEnabled = true
        showImageResolutionMenuItem?.state = SettingsManager.shared.showImageResolution ? .on : .off
        if let item = showImageResolutionMenuItem {
            viewMenu.addItem(item)
        }
        
        viewMenu.addItem(NSMenuItem.separator())
        
        // Auto-resize option
        autoResizeMenuItem = NSMenuItem(title: "Auto-resize Window to Image Size", action: #selector(toggleAutoResizeToImageSize), keyEquivalent: "")
        autoResizeMenuItem?.target = self
        autoResizeMenuItem?.isEnabled = true
        autoResizeMenuItem?.state = SettingsManager.shared.autoResizeToImageSize ? .on : .off
        if let item = autoResizeMenuItem {
            viewMenu.addItem(item)
        }
        
        viewMenu.addItem(NSMenuItem.separator())

        actualSizeMenuItem = NSMenuItem(
            title: "Actual Size",
            action: #selector(showImageAtActualSize),
            keyEquivalent: "0"
        )
        actualSizeMenuItem?.target = self
        actualSizeMenuItem?.isEnabled = viewController?.imageView.image != nil
        if let item = actualSizeMenuItem {
            viewMenu.addItem(item)
        }
        
        mainMenu.addItem(viewMenuItem)
        
        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        
        // Close Window (Cmd+W)
        let closeWindowMenuItem = NSMenuItem(title: "Close Window", action: #selector(closeWindow), keyEquivalent: "w")
        closeWindowMenuItem.target = self
        windowMenu.addItem(closeWindowMenuItem)

        // Minimize Window (Cmd+M)
        let minimizeWindowMenuItem = NSMenuItem(title: "Minimize", action: #selector(minimizeWindow), keyEquivalent: "m")
        minimizeWindowMenuItem.target = self
        windowMenu.addItem(minimizeWindowMenuItem)
        
        windowMenu.addItem(NSMenuItem.separator())
        
        resizeSmallMenuItem = NSMenuItem(title: "Small Window", action: #selector(resizeWindowSmall), keyEquivalent: "1")
        resizeSmallMenuItem?.target = self
        if let item = resizeSmallMenuItem {
            windowMenu.addItem(item)
        }
        
        resizeMediumMenuItem = NSMenuItem(title: "Medium Window", action: #selector(resizeWindowMedium), keyEquivalent: "2")
        resizeMediumMenuItem?.target = self
        if let item = resizeMediumMenuItem {
            windowMenu.addItem(item)
        }
        
        resizeLargeMenuItem = NSMenuItem(title: "Large Window", action: #selector(resizeWindowLarge), keyEquivalent: "3")
        resizeLargeMenuItem?.target = self
        if let item = resizeLargeMenuItem {
            windowMenu.addItem(item)
        }
        
        resizeToImageMenuItem = NSMenuItem(title: "Fit to Image", action: #selector(resizeWindowToImage), keyEquivalent: "4")
        resizeToImageMenuItem?.target = self
        if let item = resizeToImageMenuItem {
            windowMenu.addItem(item)
        }
        
        mainMenu.addItem(windowMenuItem)
        
        // Remove default macOS menu items we don't want
        // This removes "Show Tab Bar" and other default items
        windowMenu.autoenablesItems = false
        if let showTabBarItem = windowMenu.items.first(where: { $0.title.contains("Tab Bar") || $0.title.contains("tab bar") }) {
            windowMenu.removeItem(showTabBarItem)
        }
        
        // Help menu (macOS automatically adds search field when Help menu exists)
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        
        // Add Keyboard Shortcuts menu item
        let keyboardShortcutsMenuItem = NSMenuItem(title: "Keyboard Shortcuts", action: #selector(showKeyboardShortcuts), keyEquivalent: "")
        keyboardShortcutsMenuItem.target = self
        helpMenu.addItem(keyboardShortcutsMenuItem)
        
        mainMenu.addItem(helpMenuItem)
        
        NSApp.mainMenu = mainMenu
        
        // Remove "Show Tab Bar" menu item if it exists (macOS may add it automatically)
        // Do this after setting mainMenu to ensure it's applied
        DispatchQueue.main.async { [weak self] in
            self?.removeShowTabBarMenuItem()
        }
        
        // Update menu item states based on current settings
        updateMenuStates()
        
        // Set up menu validation
        mainMenu.delegate = self
    }
    
    // MARK: - NSMenuDelegate
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Update file action states based on whether a file/image is loaded
        let hasCurrentFile = viewController?.hasDisplayedFile ?? false
        let hasCurrentImage = viewController?.imageView.image != nil
        actualSizeMenuItem?.isEnabled = hasCurrentImage
        printMenuItem?.isEnabled = hasCurrentImage
        showInFinderMenuItem?.isEnabled = hasCurrentFile
        moveToTrashMenuItem?.isEnabled = hasCurrentFile
    }
    
    func menu(_ menu: NSMenu, update item: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool {
        // Update file action states based on whether a file/image is loaded
        if item == printMenuItem {
            item.isEnabled = viewController?.imageView.image != nil
        } else if item == showInFinderMenuItem || item == moveToTrashMenuItem {
            item.isEnabled = viewController?.hasDisplayedFile ?? false
        }
        return true
    }
    
    /// Removes the "Show Tab Bar" menu item from the Window menu
    private func removeShowTabBarMenuItem() {
        guard let windowMenu = NSApp.mainMenu?.item(withTitle: "Window")?.submenu else { return }
        
        // Find and remove "Show Tab Bar" menu item
        if let tabBarItem = windowMenu.items.first(where: { item in
            let title = item.title.lowercased()
            return title.contains("tab bar") || title.contains("show tab bar")
        }) {
            windowMenu.removeItem(tabBarItem)
        }
    }
    
    /// Updates menu item states to reflect current settings
    func updateMenuStates() {
        // Ensure all menu items are enabled
        showFileSizeMenuItem?.isEnabled = true
        showImageResolutionMenuItem?.isEnabled = true
        autoResizeMenuItem?.isEnabled = true
        // File actions are enabled based on whether a file/image is loaded
        // This will be updated dynamically via menu validation
        let hasCurrentFile = viewController?.hasDisplayedFile ?? false
        let hasCurrentImage = viewController?.imageView.image != nil
        printMenuItem?.isEnabled = hasCurrentImage
        showInFinderMenuItem?.isEnabled = hasCurrentFile
        moveToTrashMenuItem?.isEnabled = hasCurrentFile
        
        // Update checkboxes using stored references for immediate updates
        showFileSizeMenuItem?.state = SettingsManager.shared.showFileSize ? .on : .off
        showImageResolutionMenuItem?.state = SettingsManager.shared.showImageResolution ? .on : .off
        autoResizeMenuItem?.state = SettingsManager.shared.autoResizeToImageSize ? .on : .off
        
    }
    
    @objc private func toggleShowFileSize() {
        let currentValue = SettingsManager.shared.showFileSize
        let newValue = !currentValue
        SettingsManager.shared.showFileSize = newValue
        
        // Immediately update menu state
        showFileSizeMenuItem?.state = newValue ? .on : .off
        showFileSizeMenuItem?.isEnabled = true
        
        updateMenuStates()
        updateSettingsWindowUI()
        
        // Update view controller
        viewController?.updateFileInfoPillVisibility()
        if let currentFileURL = viewController?.displayedFileURL {
            viewController?.updateFileInfo(for: currentFileURL)
        }
    }
    
    @objc private func toggleShowImageResolution() {
        let currentValue = SettingsManager.shared.showImageResolution
        let newValue = !currentValue
        SettingsManager.shared.showImageResolution = newValue
        
        // Immediately update menu state
        showImageResolutionMenuItem?.state = newValue ? .on : .off
        showImageResolutionMenuItem?.isEnabled = true
        
        updateMenuStates()
        updateSettingsWindowUI()
        
        // Update view controller
        viewController?.updateFileInfoPillVisibility()
        if let currentFileURL = viewController?.displayedFileURL {
            viewController?.updateFileInfo(for: currentFileURL)
        }
    }
    
    @objc private func showInFinder() {
        viewController?.openCurrentFileInFinder()
    }
    
    @objc private func printCurrentImage() {
        viewController?.printCurrentImage()
    }
    
    @objc private func moveToTrash() {
        viewController?.moveCurrentFileToTrash()
    }
    
    @objc private func toggleAutoResizeToImageSize() {
        // Get current value and toggle it
        let currentValue = SettingsManager.shared.autoResizeToImageSize
        let newValue = !currentValue
        
        // Update the setting
        SettingsManager.shared.autoResizeToImageSize = newValue
        
        // Immediately update menu state to ensure checkmark updates
        autoResizeMenuItem?.state = newValue ? .on : .off
        autoResizeMenuItem?.isEnabled = true
        
        // Update all menu states and settings window
        updateMenuStates()
        updateSettingsWindowUI()
        
        viewController?.refreshBackgroundForCurrentImage()
        if newValue {
            if let viewController = viewController,
               viewController.imageView.image != nil {
                viewController.autoResizeToImageSizeIfEnabled()
            }
        }
    }

    @objc private func showImageAtActualSize() {
        viewController?.displayImageAtActualSize()
        updateMenuStates()
    }
    
    /// Updates the Settings window UI to reflect current settings
    /// Called when settings are changed from the menu bar
    internal func updateSettingsWindowUI() {
        guard let settingsVC = settingsViewController else { return }
        settingsVC.loadCurrentValues()
    }
    
    /// Updates the window size menu checkmarks to show only the selected item
    /// - Parameter selected: The menu item to show as checked, or nil to clear all
    private func updateWindowSizeMenuCheckmarks(selected: NSMenuItem?) {
        resizeSmallMenuItem?.state = .off
        resizeMediumMenuItem?.state = .off
        resizeLargeMenuItem?.state = .off
        resizeToImageMenuItem?.state = .off
        
        selected?.state = .on
    }
    
    @objc private func closeWindow() {
        // Close the currently key window (frontmost window)
        // This ensures Cmd+W closes the settings window when it's focused,
        // or the main window when it's focused
        if let keyWindow = NSApp.keyWindow {
            keyWindow.performClose(nil)
        } else if let mainWindow = NSApp.mainWindow {
            mainWindow.performClose(nil)
        }
    }

    @objc private func minimizeWindow() {
        // Minimize the currently key window (frontmost window)
        if let keyWindow = NSApp.keyWindow {
            keyWindow.performMiniaturize(nil)
        } else if let mainWindow = NSApp.mainWindow {
            mainWindow.performMiniaturize(nil)
        }
    }
    
    @objc private func resizeWindowSmall() {
        // If auto-resize is enabled, disable it when user manually sets size
        if SettingsManager.shared.autoResizeToImageSize {
            SettingsManager.shared.autoResizeToImageSize = false
            updateMenuStates()
            updateSettingsWindowUI()
        }
        // Update window size menu checkmarks
        updateWindowSizeMenuCheckmarks(selected: resizeSmallMenuItem)
        viewController?.resizeWindow(to: NSSize(width: 600, height: 400), animated: true)
    }
    
    @objc private func resizeWindowMedium() {
        // If auto-resize is enabled, disable it when user manually sets size
        if SettingsManager.shared.autoResizeToImageSize {
            SettingsManager.shared.autoResizeToImageSize = false
            updateMenuStates()
            updateSettingsWindowUI()
        }
        // Update window size menu checkmarks
        updateWindowSizeMenuCheckmarks(selected: resizeMediumMenuItem)
        viewController?.resizeWindow(to: NSSize(width: 900, height: 600), animated: true)
    }
    
    @objc private func resizeWindowLarge() {
        // If auto-resize is enabled, disable it when user manually sets size
        if SettingsManager.shared.autoResizeToImageSize {
            SettingsManager.shared.autoResizeToImageSize = false
            updateMenuStates()
            updateSettingsWindowUI()
        }
        // Update window size menu checkmarks
        updateWindowSizeMenuCheckmarks(selected: resizeLargeMenuItem)
        viewController?.resizeWindowToAlmostMaximized(animated: true)
    }
    
    @objc internal func resizeWindowToImage() {
        let isCurrentlyEnabled = SettingsManager.shared.autoResizeToImageSize

        // If already enabled but window was manually resized away from image-fit,
        // re-apply the fit instead of toggling off
        if isCurrentlyEnabled, let vc = viewController, !vc.isWindowAtImageFitSize() {
            vc.resizeWindowToImageSize(animated: false)
            return
        }

        // Otherwise toggle the setting
        let newValue = !isCurrentlyEnabled
        SettingsManager.shared.autoResizeToImageSize = newValue

        // Update the UI immediately
        updateMenuStates()
        updateSettingsWindowUI()

        viewController?.refreshBackgroundForCurrentImage()
        if newValue {
            // Update window size menu checkmarks
            updateWindowSizeMenuCheckmarks(selected: resizeToImageMenuItem)
            // Perform the resize now
            viewController?.resizeWindowToImageSize(animated: false)
        } else {
            // Clear all window size menu checkmarks when Fit to Image is disabled
            updateWindowSizeMenuCheckmarks(selected: nil)
        }
    }
    
    @objc private func showAbout() {
        // Reuse existing about window if it exists
        if let existingWindow = aboutWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            // Ensure view controller becomes first responder to receive keyboard events
            if let aboutVC = aboutViewController {
                DispatchQueue.main.async {
                    existingWindow.makeFirstResponder(aboutVC)
                }
            }
            return
        }
        
        // Create about window
        let aboutVC = AboutViewController()
        aboutViewController = aboutVC
        
        let windowRect = NSRect(x: 0, y: 0, width: 400, height: 240)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        
        let newAboutWindow = NSWindow(
            contentRect: windowRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        newAboutWindow.title = "About FastViewer Lite"
        newAboutWindow.contentViewController = aboutVC
        newAboutWindow.center()
        newAboutWindow.isReleasedWhenClosed = false
        newAboutWindow.delegate = self
        
        // Set initial appearance-based background (windowBackgroundColor adapts automatically)
        newAboutWindow.backgroundColor = NSColor.windowBackgroundColor
        
        // Ensure window can be closed with Cmd+W or Escape
        // This is handled automatically by NSWindow for closable windows,
        // but we ensure the window can become key and first responder
        
        aboutWindow = newAboutWindow
        newAboutWindow.makeKeyAndOrderFront(nil)
        
        // Make the view controller first responder so it can receive keyboard events (including Cmd+W and Escape)
        // Use async to ensure window is fully set up before making first responder
        DispatchQueue.main.async {
            newAboutWindow.makeFirstResponder(aboutVC)
        }
    }
    
    @objc private func showSettings() {
        // Reuse existing settings window if it exists
        if let existingWindow = settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            // Ensure view controller becomes first responder to receive keyboard events
            if let settingsVC = settingsViewController {
                DispatchQueue.main.async {
                    existingWindow.makeFirstResponder(settingsVC)
                }
            }
            return
        }
        
        // Create settings window
        let settingsVC = SettingsViewController()
        settingsViewController = settingsVC
        
        let windowRect = NSRect(origin: .zero, size: SettingsViewController.preferredContentSize)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        
        let newSettingsWindow = NSWindow(
            contentRect: windowRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        newSettingsWindow.title = "Settings"
        newSettingsWindow.contentViewController = settingsVC
        if let mainWindow = window {
            let parentFrame = mainWindow.frame
            let origin = NSPoint(
                x: parentFrame.midX - windowRect.width / 2,
                y: parentFrame.midY - windowRect.height / 2
            )
            newSettingsWindow.setFrameOrigin(origin)
        } else {
            newSettingsWindow.center()
        }
        newSettingsWindow.isReleasedWhenClosed = false
        newSettingsWindow.delegate = self
        
        // Set initial appearance-based background (windowBackgroundColor adapts automatically)
        newSettingsWindow.backgroundColor = NSColor.windowBackgroundColor
        
        // Ensure window can be closed with Cmd+W
        // This is handled automatically by NSWindow for closable windows,
        // but we ensure the window can become key and first responder
        
        settingsWindow = newSettingsWindow
        newSettingsWindow.makeKeyAndOrderFront(nil)
        
        // Make the view controller first responder so it can receive keyboard events (including Cmd+W)
        // Use async to ensure window is fully set up before making first responder
        DispatchQueue.main.async {
            newSettingsWindow.makeFirstResponder(settingsVC)
        }
    }
    
    @objc private func showKeyboardShortcuts() {
        // Reuse existing keyboard shortcuts window if it exists
        if let existingWindow = keyboardShortcutsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            // Ensure view controller becomes first responder to receive keyboard events
            if let keyboardShortcutsVC = keyboardShortcutsViewController {
                DispatchQueue.main.async {
                    existingWindow.makeFirstResponder(keyboardShortcutsVC)
                }
            }
            return
        }
        
        // Create keyboard shortcuts window
        let keyboardShortcutsVC = KeyboardShortcutsViewController()
        keyboardShortcutsViewController = keyboardShortcutsVC
        
        let windowRect = NSRect(x: 0, y: 0, width: 600, height: 500)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        
        let newKeyboardShortcutsWindow = NSWindow(
            contentRect: windowRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        newKeyboardShortcutsWindow.title = "Keyboard Shortcuts"
        newKeyboardShortcutsWindow.contentViewController = keyboardShortcutsVC
        newKeyboardShortcutsWindow.center()
        newKeyboardShortcutsWindow.isReleasedWhenClosed = false
        newKeyboardShortcutsWindow.delegate = self
        newKeyboardShortcutsWindow.minSize = NSSize(width: 500, height: 400)
        
        // Set initial appearance-based background (windowBackgroundColor adapts automatically)
        newKeyboardShortcutsWindow.backgroundColor = NSColor.windowBackgroundColor
        
        keyboardShortcutsWindow = newKeyboardShortcutsWindow
        newKeyboardShortcutsWindow.makeKeyAndOrderFront(nil)
        
        // Make the view controller first responder so it can receive keyboard events (including Cmd+W)
        DispatchQueue.main.async {
            newKeyboardShortcutsWindow.makeFirstResponder(keyboardShortcutsVC)
        }
    }

    
    @objc private func openFile() {
        presentOpenFilePanel()
    }

    /// Presents the app's single shared open panel.
    /// Repeated double-clicks or menu commands reuse the visible panel.
    internal func presentOpenFilePanel() {
        if let existingPanel = openFilePanel {
            existingPanel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSOpenPanel()
        // Support JPEG format (covers both .jpg and .jpeg extensions)
        // Add PNG, WebP, and AVIF if enabled in settings (modular support)
        var allowedTypes: [UTType] = [.jpeg]
        if SettingsManager.shared.isPNGSupportEnabled {
            allowedTypes.append(.png)
        }
        if SettingsManager.shared.isWebPSupportEnabled {
            // WebP support via UTType (available on macOS 11+)
            if let webpType = UTType("org.webmproject.webp") {
                allowedTypes.append(webpType)
            }
        }
        if SettingsManager.shared.isAVIFSupportEnabled {
            // AVIF support via UTType (available on macOS 11+)
            if let avifType = UTType("public.avif") {
                allowedTypes.append(avifType)
            }
        }
        if SettingsManager.shared.isHEICSupportEnabled {
            // HEIC support via UTType (available on macOS 10.13+)
            allowedTypes.append(.heic)
        }
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        openFilePanel = panel
        
        panel.begin { [weak self] response in
            guard let self else { return }
            if self.openFilePanel === panel {
                self.openFilePanel = nil
            }

            if response == .OK, let url = panel.url {
                // Use URL directly to avoid full disk access requests
                self.viewController?.loadImage(from: url)
            }
        }
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // Check if file is a supported image format
        let fileURL = URL(fileURLWithPath: filename)
        let pathExtension = fileURL.pathExtension.lowercased()
        
        // Check if extension is supported based on current settings (modular PNG support)
        guard SettingsManager.shared.isExtensionSupported(pathExtension) else {
            return false
        }
        
        // Ensure window exists and is visible (reuse if already open)
        ensureWindow()
        
        // Start accessing security-scoped resource if needed
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        viewController?.loadImage(from: fileURL)
        return true
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        // Handle multiple files opened via "Open with"
        // Ensure window exists and is visible (reuse if already open)
        ensureWindow()
        
        // Load the first file (for simplicity, can be extended to handle multiple)
        if let firstFile = filenames.first {
            let fileURL = URL(fileURLWithPath: firstFile)
            let pathExtension = fileURL.pathExtension.lowercased()
            
            // Only process supported image formats (modular PNG support)
            guard SettingsManager.shared.isExtensionSupported(pathExtension) else {
                return
            }
            
            // Start accessing security-scoped resource if needed
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            viewController?.loadImage(from: fileURL)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        PerformanceLog.shared.event("APP", "willTerminate")
        PerformanceLog.shared.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - Appearance Management
    
    /// Sets up observer for macOS appearance changes using modern KVO approach
    private func setupAppearanceObserver() {
        // Observe the effectiveAppearance of the application
        // This is the official, reliable way to track appearance changes
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            // Dispatch to main to ensure the system has finished the UI transition
            DispatchQueue.main.async {
                self?.updateWindowAppearance()
            }
        }
    }
    
    /// Updates window and view background based on current macOS appearance
    private func updateWindowAppearance() {
        // Get the current appearance of the app
        let appearance = NSApp.effectiveAppearance
        
        // Crucial: Perform the color lookup within the context of the new appearance
        // This forces the color to resolve against the current system state
        appearance.performAsCurrentDrawingAppearance {
            let backgroundColor = NSColor.windowBackgroundColor
            let mainWindowBackgroundColor = self.viewController?.hasDisplayedFile == true
                ? backgroundColor
                : ViewController.emptyWindowBackgroundColor
            
            // Update main window background immediately
            if let window = self.window {
                window.backgroundColor = mainWindowBackgroundColor
                window.display() // Force a redraw
            }
            
            // Update settings window background if it exists
            if let settingsWindow = self.settingsWindow {
                settingsWindow.backgroundColor = backgroundColor
                settingsWindow.display()
            }
            
            // Update the main content using its empty/image state.
            self.viewController?.refreshBackgroundForCurrentImage()
        }
    }
    
    /// Checks if macOS is currently in dark mode
    /// - Returns: true if dark mode is active, false otherwise
    func isDarkModeActive() -> Bool {
        let appearance = NSApp.effectiveAppearance
        if #available(macOS 10.14, *) {
            return appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua
        }
        return false
    }
}

/// File-backed diagnostics for reproducing intermittent scroll stalls.
/// The file is reset on every launch and is safe to write from decoder/prefetch queues.
final class PerformanceLog {
    static let shared = PerformanceLog()

    private let queue = DispatchQueue(label: "com.fastviewer.performance-log", qos: .utility)
    private var fileHandle: FileHandle?
    private var watchdog: DispatchSourceTimer?
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private(set) var fileURL: URL?

    private init() {}

    func start() {
        queue.sync {
            guard fileHandle == nil else { return }
            let directory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("FastViewer Lite", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appendingPathComponent("performance.log")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            fileHandle = try? FileHandle(forWritingTo: url)
            fileURL = url
            writeLocked("0.000 [LOG] session-start pid=\(getpid()) macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)\n")
        }

        NSLog("[PerformanceLog] %@", fileURL?.path ?? "unavailable")
        startMainThreadWatchdog()
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        queue.sync {
            writeLocked(line(category: "LOG", message: "session-stop"))
            try? fileHandle?.synchronize()
            try? fileHandle?.close()
            fileHandle = nil
        }
    }

    func event(_ category: String, _ message: String) {
        let timestamp = ProcessInfo.processInfo.systemUptime - startedAt
        let thread = Thread.isMainThread ? "main" : "bg"
        queue.async { [weak self] in
            guard let self else { return }
            self.writeLocked(
                String(format: "%.3f [%@] [%@] %@\n", timestamp, category, thread, message)
            )
        }
    }

    private func startMainThreadWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let sentAt = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let delay = ProcessInfo.processInfo.systemUptime - sentAt
                guard delay >= 0.080 else { return }
                self.event(
                    "MAIN-STALL",
                    String(
                        format: "latency=%.1fms resident=%@",
                        delay * 1_000,
                        Self.residentMemoryDescription()
                    )
                )
            }
        }
        watchdog = timer
        timer.resume()
    }

    private func line(category: String, message: String) -> String {
        let timestamp = ProcessInfo.processInfo.systemUptime - startedAt
        return String(format: "%.3f [%@] [%@] %@\n", timestamp, category, "bg", message)
    }

    private func writeLocked(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        try? fileHandle?.write(contentsOf: data)
    }

    private static func residentMemoryDescription() -> String {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: UInt8.self, capacity: size) {
                proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, $0, Int32(size))
            }
        }
        guard result == size else { return "unknown" }
        return String(format: "%.1fMB", Double(info.pti_resident_size) / 1_048_576)
    }
}
