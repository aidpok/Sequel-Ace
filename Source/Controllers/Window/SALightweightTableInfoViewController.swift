//
//  SALightweightTableInfoViewController.swift
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

struct SALightweightTableInfoRow {
    let label: String
    let value: String
    let isGroup: Bool

    init(_ label: String, value: String = "", isGroup: Bool = false) {
        self.label = label
        self.value = value
        self.isGroup = isGroup
    }
}

struct SALightweightTableInfoSnapshot {
    let rows: [SALightweightTableInfoRow]
    let createSyntax: String?
}

enum SALightweightTableInfoLoader {
    static func sidebarRows(for table: String, database: String, connection: SPMySQLConnection) -> [String] {
        guard var tableStatus = tableStatusValues(for: table, database: database, connection: connection) else {
            return [
                NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane"),
                NSLocalizedString("error occurred", comment: "error occurred")
            ]
        }

        let tableType = objectType(for: table, database: database, status: tableStatus, connection: connection)
        var rows = [tableType.headerTitle]

        if tableType == .view {
            rows.append(contentsOf: compactViewRows(for: table, database: database, connection: connection))
            return rows
        }

        addCompactDateRow(key: "Create_time", label: NSLocalizedString("created", comment: "Table Info Section : time+date table was created at"), status: tableStatus, rows: &rows)
        addCompactDateRow(key: "Update_time", label: NSLocalizedString("updated", comment: "updated"), status: tableStatus, rows: &rows)
        addCompactStringRow(key: "Engine", label: NSLocalizedString("engine", comment: "Table Info Section : Table Engine"), status: tableStatus, rows: &rows)

        if displayString(tableStatus["Rows"]) == nil, let rowCount = rowCount(for: table, database: database, connection: connection) {
            tableStatus["Rows"] = rowCount
            tableStatus["RowsCountAccurate"] = "y"
        }

        if let rowCount = integerString(tableStatus["Rows"]) {
            let accurate = displayString(tableStatus["RowsCountAccurate"]) == "y"
            let label = accurate
                ? NSLocalizedString("rows", comment: "Table Info Section : number of rows (exact value)")
                : NSLocalizedString("rows", comment: "Table Info Section : number of rows (estimated value)")
            rows.append("\(label): \(accurate ? rowCount : "~\(rowCount)")")
        }

        if let dataLength = integerValue(tableStatus["Data_length"]) {
            rows.append(String(format: NSLocalizedString("size: %@", comment: "Table Info Section : table size on disk"), ByteCountFormatter.string(byteSize: dataLength)))
        }

        if let collation = displayString(tableStatus["Collation"]) {
            let encoding = encodingName(from: collation)
            let displayCollation = collation.hasPrefix("\(encoding)_") ? String(collation.dropFirst(encoding.count + 1)) : collation
            rows.append(String(format: NSLocalizedString("encoding: %1$@ (%2$@)", comment: "Table Info Section : $1 = table charset, $2 = table collation"), encoding, displayCollation))
        }

        if let autoIncrement = integerString(tableStatus["Auto_increment"]) {
            rows.append(String(format: NSLocalizedString("auto_increment: %@", comment: "Table Info Section : current value of auto_increment"), autoIncrement))
        }

        return rows
    }

