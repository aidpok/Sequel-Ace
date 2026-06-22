//
//  SALightweightMetadataViewController.swift
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
//

import AppKit

struct SALightweightMetadataColumn {
    let identifier: String
    let title: String
    let width: CGFloat
    let minWidth: CGFloat
}

struct SALightweightMetadataSnapshot {
    let rows: [[String: String]]
    let emptyMessage: String
}

private final class SALightweightMetadataTableView: SPCopyTable {
    override func menu(for event: NSEvent) -> NSMenu? {
        SALightweightResultGrid.selectContextRow(in: self, event: event)
        return super.menu(for: event)
    }
}

final class SALightweightMetadataTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var loadToken = UUID()
    private let columns: [SALightweightMetadataColumn]
    private let loadingMessage: String
    private var rows: [[String: String]] = []
    private var isLoading = false
    private var didRegisterPreferenceObservers = false

    var selectionDidChange: (() -> Void)?
    var doubleClickAction: ((Int) -> Void)?
    var selectedRows: [[String: String]] {
        return tableView.selectedRowIndexes.compactMap { row in
            guard row >= 0, row < rows.count else { return nil }
            return rows[row]
        }
    }

    func row(at index: Int) -> [String: String]? {
        guard index >= 0, index < rows.count else { return nil }
        return rows[index]
    }

    func setContextMenu(_ menu: NSMenu?) {
        tableView.menu = menu
    }

    private lazy var placeholderView: SALightweightPlaceholderView = {
        let view = SALightweightPlaceholderView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        return view
    }()

    private lazy var tableView: NSTableView = {
        let tableView = SALightweightMetadataTableView(frame: .zero)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = true
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.backgroundColor = .controlBackgroundColor
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = Self.tableRowHeight(for: UserDefaults.getFont())
        tableView.target = self
        tableView.doubleAction = #selector(doubleClickTable(_:))
        if #available(macOS 11.0, *) {
            tableView.style = .plain
        }

        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.identifier))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column.minWidth
            tableColumn.resizingMask = .autoresizingMask

            let cell = SPTableTextFieldCell(textCell: "")
            cell.lineBreakMode = .byTruncatingTail
            cell.isEditable = false
            cell.isSelectable = true
            cell.font = UserDefaults.getFont()
            tableColumn.dataCell = cell
            tableView.addTableColumn(tableColumn)
        }

        return tableView
    }()

    init(columns: [SALightweightMetadataColumn], loadingMessage: String) {
        self.columns = columns
        self.loadingMessage = loadingMessage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let scrollView = NSScrollView(frame: view.bounds)
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = tableView
        view.addSubview(scrollView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        registerPreferenceObserversIfNeeded()
        applyTablePreferences()
    }

    deinit {
        if didRegisterPreferenceObservers {
            UserDefaults.standard.removeObserver(self, forKeyPath: SPDisplayTableViewVerticalGridlines)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPGlobalFontSettings)
        }
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == SPDisplayTableViewVerticalGridlines {
            tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
            tableView.setNeedsDisplay(tableView.visibleRect)
            return
        }

        if keyPath == SPGlobalFontSettings {
            applyTablePreferences()
            return
        }

        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }

    func showPlaceholder(_ message: String) {
        loadToken = UUID()
        isLoading = false
        rows = []
        tableView.reloadData()
        tableView.enclosingScrollView?.isHidden = true
        selectionDidChange?()

        placeholderView.message = message
        placeholderView.frame = view.bounds
        if placeholderView.superview == nil {
            view.addSubview(placeholderView)
        }
    }

    func load(_ loader: @escaping () -> SALightweightMetadataSnapshot) {
        loadToken = UUID()
        let token = loadToken
        isLoading = true

        placeholderView.removeFromSuperviewWithoutNeedingDisplay()
        tableView.enclosingScrollView?.isHidden = false
        rows = []
        tableView.reloadData()
        selectionDidChange?()
        showLoadingMessage()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = loader()

            DispatchQueue.main.async {
                guard let self = self, self.loadToken == token else { return }
                self.isLoading = false
                self.rows = snapshot.rows
                self.tableView.reloadData()
                self.selectionDidChange?()

                if snapshot.rows.isEmpty {
                    self.showPlaceholder(snapshot.emptyMessage)
                } else {
                    self.placeholderView.removeFromSuperviewWithoutNeedingDisplay()
                }
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard
            row >= 0,
            row < rows.count,
            let identifier = tableColumn?.identifier.rawValue else { return nil }

        return rows[row][identifier] ?? ""
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard let cell = cell as? SPTableTextFieldCell else { return }

        cell.font = UserDefaults.getFont()
        cell.setIndentationLevel(0)
        cell.setNote("")
        cell.image = nil
    }

    func canRemoveSelection() -> Bool {
        return !isLoading && !selectedRows.isEmpty
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectionDidChange?()
    }

    @objc private func doubleClickTable(_ sender: NSTableView) {
        doubleClickAction?(sender.clickedRow)
    }

    private func showLoadingMessage() {
        placeholderView.message = loadingMessage
        placeholderView.frame = view.bounds
        if placeholderView.superview == nil {
            view.addSubview(placeholderView)
        }
    }

    private func registerPreferenceObserversIfNeeded() {
        guard !didRegisterPreferenceObservers else { return }

        UserDefaults.standard.addObserver(self, forKeyPath: SPDisplayTableViewVerticalGridlines, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: SPGlobalFontSettings, options: .new, context: nil)
        didRegisterPreferenceObservers = true
    }

    private func applyTablePreferences() {
        let tableFont = UserDefaults.getFont()
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = Self.tableRowHeight(for: tableFont)

        for column in tableView.tableColumns {
            (column.dataCell as? NSCell)?.font = tableFont
            column.headerCell.font = Self.headerFont(for: tableFont)
        }

        tableView.headerView?.needsDisplay = true
        tableView.reloadData()
    }

    private static func tableRowHeight(for font: NSFont) -> CGFloat {
        return 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: font]).height
    }

    private static func headerFont(for font: NSFont) -> NSFont {
        return NSFontManager.shared.convert(font, toSize: max(font.pointSize * 0.75, 11.0))
    }
}

final class SALightweightRelationsViewController: NSViewController, NSMenuItemValidation {
    private weak var connection: SPMySQLConnection?
    private var database = ""
    private var table = ""
    private var relationsSupported = false
    private var relationSheetController: SALightweightRelationSheetController?

    private let tableController = SALightweightMetadataTableViewController(columns: [
        SALightweightMetadataColumn(identifier: "name", title: NSLocalizedString("Name", comment: "relations name column"), width: 120.5, minWidth: 8),
        SALightweightMetadataColumn(identifier: "columns", title: NSLocalizedString("Columns", comment: "relations columns column"), width: 83.5, minWidth: 10),
        SALightweightMetadataColumn(identifier: "fk_database", title: NSLocalizedString("FK Database", comment: "relations foreign key database column"), width: 81, minWidth: 10),
        SALightweightMetadataColumn(identifier: "fk_table", title: NSLocalizedString("FK Table", comment: "relations foreign key table column"), width: 90, minWidth: 10),
        SALightweightMetadataColumn(identifier: "fk_columns", title: NSLocalizedString("FK Columns", comment: "relations foreign key columns column"), width: 125, minWidth: 10),
        SALightweightMetadataColumn(identifier: "on_update", title: NSLocalizedString("On Update", comment: "relations update rule column"), width: 71, minWidth: 10),
        SALightweightMetadataColumn(identifier: "on_delete", title: NSLocalizedString("On Delete", comment: "relations delete rule column"), width: 65, minWidth: 10)
    ], loadingMessage: NSLocalizedString("Loading relations...", comment: "relations loading placeholder"))

