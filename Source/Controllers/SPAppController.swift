//
//  SPAppController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 09.03.2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppKit

// MARK: - Menu actions

extension SPAppController {

    // MARK: File menu actions

    @IBAction func newWindow(_ sender: Any) {
        tabManager.newWindowForWindow()
    }

    @IBAction func newTab(_ sender: Any) {
        tabManager.newWindowForTab()
    }

    /// Opens a standalone connection window (decoupled from document lifecycle).
    /// This is the modernized connection flow — the connection screen exists
    /// independently, and only creates a document tab on successful connect.
    /// Tracks open standalone connection windows so they don't get deallocated.
    private static var standaloneConnectionWindows: [SAConnectionWindowController] = []

    @IBAction func openStandaloneConnectionWindow(_ sender: Any) {
        let controller = SAConnectionWindowController()
        Self.retainConnectionWindow(controller)
        controller.showWindow(sender)
    }

    private static func retainConnectionWindow(_ controller: SAConnectionWindowController) {
        Self.standaloneConnectionWindows.append(controller)
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: controller.window,
            queue: .main
        ) { _ in
            Self.standaloneConnectionWindows.removeAll { $0 === controller }
            if let token = token {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    @IBAction func export(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        windowController.exportData()
    }

    @IBAction func addConnectionToFavorites(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.addConnectionToFavorites()
            return
        }

        windowController.addLightweightConnectionToFavorites()
    }

    @IBAction func saveConnectionSheet(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.saveConnectionSheet(sender)
            return
        }

        windowController.saveLightweightConnectionSheet(sender)
    }

    @IBAction func `import`(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.importFile()
            return
        }

        guard windowController.hasActiveLightweightConnection else { return }
        windowController.importLightweightSQLFile(sender)
    }

    @IBAction func importFromClipboard(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.importFromClipboard()
            return
        }

        guard windowController.hasActiveLightweightConnection else { return }
        windowController.importLightweightSQLFromClipboard(sender)
    }

    @IBAction func printDocument(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.print()
            return
        }

        windowController.printLightweightDocument(sender)
    }

    // MARK: Edit menu actions

    // Override default "CMD+F" for find and if we are on content view, perform Show filter
    @IBAction func performFindPanelAction(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            if document.currentlySelectedView() == .content {
                document.focusOnTableContentFilter()
            }
            return
        }

        windowController.focusActiveLightweightContentFilter()
    }

    @IBAction func copy(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController,
              windowController.loadedDatabaseDocumentIfAvailable() == nil else { return }

        windowController.copyActiveLightweightSelection(sender)
    }

    // MARK: View menu actions

    @IBAction func viewStructure(_ sender: Any) {
        tabManager.activeWindowController?.viewStructure()
    }

    @IBAction func viewContent(_ sender: Any) {
        tabManager.activeWindowController?.viewContent()
    }

    @IBAction func viewQuery(_ sender: Any) {
        tabManager.activeWindowController?.viewQuery()
    }

    @IBAction func viewStatus(_ sender: Any) {
        tabManager.activeWindowController?.viewStatus()
    }

    @IBAction func viewRelations(_ sender: Any) {
        tabManager.activeWindowController?.viewRelations()
    }

    @IBAction func viewTriggers(_ sender: Any) {
        tabManager.activeWindowController?.viewTriggers()
    }

    @IBAction func backForwardInHistory(_ sender: Any) {
        tabManager.activeWindowController?.backForwardInHistory(sender)
    }

    @IBAction func toggleConsole(_ sender: Any) {
        tabManager.activeWindowController?.showConsole()
    }

    @IBAction func clearConsole(_ sender: Any) {
        tabManager.activeWindowController?.clearConsole(sender)
    }

    @IBAction func toggleNavigator(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.toggleNavigator()
            return
        }

        windowController.toggleLightweightNavigator()
    }

    // MARK: Database menu actions

    @IBAction func showGotoDatabase(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.showGotoDatabase()
            return
        }

        windowController.showLegacyGotoDatabase()
    }

    @IBAction func addDatabase(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.addDatabase(sender)
            return
        }

        windowController.addLightweightDatabase(sender)
    }

    @IBAction func removeDatabase(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.removeDatabase(sender)
            return
        }

        windowController.removeLightweightDatabase(sender)
    }

    @IBAction func copyDatabase(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.copyDatabase()
            return
        }

        windowController.copyLightweightDatabase(sender)
    }

    @IBAction func renameDatabase(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.renameDatabase()
            return
        }

        windowController.renameLightweightDatabase(sender)
    }

    @IBAction func alterDatabase(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.alterDatabase()
            return
        }

        windowController.alterLightweightDatabase(sender)
    }

    @IBAction func refreshTables(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.refreshTables()
            return
        }

        windowController.refreshLightweightTables()
    }

    @IBAction func flushPrivileges(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.flushPrivileges()
            return
        }

        windowController.flushLightweightPrivileges(sender)
    }

    @IBAction func setDatabases(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.setDatabases()
            return
        }

        windowController.refreshLightweightDatabases()
    }

    @IBAction func showUserManager(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        guard windowController.loadedDatabaseDocumentIfAvailable() != nil || windowController.hasActiveLightweightConnection else { return }
        windowController.showUserManager()
    }

    @IBAction func chooseEncoding(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.chooseEncoding(sender)
            return
        }

        windowController.chooseLightweightEncoding(sender)
    }

    @IBAction func openDatabaseInNewTab(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.openDatabaseInNewTab()
            return
        }

        windowController.openLightweightDatabaseInNewTab(sender)
    }

    @IBAction func showServerVariables(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.showServerVariables()
            return
        }

        guard windowController.hasActiveLightweightConnection else { return }
        windowController.showLightweightServerVariables(sender)
    }

    @IBAction func showServerProcesses(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.showServerProcesses()
            return
        }

        guard windowController.hasActiveLightweightConnection else { return }
        windowController.showLightweightServerProcesses(sender)
    }

    @IBAction func shutdownServer(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.shutdownServer()
            return
        }

        guard windowController.hasActiveLightweightConnection else { return }
        windowController.shutdownLightweightServer(sender)
    }

    // MARK: Table menu actions

    @IBAction func focusOnTableContentFilter(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.focusOnTableContentFilter()
            return
        }

        windowController.focusLightweightContentFilter()
    }

    @IBAction func showFilterTable(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.showFilterTable()
            return
        }

        windowController.showLightweightFilterTable()
    }

    @IBAction func makeTableListFilterHaveFocus(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.makeTableListFilterHaveFocus(nil)
            return
        }

        windowController.focusLightweightTableFilter()
    }

    @IBAction func copyCreateTableSyntax(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.copyCreateTableSyntax(nil)
            return
        }

        windowController.copyLightweightCreateTableSyntax(sender)
    }

    @IBAction func showCreateTableSyntax(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.showCreateTableSyntax(nil)
            return
        }

        windowController.showLightweightCreateTableSyntax(sender)
    }

    @IBAction func checkTable(_ sender: Any) {
        performTableMaintenanceAction(legacy: { $0.checkTable() }, lightweight: { $0.checkLightweightTable() })
    }

    @IBAction func repairTable(_ sender: Any) {
        performTableMaintenanceAction(legacy: { $0.repairTable() }, lightweight: { $0.repairLightweightTable() })
    }

    @IBAction func analyzeTable(_ sender: Any) {
        performTableMaintenanceAction(legacy: { $0.analyzeTable() }, lightweight: { $0.analyzeLightweightTable() })
    }

    @IBAction func optimizeTable(_ sender: Any) {
        performTableMaintenanceAction(legacy: { $0.optimizeTable() }, lightweight: { $0.optimizeLightweightTable() })
    }

    @IBAction func flushTable(_ sender: Any) {
        performTableMaintenanceAction(legacy: { $0.flushTable() }, lightweight: { $0.flushLightweightTable() })
    }

    @IBAction func checksumTable(_ sender: Any) {
        performTableMaintenanceAction(legacy: { $0.checksumTable() }, lightweight: { $0.checksumLightweightTable() })
    }

    // MARK: Help menu actions

    @IBAction func showMySQLHelp(_ sender: Any) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            document.showMySQLHelp()
            return
        }

        guard windowController.hasActiveLightweightConnection else { return }
        windowController.showLightweightMySQLHelp()
    }

    private func performLegacyBackedDocumentAction(_ action: (SPDatabaseDocument) -> Void) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            action(document)
            return
        }

        guard windowController.hasActiveLightweightConnection else { return }
        action(windowController.legacyDatabaseDocumentForMenuAction())
    }

    private func performTableMaintenanceAction(legacy: (SPDatabaseDocument) -> Void, lightweight: (SPWindowController) -> Void) {
        guard let windowController = tabManager.activeWindowController else { return }
        if let document = windowController.loadedDatabaseDocumentIfAvailable() {
            legacy(document)
            return
        }

        lightweight(windowController)
    }
}

