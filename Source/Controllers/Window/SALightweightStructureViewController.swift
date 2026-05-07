//
//  SALightweightStructureViewController.swift
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

final class SALightweightStructureViewController: NSViewController {

    private struct StructureColumn {
        let title: String
        let key: String
        let width: CGFloat
        let isBoolean: Bool
        let editable: Bool
    }

    private struct StructureRow {
        var values: [String: String]
        var originalName: String?
        var isNew = false

        var name: String { values["name"] ?? "" }
    }

    private struct IndexColumn {
        let title: String
        let key: String
        let width: CGFloat
    }

    private let structureColumns: [StructureColumn] = [
        StructureColumn(title: NSLocalizedString("Field", comment: "table structure field column"), key: "name", width: 210, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Type", comment: "table structure type column"), key: "type", width: 125, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Length", comment: "table structure length column"), key: "length", width: 80, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Unsigned", comment: "table structure unsigned column"), key: "unsigned", width: 86, isBoolean: true, editable: true),
        StructureColumn(title: NSLocalizedString("Zerofill", comment: "table structure zerofill column"), key: "zerofill", width: 78, isBoolean: true, editable: true),
        StructureColumn(title: NSLocalizedString("Binary", comment: "table structure binary column"), key: "binary", width: 70, isBoolean: true, editable: true),
        StructureColumn(title: NSLocalizedString("Allow Null", comment: "table structure allow null column"), key: "null", width: 88, isBoolean: true, editable: true),
        StructureColumn(title: NSLocalizedString("Key", comment: "table structure key column"), key: "Key", width: 56, isBoolean: false, editable: false),
        StructureColumn(title: NSLocalizedString("Default", comment: "table structure default column"), key: "default", width: 120, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Extra", comment: "table structure extra column"), key: "Extra", width: 145, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Encoding", comment: "table structure encoding column"), key: "encodingName", width: 130, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Collation", comment: "table structure collation column"), key: "collationName", width: 160, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Comment", comment: "table structure comment column"), key: "comment", width: 220, isBoolean: false, editable: true)
    ]

    private let indexColumns: [IndexColumn] = [
        IndexColumn(title: "Non_unique", key: "Non_unique", width: 80),
        IndexColumn(title: "Key_name", key: "Key_name", width: 120),
        IndexColumn(title: "Seq_in_index", key: "Seq_in_index", width: 90),
        IndexColumn(title: "Column_name", key: "Column_name", width: 140),
        IndexColumn(title: "Collation", key: "Collation", width: 86),
        IndexColumn(title: "Cardinality", key: "Cardinality", width: 92),
        IndexColumn(title: "Sub_part", key: "Sub_part", width: 80),
        IndexColumn(title: "Packed", key: "Packed", width: 80),
        IndexColumn(title: "Comment", key: "Comment", width: 180)
    ]

    private weak var connection: SPMySQLConnection?
    private var database = ""
    private var table = ""
    private var rows: [StructureRow] = []
    private var filteredRows: [StructureRow]?
    private var indexes: [[String: String]] = []
    private var loadToken = UUID()
    private var isSaving = false

    private lazy var structureFilterField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = NSLocalizedString("Filter", comment: "table structure filter placeholder")
        field.target = self
        field.action = #selector(filterChanged(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }()

    private lazy var structureTableView: NSTableView = {
        let tableView = NSTableView(frame: .zero)
        tableView.identifier = NSUserInterfaceItemIdentifier("StructureTable")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: UserDefaults.getFont()]).height

        for column in structureColumns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.key))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 40
            tableColumn.isEditable = column.editable

            if column.isBoolean {
                let cell = NSButtonCell()
                cell.setButtonType(.switch)
                cell.title = ""
                cell.allowsMixedState = false
                tableColumn.dataCell = cell
            } else {
                let cell = NSTextFieldCell(textCell: "")
                cell.isEditable = column.editable
                cell.isSelectable = true
                cell.lineBreakMode = .byTruncatingTail
                cell.font = UserDefaults.getFont()
                tableColumn.dataCell = cell
            }

            tableView.addTableColumn(tableColumn)
        }

        tableView.registerForDraggedTypes([NSPasteboard.PasteboardType("SequelAceLightweightStructureRow")])
        return tableView
    }()

    private lazy var indexesLabel: NSTextField = {
        let label = NSTextField(labelWithString: NSLocalizedString("INDEXES", comment: "indexes heading"))
        label.font = NSFont.boldSystemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var indexesTableView: NSTableView = {
        let tableView = NSTableView(frame: .zero)
        tableView.identifier = NSUserInterfaceItemIdentifier("IndexesTable")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = structureTableView.rowHeight

        for column in indexColumns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.key))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 40
            let cell = NSTextFieldCell(textCell: "")
            cell.isEditable = false
            cell.isSelectable = true
            cell.lineBreakMode = .byTruncatingTail
            cell.font = UserDefaults.getFont()
            tableColumn.dataCell = cell
            tableView.addTableColumn(tableColumn)
        }

        return tableView
    }()

    private lazy var addFieldButton = toolbarButton(title: "+", action: #selector(addField(_:)))
    private lazy var removeFieldButton = toolbarButton(title: "-", action: #selector(removeField(_:)))
    private lazy var duplicateFieldButton = toolbarButton(title: "+", action: #selector(duplicateField(_:)))
    private lazy var reloadFieldsButton = toolbarButton(title: "↻", action: #selector(reloadTable(_:)))
    private lazy var addIndexButton = toolbarButton(title: "+", action: #selector(addIndex(_:)))
    private lazy var removeIndexButton = toolbarButton(title: "-", action: #selector(removeIndex(_:)))
    private lazy var refreshIndexesButton = toolbarButton(title: "↻", action: #selector(reloadTable(_:)))

    override func loadView() {
        let rootView = NSView(frame: .zero)

        let structurePane = NSView(frame: .zero)
        structurePane.translatesAutoresizingMaskIntoConstraints = false
        let structureScrollView = NSScrollView(frame: .zero)
        structureScrollView.hasVerticalScroller = true
        structureScrollView.hasHorizontalScroller = true
        structureScrollView.autohidesScrollers = true
        structureScrollView.documentView = structureTableView
        structureScrollView.translatesAutoresizingMaskIntoConstraints = false

        let structureToolbar = toolbarView(buttons: [addFieldButton, removeFieldButton, duplicateFieldButton, reloadFieldsButton])
        structurePane.addSubview(structureFilterField)
        structurePane.addSubview(structureScrollView)
        structurePane.addSubview(structureToolbar)
        rootView.addSubview(structurePane)

        let indexPane = NSView(frame: .zero)
        indexPane.translatesAutoresizingMaskIntoConstraints = false
        let indexScrollView = NSScrollView(frame: .zero)
        indexScrollView.hasVerticalScroller = true
        indexScrollView.hasHorizontalScroller = true
        indexScrollView.autohidesScrollers = true
        indexScrollView.documentView = indexesTableView
        indexScrollView.translatesAutoresizingMaskIntoConstraints = false

        let indexToolbar = toolbarView(buttons: [addIndexButton, removeIndexButton, refreshIndexesButton])
        indexPane.addSubview(indexesLabel)
        indexPane.addSubview(indexScrollView)
        indexPane.addSubview(indexToolbar)
        rootView.addSubview(indexPane)

        structureFilterField.translatesAutoresizingMaskIntoConstraints = false
        structureToolbar.translatesAutoresizingMaskIntoConstraints = false
        indexToolbar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            structurePane.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            structurePane.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            structurePane.topAnchor.constraint(equalTo: rootView.topAnchor),
            structurePane.bottomAnchor.constraint(equalTo: indexPane.topAnchor),

            indexPane.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            indexPane.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            indexPane.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            indexPane.heightAnchor.constraint(equalToConstant: 210),

            structureFilterField.leadingAnchor.constraint(equalTo: structurePane.leadingAnchor, constant: 4),
            structureFilterField.trailingAnchor.constraint(equalTo: structurePane.trailingAnchor, constant: -4),
            structureFilterField.topAnchor.constraint(equalTo: structurePane.topAnchor, constant: 4),
            structureFilterField.heightAnchor.constraint(equalToConstant: 24),

            structureScrollView.leadingAnchor.constraint(equalTo: structurePane.leadingAnchor),
            structureScrollView.trailingAnchor.constraint(equalTo: structurePane.trailingAnchor),
            structureScrollView.topAnchor.constraint(equalTo: structureFilterField.bottomAnchor, constant: 4),
            structureScrollView.bottomAnchor.constraint(equalTo: structureToolbar.topAnchor),

            structureToolbar.leadingAnchor.constraint(equalTo: structurePane.leadingAnchor),
            structureToolbar.trailingAnchor.constraint(equalTo: structurePane.trailingAnchor),
            structureToolbar.bottomAnchor.constraint(equalTo: structurePane.bottomAnchor),
            structureToolbar.heightAnchor.constraint(equalToConstant: 26),

            indexesLabel.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor, constant: 6),
            indexesLabel.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor, constant: -6),
            indexesLabel.topAnchor.constraint(equalTo: indexPane.topAnchor, constant: 3),
            indexesLabel.heightAnchor.constraint(equalToConstant: 17),

            indexScrollView.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor),
            indexScrollView.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor),
            indexScrollView.topAnchor.constraint(equalTo: indexesLabel.bottomAnchor),
            indexScrollView.bottomAnchor.constraint(equalTo: indexToolbar.topAnchor),

            indexToolbar.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor),
            indexToolbar.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor),
            indexToolbar.bottomAnchor.constraint(equalTo: indexPane.bottomAnchor),
            indexToolbar.heightAnchor.constraint(equalToConstant: 26)
        ])

        view = rootView
    }

    func loadStructure(for table: String, database: String, connection: SPMySQLConnection) {
        self.table = table
        self.database = database
        self.connection = connection
        loadToken = UUID()
        let token = loadToken

        rows = []
        filteredRows = nil
        indexes = []
        structureTableView.reloadData()
        indexesTableView.reloadData()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            _ = connection.selectDatabase(database)
            let fields = self.loadFields(table: table, database: database, connection: connection)
            let indexes = self.loadIndexes(table: table, connection: connection)

            DispatchQueue.main.async {
                guard self.loadToken == token else { return }

                self.rows = fields
                self.indexes = indexes
                self.applyFilter()
                self.structureTableView.reloadData()
                self.indexesTableView.reloadData()
                self.resetScrollPositions()
                self.updateButtonState()
            }
        }
    }

    private func loadFields(table: String, database: String, connection: SPMySQLConnection) -> [StructureRow] {
        let result = connection.queryString("SHOW FULL COLUMNS FROM \(Self.backtickQuoted(table)) FROM \(Self.backtickQuoted(database))")
        result?.returnDataAsStrings = true
        result?.defaultRowReturnType = SPMySQLResultRowAsDictionary

        var loadedRows: [StructureRow] = []
        while let row = result?.getRowAsDictionary() as? [String: Any] {
            loadedRows.append(Self.structureRow(from: row))
        }

        if connection.queryErrored() {
            DispatchQueue.main.async {
                self.showError(title: NSLocalizedString("Error loading structure", comment: "structure load error title"), message: connection.lastErrorMessage())
            }
        }

        return loadedRows
    }

    private func loadIndexes(table: String, connection: SPMySQLConnection) -> [[String: String]] {
        let result = connection.queryString("SHOW INDEX FROM \(Self.backtickQuoted(table))")
        result?.returnDataAsStrings = true
        result?.defaultRowReturnType = SPMySQLResultRowAsDictionary

        var loadedIndexes: [[String: String]] = []
        while let row = result?.getRowAsDictionary() as? [String: Any] {
            var indexRow: [String: String] = [:]
            for column in indexColumns {
                indexRow[column.key] = Self.displayString(for: row[column.key])
            }
            loadedIndexes.append(indexRow)
        }

        if connection.queryErrored() {
            DispatchQueue.main.async {
                self.showError(title: NSLocalizedString("Error loading indexes", comment: "index load error title"), message: connection.lastErrorMessage())
            }
        }

        return loadedIndexes
    }

    private static func structureRow(from row: [String: Any]) -> StructureRow {
        let field = displayString(for: row["Field"])
        let parsedType = parseType(displayString(for: row["Type"]))
        let collation = displayString(for: row["Collation"])
        var values: [String: String] = [
            "name": field,
            "type": parsedType.type,
            "length": parsedType.length,
            "unsigned": parsedType.unsigned ? "1" : "0",
            "zerofill": parsedType.zerofill ? "1" : "0",
            "binary": parsedType.binary ? "1" : "0",
            "null": displayString(for: row["Null"]).uppercased() == "YES" ? "1" : "0",
            "Key": displayString(for: row["Key"]),
            "default": displayString(for: row["Default"]),
            "Extra": displayString(for: row["Extra"]).isEmpty ? "None" : displayString(for: row["Extra"]),
            "encodingName": encodingName(from: collation),
            "collationName": collation,
            "comment": displayString(for: row["Comment"])
        ]

        if values["default"]?.isEmpty == true, row["Default"] is NSNull {
            values["default"] = UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        return StructureRow(values: values, originalName: field)
    }

    private static func parseType(_ rawType: String) -> (type: String, length: String, unsigned: Bool, zerofill: Bool, binary: Bool) {
        var type = rawType
        let lower = rawType.lowercased()
        let unsigned = lower.contains(" unsigned")
        let zerofill = lower.contains(" zerofill")
        let binary = lower.contains(" binary")

        for suffix in [" unsigned", " zerofill", " binary"] {
            type = type.replacingOccurrences(of: suffix, with: "", options: .caseInsensitive)
        }

        var length = ""
        if let open = type.firstIndex(of: "("), let close = type.lastIndex(of: ")"), open < close {
            length = String(type[type.index(after: open)..<close])
            type = String(type[..<open])
        }

        return (type.uppercased(), length, unsigned, zerofill, binary)
    }

    private static func encodingName(from collation: String) -> String {
        guard let separator = collation.firstIndex(of: "_") else { return "" }
        return String(collation[..<separator])
    }

    private func displayRows() -> [StructureRow] {
        return filteredRows ?? rows
    }

    private func sourceIndex(forDisplayedRow displayedRow: Int) -> Int? {
        let displayedRows = displayRows()
        guard displayedRow >= 0, displayedRow < displayedRows.count else { return nil }
        let originalName = displayedRows[displayedRow].originalName
        let currentName = displayedRows[displayedRow].name
        return rows.firstIndex { row in
            if let originalName = originalName {
                return row.originalName == originalName
            }
            return row.name == currentName
        }
    }

    private func applyFilter() {
        let filter = structureFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else {
            filteredRows = nil
            return
        }

        filteredRows = rows.filter { row in
            structureColumns.contains { column in
                (row.values[column.key] ?? "").range(of: filter, options: .caseInsensitive) != nil
            }
        }
    }

    private func saveRow(at index: Int, oldRow: StructureRow) {
        guard !isSaving, index >= 0, index < rows.count, let connection = connection else { return }
        var row = rows[index]
        guard !row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError(title: NSLocalizedString("Field name required", comment: "field name required title"), message: NSLocalizedString("The field name cannot be empty.", comment: "field name required message"))
            rows[index] = oldRow
            reloadVisibleRows()
            return
        }

        isSaving = true
        let query: String
        if row.isNew {
            query = addColumnQuery(for: row, at: index)
        } else {
            query = "ALTER TABLE \(Self.backtickQuoted(table)) CHANGE \(Self.backtickQuoted(oldRow.originalName ?? oldRow.name)) \(columnDefinition(for: row))"
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            connection.queryString(query)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error, !error.isEmpty {
                    self.rows[index] = oldRow
                    self.reloadVisibleRows()
                    self.showError(title: row.isNew ? NSLocalizedString("Error adding field", comment: "add field error title") : NSLocalizedString("Error changing field", comment: "change field error title"), message: "\(query)\n\n\(error)")
                    return
                }

                row.isNew = false
                row.originalName = row.name
                self.rows[index] = row
                self.loadStructure(for: self.table, database: self.database, connection: connection)
            }
        }
    }

    private func addColumnQuery(for row: StructureRow, at index: Int) -> String {
        var query = "ALTER TABLE \(Self.backtickQuoted(table)) ADD \(columnDefinition(for: row))"
        if index == 0 {
            query += " FIRST"
        } else if index - 1 < rows.count {
            query += " AFTER \(Self.backtickQuoted(rows[index - 1].name))"
        }
        return query
    }

    private func columnDefinition(for row: StructureRow) -> String {
        let values = row.values
        var type = (values["type"] ?? "INT").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if type.isEmpty {
            type = "INT"
        }

        var definition = "\(Self.backtickQuoted(row.name)) \(type)"

        let length = (values["length"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !length.isEmpty {
            definition += "(\(length))"
        }

        let encoding = (values["encodingName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let collation = (values["collationName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if isStringType(type) {
            if !encoding.isEmpty {
                definition += " CHARACTER SET \(encoding)"
            }
            if boolValue(values["binary"]) {
                definition += " BINARY"
            } else if !collation.isEmpty {
                definition += " COLLATE \(collation)"
            }
        } else if isNumericType(type), type != "BIT" {
            if boolValue(values["unsigned"]) {
                definition += " UNSIGNED"
            }
            if boolValue(values["zerofill"]) {
                definition += " ZEROFILL"
            }
        }

        definition += boolValue(values["null"]) ? " NULL" : " NOT NULL"

        let defaultValue = (values["default"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nullValue = UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        if !defaultValue.isEmpty, !extraIsAutoIncrement(values["Extra"]) {
            if defaultValue == nullValue || defaultValue.uppercased() == "NULL" {
                if boolValue(values["null"]) {
                    definition += " DEFAULT NULL"
                }
            } else if defaultLooksLikeExpression(defaultValue) || type == "BIT" {
                definition += " DEFAULT \(defaultValue)"
            } else {
                definition += " DEFAULT \(connection?.escapeAndQuoteString(defaultValue) ?? "'\(defaultValue.replacingOccurrences(of: "'", with: "''"))'")"
            }
        }

        let extra = (values["Extra"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty, extra.uppercased() != "NONE" {
            definition += " \(extra.uppercased())"
        }

        let comment = (values["comment"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty {
            definition += " COMMENT \(connection?.escapeAndQuoteString(comment) ?? "'\(comment.replacingOccurrences(of: "'", with: "''"))'")"
        }

        return definition
    }

    private func isStringType(_ type: String) -> Bool {
        let upper = type.uppercased()
        return upper.contains("CHAR") || upper.contains("TEXT") || upper == "ENUM" || upper == "SET"
    }

    private func isNumericType(_ type: String) -> Bool {
        return ["BIT", "BOOL", "BOOLEAN", "TINYINT", "SMALLINT", "MEDIUMINT", "INT", "INTEGER", "BIGINT", "DECIMAL", "NUMERIC", "FLOAT", "DOUBLE", "REAL"].contains(type.uppercased())
    }

    private func boolValue(_ value: String?) -> Bool {
        return value == "1" || value?.caseInsensitiveCompare("YES") == .orderedSame || value?.caseInsensitiveCompare("true") == .orderedSame
    }

    private func extraIsAutoIncrement(_ value: String?) -> Bool {
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("auto_increment") == .orderedSame
    }

    private func defaultLooksLikeExpression(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("'") || trimmed.hasPrefix("\"") {
            return true
        }
        if trimmed.hasSuffix(")") {
            return true
        }
        return ["CURRENT_TIMESTAMP", "CURRENT_DATE", "CURRENT_TIME", "NULL"].contains(trimmed.uppercased())
    }

    private func reloadVisibleRows() {
        applyFilter()
        structureTableView.reloadData()
        resetScrollPositions()
    }

    private func resetScrollPositions() {
        structureTableView.scrollColumnToVisible(0)
        structureTableView.scrollRowToVisible(0)
        indexesTableView.scrollColumnToVisible(0)
        indexesTableView.scrollRowToVisible(0)
        structureTableView.enclosingScrollView?.contentView.scroll(to: .zero)
        indexesTableView.enclosingScrollView?.contentView.scroll(to: .zero)
        structureTableView.enclosingScrollView?.reflectScrolledClipView(structureTableView.enclosingScrollView!.contentView)
        indexesTableView.enclosingScrollView?.reflectScrolledClipView(indexesTableView.enclosingScrollView!.contentView)
    }

    private func updateButtonState() {
        let hasStructureSelection = structureTableView.selectedRow >= 0
        removeFieldButton.isEnabled = hasStructureSelection && rows.count > 1
        duplicateFieldButton.isEnabled = hasStructureSelection
        removeIndexButton.isEnabled = indexesTableView.selectedRow >= 0
        addIndexButton.isEnabled = hasStructureSelection
    }

    private func isStructureTable(_ tableView: NSTableView) -> Bool {
        return tableView.identifier?.rawValue == "StructureTable"
    }

    private func isIndexesTable(_ tableView: NSTableView) -> Bool {
        return tableView.identifier?.rawValue == "IndexesTable"
    }

    private func toolbarButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 15)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func toolbarView(buttons: [NSButton]) -> NSView {
        let view = NSView(frame: .zero)
        var previous: NSView?

        for button in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: view.topAnchor),
                button.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            if let previous = previous {
                button.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 2).isActive = true
            } else {
                button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2).isActive = true
            }
            previous = button
        }

        return view
    }

    private func showError(title: String, message: String?) {
        NSAlert.createWarningAlert(title: title, message: message ?? "", callback: nil)
    }

    private static func displayString(for value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "" }
        return String(describing: value)
    }

    private static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }
}