    private lazy var titleLabel = NSTextField(labelWithString: "")
    private lazy var addButton = toolbarButton(imageName: "NSAddTemplate", toolTip: NSLocalizedString("Add table relation (⌥⌘A)", comment: "add relation tooltip"), keyEquivalent: "a", modifierMask: [.command, .option], action: #selector(addRelation(_:)))
    private lazy var removeButton = toolbarButton(imageName: "NSRemoveTemplate", toolTip: NSLocalizedString("Delete selected relation(s) (⌫)", comment: "remove relation tooltip"), keyEquivalent: "\u{7F}", action: #selector(removeRelation(_:)))
    private lazy var refreshButton = toolbarButton(imageName: "NSRefreshTemplate", toolTip: NSLocalizedString("Refresh table relations (⌘R)", comment: "refresh relations tooltip"), keyEquivalent: "r", modifierMask: .command, action: #selector(refreshRelations(_:)))

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view = rootView

        titleLabel.frame = NSRect(x: 14, y: rootView.bounds.height - 29, width: rootView.bounds.width - 28, height: 16)
        titleLabel.autoresizingMask = [.width, .minYMargin]
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        rootView.addSubview(titleLabel)

        addChild(tableController)
        let tableView = tableController.view
        tableView.frame = NSRect(x: 6, y: 35, width: rootView.bounds.width - 12, height: rootView.bounds.height - 70)
        tableView.autoresizingMask = [.width, .height]
        rootView.addSubview(tableView)

        addButton.frame = NSRect(x: 10, y: 10, width: 25, height: 25)
        removeButton.frame = NSRect(x: 40, y: 10, width: 25, height: 25)
        refreshButton.frame = NSRect(x: 70, y: 10, width: 25, height: 25)
        rootView.addSubview(addButton)
        rootView.addSubview(removeButton)
        rootView.addSubview(refreshButton)

        tableController.selectionDidChange = { [weak self] in
            self?.updateButtonState()
        }
        tableController.doubleClickAction = { [weak self] row in
            if row < 0 {
                self?.addRelation(row)
            }
        }
        configureContextMenu()
        updateButtonState()
    }

    func showPlaceholder(_ message: String) {
        connection = nil
        database = ""
        table = ""
        relationsSupported = false
        titleLabel.stringValue = ""
        tableController.showPlaceholder(message)
        updateButtonState()
    }

    func loadRelations(for table: String, database: String, connection: SPMySQLConnection) {
        self.table = table
        self.database = database
        self.connection = connection
        titleLabel.stringValue = String(format: NSLocalizedString("Relations for table: %@", comment: "Relations tab subtitle showing table name"), table)

        switch SALightweightMetadataReadService.relationsSupportState(table: table, database: database, connection: connection) {
        case .supported:
            relationsSupported = true
        case .unsupported(let message), .unavailable(let message):
            relationsSupported = false
            tableController.showPlaceholder(message)
            updateButtonState()
            return
        }

        updateButtonState()
        tableController.load {
            SALightweightMetadataReadService.relations(for: table, database: database, connection: connection)
        }
    }

    @objc private func addRelation(_ sender: Any) {
        openRelationSheet()
    }

    @objc private func refreshRelations(_ sender: Any) {
        guard let connection = connection, !table.isEmpty, !database.isEmpty else { return }
        loadRelations(for: table, database: database, connection: connection)
    }

    func refreshActiveRelationsDetail() {
        refreshRelations(self)
    }

    @objc private func removeRelation(_ sender: Any) {
        let selectedRows = tableController.selectedRows
        guard !selectedRows.isEmpty, let connection = connection, !database.isEmpty, !table.isEmpty else { return }

        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = NSLocalizedString("Delete relation", comment: "delete relation message")
        alert.informativeText = NSLocalizedString("Are you sure you want to delete the selected relations? This action cannot be undone.", comment: "delete selected relation informative message")
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        alert.alertStyle = .warning
        guard alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn else { return }

        for row in selectedRows {
            guard let constraint = row["name"], !constraint.isEmpty else { continue }
            let query = "ALTER TABLE \(SALightweightSchemaMetadataLoader.sqlIdentifier(database)).\(SALightweightSchemaMetadataLoader.sqlIdentifier(table)) DROP FOREIGN KEY \(SALightweightSchemaMetadataLoader.sqlIdentifier(constraint))"
            connection.queryString(query)

            if connection.queryErrored() {
                showError(title: NSLocalizedString("Unable to delete relation", comment: "error deleting relation message"),
                          message: String(format: NSLocalizedString("The selected relation couldn't be deleted.\n\nMySQL said: %@", comment: "error deleting relation informative message"), connection.lastErrorMessage() ?? ""))
                break
            }
        }

        refreshRelations(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(removeRelation(_:)) else { return true }
        return relationsSupported && tableController.canRemoveSelection()
    }

    private func updateButtonState() {
        let hasTable = connection != nil && !table.isEmpty && !database.isEmpty
        let canEditRelations = hasTable && relationsSupported
        addButton.isEnabled = canEditRelations
        refreshButton.isEnabled = hasTable
        removeButton.isEnabled = canEditRelations && tableController.canRemoveSelection()
    }

    private func configureContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = true

        let deleteItem = NSMenuItem(title: NSLocalizedString("Delete Relation", comment: "relations context delete relation menu item"),
                                    action: #selector(removeRelation(_:)),
                                    keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        tableController.setContextMenu(menu)
    }

    private func openRelationSheet() {
        guard let connection = connection, !database.isEmpty, !table.isEmpty, relationsSupported else { return }

        let sheetController = SALightweightRelationSheetController(table: table, database: database, connection: connection)
        sheetController.onConfirm = { [weak self] relation in
            guard let self = self, let connection = self.connection else { return .failure }
            return self.saveRelation(relation, connection: connection)
        }

        relationSheetController = sheetController
        guard let parentWindow = view.window, let sheet = sheetController.window else {
            sheetController.window?.makeKeyAndOrderFront(self)
            return
        }
        sheet.isRestorable = false
        sheet.animationBehavior = .none

        parentWindow.beginSheet(sheet) { [weak self] _ in
            sheet.orderOut(nil)
            self?.relationSheetController = nil
        }
    }

    private func saveRelation(_ relation: SALightweightRelationValue, connection: SPMySQLConnection) -> SALightweightRelationSaveResult {
        guard referenceColumnAllowsForeignKeyReference(relation, connection: connection) else {
            showInvalidForeignKeyReferenceAlert(column: relation.referenceColumn, table: relation.referenceTable)
            return .failure
        }

        var query = "ALTER TABLE \(SALightweightSchemaMetadataLoader.sqlIdentifier(database)).\(SALightweightSchemaMetadataLoader.sqlIdentifier(table)) ADD "
        if !relation.constraintName.isEmpty {
            query += "CONSTRAINT \(SALightweightSchemaMetadataLoader.sqlIdentifier(relation.constraintName)) "
        }

        query += "FOREIGN KEY (\(SALightweightSchemaMetadataLoader.sqlIdentifier(relation.column))) REFERENCES \(SALightweightSchemaMetadataLoader.sqlIdentifier(relation.referenceDatabase)).\(SALightweightSchemaMetadataLoader.sqlIdentifier(relation.referenceTable)) (\(SALightweightSchemaMetadataLoader.sqlIdentifier(relation.referenceColumn)))"

        if let onDelete = relation.onDelete {
            query += " ON DELETE \(onDelete)"
        }

        if let onUpdate = relation.onUpdate {
            query += " ON UPDATE \(onUpdate)"
        }

        connection.queryString(query)

        if connection.queryErrored() {
            let errorText = connection.lastErrorMessage() ?? ""
            showError(title: NSLocalizedString("Error creating relation", comment: "error creating relation message"),
                      message: String(format: NSLocalizedString("The specified relation could not be created.\n\nMySQL said: %@", comment: "error creating relation informative message"), errorText))

            if !relation.constraintName.isEmpty && errorText.contains("errno: 121") && errorText.contains("already exists") {
                return .duplicateName
            }

            return .failure
        }

        refreshRelations(self)
        return .success
    }

    private func referenceColumnAllowsForeignKeyReference(_ relation: SALightweightRelationValue, connection: SPMySQLConnection) -> Bool {
        guard SALightweightSchemaMetadataLoader.serverRequiresStandardForeignKeyReferences(connection: connection) else { return true }
        guard !relation.referenceColumn.isEmpty, !relation.referenceTable.isEmpty else { return false }

        return SALightweightSchemaMetadataLoader.singleColumnUniqueReferenceColumns(for: relation.referenceTable,
                                                                                   database: relation.referenceDatabase,
                                                                                   connection: connection)
            .contains(relation.referenceColumn)
    }

    private func toolbarButton(imageName: String, toolTip: String, keyEquivalent: String = "", modifierMask: NSEvent.ModifierFlags = [], action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(named: NSImage.Name(imageName)) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .smallSquare
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = modifierMask
        button.autoresizingMask = [.maxXMargin, .maxYMargin]
        return button
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModalCenteredInKeyWindow()
    }

    private func showInvalidForeignKeyReferenceAlert(column: String, table: String) {
        showError(title: NSLocalizedString("Referenced column needs a unique key", comment: "foreign key reference restriction title"),
                  message: String(format: NSLocalizedString("MySQL 8.4 and newer require a foreign key to reference a full unique or primary key. Add a single-column unique key to %@.%@ or choose another referenced column.", comment: "foreign key reference restriction message"), table, column))
    }
}

private struct SALightweightRelationColumn {
    let name: String
    let type: String
}

private struct SALightweightRelationValue {
    let constraintName: String
    let column: String
    let referenceDatabase: String
    let referenceTable: String
    let referenceColumn: String
    let onUpdate: String?
    let onDelete: String?
}

private enum SALightweightRelationSaveResult {
    case success
    case failure
    case duplicateName
}

private final class SALightweightRelationSheetController: NSWindowController, NSTextFieldDelegate {
    var onConfirm: ((SALightweightRelationValue) -> SALightweightRelationSaveResult)?

    private weak var connection: SPMySQLConnection?
    private let table: String
    private let database: String
    private var localColumns: [SALightweightRelationColumn] = []
    private var takenConstraintNames = Set<String>()
    private var requiresStandardReferenceColumns = false
    private var standardReferenceColumnCache: [String: Set<String>] = [:]

    private let constraintNameField = NSTextField(frame: NSRect(x: 118, y: 10, width: 165, height: 19))
    private let columnPopUpButton = NSPopUpButton(frame: NSRect(x: 115, y: 6, width: 171, height: 22), pullsDown: false)
    private let refDatabasePopUpButton = NSPopUpButton(frame: NSRect(x: 115, y: 66, width: 171, height: 22), pullsDown: false)
    private let refTablePopUpButton = NSPopUpButton(frame: NSRect(x: 115, y: 36, width: 171, height: 22), pullsDown: false)
    private let refColumnPopUpButton = NSPopUpButton(frame: NSRect(x: 115, y: 6, width: 171, height: 22), pullsDown: false)
    private let onUpdatePopUpButton = NSPopUpButton(frame: NSRect(x: 116, y: 36, width: 170, height: 22), pullsDown: false)
    private let onDeletePopUpButton = NSPopUpButton(frame: NSRect(x: 116, y: 6, width: 170, height: 22), pullsDown: false)
    private let confirmButton = NSButton(frame: NSRect(x: 268, y: 13, width: 96, height: 28))
    private let cancelButton = NSButton(frame: NSRect(x: 174, y: 13, width: 96, height: 28))

    init(table: String, database: String, connection: SPMySQLConnection) {
        self.table = table
        self.database = database
        self.connection = connection

        let panel = NSPanel(contentRect: NSRect(x: 196, y: 141, width: 379, height: 404),
                            styleMask: [.titled],
                            backing: .buffered,
                            defer: false)
        panel.title = NSLocalizedString("New Relation", comment: "new relation sheet title")
        panel.isReleasedWhenClosed = false

        super.init(window: panel)
        buildInterface()
        loadRelationData()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func controlTextDidChange(_ notification: Notification) {
        validate()
    }

    @objc private func selectTableColumn(_ sender: Any) {
        updateAvailableTableColumns()
    }

    @objc private func selectReferenceDatabase(_ sender: Any) {
        updateAvailableTables()
        updateAvailableTableColumns()
    }

    @objc private func selectReferenceTable(_ sender: Any) {
        updateAvailableTableColumns()
    }

    @objc private func closeRelationSheet(_ sender: Any) {
        guard let window = window else { return }

        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(self)
        }
    }

    @objc private func confirmAddRelation(_ sender: Any) {
        guard let relation = currentRelationValue() else { return }

        switch onConfirm?(relation) {
        case .success:
            closeRelationSheet(sender)
        case .duplicateName:
            markConstraintNameTaken(relation.constraintName)
        case .failure, .none:
            break
        }
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        addNameBox(to: contentView)
        addTableBox(to: contentView)
        addReferencesBox(to: contentView)
        addActionBox(to: contentView)

        confirmButton.title = NSLocalizedString("Add", comment: "add relation button")
        confirmButton.bezelStyle = .rounded
        confirmButton.controlSize = .small
        confirmButton.keyEquivalent = "\r"
        confirmButton.target = self
        confirmButton.action = #selector(confirmAddRelation(_:))
        contentView.addSubview(confirmButton)

        cancelButton.title = NSLocalizedString("Cancel", comment: "cancel button")
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.target = self
        cancelButton.action = #selector(closeRelationSheet(_:))
        contentView.addSubview(cancelButton)
    }

    private func addNameBox(to contentView: NSView) {
        let box = NSBox(frame: NSRect(x: 17, y: 326, width: 345, height: 58))
        box.title = NSLocalizedString("Name", comment: "relation name box title")
        box.borderType = .lineBorder
        contentView.addSubview(box)

        let content = box.contentView ?? box
        content.addSubview(label(title: NSLocalizedString("Name:", comment: "relation name label"), frame: NSRect(x: 15, y: 13, width: 98, height: 14)))
        constraintNameField.controlSize = .small
        constraintNameField.font = NSFont.messageFont(ofSize: 11)
        constraintNameField.placeholderString = NSLocalizedString("Generate one", comment: "generate constraint name placeholder")
        constraintNameField.delegate = self
        content.addSubview(constraintNameField)
    }

    private func addTableBox(to contentView: NSView) {
        let box = NSBox(frame: NSRect(x: 17, y: 266, width: 345, height: 56))
        box.title = String(format: NSLocalizedString("Table: %@", comment: "Add Relation sheet title, showing table name"), table)
        box.borderType = .lineBorder
        contentView.addSubview(box)

        let content = box.contentView ?? box
        content.addSubview(label(title: NSLocalizedString("Column:", comment: "relation column label"), frame: NSRect(x: 15, y: 11, width: 98, height: 14)))
        configurePopUp(columnPopUpButton, action: #selector(selectTableColumn(_:)))
        content.addSubview(columnPopUpButton)
    }

    private func addReferencesBox(to contentView: NSView) {
        let box = NSBox(frame: NSRect(x: 17, y: 145, width: 345, height: 117))
        box.title = NSLocalizedString("References", comment: "relation references box title")
        box.borderType = .lineBorder
        contentView.addSubview(box)

        let content = box.contentView ?? box
        content.addSubview(label(title: NSLocalizedString("Database:", comment: "reference database label"), frame: NSRect(x: 15, y: 71, width: 98, height: 14)))
        content.addSubview(label(title: NSLocalizedString("Table:", comment: "reference table label"), frame: NSRect(x: 15, y: 41, width: 98, height: 14)))
        content.addSubview(label(title: NSLocalizedString("Column:", comment: "reference column label"), frame: NSRect(x: 15, y: 11, width: 98, height: 14)))

        configurePopUp(refDatabasePopUpButton, action: #selector(selectReferenceDatabase(_:)))
        configurePopUp(refTablePopUpButton, action: #selector(selectReferenceTable(_:)))
        configurePopUp(refColumnPopUpButton, action: nil)
        content.addSubview(refDatabasePopUpButton)
        content.addSubview(refTablePopUpButton)
        content.addSubview(refColumnPopUpButton)
    }

    private func addActionBox(to contentView: NSView) {
        let box = NSBox(frame: NSRect(x: 17, y: 54, width: 345, height: 87))
        box.title = NSLocalizedString("Action", comment: "relation action box title")
        box.borderType = .lineBorder
        contentView.addSubview(box)

        let content = box.contentView ?? box
        content.addSubview(label(title: NSLocalizedString("On update:", comment: "relation on update label"), frame: NSRect(x: 15, y: 41, width: 99, height: 14)))
        content.addSubview(label(title: NSLocalizedString("On delete:", comment: "relation on delete label"), frame: NSRect(x: 15, y: 11, width: 98, height: 14)))

        configurePopUp(onUpdatePopUpButton, action: nil)
        configurePopUp(onDeletePopUpButton, action: nil)
        configureActionPopUp(onUpdatePopUpButton)
        configureActionPopUp(onDeletePopUpButton)
        content.addSubview(onUpdatePopUpButton)
        content.addSubview(onDeletePopUpButton)
    }

    private func loadRelationData() {
        guard let connection = connection else { return }

        localColumns = SALightweightSchemaMetadataLoader.columns(for: table, database: database, connection: connection)
        takenConstraintNames = SALightweightSchemaMetadataLoader.relationConstraintNames(for: table, database: database, connection: connection)
        requiresStandardReferenceColumns = SALightweightSchemaMetadataLoader.serverRequiresStandardForeignKeyReferences(connection: connection)
        standardReferenceColumnCache.removeAll()
        setPopUpItems(columnPopUpButton, items: localColumns.map { $0.name }, selecting: nil)
        setPopUpItems(refDatabasePopUpButton, items: SALightweightSchemaMetadataLoader.userDatabases(connection: connection), selecting: database)

        constraintNameField.stringValue = ""
        updateAvailableTables()
        updateAvailableTableColumns()
        validate()
    }

    private func updateAvailableTables() {
        guard let connection = connection, let selectedDatabase = refDatabasePopUpButton.titleOfSelectedItem else { return }

        setPopUpItems(refTablePopUpButton,
                      items: SALightweightSchemaMetadataLoader.innodbTables(database: selectedDatabase, connection: connection),
                      selecting: nil)
        validate()
    }

    private func updateAvailableTableColumns() {
        guard
            let connection = connection,
            let localColumn = localColumns.first(where: { $0.name == columnPopUpButton.titleOfSelectedItem }),
            let selectedDatabase = refDatabasePopUpButton.titleOfSelectedItem,
            let selectedTable = refTablePopUpButton.titleOfSelectedItem else {
            setPopUpItems(refColumnPopUpButton, items: [], selecting: nil)
            validate()
            return
        }

        var columns = SALightweightSchemaMetadataLoader.columns(for: selectedTable, database: selectedDatabase, connection: connection)
            .filter { $0.type == localColumn.type }

        if requiresStandardReferenceColumns {
            let standardReferenceColumns = singleColumnUniqueReferenceColumns(for: selectedTable,
                                                                             database: selectedDatabase,
                                                                             connection: connection)
            columns = columns.filter { standardReferenceColumns.contains($0.name) }
        }

        let columnNames = columns.map { $0.name }
        setPopUpItems(refColumnPopUpButton, items: columnNames, selecting: nil)
        validate()
    }

    private func singleColumnUniqueReferenceColumns(for table: String, database: String, connection: SPMySQLConnection) -> Set<String> {
        let cacheKey = "\(database)\u{0}\(table)"
        if let cachedColumns = standardReferenceColumnCache[cacheKey] {
            return cachedColumns
        }

        let columns = SALightweightSchemaMetadataLoader.singleColumnUniqueReferenceColumns(for: table,
                                                                                          database: database,
                                                                                          connection: connection)
        standardReferenceColumnCache[cacheKey] = columns
        return columns
    }

    private func validate() {
        let constraintName = constraintNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedConstraintName = constraintName.lowercased()
        let duplicateName = !lowercasedConstraintName.isEmpty
            && takenConstraintNames.contains(lowercasedConstraintName)

        constraintNameField.textColor = duplicateName ? .red : .controlTextColor
        confirmButton.isEnabled = !duplicateName
            && columnPopUpButton.titleOfSelectedItem?.isEmpty == false
            && refDatabasePopUpButton.titleOfSelectedItem?.isEmpty == false
            && refTablePopUpButton.titleOfSelectedItem?.isEmpty == false
            && refColumnPopUpButton.titleOfSelectedItem?.isEmpty == false
    }

    private func currentRelationValue() -> SALightweightRelationValue? {
        validate()

        guard
            confirmButton.isEnabled,
            let column = columnPopUpButton.titleOfSelectedItem,
            let referenceDatabase = refDatabasePopUpButton.titleOfSelectedItem,
            let referenceTable = refTablePopUpButton.titleOfSelectedItem,
            let referenceColumn = refColumnPopUpButton.titleOfSelectedItem else { return nil }

        return SALightweightRelationValue(constraintName: constraintNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                          column: column,
                                          referenceDatabase: referenceDatabase,
                                          referenceTable: referenceTable,
                                          referenceColumn: referenceColumn,
                                          onUpdate: selectedAction(onUpdatePopUpButton),
                                          onDelete: selectedAction(onDeletePopUpButton))
    }

    private func configurePopUp(_ popUpButton: NSPopUpButton, action: Selector?) {
        popUpButton.controlSize = .small
        popUpButton.font = NSFont.messageFont(ofSize: 11)
        popUpButton.target = self
        popUpButton.action = action
    }

    private func markConstraintNameTaken(_ constraintName: String) {
        takenConstraintNames.insert(constraintName.lowercased())
        validate()
    }

    private func configureActionPopUp(_ popUpButton: NSPopUpButton) {
        let actions = ["", "Restrict", "Cascade", "Set NULL", "No Action"]

        popUpButton.removeAllItems()
        popUpButton.addItems(withTitles: actions)
        for index in actions.indices {
            popUpButton.item(at: index)?.tag = index - 1
        }
    }

    private func selectedAction(_ popUpButton: NSPopUpButton) -> String? {
        let actions = ["RESTRICT", "CASCADE", "SET NULL", "NO ACTION"]
        let tag = popUpButton.selectedTag()
        guard tag >= 0, tag < actions.count else { return nil }
        return actions[tag]
    }

    private func setPopUpItems(_ popUpButton: NSPopUpButton, items: [String], selecting selectedItem: String?) {
        let sortedItems = UserDefaults.standard.bool(forKey: SPAlphabeticalTableSorting) ? items.sorted() : items

        popUpButton.removeAllItems()
        popUpButton.addItems(withTitles: sortedItems)
        if let selectedItem = selectedItem, sortedItems.contains(selectedItem) {
            popUpButton.selectItem(withTitle: selectedItem)
        } else if !sortedItems.isEmpty {
            popUpButton.selectItem(at: 0)
        }
        popUpButton.isEnabled = !sortedItems.isEmpty
    }

    private func label(title: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.alignment = .right
        label.controlSize = .small
        label.font = NSFont.messageFont(ofSize: 11)
        return label
    }
}

final class SALightweightTriggersViewController: NSViewController, NSMenuItemValidation {
    private weak var connection: SPMySQLConnection?
    private var database = ""
    private var table = ""
    private var triggerSheetController: SALightweightTriggerSheetController?

    private let tableController = SALightweightMetadataTableViewController(columns: [
        SALightweightMetadataColumn(identifier: "TriggerName", title: NSLocalizedString("Trigger", comment: "triggers trigger column"), width: 86.5, minWidth: 10),
        SALightweightMetadataColumn(identifier: "TriggerEvent", title: NSLocalizedString("Event", comment: "triggers event column"), width: 60, minWidth: 10),
        SALightweightMetadataColumn(identifier: "TriggerActionTime", title: NSLocalizedString("Timing", comment: "triggers timing column"), width: 59, minWidth: 10),
        SALightweightMetadataColumn(identifier: "TriggerStatement", title: NSLocalizedString("Statement", comment: "triggers statement column"), width: 224.2109375, minWidth: 10),
        SALightweightMetadataColumn(identifier: "TriggerDefiner", title: NSLocalizedString("Definer", comment: "triggers definer column"), width: 64, minWidth: 10),
        SALightweightMetadataColumn(identifier: "TriggerCreated", title: NSLocalizedString("Created", comment: "triggers created column"), width: 42, minWidth: 10),
        SALightweightMetadataColumn(identifier: "TriggerSQLMode", title: NSLocalizedString("SQL Mode", comment: "triggers sql mode column"), width: 100.5, minWidth: 10)
    ], loadingMessage: NSLocalizedString("Loading triggers...", comment: "triggers loading placeholder"))

    private lazy var titleLabel = NSTextField(labelWithString: "")
    private lazy var addButton = toolbarButton(imageName: "NSAddTemplate", toolTip: NSLocalizedString("Add table trigger (⌥⌘A)", comment: "add trigger tooltip"), keyEquivalent: "a", modifierMask: [.command, .option], action: #selector(addTrigger(_:)))
    private lazy var removeButton = toolbarButton(imageName: "NSRemoveTemplate", toolTip: NSLocalizedString("Delete selected trigger(s) (⌫)", comment: "remove trigger tooltip"), keyEquivalent: "\u{7F}", action: #selector(removeTrigger(_:)))
    private lazy var refreshButton = toolbarButton(imageName: "NSRefreshTemplate", toolTip: NSLocalizedString("Refresh table triggers (⌘R)", comment: "refresh triggers tooltip"), keyEquivalent: "r", modifierMask: .command, action: #selector(refreshTriggers(_:)))

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view = rootView

        titleLabel.frame = NSRect(x: 14, y: rootView.bounds.height - 29, width: rootView.bounds.width - 28, height: 16)
        titleLabel.autoresizingMask = [.width, .minYMargin]
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        rootView.addSubview(titleLabel)

        addChild(tableController)
        let tableView = tableController.view
        tableView.frame = NSRect(x: 6, y: 35, width: rootView.bounds.width - 12, height: rootView.bounds.height - 70)
        tableView.autoresizingMask = [.width, .height]
        rootView.addSubview(tableView)

        addButton.frame = NSRect(x: 10, y: 10, width: 25, height: 25)
        removeButton.frame = NSRect(x: 40, y: 10, width: 25, height: 25)
        refreshButton.frame = NSRect(x: 70, y: 10, width: 25, height: 25)
        rootView.addSubview(addButton)
        rootView.addSubview(removeButton)
        rootView.addSubview(refreshButton)

        tableController.selectionDidChange = { [weak self] in
            self?.updateButtonState()
        }
        tableController.doubleClickAction = { [weak self] row in
            if row >= 0 {
                self?.editTrigger(at: row)
            } else {
                self?.addTrigger(row)
            }
        }
        configureContextMenu()
        updateButtonState()
    }

    func showPlaceholder(_ message: String) {
        connection = nil
        database = ""
        table = ""
        titleLabel.stringValue = ""
        tableController.showPlaceholder(message)
        updateButtonState()
    }

    func loadTriggers(for table: String, database: String, connection: SPMySQLConnection) {
        self.table = table
        self.database = database
        self.connection = connection
        titleLabel.stringValue = String(format: NSLocalizedString("Triggers for table: %@", comment: "triggers for table label"), table)
        updateButtonState()
        tableController.load {
            SALightweightMetadataReadService.triggers(for: table, database: database, connection: connection)
        }
    }

    @objc private func addTrigger(_ sender: Any) {
        openTriggerSheet(editing: nil)
    }

    @objc private func refreshTriggers(_ sender: Any) {
        guard let connection = connection, !table.isEmpty, !database.isEmpty else { return }
        loadTriggers(for: table, database: database, connection: connection)
    }

    func refreshActiveTriggersDetail() {
        refreshTriggers(self)
    }

    @objc private func removeTrigger(_ sender: Any) {
        let selectedRows = tableController.selectedRows
        guard !selectedRows.isEmpty, let connection = connection, !database.isEmpty else { return }

        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = NSLocalizedString("Delete trigger", comment: "delete trigger message")
        alert.informativeText = NSLocalizedString("Are you sure you want to delete the selected triggers? This action cannot be undone.", comment: "delete selected trigger informative message")
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        alert.alertStyle = .warning
        guard alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn else { return }

        for row in selectedRows {
            guard let trigger = row["TriggerName"], !trigger.isEmpty else { continue }
            let query = "DROP TRIGGER \(SALightweightSchemaMetadataLoader.sqlIdentifier(database)).\(SALightweightSchemaMetadataLoader.sqlIdentifier(trigger))"
            connection.queryString(query)

            if connection.queryErrored() {
                showError(title: NSLocalizedString("Unable to delete trigger", comment: "error deleting trigger message"),
                          message: String(format: NSLocalizedString("The selected trigger couldn't be deleted.\n\nMySQL said: %@", comment: "error deleting trigger informative message"), connection.lastErrorMessage() ?? ""))
                break
            }
        }

        refreshTriggers(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(editSelectedTrigger(_:)):
            return tableController.selectedRows.count == 1
        case #selector(removeTrigger(_:)):
            return tableController.canRemoveSelection()
        default:
            return true
        }
    }

    private func updateButtonState() {
        let hasTable = connection != nil && !table.isEmpty && !database.isEmpty
        addButton.isEnabled = hasTable
        refreshButton.isEnabled = hasTable
        removeButton.isEnabled = hasTable && tableController.canRemoveSelection()
    }

    private func configureContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = true

        let editItem = NSMenuItem(title: NSLocalizedString("Edit Trigger", comment: "triggers context edit trigger menu item"),
                                  action: #selector(editSelectedTrigger(_:)),
                                  keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let deleteItem = NSMenuItem(title: NSLocalizedString("Delete Trigger", comment: "triggers context delete trigger menu item"),
                                    action: #selector(removeTrigger(_:)),
                                    keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        tableController.setContextMenu(menu)
    }

    @objc private func editSelectedTrigger(_ sender: Any) {
        guard let selectedRow = tableController.selectedRows.first,
              let triggerName = selectedRow["TriggerName"],
              !triggerName.isEmpty else { return }

        openTriggerSheet(editing: selectedRow)
    }

    private func editTrigger(at row: Int) {
        guard let trigger = tableController.row(at: row) else { return }
        openTriggerSheet(editing: trigger)
    }

    private func openTriggerSheet(editing trigger: [String: String]?) {
        guard connection != nil, !database.isEmpty, !table.isEmpty else { return }

        let sheetController = SALightweightTriggerSheetController(trigger: trigger)
        sheetController.onConfirm = { [weak self] value in
            guard let self = self, let connection = self.connection else { return false }
            return self.saveTrigger(value, replacing: trigger, connection: connection)
        }

        triggerSheetController = sheetController
        guard let parentWindow = view.window, let sheet = sheetController.window else {
            sheetController.window?.makeKeyAndOrderFront(self)
            return
        }
        sheet.isRestorable = false
        sheet.animationBehavior = .none

        parentWindow.beginSheet(sheet) { [weak self] _ in
            sheet.orderOut(nil)
            self?.triggerSheetController = nil
        }
    }

    private func saveTrigger(_ trigger: SALightweightTriggerValue, replacing originalTrigger: [String: String]?, connection: SPMySQLConnection) -> Bool {
        _ = connection.selectDatabase(database)

        if let originalName = originalTrigger?["TriggerName"], !originalName.isEmpty {
            connection.queryString(dropTriggerQuery(named: originalName))

            if connection.queryErrored() {
                showError(title: NSLocalizedString("Unable to delete trigger", comment: "error deleting trigger message"),
                          message: String(format: NSLocalizedString("The selected trigger couldn't be deleted.\n\nMySQL said: %@", comment: "error deleting trigger informative message"), connection.lastErrorMessage() ?? ""))
                return false
            }
        }

        connection.queryString(createTriggerQuery(trigger))

        if connection.queryErrored() {
            let createError = connection.lastErrorMessage() ?? ""

            if let originalTrigger = originalTrigger,
               let originalValue = SALightweightTriggerValue(row: originalTrigger) {
                connection.queryString(createTriggerQuery(originalValue))
            }

            showError(title: NSLocalizedString("Error creating trigger", comment: "error creating trigger message"),
                      message: String(format: NSLocalizedString("The specified trigger was unable to be created.\n\nMySQL said: %@", comment: "error creating trigger informative message"), createError))
            return false
        }

        refreshTriggers(self)
        return true
    }

    private func createTriggerQuery(_ trigger: SALightweightTriggerValue) -> String {
        return "CREATE TRIGGER \(SALightweightSchemaMetadataLoader.sqlIdentifier(trigger.name)) \(trigger.timing) \(trigger.event) ON \(SALightweightSchemaMetadataLoader.sqlIdentifier(table)) FOR EACH ROW \(trigger.statement)"
    }

    private func dropTriggerQuery(named triggerName: String) -> String {
        return "DROP TRIGGER \(SALightweightSchemaMetadataLoader.sqlIdentifier(database)).\(SALightweightSchemaMetadataLoader.sqlIdentifier(triggerName))"
    }

    private func toolbarButton(imageName: String, toolTip: String, keyEquivalent: String = "", modifierMask: NSEvent.ModifierFlags = [], action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(named: NSImage.Name(imageName)) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .smallSquare
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = modifierMask
        button.autoresizingMask = [.maxXMargin, .maxYMargin]
        return button
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModalCenteredInKeyWindow()
    }
}

private struct SALightweightTriggerValue {
    let name: String
    let timing: String
    let event: String
    let statement: String

    init(name: String, timing: String, event: String, statement: String) {
        self.name = name
        self.timing = timing
        self.event = event
        self.statement = statement
    }

    init?(row: [String: String]) {
        guard let name = row["TriggerName"], !name.isEmpty,
              let timing = row["TriggerActionTime"], !timing.isEmpty,
              let event = row["TriggerEvent"], !event.isEmpty,
              let statement = row["TriggerStatement"], !statement.isEmpty else { return nil }

        self.init(name: name, timing: timing.uppercased(), event: event.uppercased(), statement: statement)
    }
}

private final class SALightweightTriggerSheetController: NSWindowController, NSTextFieldDelegate, NSTextViewDelegate {
    var onConfirm: ((SALightweightTriggerValue) -> Bool)?

    private let originalTrigger: [String: String]?
    private let nameField = NSTextField(frame: NSRect(x: 92, y: 317, width: 222, height: 22))
    private let timingPopUpButton = NSPopUpButton(frame: NSRect(x: 386, y: 317, width: 98, height: 22), pullsDown: false)
    private let eventPopUpButton = NSPopUpButton(frame: NSRect(x: 386, y: 289, width: 98, height: 22), pullsDown: false)
    private let statementTextView = NSTextView(frame: .zero)
    private let statementScrollView = NSScrollView(frame: NSRect(x: 20, y: 58, width: 464, height: 218))
    private let confirmButton = NSButton(frame: NSRect(x: 388, y: 18, width: 96, height: 28))
    private let cancelButton = NSButton(frame: NSRect(x: 290, y: 18, width: 96, height: 28))

    init(trigger: [String: String]?) {
        originalTrigger = trigger

        let panel = NSPanel(contentRect: NSRect(x: 196, y: 141, width: 504, height: 358),
                            styleMask: [.titled],
                            backing: .buffered,
                            defer: false)
        panel.title = trigger == nil
            ? NSLocalizedString("New Trigger", comment: "new trigger sheet title")
            : NSLocalizedString("Edit Trigger", comment: "edit trigger sheet title")
        panel.isReleasedWhenClosed = false

        super.init(window: panel)
        buildInterface()
        populate(trigger)
        validate()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func controlTextDidChange(_ notification: Notification) {
        validate()
    }

    func textDidChange(_ notification: Notification) {
        validate()
    }

    @objc private func closeTriggerSheet(_ sender: Any) {
        guard let window = window else { return }

        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(self)
        }
    }

    @objc private func confirmTrigger(_ sender: Any) {
        guard let value = currentValue(), onConfirm?(value) == true else { return }
        closeTriggerSheet(sender)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        contentView.addSubview(label(title: NSLocalizedString("Name:", comment: "trigger name label"), frame: NSRect(x: 20, y: 321, width: 66, height: 14)))
        contentView.addSubview(label(title: NSLocalizedString("Timing:", comment: "trigger timing label"), frame: NSRect(x: 322, y: 321, width: 58, height: 14)))
        contentView.addSubview(label(title: NSLocalizedString("Event:", comment: "trigger event label"), frame: NSRect(x: 322, y: 293, width: 58, height: 14)))
        contentView.addSubview(label(title: NSLocalizedString("Statement:", comment: "trigger statement label"), frame: NSRect(x: 20, y: 293, width: 80, height: 14)))

        nameField.controlSize = .small
        nameField.font = NSFont.messageFont(ofSize: 11)
        nameField.delegate = self
        contentView.addSubview(nameField)

        configurePopUp(timingPopUpButton, items: ["BEFORE", "AFTER"])
        configurePopUp(eventPopUpButton, items: ["INSERT", "UPDATE", "DELETE"])
        contentView.addSubview(timingPopUpButton)
        contentView.addSubview(eventPopUpButton)

        statementScrollView.borderType = .bezelBorder
        statementScrollView.focusRingType = .none
        statementScrollView.hasVerticalScroller = true
        statementScrollView.hasHorizontalScroller = true
        statementScrollView.autohidesScrollers = true
        statementScrollView.documentView = statementTextView

        statementTextView.frame = NSRect(origin: .zero, size: statementScrollView.contentSize)
        statementTextView.minSize = NSSize(width: 0, height: statementScrollView.contentSize.height)
        statementTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        statementTextView.isVerticallyResizable = true
        statementTextView.isHorizontallyResizable = true
        statementTextView.autoresizingMask = [.width, .height]
        statementTextView.font = UserDefaults.getFont()
        statementTextView.delegate = self
        statementTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        statementTextView.textContainer?.widthTracksTextView = false
        contentView.addSubview(statementScrollView)

        confirmButton.title = originalTrigger == nil
            ? NSLocalizedString("Add", comment: "Add trigger button label")
            : NSLocalizedString("Save", comment: "Save trigger button label")
        confirmButton.bezelStyle = .rounded
        confirmButton.controlSize = .small
        confirmButton.keyEquivalent = "\r"
        confirmButton.target = self
        confirmButton.action = #selector(confirmTrigger(_:))
        contentView.addSubview(confirmButton)

        cancelButton.title = NSLocalizedString("Cancel", comment: "cancel button")
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.target = self
        cancelButton.action = #selector(closeTriggerSheet(_:))
        contentView.addSubview(cancelButton)

        window?.initialFirstResponder = nameField
    }

    private func populate(_ trigger: [String: String]?) {
        guard let trigger = trigger else {
            timingPopUpButton.selectItem(withTitle: "BEFORE")
            eventPopUpButton.selectItem(withTitle: "INSERT")
            return
        }

        nameField.stringValue = trigger["TriggerName"] ?? ""
        statementTextView.string = trigger["TriggerStatement"] ?? ""
        timingPopUpButton.selectItem(withTitle: (trigger["TriggerActionTime"] ?? "BEFORE").uppercased())
        eventPopUpButton.selectItem(withTitle: (trigger["TriggerEvent"] ?? "INSERT").uppercased())
    }

    private func currentValue() -> SALightweightTriggerValue? {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let statement = statementTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !statement.isEmpty else { return nil }

        return SALightweightTriggerValue(name: name,
                                         timing: timingPopUpButton.titleOfSelectedItem ?? "BEFORE",
                                         event: eventPopUpButton.titleOfSelectedItem ?? "INSERT",
                                         statement: statement)
    }

    private func validate() {
        confirmButton.isEnabled = currentValue() != nil
    }

    private func configurePopUp(_ popUpButton: NSPopUpButton, items: [String]) {
        popUpButton.controlSize = .small
        popUpButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        popUpButton.removeAllItems()
        popUpButton.addItems(withTitles: items)
    }

    private func label(title: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.alignment = .right
        label.controlSize = .small
        label.font = NSFont.messageFont(ofSize: 11)
        return label
    }
}

fileprivate enum SALightweightRelationsSupportState {
    case supported
    case unsupported(String)
    case unavailable(String)
}

private enum SALightweightMetadataReadService {
    static func relationsSupportState(table: String, database: String, connection: SPMySQLConnection) -> SALightweightRelationsSupportState {
        let query = """
            SELECT ENGINE, TABLE_TYPE \
            FROM information_schema.TABLES \
            WHERE TABLE_SCHEMA = \(sqlString(database, connection: connection)) \
              AND TABLE_NAME = \(sqlString(table, connection: connection))
            """

        guard let result = connection.queryString(query), !connection.queryErrored() else {
            return .unavailable(errorMessage(prefix: NSLocalizedString("Unable to determine whether this table supports relations.", comment: "relations support metadata error placeholder"), connection: connection))
        }

        result.defaultRowReturnType = SPMySQLResultRowAsArray
        result.returnDataAsStrings = true

        guard let row = result.getRowAsArray() else {
            return .unavailable(NSLocalizedString("Unable to determine whether this table supports relations. The table metadata was not returned; check that the table still exists and that your account can read table metadata.", comment: "relations support metadata unavailable placeholder"))
        }

        let engine = row.indices.contains(0) ? displayString(row[0]) : ""
        let tableType = row.indices.contains(1) ? displayString(row[1]) : ""

        guard tableType.caseInsensitiveCompare("BASE TABLE") == .orderedSame else {
            return .unsupported(NSLocalizedString("Relations can only be edited for base tables. Views and other database objects do not support foreign keys.", comment: "relations unsupported non-table placeholder"))
        }

        guard engine.caseInsensitiveCompare("InnoDB") == .orderedSame else {
            if engine.isEmpty {
                return .unsupported(NSLocalizedString("This table currently does not support relations. Only tables that use the InnoDB storage engine support them.", comment: "This table currently does not support relations. Only tables that use the InnoDB storage engine support them."))
            }

            return .unsupported(String(format: NSLocalizedString("This table currently does not support relations. Only tables that use the InnoDB storage engine support them. This table uses %@.", comment: "relations unsupported storage engine placeholder"), engine))
        }

        return .supported
    }

    static func relations(for table: String, database: String, connection: SPMySQLConnection) -> SALightweightMetadataSnapshot {
        let query = """
            SELECT kcu.CONSTRAINT_NAME, kcu.COLUMN_NAME, kcu.REFERENCED_TABLE_SCHEMA, kcu.REFERENCED_TABLE_NAME, kcu.REFERENCED_COLUMN_NAME, \
                   COALESCE(rc.UPDATE_RULE, '') AS UPDATE_RULE, COALESCE(rc.DELETE_RULE, '') AS DELETE_RULE \
            FROM information_schema.KEY_COLUMN_USAGE kcu \
            LEFT JOIN information_schema.REFERENTIAL_CONSTRAINTS rc \
                ON rc.CONSTRAINT_SCHEMA = kcu.CONSTRAINT_SCHEMA \
               AND rc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME \
               AND rc.TABLE_NAME = kcu.TABLE_NAME \
            WHERE kcu.TABLE_SCHEMA = \(sqlString(database, connection: connection)) \
              AND kcu.TABLE_NAME = \(sqlString(table, connection: connection)) \
              AND kcu.REFERENCED_TABLE_NAME IS NOT NULL \
            ORDER BY kcu.CONSTRAINT_NAME, kcu.ORDINAL_POSITION
            """

        guard let result = connection.queryString(query) else {
            return SALightweightMetadataSnapshot(rows: [], emptyMessage: errorMessage(prefix: NSLocalizedString("Unable to load relations.", comment: "relations error placeholder"), connection: connection))
        }

        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        result.returnDataAsStrings = true
        var relationOrder: [String] = []
        var relationRows: [String: [String: String]] = [:]
        var relationColumns: [String: [String]] = [:]
        var relationReferenceColumns: [String: [String]] = [:]
        while let row = result.getRowAsDictionary() as? [String: Any] {
            let constraintName = displayString(row["CONSTRAINT_NAME"])
            if relationRows[constraintName] == nil {
                relationOrder.append(constraintName)
                relationRows[constraintName] = [
                    "name": constraintName,
                    "columns": "",
                    "fk_database": displayString(row["REFERENCED_TABLE_SCHEMA"]),
                    "fk_table": displayString(row["REFERENCED_TABLE_NAME"]),
                    "fk_columns": "",
                    "on_update": displayString(row["UPDATE_RULE"]),
                    "on_delete": displayString(row["DELETE_RULE"])
                ]
            }

            relationColumns[constraintName, default: []].append(displayString(row["COLUMN_NAME"]))
            relationReferenceColumns[constraintName, default: []].append(displayString(row["REFERENCED_COLUMN_NAME"]))
        }

        if connection.queryErrored() {
            return SALightweightMetadataSnapshot(rows: [], emptyMessage: errorMessage(prefix: NSLocalizedString("Unable to load relations.", comment: "relations error placeholder"), connection: connection))
        }

        let rows = relationOrder.compactMap { constraintName -> [String: String]? in
            guard var relationRow = relationRows[constraintName] else { return nil }
            relationRow["columns"] = relationColumns[constraintName]?.joined(separator: ", ") ?? ""
            relationRow["fk_columns"] = relationReferenceColumns[constraintName]?.joined(separator: ", ") ?? ""
            return relationRow
        }

        return SALightweightMetadataSnapshot(rows: rows, emptyMessage: NSLocalizedString("No relations for this table.", comment: "relations empty placeholder"))
    }

    static func triggers(for table: String, database: String, connection: SPMySQLConnection) -> SALightweightMetadataSnapshot {
        let query = """
            SELECT TRIGGER_NAME, ACTION_TIMING, EVENT_MANIPULATION, ACTION_STATEMENT, CREATED, DEFINER, SQL_MODE \
            FROM information_schema.TRIGGERS \
            WHERE TRIGGER_SCHEMA = \(sqlString(database, connection: connection)) \
              AND EVENT_OBJECT_TABLE = \(sqlString(table, connection: connection)) \
            ORDER BY TRIGGER_NAME
            """

        guard let result = connection.queryString(query) else {
            return SALightweightMetadataSnapshot(rows: [], emptyMessage: errorMessage(prefix: NSLocalizedString("Unable to load triggers.", comment: "triggers error placeholder"), connection: connection))
        }

        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        var rows: [[String: String]] = []
        while let row = result.getRowAsDictionary() as? [String: Any] {
            rows.append([
                "TriggerName": displayString(row["TRIGGER_NAME"]),
                "TriggerEvent": displayString(row["EVENT_MANIPULATION"]),
                "TriggerActionTime": displayString(row["ACTION_TIMING"]),
                "TriggerStatement": displayString(row["ACTION_STATEMENT"]),
                "TriggerDefiner": displayString(row["DEFINER"]),
                "TriggerCreated": displayDate(row["CREATED"]),
                "TriggerSQLMode": displayString(row["SQL_MODE"])
            ])
        }

        if connection.queryErrored() {
            return SALightweightMetadataSnapshot(rows: [], emptyMessage: errorMessage(prefix: NSLocalizedString("Unable to load triggers.", comment: "triggers error placeholder"), connection: connection))
        }

        return SALightweightMetadataSnapshot(rows: rows, emptyMessage: NSLocalizedString("No triggers for this table.", comment: "triggers empty placeholder"))
    }

    private static func displayDate(_ value: Any?) -> String {
        let rawValue = displayString(value)
        guard let date = DateFormatter.naturalLanguageFormatter.date(from: rawValue) else { return rawValue }
        return DateFormatter.shortStyleFormatter.string(from: date)
    }

    private static func displayString(_ value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "" }

        let stringValue = String(describing: value)
        return stringValue.isEmpty ? "" : stringValue
    }

    private static func errorMessage(prefix: String, connection: SPMySQLConnection) -> String {
        guard let error = connection.lastErrorMessage(), !error.isEmpty else { return prefix }
        return "\(prefix)\n\nMySQL said: \(error)"
    }

    private static func sqlString(_ value: String, connection: SPMySQLConnection) -> String {
        return connection.escapeAndQuoteString(value) ?? "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

enum SALightweightSchemaMetadataLoader {
    fileprivate static func serverRequiresStandardForeignKeyReferences(connection: SPMySQLConnection) -> Bool {
        let serverMajorVersion = connection.serverMajorVersion()
        let serverMinorVersion = connection.serverMinorVersion()
        let serverVersionIsAtLeast84 = serverMajorVersion > 8
            || (serverMajorVersion == 8 && serverMinorVersion >= 4)
        guard !connection.isMariaDB(), serverVersionIsAtLeast84 else { return false }

        let result = connection.queryString("SELECT @@session.restrict_fk_on_non_standard_key")
        result?.returnDataAsStrings = true

        let restrictionQueryErrored = connection.queryErrored()
        let restrictionValue = restrictionQueryErrored ? nil : result?.getRowAsArray()?.first
        return SAForeignKeyReferenceRuleSupport.requiresStandardForeignKeyReferences(isMariaDB: connection.isMariaDB(),
                                                                                     serverVersionIsAtLeast84: true,
                                                                                     restrictionQueryErrored: restrictionQueryErrored,
                                                                                     restrictionValue: restrictionValue)
    }

    fileprivate static func singleColumnUniqueReferenceColumns(for table: String, database: String, connection: SPMySQLConnection) -> Set<String> {
        guard !table.isEmpty else { return [] }

        var tableReference = sqlIdentifier(table)
        if !database.isEmpty {
            tableReference = "\(sqlIdentifier(database)).\(sqlIdentifier(table))"
        }

        let changeEncoding = !(connection.encoding()?.hasPrefix("utf8") ?? false)
        if changeEncoding {
            connection.storeEncodingForRestoration()
            _ = connection.setEncoding("utf8mb4")
        }
        defer {
            if changeEncoding {
                connection.restoreStoredEncoding()
            }
        }

        guard let result = connection.queryString("SHOW INDEX FROM \(tableReference)") else { return [] }
        result.returnDataAsStrings = true

        var indexRows: [NSDictionary] = []
        while let row = result.getRowAsDictionary() {
            indexRows.append(row as NSDictionary)
        }

        guard !connection.queryErrored() else { return [] }

        let columns = SAForeignKeyReferenceRuleSupport.singleColumnUniqueReferenceColumns(indexRows as NSArray)
        return Set(columns.compactMap { $0 as? String })
    }

    fileprivate static func relationConstraintNames(for table: String, database: String, connection: SPMySQLConnection) -> Set<String> {
        let query = """
            SELECT CONSTRAINT_NAME \
            FROM information_schema.KEY_COLUMN_USAGE \
            WHERE TABLE_SCHEMA = \(sqlString(database, connection: connection)) \
              AND TABLE_NAME = \(sqlString(table, connection: connection)) \
              AND REFERENCED_TABLE_NAME IS NOT NULL
            """

        guard let result = connection.queryString(query) else { return [] }

        result.defaultRowReturnType = SPMySQLResultRowAsArray
        result.returnDataAsStrings = true

        var names = Set<String>()
        while let row = result.getRowAsArray(), let name = row.first {
            names.insert(String(describing: name).lowercased())
        }
        return names
    }

    fileprivate static func userDatabases(connection: SPMySQLConnection) -> [String] {
        guard let result = connection.queryString("SHOW DATABASES") else { return [] }

        result.defaultRowReturnType = SPMySQLResultRowAsArray
        result.returnDataAsStrings = true

        var databases: [String] = []
        while let row = result.getRowAsArray(), let database = row.first {
            let databaseName = String(describing: database)
            guard !systemDatabases.contains(databaseName.lowercased()) else { continue }
            databases.append(databaseName)
        }
        return databases
    }

    fileprivate static func innodbTables(database: String, connection: SPMySQLConnection) -> [String] {
        let query = """
            SELECT TABLE_NAME \
            FROM information_schema.TABLES \
            WHERE TABLE_TYPE = 'BASE TABLE' \
              AND ENGINE = 'InnoDB' \
              AND TABLE_SCHEMA = \(sqlString(database, connection: connection)) \
            ORDER BY TABLE_NAME
            """

        guard let result = connection.queryString(query) else { return [] }

        result.defaultRowReturnType = SPMySQLResultRowAsArray
        result.returnDataAsStrings = true

        var tables: [String] = []
        while let row = result.getRowAsArray(), let table = row.first {
            tables.append(String(describing: table))
        }
        return tables
    }

    fileprivate static func columns(for table: String, database: String, connection: SPMySQLConnection) -> [SALightweightRelationColumn] {
        let result = connection.queryString("SHOW FULL COLUMNS FROM \(sqlIdentifier(table)) FROM \(sqlIdentifier(database))")

        result?.defaultRowReturnType = SPMySQLResultRowAsDictionary
        result?.returnDataAsStrings = true

        var columns: [SALightweightRelationColumn] = []
        while let row = result?.getRowAsDictionary() as? [String: Any] {
            let name = displayString(row["Field"])
            let type = displayString(row["Type"])
            if !name.isEmpty && !type.isEmpty {
                columns.append(SALightweightRelationColumn(name: name, type: type))
            }
        }
        return columns
    }

    private static func displayString(_ value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "" }

        let stringValue = String(describing: value)
        return stringValue.isEmpty ? "" : stringValue
    }

    private static func sqlString(_ value: String, connection: SPMySQLConnection) -> String {
        return connection.escapeAndQuoteString(value) ?? "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    static func sqlIdentifier(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    private static let systemDatabases: Set<String> = [
        "information_schema",
        "performance_schema",
        "mysql",
        "sys"
    ]
}
