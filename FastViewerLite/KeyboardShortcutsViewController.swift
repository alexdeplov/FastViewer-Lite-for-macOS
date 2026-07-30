//
//  KeyboardShortcutsViewController.swift
//  FastViewer
//
//  Created by Alexander Deplov on 24.01.26.
//

import Cocoa

class KeyboardShortcutsViewController: NSViewController {
    
    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    
    // Keyboard shortcuts data
    private let shortcuts: [(category: String, items: [(action: String, shortcut: String)])] = [
        ("File Operations", [
            ("Open Image", "⌘O"),
            ("Print Current Image", "⌘P"),
            ("Show in Finder", "⌘Enter"),
            ("Move to Trash", "⌘Backspace"),
            ("Undo Move to Trash", "⌘Z")
        ]),
        ("Navigation", [
            ("Next Image", "→ or Right Arrow"),
            ("Previous Image", "← or Left Arrow")
        ]),
        ("Window Size", [
            ("Small Window (600×400)", "⌘1"),
            ("Medium Window (900×600)", "⌘2"),
            ("Large Window (90% screen)", "⌘3"),
            ("Fit to Image (toggle)", "⌘4")
        ]),
        ("Zoom Controls", [
            ("Zoom In", "⌘+ or ⌘="),
            ("Zoom Out", "⌘-"),
            ("Actual Size (100%)", "⌘0"),
            ("Pan Image", "Click and drag")
        ]),
        ("View Options", [
            ("Close Window", "⌘W"),
            ("Minimize Window", "⌘M"),
            ("Hide Application", "⌘H"),
            ("Quit Application", "⌘Q")
        ]),
        ("Settings", [
            ("Open Settings", "⌘,")
        ])
    ]
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        view.wantsLayer = true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        // Create scroll view
        scrollView = NSScrollView(frame: view.bounds)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // Create table view
        tableView = NSTableView(frame: .zero)
        tableView.style = .plain
        tableView.rowSizeStyle = .medium
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.dataSource = self
        tableView.delegate = self
        
        // Create columns
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = "Action"
        actionColumn.width = 350
        actionColumn.minWidth = 200
        tableView.addTableColumn(actionColumn)
        
        let shortcutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutColumn.title = "Shortcut"
        shortcutColumn.width = 200
        shortcutColumn.minWidth = 150
        tableView.addTableColumn(shortcutColumn)
        
        scrollView.documentView = tableView
        view.addSubview(scrollView)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }
}

// MARK: - NSTableViewDataSource
extension KeyboardShortcutsViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        var count = 0
        for category in shortcuts {
            count += 1 // Category header row
            count += category.items.count // Shortcut rows
        }
        return count
    }
}

// MARK: - NSTableViewDelegate
extension KeyboardShortcutsViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let columnIdentifier = tableColumn?.identifier.rawValue ?? ""
        
        // Calculate which category and item this row represents
        var currentRow = 0
        for category in shortcuts {
            // Category header row
            if currentRow == row {
                return createCategoryHeaderCell(text: category.category, for: columnIdentifier)
            }
            currentRow += 1
            
            // Shortcut rows
            for item in category.items {
                if currentRow == row {
                    return createShortcutCell(action: item.action, shortcut: item.shortcut, for: columnIdentifier)
                }
                currentRow += 1
            }
        }
        
        return nil
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        // Calculate which category and item this row represents
        var currentRow = 0
        for category in shortcuts {
            // Category header row (taller)
            if currentRow == row {
                return row == 0 ? 32 : 40 // First category has less top padding
            }
            currentRow += 1
            
            // Shortcut rows (normal height)
            for _ in category.items {
                if currentRow == row {
                    return 28
                }
                currentRow += 1
            }
        }
        
        return 28
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false // Disable row selection
    }
    
    private func createCategoryHeaderCell(text: String, for columnIdentifier: String) -> NSView {
        let cellView = NSTableCellView()
        
        let textField = NSTextField(labelWithString: columnIdentifier == "action" ? text : "")
        textField.font = .systemFont(ofSize: 13, weight: .semibold)
        textField.textColor = .labelColor
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        cellView.addSubview(textField)
        
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
        ])
        
        return cellView
    }
    
    private func createShortcutCell(action: String, shortcut: String, for columnIdentifier: String) -> NSView {
        let cellView = NSTableCellView()
        
        let text = columnIdentifier == "action" ? action : shortcut
        let textField = NSTextField(labelWithString: text)
        textField.font = columnIdentifier == "shortcut" 
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12, weight: .regular)
        textField.textColor = columnIdentifier == "shortcut" ? .secondaryLabelColor : .labelColor
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        cellView.addSubview(textField)
        
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: columnIdentifier == "action" ? 24 : 8),
            textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
        ])
        
        return cellView
    }
}