    static func tableInfo(for table: String, database: String, connection: SPMySQLConnection, includeCreateSyntax: Bool = true) -> SALightweightTableInfoSnapshot {
        guard var tableStatus = tableStatusValues(for: table, database: database, connection: connection) else {
            return SALightweightTableInfoSnapshot(rows: [
                SALightweightTableInfoRow(NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane"), isGroup: true),
                SALightweightTableInfoRow(NSLocalizedString("error occurred", comment: "error occurred"))
            ], createSyntax: nil)
        }

        let tableType = objectType(for: table, database: database, status: tableStatus, connection: connection)
        var rows = [SALightweightTableInfoRow(tableType.headerTitle, isGroup: true)]

        if tableType == .view {
            addViewRows(for: table, database: database, connection: connection, rows: &rows)
            addCommentRow(tableStatus: tableStatus, rows: &rows)

            let createSyntax = includeCreateSyntax ? createSyntax(for: table, database: database, connection: connection) : nil
            return SALightweightTableInfoSnapshot(rows: rows, createSyntax: createSyntax)
        }

        addDateRow(key: "Create_time", label: NSLocalizedString("created", comment: "Table Info Section : time+date table was created at"), status: tableStatus, rows: &rows)
        addDateRow(key: "Update_time", label: NSLocalizedString("updated", comment: "updated"), status: tableStatus, rows: &rows)
        addStringRow(key: "Engine", label: NSLocalizedString("engine", comment: "Table Info Section : Table Engine"), status: tableStatus, rows: &rows)

        if displayString(tableStatus["Rows"]) == nil, let rowCount = rowCount(for: table, database: database, connection: connection) {
            tableStatus["Rows"] = rowCount
            tableStatus["RowsCountAccurate"] = "y"
        }

        if let rowCount = integerString(tableStatus["Rows"]) {
            let accurate = displayString(tableStatus["RowsCountAccurate"]) == "y"
            rows.append(SALightweightTableInfoRow(accurate
                ? NSLocalizedString("rows", comment: "Table Info Section : number of rows (exact value)")
                : NSLocalizedString("rows", comment: "Table Info Section : number of rows (estimated value)"), value: accurate ? rowCount : "~\(rowCount)"))
        }

        addStringRow(key: "Row_format", label: NSLocalizedString("row format", comment: "Table Info Section : row format"), status: tableStatus, rows: &rows)
        addIntegerRow(key: "Avg_row_length", label: NSLocalizedString("average row length", comment: "Table Info Section : average row length"), status: tableStatus, rows: &rows)
        addIntegerRow(key: "Auto_increment", label: NSLocalizedString("auto_increment", comment: "Table Info Section : current value of auto_increment"), status: tableStatus, rows: &rows)

        addByteRow(key: "Data_length", label: NSLocalizedString("data size", comment: "Table Info Section : table data size"), status: tableStatus, rows: &rows)
        addByteRow(key: "Index_length", label: NSLocalizedString("index size", comment: "Table Info Section : table index size"), status: tableStatus, rows: &rows)
        addByteRow(key: "Data_free", label: NSLocalizedString("free size", comment: "Table Info Section : table free size"), status: tableStatus, rows: &rows)
        addByteRow(key: "Max_data_length", label: NSLocalizedString("max data size", comment: "Table Info Section : max data size"), status: tableStatus, rows: &rows)
        addTotalSizeRow(tableStatus: tableStatus, rows: &rows)
        addEncodingRows(tableStatus: tableStatus, rows: &rows)
        addStringRow(key: "Create_options", label: NSLocalizedString("create_options", comment: "Table Info Section : Table Create Options"), status: tableStatus, rows: &rows)
        addCommentRow(tableStatus: tableStatus, rows: &rows)

        let createSyntax = includeCreateSyntax ? createSyntax(for: table, database: database, connection: connection) : nil
        return SALightweightTableInfoSnapshot(rows: rows, createSyntax: createSyntax)
    }

    private static func addViewRows(for table: String, database: String, connection: SPMySQLConnection, rows: inout [SALightweightTableInfoRow]) {
        let query = """
            SELECT DEFINER, SECURITY_TYPE, IS_UPDATABLE, CHECK_OPTION, CHARACTER_SET_CLIENT, COLLATION_CONNECTION \
            FROM information_schema.VIEWS \
            WHERE TABLE_SCHEMA = \(sqlString(database, connection: connection)) AND TABLE_NAME = \(sqlString(table, connection: connection))
            """
        guard let result = connection.queryString(query) else { return }

        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let viewStatus = result.getRowAsDictionary() as? [String: Any], !viewStatus.isEmpty else { return }

        addStringRow(key: "DEFINER", label: NSLocalizedString("definer", comment: "definer: %@"), status: viewStatus, rows: &rows)
        addStringRow(key: "SECURITY_TYPE", label: NSLocalizedString("execution privilege", comment: "execution privilege: %@"), status: viewStatus, rows: &rows)
        addStringRow(key: "IS_UPDATABLE", label: NSLocalizedString("is updatable", comment: "is updatable: %@"), status: viewStatus, rows: &rows)
        addStringRow(key: "CHECK_OPTION", label: NSLocalizedString("check option", comment: "check option: %@"), status: viewStatus, rows: &rows)
        addStringRow(key: "CHARACTER_SET_CLIENT", label: NSLocalizedString("character set client", comment: "character set client: %@"), status: viewStatus, rows: &rows)
        addStringRow(key: "COLLATION_CONNECTION", label: NSLocalizedString("collation connection", comment: "collation connection: %@"), status: viewStatus, rows: &rows)
    }

    private static func compactViewRows(for table: String, database: String, connection: SPMySQLConnection) -> [String] {
        let query = """
            SELECT DEFINER, SECURITY_TYPE, IS_UPDATABLE, CHECK_OPTION, CHARACTER_SET_CLIENT, COLLATION_CONNECTION \
            FROM information_schema.VIEWS \
            WHERE TABLE_SCHEMA = \(sqlString(database, connection: connection)) AND TABLE_NAME = \(sqlString(table, connection: connection))
            """
        guard let result = connection.queryString(query) else { return [] }

        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let viewStatus = result.getRowAsDictionary() as? [String: Any], !viewStatus.isEmpty else { return [] }

        var rows: [String] = []
        addCompactStringRow(key: "DEFINER", label: NSLocalizedString("definer", comment: "definer: %@"), status: viewStatus, rows: &rows)
        addCompactStringRow(key: "SECURITY_TYPE", label: NSLocalizedString("execution privilege", comment: "execution privilege: %@"), status: viewStatus, rows: &rows)
        addCompactStringRow(key: "IS_UPDATABLE", label: NSLocalizedString("is updatable", comment: "is updatable: %@"), status: viewStatus, rows: &rows)
        addCompactStringRow(key: "CHECK_OPTION", label: NSLocalizedString("check option", comment: "check option: %@"), status: viewStatus, rows: &rows)
        addCompactStringRow(key: "CHARACTER_SET_CLIENT", label: NSLocalizedString("character set client", comment: "character set client: %@"), status: viewStatus, rows: &rows)
        addCompactStringRow(key: "COLLATION_CONNECTION", label: NSLocalizedString("collation connection", comment: "collation connection: %@"), status: viewStatus, rows: &rows)
        return rows
    }

    private static func addDateRow(key: String, label: String, status: [String: Any], rows: inout [SALightweightTableInfoRow]) {
        guard let rawValue = displayString(status[key]) else { return }

        let formattedValue: String
        if let date = DateFormatter.naturalLanguageFormatter.date(from: rawValue) {
            formattedValue = DateFormatter.shortStyleFormatter.string(from: date)
        } else {
            formattedValue = rawValue
        }

        rows.append(SALightweightTableInfoRow(label, value: formattedValue))
    }

    private static func addStringRow(key: String, label: String, status: [String: Any], rows: inout [SALightweightTableInfoRow]) {
        guard let value = displayString(status[key]) else { return }
        rows.append(SALightweightTableInfoRow(label, value: value))
    }

    private static func addCompactDateRow(key: String, label: String, status: [String: Any], rows: inout [String]) {
        guard let rawValue = displayString(status[key]) else { return }

        let formattedValue: String
        if let date = DateFormatter.naturalLanguageFormatter.date(from: rawValue) {
            formattedValue = DateFormatter.shortStyleFormatter.string(from: date)
        } else {
            formattedValue = rawValue
        }

        rows.append("\(label): \(formattedValue)")
    }

    private static func addCompactStringRow(key: String, label: String, status: [String: Any], rows: inout [String]) {
        guard let value = displayString(status[key]) else { return }
        rows.append("\(label): \(value)")
    }

    private static func addIntegerRow(key: String, label: String, status: [String: Any], rows: inout [SALightweightTableInfoRow]) {
        guard let value = integerString(status[key]) else { return }
        rows.append(SALightweightTableInfoRow(label, value: value))
    }

    private static func addByteRow(key: String, label: String, status: [String: Any], rows: inout [SALightweightTableInfoRow]) {
        guard let value = integerValue(status[key]) else { return }
        rows.append(SALightweightTableInfoRow(label, value: ByteCountFormatter.string(byteSize: value) as String))
    }

    private static func addTotalSizeRow(tableStatus: [String: Any], rows: inout [SALightweightTableInfoRow]) {
        let totalSize = (integerValue(tableStatus["Data_length"]) ?? 0) + (integerValue(tableStatus["Index_length"]) ?? 0)
        guard totalSize > 0 else { return }
        rows.append(SALightweightTableInfoRow(NSLocalizedString("total size", comment: "Table Info Section : total table size"), value: ByteCountFormatter.string(byteSize: totalSize) as String))
    }

    private static func addEncodingRows(tableStatus: [String: Any], rows: inout [SALightweightTableInfoRow]) {
        guard let collation = displayString(tableStatus["Collation"]) else { return }

        let encoding = encodingName(from: collation)
        let displayCollation = collation.hasPrefix("\(encoding)_") ? String(collation.dropFirst(encoding.count + 1)) : collation
        rows.append(SALightweightTableInfoRow(NSLocalizedString("encoding", comment: "Table Info Section : table charset"), value: encoding))
        rows.append(SALightweightTableInfoRow(NSLocalizedString("collation", comment: "Table Info Section : table collation"), value: displayCollation))
    }

    private static func addCommentRow(tableStatus: [String: Any], rows: inout [SALightweightTableInfoRow]) {
        guard let comment = displayString(tableStatus["Comment"]), comment != "VIEW" else { return }
        rows.append(SALightweightTableInfoRow(NSLocalizedString("comment", comment: "Table Info Section : table comment"), value: comment))
    }

    private static func tableStatusValues(for table: String, database: String, connection: SPMySQLConnection) -> [String: Any]? {
        let query = "SHOW TABLE STATUS FROM \(backtickQuoted(database)) WHERE Name = \(sqlString(table, connection: connection))"
        guard let result = connection.queryString(query) else { return nil }

        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard var tableStatus = result.getRowAsDictionary() as? [String: Any], !tableStatus.isEmpty else { return nil }

        if tableStatus["Engine"] == nil, let type = tableStatus["Type"] {
            tableStatus["Engine"] = type
        }

        tableStatus["RowsCountAccurate"] = displayString(tableStatus["Engine"]) == "MyISAM" ? "y" : "n"
        return tableStatus
    }

    private static func objectType(for table: String, database: String, status: [String: Any], connection: SPMySQLConnection) -> SALightweightTableInfoObjectType {
        if displayString(status["Comment"]) == "VIEW" || displayString(status["Engine"]) == "View" {
            return .view
        }

        let query = """
            SELECT TABLE_TYPE FROM information_schema.TABLES \
            WHERE TABLE_SCHEMA = \(sqlString(database, connection: connection)) AND TABLE_NAME = \(sqlString(table, connection: connection))
            """
        guard let result = connection.queryString(query) else { return .table }

        result.defaultRowReturnType = SPMySQLResultRowAsArray
        guard
              let row = result.getRowAsArray() as? [Any],
              let tableType = displayString(row.first),
              tableType.uppercased().contains("VIEW") else { return .table }

        return .view
    }

    private static func rowCount(for table: String, database: String, connection: SPMySQLConnection) -> String? {
        let query = "SELECT COUNT(1) FROM \(backtickQuoted(database)).\(backtickQuoted(table))"
        guard let result = connection.queryString(query),
              let row = result.getRowAsArray() as? [Any],
              let value = row.first else { return nil }

        return displayString(value)
    }

    static func createSyntax(for table: String, database: String, connection: SPMySQLConnection) -> String? {
        let query = "SHOW CREATE TABLE \(backtickQuoted(database)).\(backtickQuoted(table))"
        guard let result = connection.queryString(query) else { return nil }

        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return nil }

        let syntaxKeys = ["Create Table", "Create View"]
        for key in syntaxKeys {
            if let syntax = displayString(row[key]) {
                return syntax.hasSuffix(";") ? syntax : "\(syntax);"
            }
        }

        for (key, value) in row where key.lowercased().contains("create") {
            if let syntax = displayString(value) {
                return syntax.hasSuffix(";") ? syntax : "\(syntax);"
            }
        }

        return nil
    }

