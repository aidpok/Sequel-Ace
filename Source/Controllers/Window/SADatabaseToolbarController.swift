//
//  SADatabaseToolbarController.swift
//  Sequel Ace
//
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>

import AppKit

protocol SADatabaseToolbarControllerDelegate: AnyObject {
    func databaseToolbarDidRequestDatabaseLoad(_ controller: SADatabaseToolbarController)
    func databaseToolbarDidRequestDatabaseRefresh(_ controller: SADatabaseToolbarController)
    func databaseToolbarDidRequestAddDatabase(_ controller: SADatabaseToolbarController)
    func databaseToolbar(_ controller: SADatabaseToolbarController, didSelectDatabase database: String)
    func databaseToolbar(_ controller: SADatabaseToolbarController, didSelectViewMode mode: SAViewMode)
    func databaseToolbarDidSelectUserManager(_ controller: SADatabaseToolbarController)
    func databaseToolbarDidSelectConsole(_ controller: SADatabaseToolbarController)
    func databaseToolbar(_ controller: SADatabaseToolbarController, didSelectHistorySegment segment: Int)
}

final class SADatabaseToolbarController: NSObject {

    weak var delegate: SADatabaseToolbarControllerDelegate?
    private var fallbackItemsEnabled = false
    private var databaseSelected = false
    private var tableSelected = false

