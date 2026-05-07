//
//  SALightweightContentViewController.swift
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

final class SALightweightContentViewController: NSViewController {

    private struct ColumnInfo {
        let name: String
        let isPrimary: Bool
        let isAutoIncrement: Bool
    }

    private struct ContentRow {
        var values: [String?]
        var originalValues: [String?]
    }

    private weak var connection: SPMySQLConnection?
    private var database = ""
    private var table = ""
    private var columns: [String] = []
    private var columnInfo: [ColumnInfo] = []
    private var rows: [ContentRow] = []
    private var filteredColumns: [Int] = []
    private var loadToken = UUID()
    private var pageIndex = 0
    private var hasNextPage = false
    private var isLoading = false
    private var sortColumn: String?
    private var sortAscending = true
    private var pageSize: Int {
        let preferredPageSize = UserDefaults.standard.integer(forKey: SPLimitResultsValue)
        return max(1, preferredPageSize > 0 ? preferredPageSize : 1_000)
    }

    private lazy var rowFilterField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = NSLocalizedString("Filter Rows", comment: "lightweight content row filter placeholder")
        field.target = self
        field.action = #selector(rowFilterChanged(_:))
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = true
        return field
    }()

    private lazy var columnFilterField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = NSLocalizedString("Filter Columns", comment: "lightweight content column filter placeholder")
        field.target = self
        field.action = #selector(columnFilterChanged(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }()

    private lazy var statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }()

    private lazy var addRowButton = toolbarButton(title: "+", action: #selector(addRow(_:)))
    private lazy var duplicateRowButton = toolbarButton(title: "⧉", action: #selector(duplicateRow(_:)))
    private lazy var deleteRowButton = toolbarButton(title: "−", action: #selector(deleteRows(_:)))
    private lazy var reloadButton = toolbarButton(title: "↻", action: #selector(reloadContent(_:)))
    private lazy var previousPageButton = toolbarButton(title: "‹", action: #selector(loadPreviousPage(_:)))
    private lazy var nextPageButton = toolbarButton(title: "›", action: #selector(loadNextPage(_:)))

    private lazy var pageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    private lazy var tableView: NSTableView = {
        let tableView = NSTableView(frame: .zero)
        tableView.identifier = NSUserInterfaceItemIdentifier("LightweightContentTable")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: UserDefaults.getFont()]).height
        return tableView
    }()

    override func loadView() {
        let rootView = NSView(frame: .zero)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView

        let toolbarView = NSView(frame: .zero)

        rootView.addSubview(rowFilterField)
        rootView.addSubview(columnFilterField)
        rootView.addSubview(scrollView)
        rootView.addSubview(toolbarView)
        toolbarView.addSubview(addRowButton)
        toolbarView.addSubview(duplicateRowButton)
        toolbarView.addSubview(deleteRowButton)
        toolbarView.addSubview(reloadButton)
        toolbarView.addSubview(previousPageButton)
        toolbarView.addSubview(pageLabel)
        toolbarView.addSubview(nextPageButton)
        toolbarView.addSubview(statusLabel)

        rowFilterField.translatesAutoresizingMaskIntoConstraints = false
        columnFilterField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        addRowButton.translatesAutoresizingMaskIntoConstraints = false
        duplicateRowButton.translatesAutoresizingMaskIntoConstraints = false
        deleteRowButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        previousPageButton.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        nextPageButton.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            rowFilterField.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 4),
            rowFilterField.trailingAnchor.constraint(equalTo: rootView.centerXAnchor, constant: -2),
            rowFilterField.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 4),
            rowFilterField.heightAnchor.constraint(equalToConstant: 24),

            columnFilterField.leadingAnchor.constraint(equalTo: rootView.centerXAnchor, constant: 2),
            columnFilterField.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -4),
            columnFilterField.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 4),
            columnFilterField.heightAnchor.constraint(equalToConstant: 24),

            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: columnFilterField.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: toolbarView.topAnchor),

            toolbarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            toolbarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 26),

            addRowButton.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 2),
            addRowButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            addRowButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            addRowButton.widthAnchor.constraint(equalToConstant: 28),

            duplicateRowButton.leadingAnchor.constraint(equalTo: addRowButton.trailingAnchor, constant: 4),
            duplicateRowButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            duplicateRowButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            duplicateRowButton.widthAnchor.constraint(equalToConstant: 28),

            deleteRowButton.leadingAnchor.constraint(equalTo: duplicateRowButton.trailingAnchor, constant: 4),
            deleteRowButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            deleteRowButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            deleteRowButton.widthAnchor.constraint(equalToConstant: 28),

            reloadButton.leadingAnchor.constraint(equalTo: deleteRowButton.trailingAnchor, constant: 8),
            reloadButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            reloadButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 28),

            previousPageButton.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 4),
            previousPageButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            previousPageButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            previousPageButton.widthAnchor.constraint(equalToConstant: 28),

            pageLabel.leadingAnchor.constraint(equalTo: previousPageButton.trailingAnchor, constant: 4),
            pageLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),

            nextPageButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 4),
            nextPageButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            nextPageButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            nextPageButton.widthAnchor.constraint(equalToConstant: 28),

            statusLabel.leadingAnchor.constraint(equalTo: nextPageButton.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: toolbarView.trailingAnchor, constant: -8)
        ])

        view = rootView
    }

    func loadContent(for table: String, database: String, connection: SPMySQLConnection) {
        self.table = table
        self.database = database
        self.connection = connection
        pageIndex = 0

        loadCurrentPage()
    }
}

