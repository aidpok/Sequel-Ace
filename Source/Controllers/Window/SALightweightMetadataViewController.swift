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

final class SALightweightMetadataTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var loadToken = UUID()
    private let columns: [SALightweightMetadataColumn]
    private let loadingMessage: String
    private var rows: [[String: String]] = []
    private var isLoading = false

    var selectionDidChange: (() -> Void)?
    var doubleClickAction: (() -> Void)?
    var selectedRows: [[String: String]] {
        return tableView.selectedRowIndexes.compactMap { row in
            guard row >= 0, row < rows.count else { return nil }
            return rows[row]
        }
    }

    private lazy var placeholderLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }()

    private lazy var tableView: NSTableView = {
        let tableView = NSTableView(frame: .zero)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = true
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.rowHeight = 22
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
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = tableView
        view.addSubview(scrollView)
    }

    func showPlaceholder(_ message: String) {
        loadToken = UUID()
        isLoading = false
        rows = []
        tableView.reloadData()
        tableView.enclosingScrollView?.isHidden = true
        selectionDidChange?()

        placeholderLabel.stringValue = message
        placeholderLabel.frame = NSRect(x: 20, y: max(0, (view.bounds.height - 60) / 2), width: max(0, view.bounds.width - 40), height: 60)
        placeholderLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        if placeholderLabel.superview == nil {
            view.addSubview(placeholderLabel)
        }
    }

    func load(_ loader: @escaping () -> SALightweightMetadataSnapshot) {
        loadToken = UUID()
        let token = loadToken
        isLoading = true

        placeholderLabel.removeFromSuperviewWithoutNeedingDisplay()
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
                    self.placeholderLabel.removeFromSuperviewWithoutNeedingDisplay()
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
        doubleClickAction?()
    }

    private func showLoadingMessage() {
        placeholderLabel.stringValue = loadingMessage
        placeholderLabel.frame = NSRect(x: 20, y: max(0, (view.bounds.height - 60) / 2), width: max(0, view.bounds.width - 40), height: 60)
        placeholderLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        if placeholderLabel.superview == nil {
            view.addSubview(placeholderLabel)
        }
    }
}

final class SALightweightRelationsViewController: NSViewController {
    var requestLegacyRelationsFallback: (() -> Void)?

    private weak var connection: SPMySQLConnection?
    private var database = ""
    private var table = ""