    lazy var toolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: "LightweightDatabaseShellToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.delegate = self
        return toolbar
    }()

    private lazy var databasePopUpButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 25), pullsDown: false)
        button.cell?.alignment = .center
        button.target = self
        button.action = #selector(databaseSelected(_:))
        button.menu?.delegate = self
        button.addItem(withTitle: NSLocalizedString("Choose Database...", comment: "menu item for choose db"))
        button.isEnabled = false
        return button
    }()

    private lazy var historyControl: NSSegmentedControl = {
        let control = NSSegmentedControl(labels: ["", ""], trackingMode: .momentary, target: self, action: #selector(historyNavigationSelected(_:)))
        if #available(macOS 11.0, *) {
            control.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil), forSegment: 0)
            control.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil), forSegment: 1)
        }
        control.setWidth(34, forSegment: 0)
        control.setWidth(34, forSegment: 1)
        control.segmentStyle = .texturedRounded
        control.isEnabled = true
        return control
    }()

    func setDatabasePickerEnabled(_ enabled: Bool) {
        databasePopUpButton.isEnabled = enabled
    }

    func setFallbackItemsEnabled(_ enabled: Bool, databaseSelected: Bool, tableSelected: Bool) {
        fallbackItemsEnabled = enabled
        self.databaseSelected = databaseSelected
        self.tableSelected = tableSelected

        if (!databaseSelected || !tableSelected),
           let selectedIdentifier = toolbar.selectedItemIdentifier,
           isTableViewModeIdentifier(selectedIdentifier) {
            toolbar.selectedItemIdentifier = nil
        }
        if !databaseSelected,
           let selectedIdentifier = toolbar.selectedItemIdentifier,
           selectedIdentifier == SAViewMode.query.toolbarIdentifier {
            toolbar.selectedItemIdentifier = nil
        }

        for item in toolbar.items where item.itemIdentifier != .databasePicker && item.itemIdentifier != .historyNavigation {
            item.isEnabled = isFallbackItemEnabled(item.itemIdentifier)
        }
        toolbar.validateVisibleItems()
    }

    func setHistoryNavigationEnabled(canGoBack: Bool, canGoForward: Bool) {
        historyControl.isEnabled = canGoBack || canGoForward
        historyControl.setEnabled(canGoBack, forSegment: 0)
        historyControl.setEnabled(canGoForward, forSegment: 1)
        toolbar.items.first(where: { $0.itemIdentifier == .historyNavigation })?.isEnabled = canGoBack || canGoForward
    }

    func selectViewMode(_ mode: SAViewMode) {
        toolbar.selectedItemIdentifier = mode.toolbarIdentifier
    }

    func showDatabaseLoadingState() {
        databasePopUpButton.removeAllItems()
        databasePopUpButton.addItem(withTitle: NSLocalizedString("Loading Databases...", comment: "lightweight database shell database loading item"))
    }

    func reloadDatabases(_ databases: [String], selectedDatabase: String?) {
        databasePopUpButton.removeAllItems()
        databasePopUpButton.addItem(withTitle: NSLocalizedString("Choose Database...", comment: "menu item for choose db"))
        databasePopUpButton.menu?.addItem(NSMenuItem.separator())
        databasePopUpButton.menu?.addItem(withTitle: NSLocalizedString("Add Database...", comment: "menu item to add db"),
                                          action: #selector(addDatabase(_:)),
                                          keyEquivalent: "").target = self
        databasePopUpButton.menu?.addItem(withTitle: NSLocalizedString("Refresh Databases", comment: "menu item to refresh databases"),
                                          action: #selector(refreshDatabases(_:)),
                                          keyEquivalent: "").target = self
        databasePopUpButton.menu?.addItem(NSMenuItem.separator())

        for database in databases {
            databasePopUpButton.addItem(withTitle: database)
        }

        if let selectedDatabase = selectedDatabase {
            databasePopUpButton.selectItem(withTitle: selectedDatabase)
        }
    }

    func selectOnlyDatabase(_ database: String) {
        databasePopUpButton.removeAllItems()
        databasePopUpButton.addItem(withTitle: database)
        databasePopUpButton.selectItem(at: 0)
    }

    @objc private func databaseSelected(_ sender: NSPopUpButton) {
        guard let database = sender.titleOfSelectedItem, !database.isEmpty else { return }
        let ignoredTitles = [
            NSLocalizedString("Choose Database...", comment: "menu item for choose db"),
            NSLocalizedString("Add Database...", comment: "menu item to add db"),
            NSLocalizedString("Refresh Databases", comment: "menu item to refresh databases")
        ]
        guard !ignoredTitles.contains(database) else { return }

        delegate?.databaseToolbar(self, didSelectDatabase: database)
    }

    @objc private func refreshDatabases(_ sender: Any) {
        delegate?.databaseToolbarDidRequestDatabaseRefresh(self)
    }

    @objc private func addDatabase(_ sender: Any) {
        delegate?.databaseToolbarDidRequestAddDatabase(self)
    }

    @objc private func viewModeSelected(_ sender: NSToolbarItem) {
        guard let mode = SAViewMode.allCases.first(where: { $0.toolbarIdentifier == sender.itemIdentifier }) else { return }
        guard isFallbackItemEnabled(sender.itemIdentifier) else {
            if let selectedIdentifier = toolbar.selectedItemIdentifier,
               selectedIdentifier == sender.itemIdentifier {
                toolbar.selectedItemIdentifier = nil
            }
            return
        }

        delegate?.databaseToolbar(self, didSelectViewMode: mode)
    }

    @objc private func showUserManager(_ sender: NSToolbarItem) {
        delegate?.databaseToolbarDidSelectUserManager(self)
    }

    @objc private func showConsole(_ sender: NSToolbarItem) {
        delegate?.databaseToolbarDidSelectConsole(self)
    }

    @objc private func historyNavigationSelected(_ sender: NSSegmentedControl) {
        delegate?.databaseToolbar(self, didSelectHistorySegment: sender.selectedSegment)
    }

    private func isFallbackItemEnabled(_ identifier: NSToolbarItem.Identifier) -> Bool {
        guard fallbackItemsEnabled else { return false }

        if isTableViewModeIdentifier(identifier) {
            return databaseSelected && tableSelected
        }

        switch identifier {
        case SAViewMode.query.toolbarIdentifier:
            return databaseSelected
        case .userManager,
             .console:
            return true
        default:
            return false
        }
    }

    private func isTableViewModeIdentifier(_ identifier: NSToolbarItem.Identifier) -> Bool {
        switch identifier {
        case SAViewMode.structure.toolbarIdentifier,
             SAViewMode.content.toolbarIdentifier,
             SAViewMode.status.toolbarIdentifier,
             SAViewMode.relations.toolbarIdentifier,
             SAViewMode.triggers.toolbarIdentifier:
            return true
        default:
            return false
        }
    }
}