// MARK: - Standalone Connection Window Menu Item

extension SPAppController {

    /// Adds a "New Connection Window" menu item to the File menu.
    /// Called from applicationDidFinishLaunching via ObjC.
    @objc func installStandaloneConnectionMenuItem() {
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else {
            return
        }

        // Idempotent: don't add if already present
        if fileMenu.items.contains(where: { $0.action == #selector(openStandaloneConnectionWindow(_:)) }) {
            return
        }

        // Insert after "New Tab" (index 1) or at index 2
        let insertIndex = min(2, fileMenu.items.count)

        let menuItem = NSMenuItem(
            title: NSLocalizedString("New Connection Window", comment: "Menu item for standalone connection window"),
            action: #selector(openStandaloneConnectionWindow(_:)),
            keyEquivalent: "N"  // Cmd+Shift+N
        )
        menuItem.keyEquivalentModifierMask = [.command, .shift]
        menuItem.target = nil // Uses responder chain

        fileMenu.insertItem(menuItem, at: insertIndex)
    }
}

extension SPAppController {
    @objc func installFastQuitMenuAction() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }

        for item in appMenu.items where item.action == #selector(NSApplication.terminate(_:)) {
            item.target = self
            item.action = #selector(promptedTerminate(_:))
            return
        }
    }

    @objc func promptedTerminate(_ sender: Any?) {
        if hasVisibleWindowForQuitPrompt(),
           UserDefaults.standard.bool(forKey: SPApplicationPromptOnQuit),
           !dialogOKCancel(question: NSLocalizedString("Close the app?", comment: "quitting app informal alert title"),
                           text: NSLocalizedString("Are you sure you want to quit the app?", comment: "quitting app informal alert body")) {
            return
        }

        fastQuitConfirmationApproved = true
        NSApp.terminate(sender)
    }

    @objc func dialogOKCancel(question: String, text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.window.animationBehavior = .none
        return alert.runModalCentered(over: NSApp.keyWindow) == .alertFirstButtonReturn
    }
}