private extension SALightweightStructureViewController {
    @objc func filterChanged(_ sender: NSSearchField) {
        reloadVisibleRows()
    }

    @objc func addField(_ sender: Any?) {
        let insertIndex = structureTableView.selectedRow >= 0 ? structureTableView.selectedRow + 1 : rows.count
        let previousAllowsNull = UserDefaults.standard.bool(forKey: SPNewFieldsAllowNulls)
        let row = StructureRow(values: [
            "name": "",
            "type": "INT",
            "length": "",
            "unsigned": "0",
            "zerofill": "0",
            "binary": "0",
            "null": previousAllowsNull ? "1" : "0",
            "Key": "",
            "default": UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL",
            "Extra": "None",
            "encodingName": "",
            "collationName": "",
            "comment": ""
        ], originalName: nil, isNew: true)

        rows.insert(row, at: insertIndex)
        reloadVisibleRows()
        structureTableView.selectRowIndexes(IndexSet(integer: insertIndex), byExtendingSelection: false)
        structureTableView.editColumn(0, row: insertIndex, with: nil, select: true)
        updateButtonState()
    }

    @objc func duplicateField(_ sender: Any?) {
        let selectedRow = structureTableView.selectedRow
        guard let sourceIndex = sourceIndex(forDisplayedRow: selectedRow) else { return }
        var row = rows[sourceIndex]
        row.values["name"] = row.name + "Copy"
        row.values["Key"] = ""
        row.values["Extra"] = "None"
        row.originalName = nil
        row.isNew = true
        rows.insert(row, at: sourceIndex + 1)
        reloadVisibleRows()
        structureTableView.selectRowIndexes(IndexSet(integer: sourceIndex + 1), byExtendingSelection: false)
        structureTableView.editColumn(0, row: sourceIndex + 1, with: nil, select: true)
        updateButtonState()
    }