extension SADatabaseToolbarController: NSToolbarDelegate, NSToolbarItemValidation, NSMenuDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .databasePicker,
            .space,
            SAViewMode.structure.toolbarIdentifier,
            SAViewMode.content.toolbarIdentifier,
            SAViewMode.relations.toolbarIdentifier,
            SAViewMode.triggers.toolbarIdentifier,
            SAViewMode.status.toolbarIdentifier,
            SAViewMode.query.toolbarIdentifier,
            .space,
            .historyNavigation,
            .space,
            .userManager,
            .console
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .databasePicker,
            .historyNavigation,
            .userManager,
            .console,
            SAViewMode.structure.toolbarIdentifier,
            SAViewMode.content.toolbarIdentifier,
            SAViewMode.query.toolbarIdentifier,
            SAViewMode.status.toolbarIdentifier,
            SAViewMode.relations.toolbarIdentifier,
            SAViewMode.triggers.toolbarIdentifier,
            .flexibleSpace,
            .space,
            .separator
        ]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            SAViewMode.structure.toolbarIdentifier,
            SAViewMode.content.toolbarIdentifier,
            SAViewMode.query.toolbarIdentifier,
            SAViewMode.status.toolbarIdentifier,
            SAViewMode.relations.toolbarIdentifier,
            SAViewMode.triggers.toolbarIdentifier
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .databasePicker:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = NSLocalizedString("Select Database", comment: "toolbar database selector label")
            item.view = databasePopUpButton
            item.minSize = databasePopUpButton.frame.size
            item.maxSize = databasePopUpButton.frame.size
            return item
        case SAViewMode.structure.toolbarIdentifier,
             SAViewMode.content.toolbarIdentifier,
             SAViewMode.query.toolbarIdentifier,
             SAViewMode.status.toolbarIdentifier,
             SAViewMode.relations.toolbarIdentifier,
             SAViewMode.triggers.toolbarIdentifier:
            guard let mode = SAViewMode.allCases.first(where: { $0.toolbarIdentifier == itemIdentifier }) else { return nil }
            let item = mode.makeToolbarItem(target: self)
            item.action = #selector(viewModeSelected(_:))
            item.isEnabled = false
            return item
        case .historyNavigation:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = NSLocalizedString("Table History", comment: "toolbar item for navigation history")
            item.paletteLabel = item.label
            item.view = historyControl
            item.minSize = historyControl.frame.size
            item.maxSize = historyControl.frame.size
            item.isEnabled = false
            return item
        case .userManager:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = NSLocalizedString("Users", comment: "toolbar item label for switching to the User Manager tab")
            item.paletteLabel = item.label
            item.toolTip = NSLocalizedString("Switch to the User Manager tab", comment: "tooltip for toolbar item for switching to the User Manager tab")
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "person.3", accessibilityDescription: nil)
            } else {
                item.image = NSImage(named: NSImage.userGroupName)
            }
            item.target = self
            item.action = #selector(showUserManager(_:))
            item.isEnabled = false
            return item
        case .console:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = NSLocalizedString("Console", comment: "Console")
            item.paletteLabel = NSLocalizedString("Show Console", comment: "show console")
            item.toolTip = NSLocalizedString("Show the console which shows all MySQL commands performed by Sequel Ace", comment: "tooltip for toolbar item for show console")
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "macwindow.and.commandprompt", accessibilityDescription: nil)
            } else {
                item.image = NSImage(named: "hideconsole")
            }
            item.target = self
            item.action = #selector(showConsole(_:))
            item.isEnabled = false
            return item
        default:
            return nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == databasePopUpButton.menu {
            delegate?.databaseToolbarDidRequestDatabaseLoad(self)
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == .historyNavigation {
            return item.isEnabled
        }

        if item.itemIdentifier == .databasePicker {
            return databasePopUpButton.isEnabled
        }

        return isFallbackItemEnabled(item.itemIdentifier)
    }
}

private extension NSToolbarItem.Identifier {
    static let databasePicker = NSToolbarItem.Identifier(SPMainToolbarDatabaseSelection)
    static let historyNavigation = NSToolbarItem.Identifier(SPMainToolbarHistoryNavigation)
    static let userManager = NSToolbarItem.Identifier(SPMainToolbarUserManager)
    static let console = NSToolbarItem.Identifier(SPMainToolbarShowConsole)
}
