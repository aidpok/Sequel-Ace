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

    private weak var connection: SPMySQLConnection?
    private var database = ""
    private var table = ""
    private var columns: [String] = []
    private var rows: [[String]] = []
    private var filteredColumns: [Int] = []
    private var loadToken = UUID()
    private let rowLimit = 1_000

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

    private lazy var reloadButton = toolbarButton(title: "↻", action: #selector(reloadContent(_:)))

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

        rootView.addSubview(columnFilterField)
        rootView.addSubview(scrollView)
        rootView.addSubview(toolbarView)
        toolbarView.addSubview(reloadButton)
        toolbarView.addSubview(statusLabel)

        columnFilterField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            columnFilterField.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 4),
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

            reloadButton.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 2),
            reloadButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            reloadButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 28),

            statusLabel.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: toolbarView.trailingAnchor, constant: -8)
        ])

        view = rootView
    }

    func loadContent(for table: String, database: String, connection: SPMySQLConnection) {
        self.table = table
        self.database = database
        self.connection = connection
        loadToken = UUID()
        let token = loadToken

        columns = []
        rows = []
        filteredColumns = []
        rebuildColumns()
        statusLabel.stringValue = NSLocalizedString("Loading rows...", comment: "lightweight content loading rows")

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            _ = connection.selectDatabase(database)
            let query = "SELECT * FROM \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table)) LIMIT \(self.rowLimit)"
            let result = connection.queryString(query)
            result?.returnDataAsStrings = true
            result?.defaultRowReturnType = SPMySQLResultRowAsArray

            let fieldNames = result?.fieldNames() as? [String] ?? []
            var loadedRows: [[String]] = []

            while let row = result?.getRowAsArray() {
                loadedRows.append(row.map { Self.displayString(for: $0) })
            }

            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                guard self.loadToken == token else { return }

                if let error = error, !error.isEmpty {
                    self.columns = []
                    self.rows = []
                    self.filteredColumns = []
                    self.rebuildColumns()
                    self.statusLabel.stringValue = error
                    return
                }

                self.columns = fieldNames
                self.rows = loadedRows
                self.applyColumnFilter()
                self.rebuildColumns()
                self.statusLabel.stringValue = String(format: NSLocalizedString("%ld rows loaded", comment: "lightweight content row count"), loadedRows.count)
            }
        }
    }
}

private extension SALightweightContentViewController {
    @objc func columnFilterChanged(_ sender: NSSearchField) {
        applyColumnFilter()
        rebuildColumns()
    }

    @objc func reloadContent(_ sender: Any?) {
        guard let connection = connection else { return }
        loadContent(for: table, database: database, connection: connection)
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

            let cell = NSTextFieldCell(textCell: "")
            cell.isEditable = false
            cell.isSelectable = true
            cell.lineBreakMode = .byTruncatingTail
            cell.font = UserDefaults.getFont()
            tableColumn.dataCell = cell
            tableView.addTableColumn(tableColumn)
        }

        tableView.reloadData()
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
              columnIndex < rows[row].count else { return nil }

        return rows[row][columnIndex]
    }
}