    private let tableController = SALightweightMetadataTableViewController(columns: [
        SALightweightMetadataColumn(identifier: "constraint", title: NSLocalizedString("Constraint", comment: "relations constraint column"), width: 185, minWidth: 100),
        SALightweightMetadataColumn(identifier: "column", title: NSLocalizedString("Column", comment: "relations column column"), width: 150, minWidth: 90),
        SALightweightMetadataColumn(identifier: "referencedTable", title: NSLocalizedString("Referenced Table", comment: "relations referenced table column"), width: 190, minWidth: 110),
        SALightweightMetadataColumn(identifier: "referencedColumn", title: NSLocalizedString("Referenced Column", comment: "relations referenced column column"), width: 180, minWidth: 110),
        SALightweightMetadataColumn(identifier: "updateRule", title: NSLocalizedString("On Update", comment: "relations update rule column"), width: 120, minWidth: 80),
        SALightweightMetadataColumn(identifier: "deleteRule", title: NSLocalizedString("On Delete", comment: "relations delete rule column"), width: 120, minWidth: 80)
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
        tableController.doubleClickAction = { [weak self] in
            self?.requestLegacyRelationsFallback?()
        }
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

    func loadRelations(for table: String, database: String, connection: SPMySQLConnection) {
        self.table = table
        self.database = database
        self.connection = connection
        titleLabel.stringValue = String(format: NSLocalizedString("Relations for table: %@", comment: "Relations tab subtitle showing table name"), table)
        updateButtonState()
        tableController.load {
            SALightweightSchemaMetadataLoader.relations(for: table, database: database, connection: connection)
        }
    }

    @objc private func addRelation(_ sender: Any) {
        requestLegacyRelationsFallback?()
    }

    @objc private func refreshRelations(_ sender: Any) {
        guard let connection = connection, !table.isEmpty, !database.isEmpty else { return }
        loadRelations(for: table, database: database, connection: connection)
    }

    @objc private func removeRelation(_ sender: Any) {
        let selectedRows = tableController.selectedRows
        guard !selectedRows.isEmpty, let connection = connection, !database.isEmpty, !table.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete relation", comment: "delete relation message")
        alert.informativeText = NSLocalizedString("Are you sure you want to delete the selected relations? This action cannot be undone.", comment: "delete selected relation informative message")
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for row in selectedRows {
            guard let constraint = row["constraint"], !constraint.isEmpty else { continue }
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

    private func updateButtonState() {
        let hasTable = connection != nil && !table.isEmpty && !database.isEmpty
        addButton.isEnabled = hasTable
        refreshButton.isEnabled = hasTable
        removeButton.isEnabled = hasTable && tableController.canRemoveSelection()
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
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

final class SALightweightTriggersViewController: NSViewController {
    var requestLegacyTriggersFallback: (() -> Void)?

    private weak var connection: SPMySQLConnection?
    private var database = ""
    private var table = ""

    private let tableController = SALightweightMetadataTableViewController(columns: [
        SALightweightMetadataColumn(identifier: "name", title: NSLocalizedString("Trigger", comment: "triggers trigger column"), width: 180, minWidth: 100),
        SALightweightMetadataColumn(identifier: "timing", title: NSLocalizedString("Timing", comment: "triggers timing column"), width: 90, minWidth: 70),
        SALightweightMetadataColumn(identifier: "event", title: NSLocalizedString("Event", comment: "triggers event column"), width: 90, minWidth: 70),
        SALightweightMetadataColumn(identifier: "statement", title: NSLocalizedString("Statement", comment: "triggers statement column"), width: 360, minWidth: 180),
        SALightweightMetadataColumn(identifier: "created", title: NSLocalizedString("Created", comment: "triggers created column"), width: 150, minWidth: 100),
        SALightweightMetadataColumn(identifier: "definer", title: NSLocalizedString("Definer", comment: "triggers definer column"), width: 180, minWidth: 100),
        SALightweightMetadataColumn(identifier: "sqlMode", title: NSLocalizedString("SQL Mode", comment: "triggers sql mode column"), width: 220, minWidth: 120)
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
        tableController.doubleClickAction = { [weak self] in
            self?.requestLegacyTriggersFallback?()
        }
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
            SALightweightSchemaMetadataLoader.triggers(for: table, database: database, connection: connection)
        }
    }

    @objc private func addTrigger(_ sender: Any) {
        requestLegacyTriggersFallback?()
    }

    @objc private func refreshTriggers(_ sender: Any) {
        guard let connection = connection, !table.isEmpty, !database.isEmpty else { return }
        loadTriggers(for: table, database: database, connection: connection)
    }

    @objc private func removeTrigger(_ sender: Any) {
        let selectedRows = tableController.selectedRows
        guard !selectedRows.isEmpty, let connection = connection, !database.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delete trigger", comment: "delete trigger message")
        alert.informativeText = NSLocalizedString("Are you sure you want to delete the selected triggers? This action cannot be undone.", comment: "delete selected trigger informative message")
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for row in selectedRows {
            guard let trigger = row["name"], !trigger.isEmpty else { continue }
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

    private func updateButtonState() {
        let hasTable = connection != nil && !table.isEmpty && !database.isEmpty
        addButton.isEnabled = hasTable
        refreshButton.isEnabled = hasTable
        removeButton.isEnabled = hasTable && tableController.canRemoveSelection()
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
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

enum SALightweightSchemaMetadataLoader {
    static func relations(for table: String, database: String, connection: SPMySQLConnection) -> SALightweightMetadataSnapshot {
        let query = """
            SELECT kcu.CONSTRAINT_NAME, kcu.COLUMN_NAME, kcu.REFERENCED_TABLE_NAME, kcu.REFERENCED_COLUMN_NAME, \
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
        var rows: [[String: String]] = []
        while let row = result.getRowAsDictionary() as? [String: Any] {
            rows.append([
                "constraint": displayString(row["CONSTRAINT_NAME"]),
                "column": displayString(row["COLUMN_NAME"]),
                "referencedTable": displayString(row["REFERENCED_TABLE_NAME"]),
                "referencedColumn": displayString(row["REFERENCED_COLUMN_NAME"]),
                "updateRule": displayString(row["UPDATE_RULE"]),
                "deleteRule": displayString(row["DELETE_RULE"])
            ])
        }

        if connection.queryErrored() {
            return SALightweightMetadataSnapshot(rows: [], emptyMessage: errorMessage(prefix: NSLocalizedString("Unable to load relations.", comment: "relations error placeholder"), connection: connection))
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
                "name": displayString(row["TRIGGER_NAME"]),
                "timing": displayString(row["ACTION_TIMING"]),
                "event": displayString(row["EVENT_MANIPULATION"]),
                "statement": displayString(row["ACTION_STATEMENT"]),
                "created": displayDate(row["CREATED"]),
                "definer": displayString(row["DEFINER"]),
                "sqlMode": displayString(row["SQL_MODE"])
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

    static func sqlIdentifier(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }
}