    @objc func removeField(_ sender: Any?) {
        let selectedRow = structureTableView.selectedRow
        guard let sourceIndex = sourceIndex(forDisplayedRow: selectedRow), rows.count > 1, let connection = connection else { return }
        let row = rows[sourceIndex]

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Delete field '%@'?", comment: "delete field title"), row.name)
        alert.informativeText = NSLocalizedString("This action cannot be undone.", comment: "delete field message")
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            let query = "ALTER TABLE \(Self.backtickQuoted(self.table)) DROP \(Self.backtickQuoted(row.name))"
            connection.queryString(query)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error, !error.isEmpty {
                    self.showError(title: NSLocalizedString("Error deleting field", comment: "delete field error title"), message: error)
                    return
                }

                self.loadStructure(for: self.table, database: self.database, connection: connection)
            }
        }
    }

    @objc func reloadTable(_ sender: Any?) {
        guard let connection = connection else { return }
        loadStructure(for: table, database: database, connection: connection)
    }

    @objc func addIndex(_ sender: Any?) {
        let selectedRow = structureTableView.selectedRow
        guard let sourceIndex = sourceIndex(forDisplayedRow: selectedRow), let connection = connection else { return }
        let field = rows[sourceIndex].name

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Add index for '%@'", comment: "add index title"), field)
        alert.informativeText = NSLocalizedString("Choose the index type to create for the selected field.", comment: "add index message")

        let typePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        typePopup.addItems(withTitles: ["INDEX", "UNIQUE", "FULLTEXT", "PRIMARY KEY"])
        let nameField = NSTextField(frame: NSRect(x: 0, y: 32, width: 220, height: 24))
        nameField.placeholderString = NSLocalizedString("Index name", comment: "index name placeholder")
        nameField.stringValue = field

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 58))
        accessory.addSubview(typePopup)
        accessory.addSubview(nameField)
        alert.accessoryView = accessory
        alert.addButton(withTitle: NSLocalizedString("Add", comment: "add button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let type = typePopup.titleOfSelectedItem ?? "INDEX"
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var query = "ALTER TABLE \(Self.backtickQuoted(table)) ADD \(type)"
        if type != "PRIMARY KEY", !name.isEmpty {
            query += " \(Self.backtickQuoted(name))"
        }
        query += " (\(Self.backtickQuoted(field)))"

        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            connection.queryString(query)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error, !error.isEmpty {
                    self.showError(title: NSLocalizedString("Unable to add index", comment: "add index error title"), message: error)
                    return
                }

                self.loadStructure(for: self.table, database: self.database, connection: connection)
            }
        }
    }

    @objc func removeIndex(_ sender: Any?) {
        let selectedRow = indexesTableView.selectedRow
        guard selectedRow >= 0, selectedRow < indexes.count, let connection = connection else { return }
        let indexName = indexes[selectedRow]["Key_name"] ?? ""
        guard !indexName.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Delete index '%@'?", comment: "delete index title"), indexName)
        alert.informativeText = NSLocalizedString("This action cannot be undone.", comment: "delete index message")
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let query = indexName == "PRIMARY"
            ? "ALTER TABLE \(Self.backtickQuoted(table)) DROP PRIMARY KEY"
            : "ALTER TABLE \(Self.backtickQuoted(table)) DROP INDEX \(Self.backtickQuoted(indexName))"

        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            connection.queryString(query)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error, !error.isEmpty {
                    self.showError(title: NSLocalizedString("Unable to delete index", comment: "delete index error title"), message: error)
                    return
                }

                self.loadStructure(for: self.table, database: self.database, connection: connection)
            }
        }
    }
}

