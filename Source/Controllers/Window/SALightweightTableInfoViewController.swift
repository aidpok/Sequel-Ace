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
    let objectType: SALightweightTableInfoObjectType
    let values: [String: String]
    let engineOptions: [String]
    let encodingOptions: [SALightweightTableInfoEncodingOption]
    let collationOptions: [String]
    let selectedEncodingName: String?
    let canEdit: Bool
    let hasAutoIncrement: Bool
}

struct SALightweightTableInfoEncodingOption {
    let title: String
    let name: String
}

private enum SALightweightTableInfoRowCountQueryLevel: Int {
    case never = 0
    case ifCheap = 1
    case always = 2
}

final class SALightweightTableInfoSidebarView: NSView {
    var rows: [String] = [] {
        didSet {
            updateContent()
        }
    }

    var font: NSFont = UserDefaults.getFont() {
        didSet {
            updateContent()
        }
    }

    var rowHeight: CGFloat = 17 {
        didSet {
            updateContent()
        }
    }

    private enum Layout {
        static let headerHeight: CGFloat = 25
        static let leadingPadding: CGFloat = 2
        static let trailingPadding: CGFloat = 4
        static let iconSize: CGFloat = 16
        static let iconTextSpacing: CGFloat = 5
    }

    private let propertyImage = NSImage(named: "table-property")
    private var toolTipTags: [NSView.ToolTipTag: String] = [:]