private extension SALightweightContentViewController {
    func loadCurrentPage() {
        guard let connection = connection else { return }

        loadToken = UUID()
        let token = loadToken
        let pageSize = self.pageSize
        let offset = pageIndex * pageSize

        isLoading = true
        columns = []
        columnInfo = []
        rows = []
        filteredColumns = []
        hasNextPage = false
        rebuildColumns()
        statusLabel.stringValue = NSLocalizedString("Loading rows...", comment: "lightweight content loading rows")
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            _ = connection.selectDatabase(self.database)
            let columnInfo = self.loadColumnInfo(connection: connection)
            let query = self.contentQuery(offset: offset, limit: pageSize + 1, columnInfo: columnInfo, connection: connection)
            let result = connection.queryString(query)
            result?.returnDataAsStrings = true
            result?.defaultRowReturnType = SPMySQLResultRowAsArray

            let fieldNames = result?.fieldNames() as? [String] ?? []
            var loadedRows: [ContentRow] = []

            while let row = result?.getRowAsArray() {
                let values = row.map { Self.stringValue(for: $0) }
                loadedRows.append(ContentRow(values: values, originalValues: values))
            }

            let hasNextPage = loadedRows.count > pageSize
            if hasNextPage {
                loadedRows.removeLast()
            }

            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                guard self.loadToken == token else { return }

                self.isLoading = false

                if let error = error, !error.isEmpty {
                    self.columns = []
                    self.columnInfo = []
                    self.rows = []
                    self.filteredColumns = []
                    self.hasNextPage = false
                    self.rebuildColumns()
                    self.statusLabel.stringValue = error
                    self.updateControls()
                    return
                }

                self.columns = fieldNames
                self.columnInfo = Self.orderedColumnInfo(columnInfo, fieldNames: fieldNames)
                self.rows = loadedRows
                self.hasNextPage = hasNextPage
                self.applyColumnFilter()
                self.rebuildColumns()
                self.updateStatus()
                self.updateControls()
            }
        }
    }

    private func contentQuery(offset: Int, limit: Int, columnInfo: [ColumnInfo], connection: SPMySQLConnection) -> String {
        var query = "SELECT * FROM \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table))"

        if let whereClause = rowFilterWhereClause(columnInfo: columnInfo, connection: connection) {
            query += " WHERE \(whereClause)"
        }

        if let sortColumn = sortColumn {
            query += " ORDER BY \(Self.backtickQuoted(sortColumn)) \(sortAscending ? "ASC" : "DESC")"
        }

        query += " LIMIT \(offset),\(limit)"
        return query
    }

    private func loadColumnInfo(connection: SPMySQLConnection) -> [ColumnInfo] {
        let result = connection.queryString("SHOW FULL COLUMNS FROM \(Self.backtickQuoted(table)) FROM \(Self.backtickQuoted(database))")
        result?.returnDataAsStrings = true
        result?.defaultRowReturnType = SPMySQLResultRowAsDictionary

        var loadedColumns: [ColumnInfo] = []
        while let row = result?.getRowAsDictionary() as? [String: Any] {
            let name = Self.displayString(for: row["Field"])
            let key = Self.displayString(for: row["Key"]).uppercased()
            let extra = Self.displayString(for: row["Extra"]).lowercased()
            loadedColumns.append(ColumnInfo(name: name, isPrimary: key == "PRI", isAutoIncrement: extra.contains("auto_increment")))
        }

        return loadedColumns
    }

    private static func orderedColumnInfo(_ columnInfo: [ColumnInfo], fieldNames: [String]) -> [ColumnInfo] {
        return fieldNames.map { fieldName in
            columnInfo.first { $0.name == fieldName } ?? ColumnInfo(name: fieldName, isPrimary: false, isAutoIncrement: false)
        }
    }

    private func rowFilterWhereClause(columnInfo: [ColumnInfo], connection: SPMySQLConnection) -> String? {
        let filter = rowFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return nil }

        let escapedFilter = Self.quotedLikePattern(filter, connection: connection)
        guard !escapedFilter.isEmpty else { return nil }

        let searchableColumns = columnInfo.map { $0.name }
        guard !searchableColumns.isEmpty else { return nil }

        return searchableColumns.map { "\(Self.backtickQuoted($0)) LIKE \(escapedFilter)" }.joined(separator: " OR ")
    }

    @objc func rowFilterChanged(_ sender: NSSearchField) {
        guard !isLoading else { return }

        pageIndex = 0
        loadCurrentPage()
    }

    @objc func columnFilterChanged(_ sender: NSSearchField) {
        applyColumnFilter()
        rebuildColumns()
    }

    @objc func reloadContent(_ sender: Any?) {
        loadCurrentPage()
    }

    @objc func loadPreviousPage(_ sender: Any?) {
        guard pageIndex > 0, !isLoading else { return }

        pageIndex -= 1
        loadCurrentPage()
    }

    @objc func loadNextPage(_ sender: Any?) {
        guard hasNextPage, !isLoading else { return }

        pageIndex += 1
        loadCurrentPage()
    }

    @objc func addRow(_ sender: Any?) {
        guard connection != nil, !isLoading else { return }

        runMutation(status: NSLocalizedString("Adding row...", comment: "lightweight content adding row")) { [database, table] connection in
            let query = "INSERT INTO \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table)) () VALUES ()"
            _ = connection.queryString(query)
        }
    }

    @objc func duplicateRow(_ sender: Any?) {
        guard connection != nil, !isLoading else { return }

        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < rows.count else { return }

        let row = rows[selectedRow]
        let columnsToInsert = columnInfo.enumerated().filter { !$0.element.isAutoIncrement }
        guard !columnsToInsert.isEmpty else {
            addRow(sender)
            return
        }

        runMutation(status: NSLocalizedString("Duplicating row...", comment: "lightweight content duplicating row")) { [database, table] connection in
            let columnList = columnsToInsert.map { Self.backtickQuoted($0.element.name) }.joined(separator: ", ")
            let valueList = columnsToInsert.map { Self.sqlValue(row.values[$0.offset], connection: connection) }.joined(separator: ", ")
            let query = "INSERT INTO \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table)) (\(columnList)) VALUES (\(valueList))"
            _ = connection.queryString(query)
        }
    }

    @objc func deleteRows(_ sender: Any?) {
        guard connection != nil, !isLoading else { return }

        let selectedIndexes = tableView.selectedRowIndexes
        guard !selectedIndexes.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = selectedIndexes.count == 1
            ? NSLocalizedString("Delete selected row?", comment: "delete selected row message")
            : NSLocalizedString("Delete rows?", comment: "delete rows message")
        alert.informativeText = NSLocalizedString("This action cannot be undone.", comment: "delete rows informative text")
        alert.addButton(withTitle: selectedIndexes.count == 1
            ? NSLocalizedString("Delete Selected Row", comment: "delete selected row button")
            : NSLocalizedString("Delete Selected Rows", comment: "delete selected rows button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let rowsToDelete = selectedIndexes.compactMap { index in index < rows.count ? rows[index] : nil }
        runMutation(status: NSLocalizedString("Deleting rows...", comment: "lightweight content deleting rows")) { [database, table, columnInfo] connection in
            for row in rowsToDelete {
                guard let whereClause = Self.rowIdentityWhereClause(for: row.originalValues, columnInfo: columnInfo, connection: connection) else { continue }
                let limit = columnInfo.contains { $0.isPrimary } ? "" : " LIMIT 1"
                let query = "DELETE FROM \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table)) WHERE \(whereClause)\(limit)"
                _ = connection.queryString(query)
                if connection.queryErrored() { break }
            }
        }
    }

    func runMutation(status: String, mutation: @escaping (SPMySQLConnection) -> Void) {
        guard let connection = connection else { return }

        statusLabel.stringValue = status
        isLoading = true
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            _ = connection.selectDatabase(self.database)
            mutation(connection)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error, !error.isEmpty {
                    self.statusLabel.stringValue = error
                    self.updateControls()
                    return
                }

                self.loadCurrentPage()
            }
        }
    }

    func applyColumnFilter() {
        let filter = columnFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !filter.isEmpty else {
            filteredColumns = Array(columns.indices)
            return
        }

        filteredColumns = columns.indices.filter { index in
            columns[index].range(of: filter, options: .caseInsensitive) != nil
        }
    }

    func rebuildColumns() {
        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }

        for columnIndex in filteredColumns {
            let columnName = columns[columnIndex]
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(columnIndex)"))
            tableColumn.title = columnName
            tableColumn.width = max(90, min(260, CGFloat(columnName.count * 9 + 32)))
            tableColumn.minWidth = 40
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: "\(columnIndex)", ascending: true)

            let cell = NSTextFieldCell(textCell: "")
            cell.isEditable = true
            cell.isSelectable = true
            cell.lineBreakMode = .byTruncatingTail
            cell.font = UserDefaults.getFont()
            tableColumn.dataCell = cell
            tableView.addTableColumn(tableColumn)
        }

        tableView.reloadData()
    }

    func updateStatus() {
        guard !rows.isEmpty else {
            statusLabel.stringValue = NSLocalizedString("No rows", comment: "lightweight content no rows")
            return
        }

        let start = pageIndex * pageSize + 1
        let end = start + rows.count - 1
        statusLabel.stringValue = String(format: NSLocalizedString("Rows %ld-%ld loaded", comment: "lightweight content row range"), start, end)
    }

    func updateControls() {
        addRowButton.isEnabled = !isLoading
        duplicateRowButton.isEnabled = !isLoading && tableView.numberOfSelectedRows == 1
        deleteRowButton.isEnabled = !isLoading && tableView.numberOfSelectedRows > 0
        reloadButton.isEnabled = !isLoading
        previousPageButton.isEnabled = !isLoading && pageIndex > 0
        nextPageButton.isEnabled = !isLoading && hasNextPage
        pageLabel.stringValue = String(format: NSLocalizedString("Page %ld", comment: "lightweight content page label"), pageIndex + 1)
    }

    func toolbarButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 15)
        return button
    }

    static func displayString(for value: Any) -> String {
        if value is NSNull {
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        return String(describing: value)
    }

    static func stringValue(for value: Any) -> String? {
        if value is NSNull {
            return nil
        }

        return String(describing: value)
    }

    static func displayString(for value: Any?) -> String {
        guard let value = value else {
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        return displayString(for: value)
    }

    static func sqlValue(_ value: String?, connection: SPMySQLConnection) -> String {
        guard let value = value else { return "NULL" }

        return connection.escapeAndQuoteString(value) ?? "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    static func quotedLikePattern(_ value: String, connection: SPMySQLConnection) -> String {
        let escapedValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return sqlValue("%\(escapedValue)%", connection: connection)
    }

    private static func rowIdentityWhereClause(for values: [String?], columnInfo: [ColumnInfo], connection: SPMySQLConnection) -> String? {
        let primaryColumns = columnInfo.enumerated().filter { $0.element.isPrimary }
        let identityColumns = primaryColumns.isEmpty ? Array(columnInfo.enumerated()) : primaryColumns

        guard !identityColumns.isEmpty else { return nil }

        let parts = identityColumns.compactMap { index, column -> String? in
            guard index < values.count else { return nil }

            if values[index] == nil {
                return "\(backtickQuoted(column.name)) IS NULL"
            }

            return "\(backtickQuoted(column.name)) = \(sqlValue(values[index], connection: connection))"
        }

        guard !parts.isEmpty else { return nil }

        return parts.joined(separator: " AND ")
    }

    static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }
}