extension SALightweightStructureViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if isIndexesTable(tableView) {
            return indexes.count
        }

        return displayRows().count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let key = tableColumn?.identifier.rawValue else { return nil }

        if isIndexesTable(tableView) {
            guard row >= 0, row < indexes.count else { return nil }
            return indexes[row][key] ?? ""
        }

        let displayedRows = displayRows()
        guard row >= 0, row < displayedRows.count else { return nil }

        let value = displayedRows[row].values[key] ?? ""
        if structureColumns.first(where: { $0.key == key })?.isBoolean == true {
            return boolValue(value) ? NSControl.StateValue.on.rawValue : NSControl.StateValue.off.rawValue
        }

        return value
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard isStructureTable(tableView), let key = tableColumn?.identifier.rawValue, let sourceIndex = sourceIndex(forDisplayedRow: row) else { return }
        let oldRow = rows[sourceIndex]
        var newValue = ""

        if structureColumns.first(where: { $0.key == key })?.isBoolean == true {
            if let number = object as? NSNumber {
                newValue = number.intValue == NSControl.StateValue.on.rawValue ? "1" : "0"
            } else {
                newValue = "\(object ?? "")" == "\(NSControl.StateValue.on.rawValue)" ? "1" : "0"
            }
        } else {
            newValue = "\(object ?? "")"
        }

        if rows[sourceIndex].values[key] == newValue {
            return
        }

        rows[sourceIndex].values[key] = newValue
        if key == "type" {
            rows[sourceIndex].values[key] = newValue.uppercased()
        }
        if key == "Extra", extraIsAutoIncrement(newValue) {
            rows[sourceIndex].values["null"] = "0"
        }

        saveRow(at: sourceIndex, oldRow: oldRow)
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        guard isStructureTable(tableView), !isSaving, let key = tableColumn?.identifier.rawValue else { return false }
        return structureColumns.first(where: { $0.key == key })?.editable == true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonState()
    }

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
        guard isStructureTable(tableView), let row = rowIndexes.first, sourceIndex(forDisplayedRow: row) != nil else { return false }
        pasteboard.declareTypes([NSPasteboard.PasteboardType("SequelAceLightweightStructureRow")], owner: nil)
        pasteboard.setString("\(row)", forType: NSPasteboard.PasteboardType("SequelAceLightweightStructureRow"))
        return true
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard isStructureTable(tableView), dropOperation == .above, row >= 0 else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row destinationRow: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard isStructureTable(tableView),
              let connection = connection,
              let sourceRowString = info.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("SequelAceLightweightStructureRow")),
              let displayedSourceRow = Int(sourceRowString),
              let sourceIndex = sourceIndex(forDisplayedRow: displayedSourceRow),
              sourceIndex >= 0,
              sourceIndex < rows.count else { return false }

        let movingRow = rows[sourceIndex]
        let destinationIndex = max(0, min(destinationRow, rows.count))
        var query = "ALTER TABLE \(Self.backtickQuoted(table)) MODIFY COLUMN \(columnDefinition(for: movingRow))"
        if destinationIndex == 0 {
            query += " FIRST"
        } else {
            let afterIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex - 1
            if afterIndex >= 0, afterIndex < rows.count {
                query += " AFTER \(Self.backtickQuoted(rows[afterIndex].name))"
            }
        }

        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            connection.queryString(query)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error, !error.isEmpty {
                    self.showError(title: NSLocalizedString("Error moving field", comment: "move field error title"), message: error)
                    return
                }

                self.loadStructure(for: self.table, database: self.database, connection: connection)
            }
        }

        return true
    }
}
