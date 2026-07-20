//
//  SPWindowController+LightweightActions.swift
//  Sequel Ace
//

import Cocoa

private enum SALightweightDatabaseCopyObjectType {
    case table
    case view
    case procedure
    case function
    case trigger
    case event
}

private struct SALightweightDatabaseCopyObject {
    let name: String
    let type: SALightweightDatabaseCopyObjectType
}

private struct SALightweightRenameStatement {
    let sourceDatabase: String
    let sourceName: String
    let targetDatabase: String
    let targetName: String
}

struct SALightweightMutationSnapshot {
    let database: String?
    let table: String?
    let viewMode: SAViewMode
}

extension SPWindowController {
    @objc func addLightweightTable(_ sender: Any?) {
        guard canStartLightweightMutation() else { return }
        guard let selectedDatabase = selectedDatabase else { return }
        guard let tableDetails = promptForLightweightTable() else { return }
        let tableName = tableDetails.name

        guard validateLightweightObjectName(tableName, type: .table) else { return }

        var options: [String] = []
        if let encoding = tableDetails.encoding {
            options.append("DEFAULT CHARACTER SET \(Self.backtickQuoted(encoding))")
        }
        if let collation = tableDetails.collation {
            options.append("DEFAULT COLLATE \(Self.backtickQuoted(collation))")
        }
        if let tableType = tableDetails.tableType {
            options.append("ENGINE = \(Self.backtickQuoted(tableType))")
        }

        let primaryKey = tableDetails.tableType == "CSV" ? "" : " PRIMARY KEY AUTO_INCREMENT"
        let statement = "CREATE TABLE \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(tableName)) (id INT(11) UNSIGNED NOT NULL\(primaryKey)) \(options.joined(separator: " "))"
        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Creating %@...", comment: "Creating table task string"), tableName),
                                       statement: statement,
                                       assertingDatabase: selectedDatabase) { [weak self] success in
            guard let self = self, success else { return }
            self.refreshLightweightObjectsAfterMutation(database: selectedDatabase,
                                                        restoringTable: tableName,
                                                        restoringViewMode: .structure,
                                                        recordsHistory: true)
        }
    }

    @objc func copyLightweightTableName(_ sender: Any?) {
        guard let selectedDatabase = selectedDatabase else {
            NSSound.beep()
            return
        }

        let selectedTables = selectedLightweightTableItems()
        guard !selectedTables.isEmpty else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: self)
        pasteboard.setString(selectedTables.map { "\(selectedDatabase).\($0)" }.joined(separator: "\n"), forType: .string)
    }

    @objc func renameLightweightTable(_ sender: Any?) {
        guard canStartLightweightMutation() else { return }
        guard selectedLightweightTableCount == 1,
              let selectedTable = selectedTable else { return }

        guard let row = lightweightSidebarRowIndex(for: selectedTable) else {
            return
        }

        tablesListView.editColumn(0, row: row, with: nil, select: true)
    }

    @objc func duplicateLightweightTable(_ sender: Any?) {
        guard canStartLightweightMutation() else { return }
        guard let selectedDatabase = selectedDatabase,
              selectedLightweightTableCount == 1,
              let selectedTable = selectedTable else { return }

        let tableType = lightweightTableTypes[selectedTable] ?? .table
        guard let duplicateDetails = promptForLightweightDuplicateTable(sourceName: selectedTable,
                                                                        tableType: tableType,
                                                                        defaultValue: "\(selectedTable)_copy") else { return }
        let newName = duplicateDetails.name
        let targetDatabase = duplicateDetails.targetDatabase?.isEmpty == false ? duplicateDetails.targetDatabase! : selectedDatabase
        guard validateLightweightObjectName(newName, type: tableType) else { return }

        if tableType == .procedure || tableType == .function {
            duplicateLightweightRoutine(selectedTable, to: newName, type: tableType, database: selectedDatabase, dropSource: false)
        } else {
            duplicateLightweightObject(selectedTable,
                                       to: newName,
                                       type: tableType,
                                       sourceDatabase: selectedDatabase,
                                       targetDatabase: targetDatabase,
                                       copyContent: duplicateDetails.duplicateContent)
        }
    }

    @objc func truncateLightweightTable(_ sender: Any?) {
        guard canStartLightweightMutation() else { return }
        guard let selectedDatabase = selectedDatabase else { return }

        let selectedTables = selectedLightweightTableItems()
        guard !selectedTables.isEmpty,
              selectedTables.allSatisfy({ (lightweightTableTypes[$0] ?? .table) == .table }) else {
            NSSound.beep()
            return
        }

        let hasSingleSelection = selectedTables.count == 1
        let tableToRestore = primarySelectedLightweightTable()
        let viewModeToRestore = activeLightweightViewMode
        let hasAutoIncrement = selectedTables.contains { lightweightTableHasAutoIncrement($0, database: selectedDatabase) }

        let alert = NSAlert()
        alert.messageText = hasSingleSelection
            ? String(format: NSLocalizedString("Truncate table '%@'?", comment: "truncate table message"), selectedTables[0])
            : NSLocalizedString("Truncate selected tables?", comment: "truncate selected tables message")
        if hasAutoIncrement {
            alert.informativeText = hasSingleSelection
                ? String(format: NSLocalizedString("Are you sure you want to delete ALL records in the table '%@'? This operation cannot be undone. TRUNCATE also resets AUTO_INCREMENT; the checkbox below only updates the Delete ALL ROWS preference.", comment: "truncate table informative message with auto increment preference"), selectedTables[0])
                : String(format: NSLocalizedString("Are you sure you want to delete ALL records in the selected %d tables? This operation cannot be undone. TRUNCATE also resets AUTO_INCREMENT; the checkbox below only updates the Delete ALL ROWS preference.", comment: "truncate selected tables informative message with auto increment preference"), selectedTables.count)
            alert.showsSuppressionButton = true
            alert.suppressionButton?.state = UserDefaults.standard.bool(forKey: SPResetAutoIncrementAfterDeletionOfAllRows) ? .on : .off
            alert.suppressionButton?.title = NSLocalizedString("Remember reset preference for Delete ALL ROWS\n(TRUNCATE always resets AUTO_INCREMENT)", comment: "truncate table auto increment preference checkbox")
            alert.suppressionButton?.toolTip = NSLocalizedString("Matches the legacy Delete ALL ROWS reset preference. This truncate action always resets AUTO_INCREMENT.", comment: "truncate table auto increment preference checkbox tooltip")
        } else {
            alert.informativeText = hasSingleSelection
                ? String(format: NSLocalizedString("Are you sure you want to delete ALL records in the table '%@'? This operation cannot be undone.", comment: "truncate table informative message"), selectedTables[0])
                : String(format: NSLocalizedString("Are you sure you want to delete ALL records in the selected %d tables? This operation cannot be undone.", comment: "truncate selected tables informative message"), selectedTables.count)
        }
        alert.addButton(withTitle: NSLocalizedString("Truncate", comment: "truncate button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard runLightweightModalAlert(alert) == .alertFirstButtonReturn else { return }

        let shouldRememberAutoIncrementReset = alert.suppressionButton?.state == .on
        let statements = selectedTables.map {
            "TRUNCATE TABLE \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted($0))"
        }
        let status = hasSingleSelection
            ? String(format: NSLocalizedString("Truncating %@...", comment: "Truncating table task string"), selectedTables[0])
            : NSLocalizedString("Truncating selected tables...", comment: "Truncating selected tables task string")
        runLightweightDatabaseMutation(status: status,
                                       statements: statements,
                                       assertingDatabase: selectedDatabase) { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.refreshLightweightObjectsAfterMutation(database: selectedDatabase,
                                                            restoringTable: tableToRestore,
                                                            restoringTables: selectedTables,
                                                            restoringViewMode: viewModeToRestore)
                return
            }
            if hasAutoIncrement {
                UserDefaults.standard.set(shouldRememberAutoIncrementReset, forKey: SPResetAutoIncrementAfterDeletionOfAllRows)
            }
            self.refreshLightweightObjectsAfterMutation(database: selectedDatabase,
                                                        restoringTable: tableToRestore,
                                                        restoringTables: selectedTables,
                                                        restoringViewMode: viewModeToRestore)
        }
    }

    @objc func removeLightweightTable(_ sender: Any?) {
        guard canStartLightweightMutation() else { return }
        guard let selectedDatabase = selectedDatabase else { return }

        let selectedItems = selectedLightweightTableItems()
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }
        let selectedObjects = selectedItems.compactMap { item -> (name: String, type: SALightweightTableObjectType, dropKeyword: String)? in
            let type = lightweightTableTypes[item] ?? .table
            guard let dropKeyword = type.sqlDropKeyword else { return nil }
            return (item, type, dropKeyword)
        }
        guard selectedObjects.count == selectedItems.count else {
            NSSound.beep()
            return
        }
        let hasSingleSelection = selectedObjects.count == 1
        let tableToRestore = selectedTable.flatMap { selectedItems.contains($0) ? nil : $0 }
        let viewModeToRestore = activeLightweightViewMode

        let alert = NSAlert()
        alert.messageText = hasSingleSelection
            ? String(format: NSLocalizedString("Delete %@ '%@'?", comment: "delete table/view message"), selectedObjects[0].type.localizedName, selectedObjects[0].name)
            : NSLocalizedString("Delete selected items?", comment: "delete selected items message")
        alert.informativeText = hasSingleSelection
            ? String(format: NSLocalizedString("Are you sure you want to delete the %@ '%@'? This operation cannot be undone.", comment: "delete table/view informative message"), selectedObjects[0].type.localizedName, selectedObjects[0].name)
            : String(format: NSLocalizedString("Are you sure you want to delete the selected %d items? This operation cannot be undone.", comment: "delete selected items informative message"), selectedObjects.count)
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        alert.alertStyle = .critical
        alert.suppressionButton?.title = NSLocalizedString("Force delete (disables integrity checks)", comment: "force table deletion button text")
        alert.suppressionButton?.toolTip = NSLocalizedString("Disables foreign key checks (FOREIGN_KEY_CHECKS) before deletion and re-enables them afterwards.", comment: "force table deltion button text tooltip")
        alert.showsSuppressionButton = true

        guard runLightweightModalAlert(alert) == .alertFirstButtonReturn else { return }

        let force = alert.suppressionButton?.state == .on
        let dropStatements = selectedObjects.map {
            "DROP \($0.dropKeyword) \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted($0.name))"
        }
        let status = hasSingleSelection
            ? String(format: NSLocalizedString("Deleting %@...", comment: "Deleting table task string"), selectedObjects[0].name)
            : NSLocalizedString("Deleting selected items...", comment: "Deleting selected items task string")
        var statements: [String] = []
        if force {
            statements.append("/*!32352 SET FOREIGN_KEY_CHECKS=0 */")
        }
        statements.append(contentsOf: dropStatements)
        if force {
            statements.append("/*!32352 SET FOREIGN_KEY_CHECKS=1 */")
        }
        runLightweightDatabaseMutation(status: status,
                                       statements: statements,
                                       assertingDatabase: selectedDatabase) { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.refreshLightweightObjectsAfterMutation(database: selectedDatabase,
                                                            restoringTable: tableToRestore,
                                                            restoringViewMode: viewModeToRestore) { [weak self] in
                    guard selectedItems.count > 1 else { return }
                    self?.reconcileLightweightPinnedTables(database: selectedDatabase)
                }
                return
            }
            let removedPinnedItem = selectedItems.contains { self.lightweightPinnedTables.contains($0) }
            selectedItems.forEach { self.unpinLightweightTable($0, database: selectedDatabase, notify: false) }
            if removedPinnedItem {
                self.postLightweightPinnedTableNotification(database: selectedDatabase)
            }
            self.pruneLightweightHistory(removing: Set(selectedItems))
            self.refreshLightweightObjectsAfterMutation(database: selectedDatabase,
                                                        restoringTable: tableToRestore,
                                                        restoringViewMode: viewModeToRestore)
        }
    }

    @objc func togglePinLightweightTable(_ sender: Any?) {
        guard canStartLightweightMutation() else { return }
        guard let selectedDatabase = selectedDatabase else { return }

        let selectedItems = selectedLightweightTableItems()
        guard !selectedItems.isEmpty else {
            NSSound.beep()
            return
        }
        let tableToRestore = primarySelectedLightweightTable()

        if selectedItems.allSatisfy({ lightweightPinnedTables.contains($0) }) {
            selectedItems.forEach { unpinLightweightTable($0, database: selectedDatabase, notify: false) }
        } else {
            selectedItems.forEach { pinLightweightTable($0, database: selectedDatabase, notify: false) }
        }

        postLightweightPinnedTableNotification(database: selectedDatabase)
        restoreLightweightSidebarSelections(selectedItems, primaryTable: tableToRestore)
    }

    @objc func openLightweightTableInNewTab(_ sender: Any?) {
        guard selectedTable != nil,
              let state = lightweightConnectionStateDictionary(includePasswords: true, includeSession: true, includeQuery: true) else { return }

        NotificationCenter.default.post(name: .SPDocumentDuplicateTab, object: nil, userInfo: [
            "isLightweight": true,
            "lightweightState": state
        ])
    }

    @objc func openLightweightTableInNewWindow(_ sender: Any?) {
        guard selectedTable != nil,
              let state = lightweightConnectionStateDictionary(includePasswords: true, includeSession: true, includeQuery: true),
              let appController = NSApp.delegate as? SPAppController else {
            NSSound.beep()
            return
        }

        let newWindowController = appController.tabManager.newWindowForWindow()
        if !newWindowController.restoreLightweightConnectionStateDictionary(state) {
            newWindowController.close()
            NSSound.beep()
        }
    }

    @objc func exportSelectedLightweightTableAs(_ sender: Any?) {
        guard loadedDatabaseDocument == nil,
              selectedDatabase != nil else {
            NSSound.beep()
            return
        }

        let selectedItems = selectedLightweightTableItems()
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        guard !selectedItems.isEmpty,
              tag >= 0,
              let format = SPExportType(rawValue: UInt(tag)),
              canExportSelectedLightweightItems(selectedItems, formatTag: tag) else {
            NSSound.beep()
            return
        }

        let tableNames = selectedItems.filter { item in
            let objectType = lightweightTableTypes[item] ?? .table
            return objectType == .table || objectType == .view
        }
        let procedureNames = selectedItems.filter { lightweightTableTypes[$0] == .procedure }
        let functionNames = selectedItems.filter { lightweightTableTypes[$0] == .function }

        guard let controller = configuredLightweightExportController(preferredSource: SALightweightExportSource.tableExport,
                                                                     selectedTableItems: selectedItems,
                                                                     tableNames: tableNames,
                                                                     procedureNames: procedureNames,
                                                                     functionNames: functionNames) else {
            NSSound.beep()
            return
        }

        lightweightExportController = controller
        controller.exportTables(selectedItems, asFormat: format, using: SALightweightExportSource.tableExport)
    }

    var canExportSelectedLightweightTable: Bool {
        guard loadedDatabaseDocument == nil,
              selectedDatabase != nil else {
            return false
        }

        let selectedItems = selectedLightweightTableItems()
        return !selectedItems.isEmpty && canExportSelectedLightweightItems(selectedItems, formatTag: 0)
    }

    private func canExportSelectedLightweightItems(_ selectedItems: [String], formatTag: Int) -> Bool {
        guard !selectedItems.isEmpty else { return false }

        switch formatTag {
        case 0:
            return selectedItems.allSatisfy {
                let objectType = lightweightTableTypes[$0] ?? .table
                return objectType == .table || objectType == .view || objectType == .procedure || objectType == .function
            }
        case 1, 2, 3:
            return selectedItems.allSatisfy {
                let objectType = lightweightTableTypes[$0] ?? .table
                return objectType == .table || objectType == .view
            }
        default:
            return false
        }
    }

    func updateLightweightSidebarActionMenuState() {
        let menu = lightweightSelectedTableExportMenuItem?.menu
        let selectedItems = selectedLightweightTableItems()
        let hasSelection = loadedDatabaseDocument == nil && selectedDatabase != nil && !selectedItems.isEmpty
        let hasSingleSelection = selectedItems.count == 1
        let selectedObjectType = hasSingleSelection ? (selectedItems.first.map { lightweightTableTypes[$0] ?? .table } ?? .none) : .none
        let objectTitle = hasSingleSelection
            ? lightweightSidebarActionObjectTitle(for: selectedObjectType)
            : NSLocalizedString("Selected Items", comment: "selected items menu title component")
        let isTableSelection = hasSelection && selectedItems.allSatisfy { (lightweightTableTypes[$0] ?? .table) == .table }
        let isPinned = hasSelection && selectedItems.allSatisfy { lightweightPinnedTables.contains($0) }
        let canRemoveSelection = hasSelection && selectedItems.allSatisfy { (lightweightTableTypes[$0] ?? .table).sqlDropKeyword != nil }
        let multiSafeCreateSyntax = hasSelection
        let mutationAllowed = !processing && !isLightweightImportRunning && !databaseListIsLoading
        let singleOnlySelection = hasSelection && hasSingleSelection && mutationAllowed

        updateLightweightSidebarAction(#selector(copyLightweightTableName(_:)),
                                       title: hasSingleSelection
                                           ? String(format: NSLocalizedString("Copy %@ Name", comment: "copy selected object name menu item"), objectTitle)
                                           : NSLocalizedString("Copy Item Names", comment: "copy selected object names menu item"),
                                       enabled: hasSelection,
                                       hidden: !hasSelection,
                                       in: menu)
        updateLightweightSidebarAction(#selector(copyLightweightCreateTableSyntax(_:)),
                                       title: hasSingleSelection
                                           ? String(format: NSLocalizedString("Copy Create %@ Syntax", comment: "copy selected object create syntax menu item"), objectTitle)
                                           : NSLocalizedString("Copy Create Syntax", comment: "copy selected objects create syntax menu item"),
                                       enabled: multiSafeCreateSyntax,
                                       hidden: !hasSelection,
                                       in: menu)
        updateLightweightSidebarAction(#selector(showLightweightCreateTableSyntax(_:)),
                                       title: hasSingleSelection
                                           ? String(format: NSLocalizedString("Show Create %@ Syntax...", comment: "show selected object create syntax menu item"), objectTitle)
                                           : NSLocalizedString("Show Create Syntax...", comment: "show selected objects create syntax menu item"),
                                       enabled: multiSafeCreateSyntax,
                                       hidden: !hasSelection,
                                       in: menu)
        updateLightweightSidebarAction(#selector(renameLightweightTable(_:)),
                                       title: String(format: NSLocalizedString("Rename %@...", comment: "rename selected object menu title"), objectTitle),
                                       enabled: singleOnlySelection,
                                       hidden: !singleOnlySelection,
                                       in: menu)
        updateLightweightSidebarAction(#selector(duplicateLightweightTable(_:)),
                                       title: String(format: NSLocalizedString("Duplicate %@...", comment: "duplicate selected object menu title"), objectTitle),
                                       enabled: singleOnlySelection,
                                       hidden: !singleOnlySelection,
                                       in: menu)
        updateLightweightSidebarAction(#selector(truncateLightweightTable(_:)),
                                       title: hasSingleSelection
                                           ? NSLocalizedString("Truncate Table...", comment: "truncate table menu title")
                                           : NSLocalizedString("Truncate Selected Tables...", comment: "truncate selected tables menu title"),
                                       enabled: isTableSelection && mutationAllowed,
                                       hidden: !isTableSelection,
                                       in: menu)
        updateLightweightSidebarAction(#selector(removeLightweightTable(_:)),
                                       title: String(format: NSLocalizedString("Remove %@...", comment: "remove selected object menu title"), objectTitle),
                                       enabled: canRemoveSelection && mutationAllowed,
                                       hidden: !canRemoveSelection,
                                       in: menu)
        updateLightweightSidebarAction(#selector(togglePinLightweightTable(_:)),
                                       title: String(format: isPinned
                                                     ? NSLocalizedString("Unpin %@", comment: "unpin selected object menu item")
                                                     : NSLocalizedString("Pin %@", comment: "pin selected object menu item"),
                                                     objectTitle),
                                       enabled: hasSelection && mutationAllowed,
                                       hidden: !hasSelection,
                                       in: menu)
        updateLightweightSidebarAction(#selector(openLightweightTableInNewTab(_:)),
                                       title: String(format: NSLocalizedString("Open %@ in New Tab", comment: "open selected object in new tab title"), objectTitle),
                                       enabled: singleOnlySelection,
                                       hidden: !singleOnlySelection,
                                       in: menu)
        updateLightweightSidebarAction(#selector(openLightweightTableInNewWindow(_:)),
                                       title: String(format: NSLocalizedString("Open %@ in New Window", comment: "open selected object in new window title"), objectTitle),
                                       enabled: singleOnlySelection,
                                       hidden: !singleOnlySelection,
                                       in: menu)

        let canExport = canExportSelectedLightweightTable
        lightweightSelectedTableExportMenuItem?.isHidden = !canExport
        lightweightSelectedTableExportMenuItem?.isEnabled = canExport
        lightweightSelectedTableExportMenuItem?.submenu?.items.forEach { item in
            item.isEnabled = canExport && canExportSelectedLightweightItems(selectedItems, formatTag: item.tag)
        }
        updateLightweightSidebarActionMenuSeparators(in: menu)
    }

    private func updateLightweightSidebarAction(_ action: Selector, title: String, enabled: Bool, hidden: Bool, in menu: NSMenu?) {
        guard let item = menu?.items.first(where: { $0.action == action }) else { return }

        item.title = title
        item.isEnabled = enabled
        item.isHidden = hidden
    }

    private func updateLightweightSidebarActionMenuSeparators(in menu: NSMenu?) {
        guard let menu = menu else { return }

        menu.items.filter { $0.isSeparatorItem }.forEach { $0.isHidden = false }

        var sawVisibleAction = false
        var lastVisibleSeparator: NSMenuItem?
        for item in menu.items where !item.isHidden {
            if item.isSeparatorItem {
                if sawVisibleAction {
                    lastVisibleSeparator?.isHidden = true
                    lastVisibleSeparator = item
                } else {
                    item.isHidden = true
                }
            } else {
                sawVisibleAction = true
                lastVisibleSeparator = nil
            }
        }

        lastVisibleSeparator?.isHidden = true
    }

    private func lightweightSidebarActionObjectTitle(for type: SALightweightTableObjectType) -> String {
        switch type {
        case .view:
            return NSLocalizedString("View", comment: "selected view menu title component")
        case .procedure:
            return NSLocalizedString("Procedure", comment: "selected procedure menu title component")
        case .function:
            return NSLocalizedString("Function", comment: "selected function menu title component")
        case .none, .table:
            return NSLocalizedString("Table", comment: "selected table menu title component")
        }
    }

    func promptForLightweightName(title: String,
                                  message: String,
                                  defaultValue: String = "",
                                  buttonTitle: String,
                                  nameValidator: ((String) -> Bool)? = nil) -> String? {
        let result = promptForLightweightSimpleName(title: title,
                                                    message: message,
                                                    defaultValue: defaultValue,
                                                    buttonTitle: buttonTitle,
                                                    nameValidator: nameValidator)
        return result?.name
    }

    func promptForLightweightSimpleName(title: String,
                                        message: String,
                                        defaultValue: String = "",
                                        buttonTitle: String,
                                        nameValidator: ((String) -> Bool)? = nil) -> SALightweightLegacySheetResult? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 314, height: 112),
                              styleMask: [.titled, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.minSize = NSSize(width: 292, height: 112)
        window.maxSize = NSSize(width: 650, height: 112)
        let controller = SALightweightLegacySheetController(window: window)
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView

        let messageField = legacyLabel(message, frame: NSRect(x: 17, y: 78, width: 280, height: 14), alignment: .left)
        messageField.lineBreakMode = .byTruncatingMiddle
        let nameField = legacyTextField(frame: NSRect(x: 20, y: 52, width: 274, height: 18), value: defaultValue)
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: 15, y: 13, width: 99, height: 28), keyEquivalent: "\u{1b}")
        let okButton = legacyButton(title: buttonTitle, frame: NSRect(x: 186, y: 13, width: 113, height: 28), keyEquivalent: "\r")

        contentView.addSubview(messageField)
        contentView.addSubview(nameField)
        contentView.addSubview(cancelButton)
        contentView.addSubview(okButton)

        controller.nameField = nameField
        controller.okButton = okButton
        controller.nameValidator = nameValidator
        nameField.delegate = controller
        nameField.target = controller
        nameField.action = #selector(SALightweightLegacySheetController.accept(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        okButton.target = controller
        okButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: nameField) == .OK else { return nil }
        return controller.result
    }

    func promptForLightweightDatabase() -> SALightweightLegacySheetResult? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 384, height: 133),
                              styleMask: .titled,
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("New Database", comment: "new database sheet title")
        window.minSize = NSSize(width: 384, height: 133)
        window.maxSize = NSSize(width: 600, height: 133)
        return runLightweightNamedObjectSheet(window: window,
                                              nameLabel: NSLocalizedString("Database Name:", comment: "database name label"),
                                              encodingLabel: NSLocalizedString("Database Encoding:", comment: "database encoding label"),
                                              collationLabel: NSLocalizedString("Database Collation:", comment: "database collation label"),
                                              defaultEncodingTitle: lightweightDefaultEncodingTitle(database: nil, format: NSLocalizedString("Server Default (%@)", comment: "Add Database : Charset dropdown : default item ($1 = charset name)")),
                                              defaultCollationTitle: lightweightDefaultCollationTitle(database: nil, format: NSLocalizedString("Server Default (%@)", comment: "Add Database : Collation dropdown : default item ($1 = collation name)")),
                                               buttonTitle: NSLocalizedString("Add", comment: "add database button"),
                                               nameValidator: lightweightDatabaseNameLiveValidator())
    }

    func promptForLightweightDatabaseCopy(sourceDatabase: String) -> SALightweightLegacySheetResult? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 379, height: 154),
                              styleMask: .titled,
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("Duplicate Database", comment: "copy database sheet title")
        window.minSize = NSSize(width: 379, height: 154)
        window.maxSize = NSSize(width: 379, height: 154)

        let controller = SALightweightLegacySheetController(window: window)
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView

        let titleField = legacyLabel(NSLocalizedString("Duplicate database:", comment: "duplicate database title label"), frame: NSRect(x: 104, y: 120, width: 258, height: 14), alignment: .left)
        let sourceLabel = legacyLabel(NSLocalizedString("Source:", comment: "source database label"), frame: NSRect(x: -3, y: 98, width: 105, height: 14), alignment: .right)
        let sourceField = legacyLabel(sourceDatabase, frame: NSRect(x: 104, y: 98, width: 258, height: 14), alignment: .left)
        sourceField.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let destinationLabel = legacyLabel(NSLocalizedString("Destination:", comment: "destination database label"), frame: NSRect(x: -3, y: 74, width: 105, height: 14), alignment: .right)
        let nameField = legacyTextField(frame: NSRect(x: 107, y: 72, width: 252, height: 18), value: sourceDatabase)
        let duplicateContent = NSButton(checkboxWithTitle: NSLocalizedString("Duplicate database content", comment: "duplicate database content checkbox"), target: nil, action: nil)
        duplicateContent.frame = NSRect(x: 105, y: 48, width: 256, height: 18)
        duplicateContent.controlSize = .small
        duplicateContent.font = .messageFont(ofSize: 11)
        duplicateContent.state = .on
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: 172, y: 13, width: 93, height: 28), keyEquivalent: "\u{1b}")
        let duplicateButton = legacyButton(title: NSLocalizedString("Duplicate", comment: "duplicate database button"), frame: NSRect(x: 261, y: 13, width: 103, height: 28), keyEquivalent: "\r")

        [titleField, sourceLabel, sourceField, destinationLabel, nameField, duplicateContent, cancelButton, duplicateButton].forEach(contentView.addSubview)

        controller.nameField = nameField
        controller.okButton = duplicateButton
        controller.duplicateContentButton = duplicateContent
        controller.nameValidator = lightweightDatabaseNameLiveValidator()
        nameField.delegate = controller
        nameField.target = controller
        nameField.action = #selector(SALightweightLegacySheetController.accept(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        duplicateButton.target = controller
        duplicateButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: nameField) == .OK else { return nil }
        return controller.result
    }

    func promptForLightweightDatabaseAlter(database: String) -> SALightweightLegacySheetResult? {
        guard let activeConnection = activeConnection else { return nil }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 384, height: 119),
                              styleMask: .titled,
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("Alter Database", comment: "alter database sheet title")
        window.minSize = NSSize(width: 384, height: 119)
        window.maxSize = NSSize(width: 600, height: 119)

        let controller = SALightweightLegacySheetController(window: window)
        controller.requiresName = false
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView

        let currentDefaults = lightweightDatabaseDefaults(for: database, connection: activeConnection)
        let currentEncoding = currentDefaults?.encoding ?? ""
        let currentCollation = currentDefaults?.collation ?? ""
        let encodingChoices = lightweightEncodingChoices(defaultTitle: NSLocalizedString("Default", comment: "default encoding title")).filter { $0.name != nil }
        let selectedEncodingTitle = encodingChoices.first { $0.name?.caseInsensitiveCompare(currentEncoding) == .orderedSame }?.title ?? encodingChoices.first?.title ?? currentEncoding

        let encodingButton = legacyPopup(frame: NSRect(x: 143, y: 78, width: 224, height: 22),
                                         choices: encodingChoices,
                                         defaultTitle: selectedEncodingTitle)
        let collationButton = legacyPopup(frame: NSRect(x: 143, y: 53, width: 224, height: 22),
                                           choices: [SALightweightEncodingChoice(title: currentCollation.isEmpty ? NSLocalizedString("Default", comment: "default collation title") : currentCollation, name: currentCollation.isEmpty ? nil : currentCollation)],
                                           defaultTitle: currentCollation.isEmpty ? NSLocalizedString("Default", comment: "default collation title") : currentCollation)
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: 174, y: 13, width: 96, height: 28), keyEquivalent: "\u{1b}")
        let alterButton = legacyButton(title: NSLocalizedString("Apply", comment: "apply button"), frame: NSRect(x: 268, y: 13, width: 101, height: 28), keyEquivalent: "\r")

        contentView.addSubview(legacyLabel(NSLocalizedString("Database Encoding:", comment: "database encoding label"), frame: NSRect(x: 17, y: 83, width: 122, height: 14), alignment: .right))
        contentView.addSubview(encodingButton)
        contentView.addSubview(legacyLabel(NSLocalizedString("Database Collation:", comment: "database collation label"), frame: NSRect(x: 17, y: 58, width: 122, height: 14), alignment: .right))
        contentView.addSubview(collationButton)
        contentView.addSubview(cancelButton)
        contentView.addSubview(alterButton)

        controller.okButton = alterButton
        controller.encodingButton = encodingButton
        controller.collationButton = collationButton
        controller.encodingNamesByTitle = Dictionary(uniqueKeysWithValues: encodingChoices.map { ($0.title, $0.name) })
        let collationChoices = lightweightCollationChoices()
        controller.collationsByEncoding = collationChoices.collationsByEncoding
        controller.defaultCollationTitlesByEncoding = collationChoices.defaultCollationTitlesByEncoding
        controller.defaultCollationTitle = currentCollation.isEmpty ? NSLocalizedString("Default", comment: "default collation title") : currentCollation
        encodingButton.target = controller
        encodingButton.action = #selector(SALightweightLegacySheetController.encodingDidChange(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        alterButton.target = controller
        alterButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.encodingDidChange(encodingButton)
        if !currentCollation.isEmpty {
            collationButton.selectItem(withTitle: currentCollation)
        }
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: encodingButton) == .OK else { return nil }
        return controller.result
    }

    func promptForLightweightTable() -> SALightweightLegacySheetResult? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 425, height: 162),
                              styleMask: [.titled, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("New Table", comment: "new table sheet title")
        window.minSize = NSSize(width: 425, height: 162)
        window.maxSize = NSSize(width: 600, height: 162)
        let result = runLightweightNamedObjectSheet(window: window,
                                                    nameLabel: NSLocalizedString("Table Name:", comment: "table name label"),
                                                    encodingLabel: NSLocalizedString("Table Encoding:", comment: "table encoding label"),
                                                    collationLabel: NSLocalizedString("Table Collation:", comment: "table collation label"),
                                                    defaultEncodingTitle: lightweightDefaultEncodingTitle(database: selectedDatabase, format: NSLocalizedString("Inherit from database (%@)", comment: "New Table Sheet : Table Encoding Dropdown : Default inherited from database")),
                                                    defaultCollationTitle: lightweightDefaultCollationTitle(database: selectedDatabase, format: NSLocalizedString("Inherit from database (%@)", comment: "New Table Sheet : Table Collation Dropdown : Default inherited from database")),
                                                    buttonTitle: NSLocalizedString("Add", comment: "add table button"),
                                                    typeLabel: NSLocalizedString("Table Type:", comment: "table type label"),
                                                    typeChoices: lightweightTableTypeChoices())
        return result
    }

    func promptForLightweightDuplicateTable(sourceName: String, tableType: SALightweightTableObjectType, defaultValue: String) -> SALightweightLegacySheetResult? {
        let supportsTargetDatabase = tableType == .table
        let windowHeight: CGFloat = supportsTargetDatabase ? 192 : 154
        let topOffset: CGFloat = supportsTargetDatabase ? 0 : -38
        let objectTitle = lightweightSidebarActionObjectTitle(for: tableType)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: windowHeight),
                              styleMask: [.titled, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = String(format: NSLocalizedString("Duplicate %@", comment: "duplicate object sheet title"), objectTitle)
        window.minSize = NSSize(width: 260, height: windowHeight)
        window.maxSize = NSSize(width: 260, height: windowHeight)

        let controller = SALightweightLegacySheetController(window: window)
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView

        let titleField = legacyLabel(window.title, frame: NSRect(x: 18, y: 167 + topOffset, width: 224, height: 19), alignment: .center)
        let databaseLabel = legacyLabel(NSLocalizedString("Database:", comment: "database label"), frame: NSRect(x: 16, y: 145, width: 226, height: 14), alignment: .left)
        let databaseButton = legacyPopup(frame: NSRect(x: 16, y: 113, width: 228, height: 25),
                                         choices: lightweightDatabases.map { SALightweightEncodingChoice(title: $0, name: $0) },
                                         defaultTitle: selectedDatabase ?? NSLocalizedString("Choose Database...", comment: "menu item for choose db"))
        let message = String(format: NSLocalizedString("Duplicate %@ '%@' to:", comment: "duplicate object message"), tableType.localizedName, sourceName)
        let messageField = legacyLabel(message, frame: NSRect(x: 17, y: 95, width: 226, height: 14), alignment: .left)
        let nameField = legacyTextField(frame: NSRect(x: 19, y: 68, width: 222, height: 19), value: defaultValue)
        let duplicateContent = NSButton(checkboxWithTitle: NSLocalizedString("Duplicate table content", comment: "duplicate table content checkbox"), target: nil, action: nil)
        duplicateContent.frame = NSRect(x: 17, y: 43, width: 227, height: 18)
        duplicateContent.controlSize = .small
        duplicateContent.font = .messageFont(ofSize: 11)
        duplicateContent.state = (tableType == .table && UserDefaults.standard.bool(forKey: SPCopyContentOnTableCopy)) ? .on : .off
        duplicateContent.isEnabled = tableType == .table
        duplicateContent.isHidden = tableType != .table
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: 61, y: 13, width: 91, height: 28), keyEquivalent: "\u{1b}")
        let duplicateButton = legacyButton(title: NSLocalizedString("Duplicate", comment: "duplicate table button"), frame: NSRect(x: 150, y: 13, width: 97, height: 28), keyEquivalent: "\r")

        [titleField, messageField, nameField, duplicateContent, cancelButton, duplicateButton].forEach(contentView.addSubview)
        if supportsTargetDatabase {
            contentView.addSubview(databaseLabel)
            contentView.addSubview(databaseButton)
        }

        controller.nameField = nameField
        controller.okButton = duplicateButton
        if supportsTargetDatabase {
            controller.targetDatabaseButton = databaseButton
        }
        controller.duplicateContentButton = duplicateContent
        nameField.delegate = controller
        nameField.target = controller
        nameField.action = #selector(SALightweightLegacySheetController.accept(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        duplicateButton.target = controller
        duplicateButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: nameField) == .OK else { return nil }
        return controller.result
    }

    func runLightweightNamedObjectSheet(window: NSWindow,
                                        nameLabel: String,
                                        encodingLabel: String,
                                        collationLabel: String,
                                        defaultEncodingTitle: String,
                                        defaultCollationTitle: String,
                                        buttonTitle: String,
                                        typeLabel: String? = nil,
                                        typeChoices: [SALightweightEncodingChoice] = [],
                                        nameValidator: ((String) -> Bool)? = nil) -> SALightweightLegacySheetResult? {
        let controller = SALightweightLegacySheetController(window: window)
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView
        let hasType = typeLabel != nil
        let choices = lightweightEncodingChoices(defaultTitle: defaultEncodingTitle)

        let labelWidth = hasType ? 128.0 : 134.0
        let fieldX = hasType ? 135.0 : 143.0
        let textFieldX = hasType ? 138.0 : 146.0
        let fieldWidth = hasType ? 273.0 : 224.0
        let textFieldWidth = hasType ? 267.0 : 218.0
        let topY = hasType ? 125.0 : 96.0
        let nameFieldY = hasType ? 124.0 : 94.0
        let encodingY = hasType ? 100.0 : 71.0
        let encodingPopupY = hasType ? 95.0 : 66.0
        let collationY = hasType ? 75.0 : 46.0
        let collationPopupY = hasType ? 70.0 : 41.0

        let nameField = legacyTextField(frame: NSRect(x: textFieldX, y: nameFieldY, width: textFieldWidth, height: 19), value: "")
        let encodingButton = legacyPopup(frame: NSRect(x: fieldX, y: encodingPopupY, width: fieldWidth, height: 22),
                                         choices: choices,
                                         defaultTitle: defaultEncodingTitle)
        let collationButton = legacyPopup(frame: NSRect(x: fieldX, y: collationPopupY, width: fieldWidth, height: 22),
                                          choices: [SALightweightEncodingChoice(title: defaultCollationTitle, name: nil)],
                                          defaultTitle: defaultCollationTitle)
        let cancelX = hasType ? 250.0 : 205.0
        let okX = hasType ? 332.0 : 289.0
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: cancelX, y: 13, width: hasType ? 84 : 86, height: 28), keyEquivalent: "\u{1b}")
        let okButton = legacyButton(title: buttonTitle, frame: NSRect(x: okX, y: 13, width: hasType ? 78 : 80, height: 28), keyEquivalent: "\r")

        contentView.addSubview(legacyLabel(nameLabel, frame: NSRect(x: 5, y: topY, width: labelWidth, height: 14), alignment: .right))
        contentView.addSubview(nameField)
        contentView.addSubview(legacyLabel(encodingLabel, frame: NSRect(x: 5, y: encodingY, width: labelWidth, height: 14), alignment: .right))
        contentView.addSubview(encodingButton)
        contentView.addSubview(legacyLabel(collationLabel, frame: NSRect(x: 5, y: collationY, width: labelWidth, height: 14), alignment: .right))
        contentView.addSubview(collationButton)

        if let typeLabel = typeLabel {
            let typeButton = legacyPopup(frame: NSRect(x: 135, y: 45, width: 273, height: 22),
                                         choices: typeChoices,
                                         defaultTitle: typeChoices.first?.title ?? NSLocalizedString("Default", comment: "default table type"))
            contentView.addSubview(legacyLabel(typeLabel, frame: NSRect(x: 5, y: 49, width: 128, height: 14), alignment: .right))
            contentView.addSubview(typeButton)
            controller.tableTypeButton = typeButton
        }

        contentView.addSubview(cancelButton)
        contentView.addSubview(okButton)

        controller.nameField = nameField
        controller.okButton = okButton
        controller.nameValidator = nameValidator
        controller.encodingButton = encodingButton
        controller.collationButton = collationButton
        controller.encodingNamesByTitle = Dictionary(uniqueKeysWithValues: choices.map { ($0.title, $0.name) })
        let collationChoices = lightweightCollationChoices()
        controller.collationsByEncoding = collationChoices.collationsByEncoding
        controller.defaultCollationTitlesByEncoding = collationChoices.defaultCollationTitlesByEncoding
        controller.defaultCollationTitle = defaultCollationTitle
        nameField.delegate = controller
        nameField.target = controller
        nameField.action = #selector(SALightweightLegacySheetController.accept(_:))
        encodingButton.target = controller
        encodingButton.action = #selector(SALightweightLegacySheetController.encodingDidChange(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        okButton.target = controller
        okButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: nameField) == .OK else { return nil }
        return controller.result
    }

    func runLightweightLegacySheet(_ controller: SALightweightLegacySheetController, firstResponder: NSResponder?) -> NSApplication.ModalResponse {
        configureLightweightModalWindow(controller.window)
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak controller] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.command) else { return event }

            switch event.charactersIgnoringModifiers ?? "" {
            case ".":
                controller?.cancel(nil)
                return nil
            case "\r", "\u{3}":
                controller?.accept(nil)
                return nil
            default:
                return event
            }
        }
        defer {
            if let keyMonitor = keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }

        guard let parentWindow = window else {
            controller.window.center()
            controller.window.makeKeyAndOrderFront(nil)
            if let firstResponder = firstResponder {
                controller.window.makeFirstResponder(firstResponder)
            }
            return NSApp.runModal(for: controller.window)
        }

        centerLightweightModalWindow(controller.window)
        if let firstResponder = firstResponder {
            controller.window.makeFirstResponder(firstResponder)
        }

        var response: NSApplication.ModalResponse = .cancel
        activeLightweightLegacySheetController = controller
        parentWindow.beginSheet(controller.window) { modalResponse in
            response = modalResponse
            controller.window.orderOut(nil)
            self.activeLightweightLegacySheetController = nil
            NSApp.stopModal(withCode: modalResponse)
        }

        let modalResponse = NSApp.runModal(for: controller.window)
        return response == .cancel ? modalResponse : response
    }

    func applyLightweightDefaultEncodingPreference() {
        let preferredTag = UserDefaults.standard.integer(forKey: SPDefaultEncoding)
        let mysqlEncoding = preferredTag == SALightweightEncodingMenu.autodetectTag
            ? "utf8mb4"
            : Self.lightweightMySQLEncoding(fromEncodingTag: preferredTag)
        setLightweightConnectionEncoding(mysqlEncoding, reloadingViews: false)
    }

    @discardableResult
    func setLightweightConnectionEncoding(_ mysqlEncoding: String, reloadingViews reloadViews: Bool) -> Bool {
        guard let activeConnection = activeConnection else { return false }

        var mysqlEncoding = mysqlEncoding
        var useLatin1Transport = false
        if mysqlEncoding == "utf8-" {
            useLatin1Transport = true
            mysqlEncoding = "utf8mb4"
        }

        guard activeConnection.setEncoding(mysqlEncoding) else {
            NSLog("Error: could not set encoding to %@ nor fall back to database encoding on MySQL %@", mysqlEncoding, activeServerVersion ?? "")
            return false
        }

        activeConnection.setEncodingUsesLatin1Transport(useLatin1Transport)
        activeConnection.storeEncodingForRestoration()

        if reloadViews {
            reloadLightweightViewsAfterEncodingChange()
        }

        return true
    }

    func reloadLightweightViewsAfterEncodingChange() {
        lightweightStructureController.clearCachedTables()
        lightweightContentController.clearCachedTables()

        guard let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else { return }

        if let selectedTable = selectedTable {
            loadLightweightTableInfo(for: selectedTable)

            switch activeLightweightViewMode {
            case .content:
                lightweightContentController.loadContent(for: selectedTable, database: selectedDatabase, connection: activeConnection)
            case .query:
                let fieldNames = lightweightStructureController.cachedColumnMetadata(for: selectedTable, database: selectedDatabase)?.compactMap { $0["name"] } ?? []
                lightweightQueryController.loadQuery(database: selectedDatabase,
                                                     table: selectedTable,
                                                     connection: activeConnection,
                                                     databases: lightweightDatabases,
                                                     tables: lightweightTables,
                                                     tableTypes: lightweightTableTypes,
                                                     fieldNames: fieldNames)
            case .status:
                lightweightTableInfoController.loadTableInfo(for: selectedTable, database: selectedDatabase, connection: activeConnection)
            case .relations:
                showLightweightRelations(for: selectedTable)
            case .triggers:
                showLightweightTriggers(for: selectedTable)
            default:
                lightweightStructureController.loadStructure(for: selectedTable, database: selectedDatabase, connection: activeConnection, useCache: false)
            }
        } else {
            loadTables(for: selectedDatabase, preservingSelection: true)
        }
    }

    func currentLightweightEncodingMenuTag() -> Int {
        guard let activeConnection = activeConnection else { return SALightweightEncodingMenu.autodetectTag }

        if activeConnection.encodingUsesLatin1Transport() {
            return SALightweightEncodingMenu.utf8ViaLatin1Tag
        }

        let mysqlEncoding = activeConnection.encoding() ?? ""
        return SALightweightEncodingMenu.mysqlEncodingToTag[mysqlEncoding] ?? SALightweightEncodingMenu.autodetectTag
    }

    static func lightweightMySQLEncoding(fromEncodingTag tag: Int) -> String {
        return SALightweightEncodingMenu.tagToMySQLEncoding[tag] ?? "utf8mb4"
    }

    func legacyLabel(_ title: String, frame: NSRect, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.font = .messageFont(ofSize: 11)
        label.alignment = alignment
        label.lineBreakMode = .byClipping
        return label
    }

    func legacyTextField(frame: NSRect, value: String) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.controlSize = .small
        field.font = .messageFont(ofSize: 11)
        field.cell?.controlSize = .small
        field.cell?.usesSingleLineMode = true
        field.stringValue = value
        return field
    }

    func legacyButton(title: String, frame: NSRect, keyEquivalent: String) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .messageFont(ofSize: 11)
        button.keyEquivalent = keyEquivalent
        return button
    }

    func legacyPopup(frame: NSRect, choices: [SALightweightEncodingChoice], defaultTitle: String) -> NSPopUpButton {
        let button = NSPopUpButton(frame: frame, pullsDown: false)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .messageFont(ofSize: 11)
        button.addItem(withTitle: defaultTitle)
        if choices.contains(where: { $0.title != defaultTitle }) {
            button.menu?.addItem(.separator())
        }
        choices.filter { $0.title != defaultTitle }.forEach { button.addItem(withTitle: $0.title) }
        return button
    }

    func lightweightDefaultEncodingTitle(database: String?, format: String) -> String {
        guard let activeConnection = activeConnection else { return NSLocalizedString("Default", comment: "default encoding title") }

        let query: String
        if let database = database {
            query = "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = \(Self.sqlString(database))"
        } else {
            query = "SHOW VARIABLES LIKE 'character_set_server'"
        }

        let result = database.map { activeConnection.queryString(query, assertingDatabase: $0) }
            ?? activeConnection.queryString(query)
        guard let result = result else { return NSLocalizedString("Default", comment: "default encoding title") }
        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return NSLocalizedString("Default", comment: "default encoding title") }
        let value = Self.displayString(for: row["DEFAULT_CHARACTER_SET_NAME"] ?? row["Value"])
        return value.isEmpty ? NSLocalizedString("Default", comment: "default encoding title") : String(format: format, value)
    }

    func lightweightDefaultCollationTitle(database: String?, format: String) -> String {
        guard let activeConnection = activeConnection else { return NSLocalizedString("Default", comment: "default collation title") }

        let query: String
        if let database = database {
            query = "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = \(Self.sqlString(database))"
        } else {
            query = "SHOW VARIABLES LIKE 'collation_server'"
        }

        let result = database.map { activeConnection.queryString(query, assertingDatabase: $0) }
            ?? activeConnection.queryString(query)
        guard let result = result else { return NSLocalizedString("Default", comment: "default collation title") }
        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return NSLocalizedString("Default", comment: "default collation title") }
        let value = Self.displayString(for: row["DEFAULT_COLLATION_NAME"] ?? row["Value"])
        return value.isEmpty ? NSLocalizedString("Default", comment: "default collation title") : String(format: format, value)
    }

    func lightweightEncodingChoices(defaultTitle: String) -> [SALightweightEncodingChoice] {
        guard let activeConnection = activeConnection else { return [SALightweightEncodingChoice(title: defaultTitle, name: nil)] }

        let queries = [
            "SELECT CHARACTER_SET_NAME, DESCRIPTION FROM information_schema.character_sets ORDER BY character_set_name ASC",
            "SHOW CHARACTER SET"
        ]

        for query in queries {
            guard let result = activeConnection.queryString(query) else { continue }

            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            var utf8Choices: [SALightweightEncodingChoice] = []
            var otherChoices: [SALightweightEncodingChoice] = []

            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = Self.displayString(for: row["CHARACTER_SET_NAME"] ?? row["Charset"])
                guard !name.isEmpty else { continue }
                let description = Self.displayString(for: row["DESCRIPTION"] ?? row["Description"])
                let title = description.isEmpty ? name : "\(description) (\(name))"
                let choice = SALightweightEncodingChoice(title: title, name: name)
                if name.hasPrefix("utf8") {
                    utf8Choices.append(choice)
                } else {
                    otherChoices.append(choice)
                }
            }

            let choices = [SALightweightEncodingChoice(title: defaultTitle, name: nil)] + utf8Choices + otherChoices
            if choices.count > 1 {
                return choices
            }
        }

        return [SALightweightEncodingChoice(title: defaultTitle, name: nil)]
    }

    func lightweightCollationChoices() -> (collationsByEncoding: [String: [String]], defaultCollationTitlesByEncoding: [String: String]) {
        guard let activeConnection = activeConnection else { return ([:], [:]) }

        let queries = [
            "SELECT COLLATION_NAME, CHARACTER_SET_NAME, IS_DEFAULT FROM information_schema.collations ORDER BY collation_name ASC",
            "SHOW COLLATION"
        ]

        for query in queries {
            guard let result = activeConnection.queryString(query) else { continue }

            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            var collationsByEncoding: [String: [String]] = [:]
            var defaultCollationsByEncoding: [String: String] = [:]

            while let row = result.getRowAsDictionary() as? [String: Any] {
                let collation = Self.displayString(for: row["COLLATION_NAME"] ?? row["Collation"])
                let encoding = Self.displayString(for: row["CHARACTER_SET_NAME"] ?? row["Charset"])
                guard !collation.isEmpty, !encoding.isEmpty else { continue }
                collationsByEncoding[encoding, default: []].append(collation)
                let isDefault = Self.displayString(for: row["IS_DEFAULT"] ?? row["Default"])
                if isDefault.caseInsensitiveCompare("Yes") == .orderedSame {
                    defaultCollationsByEncoding[encoding] = collation
                }
            }

            if !collationsByEncoding.isEmpty {
                if collationsByEncoding["utf8mb3"] == nil, let utf8Collations = collationsByEncoding["utf8"] {
                    collationsByEncoding["utf8mb3"] = utf8Collations
                    defaultCollationsByEncoding["utf8mb3"] = defaultCollationsByEncoding["utf8"]
                } else if collationsByEncoding["utf8"] == nil, let utf8mb3Collations = collationsByEncoding["utf8mb3"] {
                    collationsByEncoding["utf8"] = utf8mb3Collations
                    defaultCollationsByEncoding["utf8"] = defaultCollationsByEncoding["utf8mb3"]
                }

                let defaultTitlesByEncoding = defaultCollationsByEncoding.mapValues {
                    String(format: NSLocalizedString("Default (%@)", comment: "Collation Dropdown : Default ($1 = collation name)"), $0)
                }
                return (collationsByEncoding.mapValues { Self.uniqueStrings($0).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } },
                        defaultTitlesByEncoding)
            }
        }

        return ([:], [:])
    }

    func lightweightTableTypeChoices() -> [SALightweightEncodingChoice] {
        let defaultEngine = lightweightDefaultStorageEngine()
        var choices = [SALightweightEncodingChoice(title: String(format: NSLocalizedString("Default (%@)", comment: "New Table Sheet : Table Engine Dropdown : Default"), defaultEngine), name: nil)]
        guard let activeConnection = activeConnection,
              let result = activeConnection.queryString("SHOW ENGINES") else { return choices }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        while let row = result.getRowAsDictionary() as? [String: Any] {
            let support = Self.displayString(for: row["Support"])
            guard support != "NO" else { continue }
            let engine = Self.displayString(for: row["Engine"])
            guard !engine.isEmpty else { continue }
            choices.append(SALightweightEncodingChoice(title: engine, name: engine))
        }

        return choices
    }

    func lightweightDefaultStorageEngine() -> String {
        guard let activeConnection = activeConnection,
              let result = activeConnection.queryString("SHOW VARIABLES LIKE 'default_storage_engine'") else { return "InnoDB" }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return "InnoDB" }
        let value = Self.displayString(for: row["Value"])
        return value.isEmpty ? "InnoDB" : value
    }

    func lightweightTableHasAutoIncrement(_ table: String, database: String) -> Bool {
        guard let activeConnection = activeConnection,
              let result = activeConnection.queryString("SHOW TABLE STATUS FROM \(Self.backtickQuoted(database)) WHERE Name = \(Self.sqlString(table))",
                                                        assertingDatabase: database) else {
            return false
        }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary

        guard let row = result.getRowAsDictionary() as? [String: Any],
              let autoIncrement = row["Auto_increment"],
              !(autoIncrement is NSNull) else {
            return false
        }

        return !Self.displayString(for: autoIncrement).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func runLightweightModalAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alert.window.isRestorable = false
        alert.window.animationBehavior = .none

        return alert.runModalCentered(over: window)
    }

    func centerLightweightModalWindow(_ modalWindow: NSWindow) {
        guard let parentWindow = window else {
            modalWindow.center()
            return
        }

        let parentFrame = parentWindow.frame
        let modalFrame = modalWindow.frame
        modalWindow.setFrameOrigin(NSPoint(x: parentFrame.midX - modalFrame.width / 2,
                                           y: parentFrame.midY - modalFrame.height / 2))
    }

    func configureLightweightModalWindow(_ modalWindow: NSWindow) {
        modalWindow.isRestorable = false
        modalWindow.animationBehavior = .none
    }

    func validateLightweightObjectName(_ name: String, type: SALightweightTableObjectType, ignoring ignoredName: String? = nil) -> Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) != name || name.isEmpty {
            NSSound.beep()
            return false
        }

        let matchesExisting = lightweightTables.contains { table in
            guard table.caseInsensitiveCompare(ignoredName ?? "") != .orderedSame else { return false }
            guard (lightweightTableTypes[table] ?? .table) == type || type == .table || type == .view else { return false }
            return table.caseInsensitiveCompare(name) == .orderedSame
        }

        guard !matchesExisting else {
            showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                 message: String(format: NSLocalizedString("The name '%@' is already used.", comment: "message when trying to rename a table/view/proc/etc to an already used name"), name))
            return false
        }

        return true
    }

    func validateLightweightDatabaseName(_ name: String, ignoring ignoredName: String? = nil) -> Bool {
        guard !name.isEmpty else {
            showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                 message: NSLocalizedString("Database must have a name.", comment: "message of panel when no db name is given"))
            return false
        }

        let databases = activeConnection?.databases() as? [String] ?? lightweightDatabases
        let matchesExisting = databases.contains { database in
            guard database.caseInsensitiveCompare(ignoredName ?? "") != .orderedSame else { return false }
            return database.caseInsensitiveCompare(name) == .orderedSame
        }

        guard !matchesExisting else {
            showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                 message: String(format: NSLocalizedString("The name '%@' is already used.", comment: "message when trying to rename a table/view/proc/etc to an already used name"), name))
            return false
        }

        return true
    }

    func lightweightDatabaseNameLiveValidator() -> (String) -> Bool {
        let databases = activeConnection?.databases() as? [String] ?? lightweightDatabases
        return { candidate in
            !databases.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
    }

    func showLightweightDatabaseRenameUnsupportedAlert(database: String, unsupportedTypes: [SALightweightDatabaseRenameObjectType]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Database Rename Unsupported", comment: "database rename unsupported message")
        let unsupportedDescription = lightweightDatabaseRenameUnsupportedDescription(for: unsupportedTypes)
        alert.informativeText = String(format: NSLocalizedString("Renaming the database '%@' is currently supported only when it contains base tables. This database also contains %@, so Sequel Ace will not create a replacement database and automatically drop the original.\n\nUse 'Duplicate Database' instead; that copy path includes tables, views, routines, triggers, and events. After manually verifying the duplicate, drop the old database yourself.", comment: "database rename unsupported informative message"), database, unsupportedDescription)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        _ = runLightweightModalAlert(alert)
    }

    func lightweightDatabaseRenameUnsupportedDescription(for types: [SALightweightDatabaseRenameObjectType]) -> String {
        let orderedTypes: [SALightweightDatabaseRenameObjectType] = [.view, .procedure, .function, .trigger, .event]
        let labels = orderedTypes.compactMap { type -> String? in
            guard types.contains(type) else { return nil }
            switch type {
            case .view:
                return NSLocalizedString("views", comment: "database rename unsupported views label")
            case .procedure:
                return NSLocalizedString("procedures", comment: "database rename unsupported procedures label")
            case .function:
                return NSLocalizedString("functions", comment: "database rename unsupported functions label")
            case .trigger:
                return NSLocalizedString("triggers", comment: "database rename unsupported triggers label")
            case .event:
                return NSLocalizedString("events", comment: "database rename unsupported events label")
            case .table:
                return nil
            }
        }

        guard !labels.isEmpty else {
            return NSLocalizedString("objects that cannot be safely moved by the lightweight rename path", comment: "database rename unsupported fallback label")
        }

        return labels.joined(separator: ", ")
    }

    func lightweightDatabaseRenamePreflight(from sourceDatabase: String, to targetDatabase: String, connection: SPMySQLConnection) -> SALightweightDatabaseRenamePreflightResult {
        let databases = connection.databases() as? [String] ?? []
        guard databases.contains(sourceDatabase) else { return .sourceMissing }
        guard !databases.contains(targetDatabase) else { return .targetExists }

        let objects = loadLightweightDatabaseRenameObjects(for: sourceDatabase, connection: connection)
        if connection.queryErrored() {
            let error = connection.lastErrorMessage()
            return .failed(error?.isEmpty == false ? error! : NSLocalizedString("Unable to inspect database objects before rename.", comment: "database rename preflight failed"))
        }

        let unsupportedTypes = objects
            .filter { $0.type != .table }
            .map { $0.type }
            .reduce(into: [SALightweightDatabaseRenameObjectType]()) { types, type in
                if !types.contains(type) {
                    types.append(type)
                }
            }
        guard unsupportedTypes.isEmpty else { return .unsupportedObjects(unsupportedTypes) }

        var options: [String] = []
        if let defaults = lightweightDatabaseDefaults(for: sourceDatabase, connection: connection) {
            if let encoding = defaults.encoding, !encoding.isEmpty {
                options.append("DEFAULT CHARACTER SET = \(Self.backtickQuoted(encoding))")
            }
            if let collation = defaults.collation, !collation.isEmpty {
                options.append("DEFAULT COLLATE = \(Self.backtickQuoted(collation))")
            }
        }

        var statements = [
            "CREATE DATABASE \(Self.backtickQuoted(targetDatabase)) \(options.joined(separator: " "))"
        ]

        let tableRenames = objects
            .filter { $0.type == .table }
            .map { table in
                "\(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(table.name)) TO \(Self.backtickQuoted(targetDatabase)).\(Self.backtickQuoted(table.name))"
            }
        if !tableRenames.isEmpty {
            statements.append("RENAME TABLE \(tableRenames.joined(separator: ", "))")
        }

        statements.append("DROP DATABASE \(Self.backtickQuoted(sourceDatabase))")
        return .ready(statements)
    }

    func loadLightweightDatabaseRenameObjects(for database: String, connection: SPMySQLConnection) -> [(name: String, type: SALightweightDatabaseRenameObjectType)] {
        var objects: [(name: String, type: SALightweightDatabaseRenameObjectType)] = []

        if let result = connection.queryString("SHOW FULL TABLES FROM \(Self.backtickQuoted(database))", assertingDatabase: database) {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = row.first { key, _ in
                    let keyString = String(describing: key).lowercased()
                    return keyString != "table_type"
                }.map { stringValue($0.value) } ?? ""
                let tableType = row.first { key, _ in
                    String(describing: key).lowercased() == "table_type"
                }.map { stringValue($0.value).uppercased() } ?? ""

                guard !name.isEmpty else { continue }
                objects.append((name: name, type: tableType == "VIEW" ? .view : .table))
            }
        }

        if connection.queryErrored() {
            return objects
        }

        if let quotedDatabase = connection.escapeAndQuoteString(database),
           let result = connection.queryString("SELECT ROUTINE_NAME, ROUTINE_TYPE FROM information_schema.routines WHERE routine_schema = \(quotedDatabase) ORDER BY routine_name",
                                               assertingDatabase: database) {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = stringValue(row["ROUTINE_NAME"] ?? row["routine_name"])
                let routineType = stringValue(row["ROUTINE_TYPE"] ?? row["routine_type"]).uppercased()
                guard !name.isEmpty else { continue }
                objects.append((name: name, type: routineType == "PROCEDURE" ? .procedure : .function))
            }
        }

        if connection.queryErrored() {
            return objects
        }

        if let quotedDatabase = connection.escapeAndQuoteString(database),
           let result = connection.queryString("SELECT TRIGGER_NAME FROM information_schema.triggers WHERE trigger_schema = \(quotedDatabase) ORDER BY event_object_table, action_timing, event_manipulation, trigger_name",
                                               assertingDatabase: database) {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = stringValue(row["TRIGGER_NAME"] ?? row["trigger_name"])
                guard !name.isEmpty else { continue }
                objects.append((name: name, type: .trigger))
            }
        }

        if connection.queryErrored() {
            return objects
        }

        if let quotedDatabase = connection.escapeAndQuoteString(database),
           let result = connection.queryString("SELECT EVENT_NAME FROM information_schema.events WHERE event_schema = \(quotedDatabase) ORDER BY event_name",
                                               assertingDatabase: database) {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = stringValue(row["EVENT_NAME"] ?? row["event_name"])
                guard !name.isEmpty else { continue }
                objects.append((name: name, type: .event))
            }
        }

        return objects
    }

    func lightweightDatabaseDefaults(for database: String, connection: SPMySQLConnection) -> (encoding: String?, collation: String?)? {
        guard let result = connection.queryString("SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = \(Self.sqlString(database))",
                                                  assertingDatabase: database) else {
            return nil
        }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return nil }
        return (Self.displayString(for: row["DEFAULT_CHARACTER_SET_NAME"]),
                Self.displayString(for: row["DEFAULT_COLLATION_NAME"]))
    }

    func canStartLightweightMutation() -> Bool {
        guard !processing, !isLightweightImportRunning, !databaseListIsLoading else {
            NSSound.beep()
            return false
        }

        return true
    }

    func beginLightweightMutation(status: String) -> SALightweightMutationSnapshot? {
        guard canStartLightweightMutation() else { return nil }

        let snapshot = SALightweightMutationSnapshot(database: selectedDatabase,
                                                     table: selectedTable,
                                                     viewMode: activeLightweightViewMode)
        processing = true
        setLightweightMutationControlsEnabled(false)
        showLightweightPlaceholder(status)
        return snapshot
    }

    func finishLightweightMutation(_ snapshot: SALightweightMutationSnapshot, restoringDetail: Bool) {
        processing = false
        setLightweightMutationControlsEnabled(true)
        if restoringDetail {
            restoreLightweightDetail(after: snapshot)
        }
    }

    func refreshLightweightObjectsAfterMutation(database: String,
                                                restoringTable: String?,
                                                restoringTables: [String]? = nil,
                                                restoringViewMode: SAViewMode,
                                                recordsHistory: Bool = false,
                                                completion: (() -> Void)? = nil) {
        // Intentionally do not post SPTableChangedNotification or the legacy query notifications here.
        // Their listeners belong to loaded DBView controllers and would duplicate this direct lightweight refresh.
        processing = true
        setLightweightMutationControlsEnabled(false)
        loadTables(for: database,
                   restoringTable: restoringTable,
                   restoringTables: restoringTables,
                   restoringViewMode: restoringViewMode) { [weak self] in
            guard let self = self else { return }
            let currentTables = Set(self.lightweightTables)
            let missingHistoryTables = Set(self.lightweightHistoryBackStack + self.lightweightHistoryForwardStack)
                .subtracting(currentTables)
            if !missingHistoryTables.isEmpty {
                self.pruneLightweightHistory(removing: missingHistoryTables)
            }
            if recordsHistory, let restoringTable = restoringTable, self.lightweightTables.contains(restoringTable) {
                self.recordLightweightHistorySelection(restoringTable)
            }
            self.markLightweightResumeStateChanged()
            self.processing = false
            self.setLightweightMutationControlsEnabled(true)
            completion?()
        }
    }

    private func setLightweightMutationControlsEnabled(_ enabled: Bool) {
        tablesListView.isEnabled = enabled
        tableFilterField.isEnabled = enabled
        setLightweightFallbackToolbarItemsEnabled(enabled)
        updateLightweightSidebarActionMenuState()
    }

    private func restoreLightweightDetail(after snapshot: SALightweightMutationSnapshot) {
        guard snapshot.database == selectedDatabase else { return }

        setActiveLightweightViewMode(snapshot.viewMode, persist: false)
        if let table = snapshot.table, lightweightTables.contains(table) {
            selectLightweightTableInSidebar(table)
            selectLightweightTable(table, recordsHistory: false)
            return
        }

        switch snapshot.viewMode {
        case .query:
            showLightweightQuery()
        case .status:
            showLightweightStatus(for: nil)
        case .relations:
            showLightweightRelations(for: nil)
        case .triggers:
            showLightweightTriggers(for: nil)
        default:
            showLightweightPlaceholder(lightweightTables.isEmpty
                ? NSLocalizedString("No tables in this database.", comment: "lightweight database shell no tables")
                : NSLocalizedString("Select a table or choose a toolbar section.", comment: "lightweight database shell table loaded empty state"))
        }
    }

    func runLightweightDatabaseMutation(status: String,
                                        statement: String,
                                        assertingDatabase database: String? = nil,
                                        completion: @escaping (Bool) -> Void) {
        runLightweightDatabaseMutation(status: status,
                                       statements: [statement],
                                       assertingDatabase: database,
                                       completion: completion)
    }

    func runLightweightDatabaseMutation(status: String,
                                        statements: [String],
                                        assertingDatabase database: String? = nil,
                                        completion: @escaping (Bool) -> Void) {
        guard let activeConnection = activeConnection,
              let mutationSnapshot = beginLightweightMutation(status: status) else {
            completion(false)
            return
        }
        let statements = expandedLightweightDatabaseMutationStatements(statements)
        let assertionDatabase = database ?? mutationSnapshot.database

        DispatchQueue.global(qos: .userInitiated).async { [weak self, activeConnection] in
            guard let self = self else { return }

            var failedStatementIndex: Int?
            var mutationError: String?
            for (index, statement) in statements.enumerated() {
                self.runLightweightMutationStatement(statement,
                                                     connection: activeConnection,
                                                     assertingDatabase: assertionDatabase)
                if activeConnection.queryErrored() {
                    failedStatementIndex = index
                    mutationError = activeConnection.lastErrorMessage()
                    break
                }
            }

            if let failedStatementIndex = failedStatementIndex {
                for cleanupStatement in statements.dropFirst(failedStatementIndex + 1)
                    where cleanupStatement.uppercased().contains("FOREIGN_KEY_CHECKS=1") {
                    self.runLightweightMutationStatement(cleanupStatement,
                                                         connection: activeConnection,
                                                         assertingDatabase: assertionDatabase)
                }
            }
            let mutationFailed = failedStatementIndex != nil
            DispatchQueue.main.async {
                if !statements.isEmpty {
                    self.lightweightStructureController.clearCachedTables()
                    self.lightweightContentController.clearCachedTables()
                }
                self.finishLightweightMutation(mutationSnapshot, restoringDetail: mutationFailed)
                if mutationFailed {
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: mutationError?.isEmpty == false
                                                ? mutationError!
                                                : NSLocalizedString("The database operation failed.", comment: "lightweight database mutation fallback error"))
                    completion(false)
                    return
                }

                completion(true)
            }
        }
    }

    private func runLightweightMutationStatement(_ statement: String,
                                                 connection: SPMySQLConnection,
                                                 assertingDatabase database: String?) {
        let normalizedStatement = statement.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isConnectionGlobal = normalizedStatement.hasPrefix("SET ")
            || (normalizedStatement.hasPrefix("/*!") && normalizedStatement.contains(" SET "))

        if let database = database, !isConnectionGlobal {
            _ = connection.queryString(statement, assertingDatabase: database)
        } else {
            _ = connection.queryString(statement)
        }
    }

    private func expandedLightweightDatabaseMutationStatements(_ statements: [String]) -> [String] {
        return statements.flatMap { statement -> [String] in
            lightweightCaseOnlyRenameStatements(for: statement) ?? [statement]
        }
    }

    private func lightweightCaseOnlyRenameStatements(for statement: String) -> [String]? {
        guard let rename = lightweightRenameStatement(from: statement),
              rename.sourceDatabase.caseInsensitiveCompare(rename.targetDatabase) == .orderedSame,
              rename.sourceName != rename.targetName,
              rename.sourceName.caseInsensitiveCompare(rename.targetName) == .orderedSame else {
            return nil
        }

        let existingNames = lightweightTables + [rename.sourceName, rename.targetName]
        let tempName = lightweightTemporaryRenameName(avoiding: existingNames)
        let database = Self.backtickQuoted(rename.sourceDatabase)
        return [
            "RENAME TABLE \(database).\(Self.backtickQuoted(rename.sourceName)) TO \(database).\(Self.backtickQuoted(tempName))",
            "RENAME TABLE \(database).\(Self.backtickQuoted(tempName)) TO \(database).\(Self.backtickQuoted(rename.targetName))"
        ]
    }

    private func lightweightRenameStatement(from statement: String) -> SALightweightRenameStatement? {
        let pattern = #"(?i)^\s*RENAME\s+TABLE\s+(`(?:``|[^`])+`)\.(`(?:``|[^`])+`)\s+TO\s+(`(?:``|[^`])+`)\.(`(?:``|[^`])+`)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsString = statement as NSString
        let match = regex.firstMatch(in: statement, range: NSRange(location: 0, length: nsString.length))
        guard let match = match, match.numberOfRanges == 5 else { return nil }

        return SALightweightRenameStatement(sourceDatabase: lightweightUnquotedIdentifier(nsString.substring(with: match.range(at: 1))),
                                            sourceName: lightweightUnquotedIdentifier(nsString.substring(with: match.range(at: 2))),
                                            targetDatabase: lightweightUnquotedIdentifier(nsString.substring(with: match.range(at: 3))),
                                            targetName: lightweightUnquotedIdentifier(nsString.substring(with: match.range(at: 4))))
    }

    private func lightweightUnquotedIdentifier(_ identifier: String) -> String {
        guard identifier.hasPrefix("`"), identifier.hasSuffix("`"), identifier.count >= 2 else { return identifier }

        let unquoted = identifier.dropFirst().dropLast()
        return String(unquoted).replacingOccurrences(of: "``", with: "`")
    }

    private func lightweightTemporaryRenameName(avoiding existingNames: [String]) -> String {
        for _ in 0..<20 {
            let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
            let candidate = "_sequel_ace_tmp_\(suffix)"
            if !existingNames.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return candidate
            }
        }

        return "_sequel_ace_tmp_\(UUID().uuidString.prefix(8))"
    }

    func runLightweightDatabaseRenameMutation(from sourceDatabase: String, to targetDatabase: String, status: String, completion: @escaping (Bool) -> Void) {
        guard let activeConnection = activeConnection,
              let mutationSnapshot = beginLightweightMutation(status: status) else {
            completion(false)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, activeConnection] in
            guard let self = self else { return }

            switch self.lightweightDatabaseRenamePreflight(from: sourceDatabase, to: targetDatabase, connection: activeConnection) {
            case .ready(let statements):
                for statement in statements {
                    _ = activeConnection.queryString(statement, assertingDatabase: sourceDatabase)
                    if activeConnection.queryErrored() { break }
                }

                let mutationFailed = activeConnection.queryErrored()
                let error = mutationFailed ? activeConnection.lastErrorMessage() : nil
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: mutationFailed)
                    if mutationFailed {
                        self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                                  message: error?.isEmpty == false
                                                    ? error!
                                                    : NSLocalizedString("The database operation failed.", comment: "lightweight database mutation fallback error"))
                        completion(false)
                        return
                    }

                    self.lightweightStructureController.clearCachedTables()
                    self.lightweightContentController.clearCachedTables()
                    completion(true)
                }
            case .sourceMissing:
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Unable to rename database", comment: "unable to rename database message"),
                                             message: String(format: NSLocalizedString("The database '%@' no longer exists.", comment: "database rename source missing message"), sourceDatabase))
                    completion(false)
                }
            case .targetExists:
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                             message: String(format: NSLocalizedString("The name '%@' is already used.", comment: "message when trying to rename a table/view/proc/etc to an already used name"), targetDatabase))
                    completion(false)
                }
            case .unsupportedObjects(let unsupportedTypes):
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightDatabaseRenameUnsupportedAlert(database: sourceDatabase,
                                                                       unsupportedTypes: unsupportedTypes)
                    completion(false)
                }
            case .failed(let message):
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Unable to rename database", comment: "unable to rename database message"), message: message)
                    completion(false)
                }
            }
        }
    }

    func runLightweightDatabaseCopyMutation(from sourceDatabase: String,
                                            to targetDatabase: String,
                                            copyContent: Bool,
                                            status: String,
                                            completion: @escaping (Bool) -> Void) {
        guard let activeConnection = activeConnection,
              let mutationSnapshot = beginLightweightMutation(status: status) else {
            completion(false)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, activeConnection] in
            guard let self = self else { return }

            let databases = activeConnection.databases() as? [String] ?? []
            guard databases.contains(sourceDatabase), !databases.contains(targetDatabase) else {
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Unable to copy database", comment: "unable to copy database message"),
                                              message: String(format: NSLocalizedString("An error occurred while trying to copy the database '%@' to '%@'.", comment: "unable to copy database message informative message"), sourceDatabase, targetDatabase))
                    completion(false)
                }
                return
            }

            let objects = self.loadLightweightDatabaseCopyObjects(for: sourceDatabase, connection: activeConnection)
            if activeConnection.queryErrored() {
                let error = activeConnection.lastErrorMessage() ?? ""
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Unable to copy database", comment: "unable to copy database message"),
                                              message: error.isEmpty ? String(format: NSLocalizedString("An error occurred while trying to copy the database '%@' to '%@'.", comment: "unable to copy database message informative message"), sourceDatabase, targetDatabase) : error)
                    completion(false)
                }
                return
            }

            let tables = objects.filter { $0.type == .table }
            let routines = objects.filter { $0.type == .function || $0.type == .procedure }.sorted { left, right in
                if left.type == right.type { return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending }
                return left.type == .function
            }
            let views = objects.filter { $0.type == .view }
            let triggers = objects.filter { $0.type == .trigger }
            let events = objects.filter { $0.type == .event }
            var options: [String] = []
            if let defaults = self.lightweightDatabaseDefaults(for: sourceDatabase, connection: activeConnection) {
                if let encoding = defaults.encoding, !encoding.isEmpty {
                    options.append("DEFAULT CHARACTER SET = \(Self.backtickQuoted(encoding))")
                }
                if let collation = defaults.collation, !collation.isEmpty {
                    options.append("DEFAULT COLLATE = \(Self.backtickQuoted(collation))")
                }
            }

            _ = activeConnection.queryString("CREATE DATABASE \(Self.backtickQuoted(targetDatabase)) \(options.joined(separator: " "))",
                                             assertingDatabase: sourceDatabase)
            var success = !activeConnection.queryErrored()
            var error = success ? nil : activeConnection.lastErrorMessage()
            var didDisableForeignKeyChecks = false
            var didStoreSQLMode = false

            if success {
                _ = activeConnection.queryString("/*!32352 SET foreign_key_checks=0 */")
                success = success && !activeConnection.queryErrored()
                didDisableForeignKeyChecks = success
                if !success { error = activeConnection.lastErrorMessage() }
            }
            if success {
                _ = activeConnection.queryString("/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */")
                success = success && !activeConnection.queryErrored()
                didStoreSQLMode = success
                if !success { error = activeConnection.lastErrorMessage() }
            }

            if success {
                for table in tables {
                    guard let createStatement = self.lightweightCreateTableCopyStatement(table: table.name,
                                                                                        sourceDatabase: sourceDatabase,
                                                                                        targetDatabase: targetDatabase,
                                                                                        connection: activeConnection) else {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }

                    _ = activeConnection.queryString(createStatement, assertingDatabase: sourceDatabase)
                    if activeConnection.queryErrored() {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }

                    if copyContent {
                        _ = activeConnection.queryString("INSERT INTO \(Self.backtickQuoted(targetDatabase)).\(Self.backtickQuoted(table.name)) SELECT * FROM \(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(table.name))",
                                                         assertingDatabase: sourceDatabase)
                        if activeConnection.queryErrored() {
                            success = false
                            error = activeConnection.lastErrorMessage()
                            break
                        }
                    }
                }
            }

            if success {
                for routine in routines {
                    guard let createStatement = self.lightweightCreateDatabaseObjectCopyStatement(object: routine,
                                                                                                 sourceDatabase: sourceDatabase,
                                                                                                 targetDatabase: targetDatabase,
                                                                                                 connection: activeConnection) else {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }

                    _ = activeConnection.queryString(createStatement, assertingDatabase: targetDatabase)
                    if activeConnection.queryErrored() {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }
                }
            }

            if success {
                for view in views {
                    guard let createStatement = self.lightweightCreateDatabaseObjectCopyStatement(object: view,
                                                                                                 sourceDatabase: sourceDatabase,
                                                                                                 targetDatabase: targetDatabase,
                                                                                                 connection: activeConnection) else {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }

                    _ = activeConnection.queryString(createStatement, assertingDatabase: targetDatabase)
                    if activeConnection.queryErrored() {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }
                }
            }

            if success {
                for trigger in triggers {
                    guard let createStatement = self.lightweightCreateDatabaseObjectCopyStatement(object: trigger,
                                                                                                 sourceDatabase: sourceDatabase,
                                                                                                 targetDatabase: targetDatabase,
                                                                                                 connection: activeConnection) else {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }

                    _ = activeConnection.queryString(createStatement, assertingDatabase: targetDatabase)
                    if activeConnection.queryErrored() {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }
                }
            }

            if success {
                for event in events {
                    guard let createStatement = self.lightweightCreateDatabaseObjectCopyStatement(object: event,
                                                                                                sourceDatabase: sourceDatabase,
                                                                                                targetDatabase: targetDatabase,
                                                                                                connection: activeConnection) else {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }

                    _ = activeConnection.queryString(createStatement, assertingDatabase: targetDatabase)
                    if activeConnection.queryErrored() {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }
                }
            }

            if didDisableForeignKeyChecks {
                _ = activeConnection.queryString("/*!32352 SET foreign_key_checks=1 */")
                if activeConnection.queryErrored(), error == nil {
                    success = false
                    error = activeConnection.lastErrorMessage()
                }
            }
            if didStoreSQLMode {
                _ = activeConnection.queryString("/*!40101 SET SQL_MODE=@OLD_SQL_MODE */")
                if activeConnection.queryErrored(), error == nil {
                    success = false
                    error = activeConnection.lastErrorMessage()
                }
            }

            DispatchQueue.main.async {
                self.finishLightweightMutation(mutationSnapshot, restoringDetail: !success)
                if success {
                    self.lightweightStructureController.clearCachedTables()
                    self.lightweightContentController.clearCachedTables()
                    completion(true)
                    return
                }

                self.showLightweightError(title: NSLocalizedString("Unable to copy database", comment: "unable to copy database message"),
                                          message: error?.isEmpty == false ? error! : String(format: NSLocalizedString("An error occurred while trying to copy the database '%@' to '%@'.", comment: "unable to copy database message informative message"), sourceDatabase, targetDatabase))
                completion(false)
            }
        }
    }

    func lightweightCreateTableCopyStatement(table: String,
                                             sourceDatabase: String,
                                             targetDatabase: String,
                                             connection: SPMySQLConnection,
                                             targetTable: String? = nil,
                                             stripForeignKeyConstraintNames: Bool = false,
                                             stripAutoIncrement: Bool = false) -> String? {
        guard let result = connection.queryString("SHOW CREATE TABLE \(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(table))",
                                                  assertingDatabase: sourceDatabase) else {
            return nil
        }

        result.returnDataAsStrings = true
        guard let row = result.getRowAsArray(), row.count > 1 else { return nil }
        var createStatement = Self.displayString(for: row[1])
        let unqualifiedTable = Self.backtickQuoted(table)
        let qualifiedTable = "\(Self.backtickQuoted(targetDatabase)).\(Self.backtickQuoted(targetTable ?? table))"
        for prefix in ["CREATE TABLE ", "CREATE TEMPORARY TABLE "] {
            let needle = "\(prefix)\(unqualifiedTable)"
            if let range = createStatement.range(of: needle, options: [.caseInsensitive]) {
                createStatement.replaceSubrange(range, with: "\(prefix)\(qualifiedTable)")
                if stripForeignKeyConstraintNames {
                    createStatement = createStatement.replacingOccurrences(of: #"CONSTRAINT\s+`(?:``|[^`])+`\s+"#,
                                                                           with: "",
                                                                           options: .regularExpression)
                }
                if stripAutoIncrement {
                    createStatement = createStatement.replacingOccurrences(of: #"\sAUTO_INCREMENT=\d+"#,
                                                                           with: "",
                                                                           options: .regularExpression)
                }
                return createStatement
            }
        }

        return nil
    }

    private func loadLightweightDatabaseCopyObjects(for database: String, connection: SPMySQLConnection) -> [SALightweightDatabaseCopyObject] {
        var objects: [SALightweightDatabaseCopyObject] = []

        if let result = connection.queryString("SHOW FULL TABLES FROM \(Self.backtickQuoted(database))", assertingDatabase: database) {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = row.first { key, _ in
                    let keyString = String(describing: key).lowercased()
                    return keyString != "table_type"
                }.map { stringValue($0.value) } ?? ""
                let tableType = row.first { key, _ in
                    String(describing: key).lowercased() == "table_type"
                }.map { stringValue($0.value).uppercased() } ?? ""

                guard !name.isEmpty else { continue }
                objects.append(SALightweightDatabaseCopyObject(name: name, type: tableType == "VIEW" ? .view : .table))
            }
        }

        if connection.queryErrored() {
            return objects
        }

        if let quotedDatabase = connection.escapeAndQuoteString(database),
           let result = connection.queryString("SELECT ROUTINE_NAME, ROUTINE_TYPE FROM information_schema.routines WHERE routine_schema = \(quotedDatabase) ORDER BY routine_type, routine_name",
                                               assertingDatabase: database) {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = stringValue(row["ROUTINE_NAME"] ?? row["routine_name"])
                let routineType = stringValue(row["ROUTINE_TYPE"] ?? row["routine_type"]).uppercased()
                guard !name.isEmpty else { continue }
                objects.append(SALightweightDatabaseCopyObject(name: name, type: routineType == "PROCEDURE" ? .procedure : .function))
            }
        }

        if connection.queryErrored() {
            return objects
        }

        if let quotedDatabase = connection.escapeAndQuoteString(database),
           let result = connection.queryString("SELECT TRIGGER_NAME FROM information_schema.triggers WHERE trigger_schema = \(quotedDatabase) ORDER BY event_object_table, action_timing, event_manipulation, trigger_name",
                                               assertingDatabase: database) {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = stringValue(row["TRIGGER_NAME"] ?? row["trigger_name"])
                guard !name.isEmpty else { continue }
                objects.append(SALightweightDatabaseCopyObject(name: name, type: .trigger))
            }
        }

        if connection.queryErrored() {
            return objects
        }

        if let quotedDatabase = connection.escapeAndQuoteString(database),
           let result = connection.queryString("SELECT EVENT_NAME FROM information_schema.events WHERE event_schema = \(quotedDatabase) ORDER BY event_name",
                                               assertingDatabase: database) {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = stringValue(row["EVENT_NAME"] ?? row["event_name"])
                guard !name.isEmpty else { continue }
                objects.append(SALightweightDatabaseCopyObject(name: name, type: .event))
            }
        }

        return objects
    }

    private func lightweightCreateDatabaseObjectCopyStatement(object: SALightweightDatabaseCopyObject,
                                                              sourceDatabase: String,
                                                              targetDatabase: String,
                                                              connection: SPMySQLConnection) -> String? {
        let keyword: String
        switch object.type {
        case .view:
            keyword = "VIEW"
        case .procedure:
            keyword = "PROCEDURE"
        case .function:
            keyword = "FUNCTION"
        case .trigger:
            keyword = "TRIGGER"
        case .event:
            keyword = "EVENT"
        case .table:
            return lightweightCreateTableCopyStatement(table: object.name,
                                                       sourceDatabase: sourceDatabase,
                                                       targetDatabase: targetDatabase,
                                                       connection: connection)
        }

        guard let createStatement = lightweightShowCreateStatement(keyword: keyword,
                                                                   object: object.name,
                                                                   database: sourceDatabase,
                                                                   connection: connection) else {
            return nil
        }

        return lightweightRetargetCreateStatement(createStatement,
                                                  keyword: keyword,
                                                  sourceName: object.name,
                                                  targetName: object.name,
                                                  sourceDatabase: sourceDatabase,
                                                  targetDatabase: targetDatabase)
    }

    private func lightweightShowCreateStatement(keyword: String, object: String, database: String, connection: SPMySQLConnection) -> String? {
        guard let result = connection.queryString("SHOW CREATE \(keyword) \(Self.backtickQuoted(database)).\(Self.backtickQuoted(object))",
                                                  assertingDatabase: database) else {
            return nil
        }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        if let row = result.getRowAsDictionary() as? [String: Any],
           let statement = lightweightCreateStatement(from: row, keyword: keyword) {
            return statement
        }

        return nil
    }

    private func lightweightCreateStatement(from row: [String: Any], keyword: String) -> String? {
        let preferredKeys: [String]
        switch keyword {
        case "VIEW":
            preferredKeys = ["Create View"]
        case "PROCEDURE":
            preferredKeys = ["Create Procedure"]
        case "FUNCTION":
            preferredKeys = ["Create Function"]
        case "TRIGGER":
            preferredKeys = ["SQL Original Statement", "Create Trigger"]
        case "EVENT":
            preferredKeys = ["Create Event"]
        default:
            preferredKeys = ["Create Table"]
        }

        for key in preferredKeys {
            let statement = Self.displayString(for: row[key])
            if !statement.isEmpty {
                return statement
            }
        }

        for (_, value) in row {
            let statement = Self.displayString(for: value)
            if statement.range(of: "CREATE ", options: [.caseInsensitive, .anchored]) != nil {
                return statement
            }
        }

        return nil
    }

    private func lightweightRetargetCreateStatement(_ createStatement: String,
                                                    keyword: String,
                                                    sourceName: String,
                                                    targetName: String,
                                                    sourceDatabase: String,
                                                    targetDatabase: String) -> String? {
        var statement = createStatement
        let unqualifiedSource = "\(keyword) \(Self.backtickQuoted(sourceName))"
        let qualifiedSource = "\(keyword) \(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(sourceName))"
        let qualifiedTarget = "\(keyword) \(Self.backtickQuoted(targetDatabase)).\(Self.backtickQuoted(targetName))"

        if let range = statement.range(of: qualifiedSource, options: [.caseInsensitive]) {
            statement.replaceSubrange(range, with: qualifiedTarget)
        } else if let range = statement.range(of: unqualifiedSource, options: [.caseInsensitive]) {
            statement.replaceSubrange(range, with: qualifiedTarget)
        } else {
            return nil
        }

        statement = statement.replacingOccurrences(of: Self.backtickQuoted(sourceDatabase),
                                                   with: Self.backtickQuoted(targetDatabase))
        return statement
    }

    func runLightweightDatabaseAlterMutation(database: String,
                                             encoding: String,
                                             collation: String?,
                                             completion: @escaping (Bool) -> Void) {
        var statement = "ALTER DATABASE \(Self.backtickQuoted(database)) DEFAULT CHARACTER SET \(Self.backtickQuoted(encoding))"
        if let collation = collation, !collation.isEmpty {
            statement += " DEFAULT COLLATE \(Self.backtickQuoted(collation))"
        }

        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Altering %@...", comment: "Altering database task string"), database),
                                       statement: statement,
                                       assertingDatabase: database) { success in
            guard success else {
                completion(false)
                return
            }

            completion(true)
        }
    }

    func duplicateLightweightObject(_ sourceName: String,
                                    to targetName: String,
                                    type: SALightweightTableObjectType,
                                    sourceDatabase: String,
                                    targetDatabase: String,
                                    copyContent: Bool) {
        let status = String(format: NSLocalizedString("Duplicating %@...", comment: "Duplicating table task string"), sourceName)
        guard let activeConnection = activeConnection,
              let mutationSnapshot = beginLightweightMutation(status: status) else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, activeConnection] in
            guard let self = self else { return }

            var statements: [(statement: String, assertingDatabase: String)] = []
            if type == .view {
                if let createView = self.lightweightShowCreateStatement(keyword: "VIEW",
                                                                        object: sourceName,
                                                                        database: sourceDatabase,
                                                                        connection: activeConnection),
                   let statement = self.lightweightRetargetCreateStatement(createView,
                                                                           keyword: "VIEW",
                                                                           sourceName: sourceName,
                                                                           targetName: targetName,
                                                                           sourceDatabase: sourceDatabase,
                                                                           targetDatabase: targetDatabase) {
                    statements = [(statement, targetDatabase)]
                }
            } else {
                if let createTable = self.lightweightCreateTableCopyStatement(table: sourceName,
                                                                              sourceDatabase: sourceDatabase,
                                                                              targetDatabase: targetDatabase,
                                                                              connection: activeConnection,
                                                                              targetTable: targetName,
                                                                              stripForeignKeyConstraintNames: true,
                                                                              stripAutoIncrement: !copyContent) {
                    statements = [(createTable, sourceDatabase)]
                    if copyContent {
                        statements.append(("INSERT INTO \(Self.backtickQuoted(targetDatabase)).\(Self.backtickQuoted(targetName)) SELECT * FROM \(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(sourceName))",
                                           sourceDatabase))
                    }
                }
            }

            if statements.isEmpty {
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: NSLocalizedString("The object could not be duplicated.", comment: "lightweight duplicate failed message"))
                }
                return
            }

            var mutationFailed = false
            var error: String?
            var contentCopyWarning: String?
            for (index, operation) in statements.enumerated() {
                _ = activeConnection.queryString(operation.statement,
                                                 assertingDatabase: operation.assertingDatabase)
                guard activeConnection.queryErrored() else { continue }

                let queryError = activeConnection.lastErrorMessage()
                let isContentCopyFailure = type == .table && copyContent && index == statements.count - 1 && statements.count > 1
                if isContentCopyFailure {
                    contentCopyWarning = queryError
                } else {
                    mutationFailed = true
                    error = queryError
                }
                break
            }

            DispatchQueue.main.async {
                if mutationFailed {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: error?.isEmpty == false
                                                ? error!
                                                : NSLocalizedString("The object could not be duplicated.", comment: "lightweight duplicate failed message"))
                    return
                }

                self.finishLightweightMutation(mutationSnapshot, restoringDetail: contentCopyWarning != nil)
                if contentCopyWarning != nil {
                    self.showLightweightError(title: NSLocalizedString("Warning", comment: "warning"),
                                              message: NSLocalizedString("There have been errors while copying table content. Please check the new table.", comment: "message of panel when copying table content fails"))
                }
                self.lightweightStructureController.clearCachedTables()
                self.lightweightContentController.clearCachedTables()
                self.refreshLightweightObjectsAfterMutation(database: targetDatabase,
                                                            restoringTable: targetName,
                                                            restoringViewMode: mutationSnapshot.viewMode,
                                                            recordsHistory: true)
            }
        }
    }

    func duplicateLightweightRoutine(_ sourceName: String, to targetName: String, type: SALightweightTableObjectType, database: String, dropSource: Bool) {
        let status = String(format: NSLocalizedString("Duplicating %@...", comment: "Duplicating table task string"), sourceName)
        guard let activeConnection = activeConnection,
              let mutationSnapshot = beginLightweightMutation(status: status) else { return }

        let keyword = type == .procedure ? "PROCEDURE" : "FUNCTION"
        DispatchQueue.global(qos: .userInitiated).async { [weak self, activeConnection] in
            guard let self = self else { return }

            guard let result = activeConnection.queryString("SHOW CREATE \(keyword) \(Self.backtickQuoted(database)).\(Self.backtickQuoted(sourceName))",
                                                            assertingDatabase: database) else {
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: activeConnection.lastErrorMessage() ?? "")
                }
                return
            }

            result.returnDataAsStrings = true
            guard let row = result.getRowAsArray(), row.count > 2, let createSyntax = row[2] as? String else {
                DispatchQueue.main.async {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: NSLocalizedString("Couldn't get create syntax.", comment: "message of panel when table information cannot be retrieved"))
                }
                return
            }

            let escapedSource = NSRegularExpression.escapedPattern(for: Self.backtickQuoted(sourceName))
            let pattern = "(?<=\(keyword) )\(escapedSource)"
            let renamedSyntax = createSyntax.replacingOccurrences(of: pattern,
                                                                  with: Self.backtickQuoted(targetName),
                                                                  options: .regularExpression)
            _ = activeConnection.queryString(renamedSyntax, assertingDatabase: database)
            let createdTarget = !activeConnection.queryErrored()
            if createdTarget, dropSource {
                _ = activeConnection.queryString("DROP \(keyword) \(Self.backtickQuoted(database)).\(Self.backtickQuoted(sourceName))",
                                                 assertingDatabase: database)
            }

            let mutationFailed = activeConnection.queryErrored()
            let error = mutationFailed ? activeConnection.lastErrorMessage() : nil
            DispatchQueue.main.async {
                if mutationFailed {
                    self.finishLightweightMutation(mutationSnapshot, restoringDetail: true)
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: error?.isEmpty == false
                                                ? error!
                                                : NSLocalizedString("The object could not be duplicated.", comment: "lightweight duplicate failed message"))
                    if createdTarget {
                        self.refreshLightweightObjectsAfterMutation(database: database,
                                                                    restoringTable: sourceName,
                                                                    restoringViewMode: mutationSnapshot.viewMode)
                    }
                    return
                }

                self.finishLightweightMutation(mutationSnapshot, restoringDetail: false)
                self.lightweightStructureController.clearCachedTables()
                self.lightweightContentController.clearCachedTables()
                if dropSource {
                    self.handleLightweightPinnedTableRename(from: sourceName, to: targetName)
                    self.renameLightweightHistory(from: sourceName, to: targetName)
                }
                self.refreshLightweightObjectsAfterMutation(database: database,
                                                            restoringTable: targetName,
                                                            restoringViewMode: mutationSnapshot.viewMode,
                                                            recordsHistory: !dropSource)
            }
        }
    }

}