    private static func integerString(_ value: Any?) -> String? {
        guard let integer = integerValue(value) else { return nil }
        return NumberFormatter.decimalStyleFormatter.string(from: NSNumber(value: integer))
    }

    private static func integerValue(_ value: Any?) -> Int64? {
        guard let displayValue = displayString(value) else { return nil }
        return Int64(displayValue)
    }

    private static func displayString(_ value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }

        let stringValue = String(describing: value)
        return stringValue.isEmpty ? nil : stringValue
    }

    private static func encodingName(from collation: String) -> String {
        if collation.hasPrefix("utf8mb4_") {
            return "utf8mb4"
        }
        if collation.hasPrefix("utf8_") {
            return "utf8"
        }

        return collation.components(separatedBy: "_").first ?? collation
    }

    private static func sqlString(_ value: String, connection: SPMySQLConnection) -> String {
        return connection.escapeAndQuoteString(value) ?? "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }
}

private enum SALightweightTableInfoObjectType {
    case table
    case view

    var headerTitle: String {
        switch self {
        case .table:
            return NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane")
        case .view:
            return NSLocalizedString("VIEW INFORMATION", comment: "header for view info pane")
        }
    }
}

final class SALightweightTableInfoViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var loadToken = UUID()
    private var rows: [SALightweightTableInfoRow] = []
    private var didRegisterPreferenceObservers = false

    private let tableContainerView = NSView(frame: .zero)
    private let syntaxContainerView = NSView(frame: .zero)
    private let tableScrollView = NSScrollView(frame: .zero)
    private let syntaxScrollView = NSScrollView(frame: .zero)

    private lazy var placeholderLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }()

    private lazy var splitView: NSSplitView = {
        let splitView = NSSplitView(frame: .zero)
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        return splitView
    }()

    private lazy var tableView: NSTableView = {
        let tableView = NSTableView(frame: .zero)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.backgroundColor = .controlBackgroundColor
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = Self.tableRowHeight(for: UserDefaults.getFont())
        if #available(macOS 11.0, *) {
            tableView.style = .plain
        }

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = NSLocalizedString("Name", comment: "table info name column")
        nameColumn.width = 185
        nameColumn.minWidth = 110
        nameColumn.resizingMask = .autoresizingMask
        let nameCell = SPTableTextFieldCell(textCell: "")
        nameCell.isEditable = false
        nameCell.isSelectable = false
        nameCell.font = UserDefaults.getFont()
        nameColumn.dataCell = nameCell
        tableView.addTableColumn(nameColumn)

        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.title = NSLocalizedString("Value", comment: "table info value column")
        valueColumn.width = 420
        valueColumn.minWidth = 180
        valueColumn.resizingMask = .autoresizingMask
        let valueCell = SPTableTextFieldCell(textCell: "")
        valueCell.lineBreakMode = .byTruncatingTail
        valueCell.isEditable = false
        valueCell.isSelectable = true
        valueCell.font = UserDefaults.getFont()
        valueColumn.dataCell = valueCell
        tableView.addTableColumn(valueColumn)

        return tableView
    }()

    private lazy var syntaxLabel: NSTextField = {
        let label = NSTextField(labelWithString: NSLocalizedString("Create syntax:", comment: "table info create syntax label"))
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .controlTextColor
        return label
    }()

    private lazy var syntaxTextView: NSTextView = {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = UserDefaults.getFont()
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        return textView
    }()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        tableScrollView.borderType = .noBorder
        tableScrollView.focusRingType = .none
        tableScrollView.hasVerticalScroller = true
        tableScrollView.hasHorizontalScroller = true
        tableScrollView.autohidesScrollers = true
        tableScrollView.contentView.drawsBackground = false
        tableScrollView.documentView = tableView

        syntaxScrollView.focusRingType = .none
        syntaxScrollView.hasVerticalScroller = true
        syntaxScrollView.hasHorizontalScroller = false
        syntaxScrollView.autohidesScrollers = true
        syntaxScrollView.documentView = syntaxTextView

        tableContainerView.addSubview(tableScrollView)
        syntaxContainerView.addSubview(syntaxLabel)
        syntaxContainerView.addSubview(syntaxScrollView)
        splitView.addArrangedSubview(tableContainerView)
        splitView.addArrangedSubview(syntaxContainerView)
        splitView.frame = view.bounds.insetBy(dx: 12, dy: 30)
        splitView.autoresizingMask = [.width, .height]
        view.addSubview(splitView)

        tableScrollView.translatesAutoresizingMaskIntoConstraints = false
        syntaxLabel.translatesAutoresizingMaskIntoConstraints = false
        syntaxScrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tableScrollView.leadingAnchor.constraint(equalTo: tableContainerView.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: tableContainerView.trailingAnchor),
            tableScrollView.topAnchor.constraint(equalTo: tableContainerView.topAnchor),
            tableScrollView.bottomAnchor.constraint(equalTo: tableContainerView.bottomAnchor),

            syntaxLabel.leadingAnchor.constraint(equalTo: syntaxContainerView.leadingAnchor, constant: 3),
            syntaxLabel.topAnchor.constraint(equalTo: syntaxContainerView.topAnchor, constant: 7),
            syntaxLabel.widthAnchor.constraint(equalToConstant: 101),

            syntaxScrollView.leadingAnchor.constraint(equalTo: syntaxContainerView.leadingAnchor, constant: 109),
            syntaxScrollView.trailingAnchor.constraint(equalTo: syntaxContainerView.trailingAnchor),
            syntaxScrollView.topAnchor.constraint(equalTo: syntaxContainerView.topAnchor),
            syntaxScrollView.bottomAnchor.constraint(equalTo: syntaxContainerView.bottomAnchor)
        ])
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
        if keyPath == SPDisplayTableViewVerticalGridlines || keyPath == SPGlobalFontSettings {
            applyTablePreferences()
            return
        }

        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        if splitView.arrangedSubviews.count == 2, splitView.arrangedSubviews[1].frame.height < 160 {
            splitView.setPosition(max(120, splitView.bounds.height - 200), ofDividerAt: 0)
        }
    }

    func showPlaceholder(_ message: String) {
        loadToken = UUID()
        rows = []
        tableView.reloadData()
        syntaxTextView.string = ""
        splitView.isHidden = true

        placeholderLabel.stringValue = message
        placeholderLabel.frame = NSRect(x: 20, y: max(0, (view.bounds.height - 60) / 2), width: max(0, view.bounds.width - 40), height: 60)
        placeholderLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        if placeholderLabel.superview == nil {
            view.addSubview(placeholderLabel)
        }
    }

    func loadTableInfo(for table: String, database: String, connection: SPMySQLConnection) {
        loadToken = UUID()
        let token = loadToken

        placeholderLabel.removeFromSuperviewWithoutNeedingDisplay()
        splitView.isHidden = false
        rows = [
            SALightweightTableInfoRow(NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane"), isGroup: true),
            SALightweightTableInfoRow(NSLocalizedString("loading...", comment: "table info loading row"))
        ]
        syntaxTextView.string = ""
        tableView.reloadData()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            let snapshot = SALightweightTableInfoLoader.tableInfo(for: table, database: database, connection: connection)

            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                self.rows = snapshot.rows
                self.syntaxTextView.string = snapshot.createSyntax ?? ""
                self.tableView.reloadData()
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0, row < rows.count else { return nil }
        let item = rows[row]

        if tableColumn?.identifier.rawValue == "value" {
            return item.isGroup ? "" : item.value
        }

        return item.label
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard row >= 0, row < rows.count else { return false }
        return rows[row].isGroup
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < rows.count else { return tableView.rowHeight }
        return rows[row].isGroup ? 25 : tableView.rowHeight
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard let cell = cell as? SPTableTextFieldCell, row >= 0, row < rows.count else { return }

        cell.font = rows[row].isGroup ? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize) : UserDefaults.getFont()
        cell.setIndentationLevel(0)
        cell.setNote("")
        cell.image = !rows[row].isGroup && tableColumn?.identifier.rawValue == "name" ? NSImage(named: "table-property") : nil
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

        syntaxTextView.font = tableFont
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