extension SALightweightContentViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0,
              row < rows.count,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].values.count else { return nil }

        return SALightweightContentViewController.displayString(for: rows[row].values[columnIndex])
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard row >= 0,
              row < rows.count,
              let connection = connection,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].values.count,
              columnIndex < columnInfo.count,
              !isLoading else { return }

        let oldRowValues = rows[row].originalValues
        let newValue = String(describing: object ?? "")
        guard newValue != rows[row].values[columnIndex] else { return }

        guard let whereClause = Self.rowIdentityWhereClause(for: oldRowValues, columnInfo: columnInfo, connection: connection) else {
            statusLabel.stringValue = NSLocalizedString("Cannot edit row without identifiable columns", comment: "lightweight content edit no identity")
            return
        }

        let columnName = columnInfo[columnIndex].name
        let limit = columnInfo.contains { $0.isPrimary } ? "" : " LIMIT 1"
        let query = "UPDATE \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table)) SET \(Self.backtickQuoted(columnName)) = \(Self.sqlValue(newValue, connection: connection)) WHERE \(whereClause)\(limit)"

        statusLabel.stringValue = NSLocalizedString("Saving cell...", comment: "lightweight content saving cell")
        isLoading = true
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            _ = connection.selectDatabase(self.database)
            _ = connection.queryString(query)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error, !error.isEmpty {
                    self.statusLabel.stringValue = error
                    self.updateControls()
                    self.tableView.reloadData()
                    return
                }

                self.rows[row].values[columnIndex] = newValue
                self.rows[row].originalValues[columnIndex] = newValue
                self.updateStatus()
                self.updateControls()
                self.tableView.reloadData()
            }
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateControls()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isLoading, let descriptor = tableView.sortDescriptors.first, let key = descriptor.key, let columnIndex = Int(key), columnIndex < columns.count else { return }

        sortColumn = columns[columnIndex]
        sortAscending = descriptor.ascending
        pageIndex = 0
        loadCurrentPage()
    }
}