    override var isFlipped: Bool {
        return true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func reloadData() {
        updateContent()
    }

    private func configureView() {
        wantsLayer = true
        canDrawSubviewsIntoLayer = true
        setAccessibilityRole(.group)
        updateContent()
    }

    private func updateContent() {
        updateToolTips()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (index, row) in rows.enumerated() {
            let rect = rowRect(for: index)
            guard rect.intersects(dirtyRect) else { continue }
            drawRow(row, at: index, in: rect)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateToolTips()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateToolTips()
    }

    private func drawRow(_ row: String, at index: Int, in rect: NSRect) {
        let isHeader = index == 0
        let rowFont = isHeader ? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize) : font
        let textX = Layout.leadingPadding + Layout.iconSize + Layout.iconTextSpacing
        let textRect = NSRect(x: textX,
                              y: rect.minY + textVerticalInset(for: rowFont, rowHeight: rect.height),
                              width: max(0, rect.width - textX - Layout.trailingPadding),
                              height: rect.height)

        if !isHeader, let propertyImage = propertyImage {
            let iconRect = NSRect(x: Layout.leadingPadding,
                                  y: rect.minY + floor((rect.height - Layout.iconSize) / 2),
                                  width: Layout.iconSize,
                                  height: Layout.iconSize)
            propertyImage.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        row.draw(in: textRect, withAttributes: textAttributes(for: rowFont))
    }

    private func textAttributes(for font: NSFont) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .left

        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func textVerticalInset(for font: NSFont, rowHeight: CGFloat) -> CGFloat {
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return max(0, floor((rowHeight - lineHeight) / 2))
    }

    private func rowRect(for index: Int) -> NSRect {
        let y: CGFloat
        if index == 0 {
            y = 0
        } else {
            y = Layout.headerHeight + (CGFloat(index - 1) * rowHeight)
        }

        let height = index == 0 ? Layout.headerHeight : rowHeight
        return NSRect(x: 0, y: y, width: bounds.width, height: height)
    }

    private func updateToolTips() {
        toolTipTags.removeAll()
        removeAllToolTips()

        for (index, row) in rows.enumerated() {
            let rect = rowRect(for: index)
            guard rect.intersects(bounds) else { continue }
            let tag = addToolTip(rect, owner: self, userData: nil)
            toolTipTags[tag] = row
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        return toolTipTags[tag] ?? ""
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }

    override func accessibilityChildren() -> [Any]? {
        return rows.enumerated().map { index, row -> NSAccessibilityElement in
            let element = NSAccessibilityElement()
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.staticText)
            element.setAccessibilityLabel(row)
            element.setAccessibilityFrame(accessibilityFrame(forRow: index))
            return element
        }
    }

    private func accessibilityFrame(forRow index: Int) -> NSRect {
        guard let window else { return .zero }
        let rowRectInWindow = convert(rowRect(for: index), to: nil)
        return window.convertToScreen(rowRectInWindow)
    }
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
            ], createSyntax: nil, objectType: .table, values: [:], engineOptions: [], encodingOptions: [], collationOptions: [], selectedEncodingName: nil, canEdit: false, hasAutoIncrement: false)
        }

        let tableType = objectType(for: table, database: database, status: tableStatus, connection: connection)
        var rows = [SALightweightTableInfoRow(tableType.headerTitle, isGroup: true)]
        let selectedCollation = displayString(tableStatus["Collation"])
        let selectedEncoding = selectedCollation.map { encodingName(from: $0) }
        let canEdit = tableType == .table && !isSystemDatabase(database)

        if tableType == .view {
            addViewRows(for: table, database: database, connection: connection, rows: &rows)
            addCommentRow(tableStatus: tableStatus, rows: &rows)

            let createSyntax = includeCreateSyntax ? createSyntax(for: table, database: database, connection: connection) : nil
            return SALightweightTableInfoSnapshot(rows: rows,
                                                  createSyntax: createSyntax,
                                                  objectType: tableType,
                                                  values: formValues(from: tableStatus),
                                                  engineOptions: [],
                                                  encodingOptions: [],
                                                  collationOptions: [],
                                                  selectedEncodingName: selectedEncoding,
                                                  canEdit: false,
                                                  hasAutoIncrement: false)
        }

        addDateRow(key: "Create_time", label: NSLocalizedString("created", comment: "Table Info Section : time+date table was created at"), status: tableStatus, rows: &rows)
        addDateRow(key: "Update_time", label: NSLocalizedString("updated", comment: "updated"), status: tableStatus, rows: &rows)
        addStringRow(key: "Engine", label: NSLocalizedString("engine", comment: "Table Info Section : Table Engine"), status: tableStatus, rows: &rows)

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
        return SALightweightTableInfoSnapshot(rows: rows,
                                              createSyntax: createSyntax,
                                              objectType: tableType,
                                              values: formValues(from: tableStatus),
                                              engineOptions: storageEngineOptions(connection: connection),
                                              encodingOptions: encodingOptions(connection: connection),
                                              collationOptions: selectedEncoding.map { collationOptions(for: $0, connection: connection) } ?? [],
                                              selectedEncodingName: selectedEncoding,
                                              canEdit: canEdit,
                                              hasAutoIncrement: displayString(tableStatus["Auto_increment"]) != nil)
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

    private static func formValues(from tableStatus: [String: Any]) -> [String: String] {
        var values: [String: String] = [:]

        values["Engine"] = formattedValue("Engine", tableStatus: tableStatus)
        values["Create_time"] = formattedValue("Create_time", tableStatus: tableStatus)
        values["Update_time"] = formattedValue("Update_time", tableStatus: tableStatus)
        values["Rows"] = formattedValue("Rows", tableStatus: tableStatus)
        values["Row_format"] = formattedValue("Row_format", tableStatus: tableStatus)
        values["Avg_row_length"] = formattedValue("Avg_row_length", tableStatus: tableStatus)
        values["Auto_increment"] = formattedValue("Auto_increment", tableStatus: tableStatus)
        values["Data_length"] = formattedValue("Data_length", tableStatus: tableStatus)
        values["Max_data_length"] = formattedValue("Max_data_length", tableStatus: tableStatus)
        values["Index_length"] = formattedValue("Index_length", tableStatus: tableStatus)
        values["Data_free"] = formattedValue("Data_free", tableStatus: tableStatus)
        values["Collation"] = displayString(tableStatus["Collation"]) ?? ""
        values["Comment"] = displayString(tableStatus["Comment"]) == "VIEW" ? "" : (displayString(tableStatus["Comment"]) ?? "")

        if let collation = displayString(tableStatus["Collation"]) {
            values["Encoding"] = encodingName(from: collation)
        }

        return values
    }

    private static func formattedValue(_ key: String, tableStatus: [String: Any]) -> String {
        let notAvailable = NSLocalizedString("Not available", comment: "not available label")
        guard let rawValue = displayString(tableStatus[key]) else { return notAvailable }

        switch key {
        case "Data_length", "Max_data_length", "Index_length", "Data_free":
            guard let value = Int64(rawValue) else { return notAvailable }
            return ByteCountFormatter.string(byteSize: value) as String

        case "Create_time", "Update_time":
            guard let date = DateFormatter.naturalLanguageFormatter.date(from: rawValue) else { return rawValue }
            return DateFormatter.mediumStyleFormatter.string(from: date)

        case "Rows", "Avg_row_length", "Auto_increment":
            guard let value = Int64(rawValue),
                  let formattedValue = NumberFormatter.decimalStyleFormatter.string(from: NSNumber(value: value)) else { return notAvailable }

            if key == "Rows", displayString(tableStatus["RowsCountAccurate"]) != "y" {
                return "~\(formattedValue)"
            }

            return formattedValue

        default:
            return rawValue.isEmpty ? notAvailable : rawValue
        }
    }

    private static func storageEngineOptions(connection: SPMySQLConnection) -> [String] {
        guard let result = connection.queryString("SHOW ENGINES") else { return [] }

        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        var engines: [String] = []

        while let row = result.getRowAsDictionary() as? [String: Any] {
            guard let engine = displayString(row["Engine"]),
                  engine != "PERFORMANCE_SCHEMA",
                  let support = displayString(row["Support"])?.uppercased(),
                  support == "YES" || support == "DEFAULT" else { continue }

            engines.append(engine)
        }

        return engines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func encodingOptions(connection: SPMySQLConnection) -> [SALightweightTableInfoEncodingOption] {
        let queries = [
            "SELECT CHARACTER_SET_NAME, DESCRIPTION FROM information_schema.character_sets ORDER BY character_set_name ASC",
            "SHOW CHARACTER SET"
        ]

        for query in queries {
            guard let result = connection.queryString(query) else { continue }

            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            var encodings: [SALightweightTableInfoEncodingOption] = []

            while let row = result.getRowAsDictionary() as? [String: Any] {
                guard let name = displayString(row["CHARACTER_SET_NAME"] ?? row["Charset"]) else { continue }
                let description = displayString(row["DESCRIPTION"] ?? row["Description"])
                let title = description.map { "\($0) (\(name))" } ?? name
                encodings.append(SALightweightTableInfoEncodingOption(title: title, name: name))
            }

            if !encodings.isEmpty {
                return encodings
            }
        }

        return []
    }

    static func collationOptions(for encoding: String, connection: SPMySQLConnection) -> [String] {
        var collations = collationOptionsFromShowCollation(for: encoding, connection: connection)
        if collations.isEmpty, let alias = utf8Alias(for: encoding) {
            collations = collationOptionsFromShowCollation(for: alias, connection: connection)
        }

        return collations
    }

    private static func collationOptionsFromShowCollation(for encoding: String, connection: SPMySQLConnection) -> [String] {
        guard let result = connection.queryString("SHOW COLLATION WHERE Charset = \(sqlString(encoding, connection: connection))") else { return [] }

        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        var collations: [String] = []

        while let row = result.getRowAsDictionary() as? [String: Any] {
            guard let collation = displayString(row["Collation"]) else { continue }
            collations.append(collation)
        }

        return Array(NSOrderedSet(array: collations).compactMap { $0 as? String })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func tableStatusValues(for table: String, database: String, connection: SPMySQLConnection) -> [String: Any]? {
        let query = "SHOW TABLE STATUS FROM \(backtickQuoted(database)) WHERE Name = \(sqlString(table, connection: connection))"
        guard let result = connection.queryString(query) else { return nil }

        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard var tableStatus = result.getRowAsDictionary() as? [String: Any], !tableStatus.isEmpty else { return nil }

        if tableStatus["Engine"] == nil, let type = tableStatus["Type"] {
            tableStatus["Engine"] = type
        }

        let engine = (displayString(tableStatus["Engine"]) ?? "").lowercased()
        if engine == "myisam" {
            tableStatus["RowsCountAccurate"] = "y"
        } else if shouldFetchAccurateRowCount(for: tableStatus),
                  let accurateRowCount = accurateRowCount(for: table, database: database, connection: connection) {
            tableStatus["Rows"] = "\(accurateRowCount)"
            tableStatus["RowsCountAccurate"] = "y"
        } else {
            tableStatus["RowsCountAccurate"] = "n"
        }

        return tableStatus
    }

    private static func accurateRowCount(for table: String, database: String, connection: SPMySQLConnection) -> Int? {
        let query = "SELECT COUNT(1) FROM \(backtickQuoted(database)).\(backtickQuoted(table))"
        guard let result = connection.queryString(query),
              let row = result.getRowAsArray(),
              let value = row.first else { return nil }

        guard let count = Int(displayString(value) ?? "") else { return nil }
        return count
    }

    private static func shouldFetchAccurateRowCount(for tableStatus: [String: Any]) -> Bool {
        let defaults = UserDefaults.standard
        let level = SALightweightTableInfoRowCountQueryLevel(rawValue: defaults.integer(forKey: SPTableRowCountQueryLevel)) ?? .always

        switch level {
        case .never:
            return false
        case .always:
            return true
        case .ifCheap:
            let cheapBoundary = defaults.object(forKey: SPTableRowCountCheapSizeBoundary) as? Int ?? 5_242_880
            guard let dataLength = Int(displayString(tableStatus["Data_length"]) ?? "") else {
                return false
            }
            return dataLength < cheapBoundary
        }
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

        let stringValue: String
        if let data = value as? Data {
            stringValue = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
        } else if let data = value as? NSData {
            stringValue = String(data: data as Data, encoding: .utf8)
                ?? String(data: data as Data, encoding: .isoLatin1)
                ?? ""
        } else {
            stringValue = String(describing: value)
        }

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

    private static func utf8Alias(for encoding: String) -> String? {
        switch encoding.lowercased() {
        case "utf8":
            return "utf8mb3"
        case "utf8mb3":
            return "utf8"
        default:
            return nil
        }
    }

    private static func sqlString(_ value: String, connection: SPMySQLConnection) -> String {
        return connection.escapeAndQuoteString(value) ?? "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func isSystemDatabase(_ database: String) -> Bool {
        return ["information_schema", "performance_schema", "mysql"].contains(database.lowercased())
    }

    private static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }
}

enum SALightweightTableInfoObjectType {
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

final class SALightweightTableInfoViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    private static let formBaseSize = NSSize(width: 706, height: 546)

    private var loadToken = UUID()
    private var rows: [SALightweightTableInfoRow] = []
    private var preferenceObserver: SALightweightPreferenceObserver?
    private var table = ""
    private var database = ""
    private weak var connection: SPMySQLConnection?
    private var currentSnapshot: SALightweightTableInfoSnapshot?
    private var isApplyingSnapshot = false
    var tableInfoDidChange: (() -> Void)?

    private let formView = NSView(frame: .zero)
    private let tableContainerView = NSView(frame: .zero)
    private let syntaxContainerView = NSView(frame: .zero)
    private let tableScrollView = NSScrollView(frame: .zero)
    private let commentsScrollView = NSScrollView(frame: .zero)
    private let syntaxScrollView = NSScrollView(frame: .zero)

    private lazy var typePopUpButton = formPopUpButton(action: #selector(updateTableType(_:)))
    private lazy var encodingPopUpButton = formPopUpButton(action: #selector(updateTableEncoding(_:)))
    private lazy var collationPopUpButton = formPopUpButton(action: #selector(updateTableCollation(_:)))
    private lazy var resetAutoIncrementButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20), pullsDown: true)
        button.controlSize = .small
        button.bezelStyle = .smallSquare
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.addItem(withTitle: "")
        button.item(at: 0)?.image = NSImage(named: "NSAdvanced")
        button.item(at: 0)?.isHidden = true
        button.addItem(withTitle: NSLocalizedString("Reset AUTO_INCREMENT", comment: "Reset AUTO_INCREMENT menu item"))
        button.item(at: 1)?.target = self
        button.item(at: 1)?.action = #selector(resetAutoIncrement(_:))
        button.item(at: 1)?.tag = 2
        button.addItem(withTitle: NSLocalizedString("Reset AUTO_INCREMENT to...", comment: "Reset AUTO_INCREMENT to menu item"))
        button.item(at: 2)?.target = self
        button.item(at: 2)?.action = #selector(resetAutoIncrement(_:))
        button.item(at: 2)?.tag = 1
        button.toolTip = NSLocalizedString("Reset AUTO_INCREMENT...", comment: "Reset AUTO_INCREMENT tooltip")
        return button
    }()

    private lazy var createdAtField = valueTextField()
    private lazy var updatedAtField = valueTextField()
    private lazy var rowNumberField = valueTextField()
    private lazy var rowFormatField = valueTextField()
    private lazy var rowAvgLengthField = valueTextField()
    private lazy var autoIncrementField: NSTextField = {
        let field = valueTextField()
        field.isEditable = false
        field.target = self
        field.action = #selector(tableRowAutoIncrementWasEdited(_:))
        field.delegate = self
        return field
    }()
    private lazy var dataSizeField = valueTextField()
    private lazy var maxDataSizeField = valueTextField()
    private lazy var indexSizeField = valueTextField()
    private lazy var sizeFreeField = valueTextField()

    private lazy var commentsTextView: NSTextView = {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = UserDefaults.getFont()
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.delegate = self
        return textView
    }()

    private lazy var placeholderView: SALightweightPlaceholderView = {
        let view = SALightweightPlaceholderView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        return view
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
        view = NSView(frame: NSRect(origin: .zero, size: Self.formBaseSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        formView.frame = view.bounds
        formView.autoresizingMask = [.width, .height]
        view.addSubview(formView)

        addFormLabel(NSLocalizedString("Type:", comment: "table info type label"), frame: NSRect(x: 22, y: 503, width: 91, height: 14))
        addFormLabel(NSLocalizedString("Encoding:", comment: "table info encoding label"), frame: NSRect(x: 23, y: 477, width: 90, height: 14))
        addFormLabel(NSLocalizedString("Collation:", comment: "table info collation label"), frame: NSRect(x: 23, y: 452, width: 91, height: 14))
        addFormLabel(NSLocalizedString("Created at:", comment: "table info created at label"), frame: NSRect(x: 286, y: 502, width: 82, height: 14))
        addFormLabel(NSLocalizedString("Updated at:", comment: "table info updated at label"), frame: NSRect(x: 286, y: 477, width: 82, height: 14))

        addFormView(typePopUpButton, frame: NSRect(x: 115, y: 498, width: 161, height: 22), resizingMask: [.maxXMargin, .minYMargin])
        addFormView(encodingPopUpButton, frame: NSRect(x: 115, y: 473, width: 161, height: 22), resizingMask: [.maxXMargin, .minYMargin])
        addFormView(collationPopUpButton, frame: NSRect(x: 115, y: 448, width: 161, height: 22), resizingMask: [.maxXMargin, .minYMargin])
        addFormView(createdAtField, frame: NSRect(x: 369, y: 502, width: 305, height: 14), resizingMask: [.width, .minYMargin])
        addFormView(updatedAtField, frame: NSRect(x: 369, y: 477, width: 305, height: 14), resizingMask: [.width, .minYMargin])

        addSeparator(frame: NSRect(x: 25, y: 429, width: 650, height: 5))
        addSeparator(frame: NSRect(x: 24, y: 318, width: 650, height: 5))

        addFormLabel(NSLocalizedString("Number of rows:", comment: "table info number of rows label"), frame: NSRect(x: 23, y: 402, width: 150, height: 14))
        addFormLabel(NSLocalizedString("Row format:", comment: "table info row format label"), frame: NSRect(x: 23, y: 380, width: 150, height: 14))
        addFormLabel(NSLocalizedString("Avg. row length:", comment: "table info average row length label"), frame: NSRect(x: 23, y: 358, width: 150, height: 14))
        addFormLabel(NSLocalizedString("Auto increment:", comment: "table info auto increment label"), frame: NSRect(x: 50, y: 336, width: 123, height: 14))
        addFormLabel(NSLocalizedString("Data size:", comment: "table info data size label"), frame: NSRect(x: 286, y: 402, width: 172, height: 14))
        addFormLabel(NSLocalizedString("Max data size:", comment: "table info max data size label"), frame: NSRect(x: 286, y: 380, width: 172, height: 14))
        addFormLabel(NSLocalizedString("Index size:", comment: "table info index size label"), frame: NSRect(x: 286, y: 358, width: 172, height: 14))
        addFormLabel(NSLocalizedString("Free data size:", comment: "table info free data size label"), frame: NSRect(x: 286, y: 336, width: 172, height: 14))

        addFormView(rowNumberField, frame: NSRect(x: 175, y: 402, width: 99, height: 14), resizingMask: [.maxXMargin, .minYMargin])
        addFormView(rowFormatField, frame: NSRect(x: 175, y: 380, width: 99, height: 14), resizingMask: [.maxXMargin, .minYMargin])
        addFormView(rowAvgLengthField, frame: NSRect(x: 175, y: 358, width: 99, height: 14), resizingMask: [.maxXMargin, .minYMargin])
        addFormView(resetAutoIncrementButton, frame: NSRect(x: 26, y: 334, width: 20, height: 20), resizingMask: [.maxXMargin, .minYMargin])
        addFormView(autoIncrementField, frame: NSRect(x: 175, y: 336, width: 101, height: 14), resizingMask: [.maxXMargin, .minYMargin])
        addFormView(dataSizeField, frame: NSRect(x: 462, y: 402, width: 210, height: 14), resizingMask: [.width, .minYMargin])
        addFormView(maxDataSizeField, frame: NSRect(x: 462, y: 380, width: 210, height: 14), resizingMask: [.width, .minYMargin])
        addFormView(indexSizeField, frame: NSRect(x: 462, y: 358, width: 212, height: 14), resizingMask: [.width, .minYMargin])
        addFormView(sizeFreeField, frame: NSRect(x: 462, y: 336, width: 212, height: 14), resizingMask: [.width, .minYMargin])

        addFormLabel(NSLocalizedString("Comments:", comment: "table info comments label"), frame: NSRect(x: 4, y: 273, width: 100, height: 14))
        configureTextScrollView(commentsScrollView, textView: commentsTextView, frame: NSRect(x: 109, y: 214, width: 554, height: 73))

        addFormLabel(NSLocalizedString("Create syntax:", comment: "table info create syntax label"), frame: NSRect(x: 3, y: 186, width: 101, height: 14))
        configureTextScrollView(syntaxScrollView, textView: syntaxTextView, frame: NSRect(x: 109, y: 30, width: 554, height: 170))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        registerPreferenceObserversIfNeeded()
        applyTablePreferences()
    }

    deinit {
        preferenceObserver?.invalidate()
    }

    private func preferenceDidChange(_ keyPath: String) {
        if keyPath == SPDisplayTableViewVerticalGridlines {
            tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
            tableView.setNeedsDisplay(tableView.visibleRect)
            return
        }

        if keyPath == SPGlobalFontSettings {
            applyTablePreferences()
            return
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateFormDocumentFrame()
    }

    func showPlaceholder(_ message: String) {
        loadToken = UUID()
        rows = []
        tableView.reloadData()
        clearForm()
        formView.isHidden = true

        placeholderView.message = message
        placeholderView.frame = view.bounds
        if placeholderView.superview == nil {
            view.addSubview(placeholderView)
        }
    }

    func loadTableInfo(for table: String, database: String, connection: SPMySQLConnection) {
        loadToken = UUID()
        let token = loadToken
        self.table = table
        self.database = database
        self.connection = connection

        placeholderView.removeFromSuperviewWithoutNeedingDisplay()
        formView.isHidden = false
        rows = [
            SALightweightTableInfoRow(NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane"), isGroup: true),
            SALightweightTableInfoRow(NSLocalizedString("loading...", comment: "table info loading row"))
        ]
        clearForm()
        typePopUpButton.addItem(withTitle: NSLocalizedString("loading...", comment: "table info loading row"))
        typePopUpButton.isEnabled = false
        tableView.reloadData()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            let snapshot = SALightweightTableInfoLoader.tableInfo(for: table, database: database, connection: connection)

            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                self.rows = snapshot.rows
                self.currentSnapshot = snapshot
                self.applySnapshot(snapshot)
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

    private func applySnapshot(_ snapshot: SALightweightTableInfoSnapshot) {
        isApplyingSnapshot = true
        updateFormDocumentFrame()

        populate(typePopUpButton, with: snapshot.engineOptions, selectedTitle: snapshot.values["Engine"])
        populateEncodingPopUpButton(snapshot)
        populate(collationPopUpButton, with: snapshot.collationOptions, selectedTitle: snapshot.values["Collation"])

        createdAtField.stringValue = snapshot.values["Create_time"] ?? ""
        updatedAtField.stringValue = snapshot.values["Update_time"] ?? ""
        rowNumberField.stringValue = snapshot.values["Rows"] ?? ""
        rowFormatField.stringValue = snapshot.values["Row_format"] ?? ""
        rowAvgLengthField.stringValue = snapshot.values["Avg_row_length"] ?? ""
        autoIncrementField.stringValue = snapshot.values["Auto_increment"] ?? ""
        dataSizeField.stringValue = snapshot.values["Data_length"] ?? ""
        maxDataSizeField.stringValue = snapshot.values["Max_data_length"] ?? ""
        indexSizeField.stringValue = snapshot.values["Index_length"] ?? ""
        sizeFreeField.stringValue = snapshot.values["Data_free"] ?? ""
        commentsTextView.string = snapshot.values["Comment"] ?? ""
        syntaxTextView.string = snapshot.createSyntax ?? ""

        typePopUpButton.isEnabled = snapshot.canEdit && snapshot.engineOptions.count > 1
        encodingPopUpButton.isEnabled = snapshot.canEdit && snapshot.encodingOptions.count > 1
        collationPopUpButton.isEnabled = snapshot.canEdit && snapshot.collationOptions.count > 1
        commentsTextView.isEditable = snapshot.canEdit
        resetAutoIncrementButton.isHidden = !snapshot.hasAutoIncrement
        autoIncrementField.isEditable = false

        if snapshot.objectType == .view {
            populate(typePopUpButton, with: ["View"], selectedTitle: "View")
            encodingPopUpButton.isEnabled = false
            collationPopUpButton.isEnabled = false
        }

        isApplyingSnapshot = false
    }

    private func clearForm() {
        isApplyingSnapshot = true

        for popUpButton in [typePopUpButton, encodingPopUpButton, collationPopUpButton] {
            popUpButton.removeAllItems()
            popUpButton.isEnabled = false
        }

        for field in [createdAtField, updatedAtField, rowNumberField, rowFormatField, rowAvgLengthField, autoIncrementField, dataSizeField, maxDataSizeField, indexSizeField, sizeFreeField] {
            field.stringValue = ""
        }

        commentsTextView.string = ""
        commentsTextView.isEditable = false
        syntaxTextView.string = ""
        resetAutoIncrementButton.isHidden = true
        autoIncrementField.isEditable = false
        currentSnapshot = nil

        isApplyingSnapshot = false
    }

    private func populate(_ popUpButton: NSPopUpButton, with items: [String], selectedTitle: String?) {
        popUpButton.removeAllItems()

        if items.isEmpty {
            popUpButton.addItem(withTitle: selectedTitle?.isEmpty == false ? selectedTitle! : NSLocalizedString("Not available", comment: "not available label"))
            return
        }

        for item in items {
            popUpButton.addItem(withTitle: item)
        }

        if let selectedTitle, popUpButton.itemTitles.contains(selectedTitle) {
            popUpButton.selectItem(withTitle: selectedTitle)
        } else if let selectedTitle, !selectedTitle.isEmpty {
            popUpButton.addItem(withTitle: selectedTitle)
            popUpButton.selectItem(withTitle: selectedTitle)
        }
    }

    private func populateEncodingPopUpButton(_ snapshot: SALightweightTableInfoSnapshot) {
        encodingPopUpButton.removeAllItems()

        if snapshot.encodingOptions.isEmpty {
            encodingPopUpButton.addItem(withTitle: snapshot.values["Encoding"] ?? NSLocalizedString("Not available", comment: "not available label"))
            return
        }

        for option in snapshot.encodingOptions {
            encodingPopUpButton.addItem(withTitle: option.title)
            encodingPopUpButton.lastItem?.representedObject = option.name
        }

        if let selectedEncodingName = snapshot.selectedEncodingName,
           let item = encodingPopUpButton.itemArray.first(where: { ($0.representedObject as? String) == selectedEncodingName }) {
            encodingPopUpButton.select(item)
        }
    }

    @objc private func updateTableType(_ sender: NSPopUpButton) {
        guard !isApplyingSnapshot,
              let currentType = currentSnapshot?.values["Engine"],
              let newType = sender.titleOfSelectedItem,
              newType != currentType else { return }

        let changeType = { [weak self] in
            guard let self = self else { return }
            self.executeTableInfoMutation(query: "ALTER TABLE \(self.qualifiedTableName()) ENGINE = \(newType)",
                                          errorTitle: NSLocalizedString("Error changing table type", comment: "error changing table type message"),
                                          errorMessage: { mysqlError in
                                              String(format: NSLocalizedString("An error occurred when trying to change the table type to '%@'.\n\nMySQL said: %@", comment: "error changing table type informative message"), newType, mysqlError ?? "")
                                          },
                                          useQueryWarning: false,
                                          restoreHandler: { sender.selectItem(withTitle: currentType) })
        }

        if formattedIntegerIsZero(currentSnapshot?.values["Rows"]) {
            changeType()
            return
        }

        NSAlert.createDefaultAlert(title: NSLocalizedString("Change table type", comment: "change table type message"),
                                   message: String(format: NSLocalizedString("Are you sure you want to change this table's type to %@?\n\nPlease be aware that changing a table's type has the potential to cause the loss of some or all of its data. This action cannot be undone.", comment: "change table type informative message"), newType),
                                   primaryButtonTitle: NSLocalizedString("Change", comment: "change button"),
                                   primaryButtonHandler: changeType,
                                   cancelButtonHandler: {
                                       sender.selectItem(withTitle: currentType)
                                   })
    }

    @objc private func updateTableEncoding(_ sender: NSPopUpButton) {
        guard !isApplyingSnapshot,
              let currentEncoding = currentSnapshot?.selectedEncodingName,
              let newEncoding = sender.selectedItem?.representedObject as? String,
              newEncoding != currentEncoding else { return }

        executeTableInfoMutation(query: "ALTER TABLE \(qualifiedTableName()) CHARACTER SET = \(newEncoding)",
                                 errorTitle: NSLocalizedString("Error changing table encoding", comment: "error changing table encoding message"),
                                 errorMessage: { mysqlError in
                                     String(format: NSLocalizedString("An error occurred when trying to change the table encoding to '%@'.\n\nMySQL said: %@", comment: "error changing table encoding informative message"), newEncoding, mysqlError ?? "")
                                 },
                                 useQueryWarning: false,
                                 restoreHandler: { [weak self] in
                                     self?.selectEncoding(named: currentEncoding)
                                 })
    }

    @objc private func updateTableCollation(_ sender: NSPopUpButton) {
        guard !isApplyingSnapshot,
              let currentCollation = currentSnapshot?.values["Collation"],
              let newCollation = sender.titleOfSelectedItem,
              newCollation != currentCollation else { return }

        executeTableInfoMutation(query: "ALTER TABLE \(qualifiedTableName()) COLLATE = \(newCollation)",
                                 errorTitle: NSLocalizedString("Error changing table collation", comment: "error changing table collation message"),
                                 errorMessage: { mysqlError in
                                     String(format: NSLocalizedString("An error occurred when trying to change the table collation to '%@'.\n\nMySQL said: %@", comment: "error changing table collation informative message"), newCollation, mysqlError ?? "")
                                 },
                                 useQueryWarning: false,
                                 restoreHandler: { sender.selectItem(withTitle: currentCollation) })
    }

    @objc private func resetAutoIncrement(_ sender: NSMenuItem) {
        if sender.tag == 1 {
            autoIncrementField.isEditable = true
            autoIncrementField.selectText(nil)
            return
        }

        executeTableInfoMutation(query: "ALTER TABLE \(qualifiedTableName()) AUTO_INCREMENT = 1",
                                 errorTitle: NSLocalizedString("Error", comment: "error"),
                                 errorMessage: { [weak self] mysqlError in
                                     String(format: NSLocalizedString("An error occurred while trying to reset AUTO_INCREMENT of table '%@'.\n\nMySQL said: %@", comment: "error resetting auto_increment informative message"), self?.table ?? "", mysqlError ?? "")
                                 },
                                 useQueryWarning: false,
                                 restoreHandler: nil)
    }

    @objc private func tableRowAutoIncrementWasEdited(_ sender: NSTextField) {
        sender.isEditable = false
        let currentAutoIncrement = currentSnapshot?.values["Auto_increment"] ?? ""

        guard let value = NumberFormatter.decimalStyleFormatter.number(from: sender.stringValue) else {
            sender.stringValue = currentAutoIncrement
            return
        }

        if let currentValue = NumberFormatter.decimalStyleFormatter.number(from: currentAutoIncrement),
           currentValue.uint64Value == value.uint64Value {
            sender.stringValue = currentAutoIncrement
            return
        }

        executeTableInfoMutation(query: "ALTER TABLE \(qualifiedTableName()) AUTO_INCREMENT = \(value.uint64Value)",
                                 errorTitle: NSLocalizedString("Error", comment: "error"),
                                 errorMessage: { [weak self] mysqlError in
                                     String(format: NSLocalizedString("An error occurred while trying to reset AUTO_INCREMENT of table '%@'.\n\nMySQL said: %@", comment: "error resetting auto_increment informative message"), self?.table ?? "", mysqlError ?? "")
                                 },
                                 useQueryWarning: false,
                                 restoreHandler: nil)
    }

    func textDidEndEditing(_ notification: Notification) {
        guard !isApplyingSnapshot,
              let textView = notification.object as? NSTextView,
              textView === commentsTextView,
              commentsTextView.isEditable,
              let connection = connection else { return }

        let currentCommentRaw = currentSnapshot?.values["Comment"] ?? ""
        let currentComment = currentCommentRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let newComment = commentsTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentComment != newComment else { return }

        let quotedComment = connection.escapeAndQuoteString(newComment) ?? "'\(newComment.replacingOccurrences(of: "'", with: "''"))'"
        executeTableInfoMutation(query: "ALTER TABLE \(qualifiedTableName()) COMMENT = \(quotedComment)",
                                 errorTitle: NSLocalizedString("Error changing table comment", comment: "error changing table comment message"),
                                 errorMessage: { mysqlError in
                                     String(format: NSLocalizedString("An error occurred when trying to change the table's comment to '%@'.\n\nMySQL said: %@", comment: "error changing table comment informative message"), newComment, mysqlError ?? "")
                                 },
                                 useQueryWarning: true,
                                 restoreHandler: { [weak self] in
                                     self?.commentsTextView.string = currentCommentRaw
                                 })
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(cancelOperation(_:)), control == autoIncrementField {
            autoIncrementField.abortEditing()
            autoIncrementField.isEditable = false
            return true
        }

        return false
    }

    private func executeTableInfoMutation(query: String,
                                          errorTitle: String,
                                          errorMessage: ((String?) -> String)? = nil,
                                          useQueryWarning: Bool,
                                          restoreHandler: (() -> Void)?) {
        guard let connection = connection else { return }

        let executeChange = { [weak self] in
            guard let self = self else { return }

            _ = connection.queryString(query)

            if connection.queryErrored() {
                restoreHandler?()
                let mysqlError = connection.lastErrorMessage()
                self.showError(title: errorTitle, message: errorMessage?(mysqlError) ?? mysqlError)
                return
            }

            self.reloadCurrentTableInfo()
            self.tableInfoDidChange?()
        }

        if useQueryWarning && UserDefaults.standard.bool(forKey: SPQueryWarningEnabled) {
            let alert = NSAlert()
            alert.window.animationBehavior = .none
            alert.messageText = NSLocalizedString("Execute SQL?", comment: "Execute SQL?")
            alert.informativeText = String(format: NSLocalizedString("Do you really want to proceed with this query?\n\n %@", comment: "message of panel asking for confirmation for exec query"), query)
            alert.addButton(withTitle: NSLocalizedString("Proceed", comment: "Proceed"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

            if alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn {
                executeChange()
            } else {
                restoreHandler?()
            }
        } else {
            executeChange()
        }
    }

    func refreshActiveTableInfoDetail() {
        reloadCurrentTableInfo()
    }

    private func reloadCurrentTableInfo() {
        guard let connection = connection, !table.isEmpty, !database.isEmpty else { return }
        loadTableInfo(for: table, database: database, connection: connection)
    }

    private func formattedIntegerIsZero(_ value: String?) -> Bool {
        guard let value = value else { return false }
        let digits = value
            .replacingOccurrences(of: "~", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return UInt64(digits) == 0
    }

    private func selectEncoding(named encodingName: String) {
        guard let item = encodingPopUpButton.itemArray.first(where: { ($0.representedObject as? String) == encodingName }) else { return }
        encodingPopUpButton.select(item)
    }

    private func qualifiedTableName() -> String {
        return "\(backtickQuoted(database)).\(backtickQuoted(table))"
    }

    private func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    private func showError(title: String, message: String?) {
        NSAlert.createWarningAlert(title: title, message: message ?? "", callback: nil)
    }

    private func updateFormDocumentFrame() {
        let size = NSSize(width: max(Self.formBaseSize.width, view.bounds.width),
                          height: max(Self.formBaseSize.height, view.bounds.height))

        guard formView.frame.size != size else { return }

        formView.frame = NSRect(origin: .zero, size: size)
    }

    private func addFormLabel(_ title: String, frame: NSRect) {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.autoresizingMask = [.maxXMargin, .minYMargin]
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .controlTextColor
        formView.addSubview(label)
    }

    private func addFormView(_ subview: NSView, frame: NSRect, resizingMask: NSView.AutoresizingMask) {
        subview.frame = frame
        subview.autoresizingMask = resizingMask
        formView.addSubview(subview)
    }

    private func addSeparator(frame: NSRect) {
        let separator = NSBox(frame: frame)
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .minYMargin]
        formView.addSubview(separator)
    }

    private func configureTextScrollView(_ scrollView: NSScrollView, textView: NSTextView, frame: NSRect) {
        scrollView.frame = frame
        scrollView.autoresizingMask = [.width, .height, .minYMargin]
        scrollView.focusRingType = .none
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        textView.frame = NSRect(origin: .zero, size: frame.size)
        textView.autoresizingMask = [.width, .height]
        formView.addSubview(scrollView)
    }

    private func formPopUpButton(action: Selector) -> NSPopUpButton {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 161, height: 22), pullsDown: false)
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.target = self
        button.action = action
        return button
    }

    private func valueTextField() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .controlTextColor
        field.lineBreakMode = .byClipping
        return field
    }

    private func registerPreferenceObserversIfNeeded() {
        guard preferenceObserver == nil else { return }

        preferenceObserver = SALightweightPreferenceObserver(keys: [
            SPDisplayTableViewVerticalGridlines,
            SPGlobalFontSettings
        ]) { [weak self] keyPath in
            self?.preferenceDidChange(keyPath)
        }
        preferenceObserver?.start()
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
