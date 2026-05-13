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
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let isBoolean: Bool
        let editable: Bool
    }

    private struct StructureRow {
        let id = UUID()
        var values: [String: String]
        var originalName: String?
        var isNew = false

        var name: String { values["name"] ?? "" }
    }

    private struct IndexColumn {
        let title: String
        let key: String
        let width: CGFloat
        let minWidth: CGFloat
    }

    private struct StructureCacheEntry {
        let rows: [StructureRow]
        let indexes: [[String: String]]
        let filterString: String
        let structureSortKey: String?
        let structureSortAscending: Bool
        let indexSortKey: String?
        let indexSortAscending: Bool
    }

    private let structureColumns: [StructureColumn] = [
        StructureColumn(title: NSLocalizedString("Field", comment: "table structure field column"), key: "name", width: 54.5, minWidth: 50, maxWidth: 1000, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Type", comment: "table structure type column"), key: "type", width: 69.5, minWidth: 65, maxWidth: 1000, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Length", comment: "table structure length column"), key: "length", width: 33.5, minWidth: 25, maxWidth: 1000, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Unsigned", comment: "table structure unsigned column"), key: "unsigned", width: 54, minWidth: 14, maxWidth: 82, isBoolean: true, editable: true),
        StructureColumn(title: NSLocalizedString("Zerofill", comment: "table structure zerofill column"), key: "zerofill", width: 41, minWidth: 14, maxWidth: 84, isBoolean: true, editable: true),
        StructureColumn(title: NSLocalizedString("Binary", comment: "table structure binary column"), key: "binary", width: 37, minWidth: 14, maxWidth: 39, isBoolean: true, editable: true),
        StructureColumn(title: NSLocalizedString("Allow Null", comment: "table structure allow null column"), key: "null", width: 57, minWidth: 14, maxWidth: 78, isBoolean: true, editable: true),
        StructureColumn(title: NSLocalizedString("Key", comment: "table structure key column"), key: "Key", width: 26, minWidth: 26, maxWidth: 60, isBoolean: false, editable: false),
        StructureColumn(title: NSLocalizedString("Default", comment: "table structure default column"), key: "default", width: 39, minWidth: 34, maxWidth: 1000, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Extra", comment: "table structure extra column"), key: "Extra", width: 65, minWidth: 60, maxWidth: 1000, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Encoding", comment: "table structure encoding column"), key: "encodingName", width: 48.5, minWidth: 10, maxWidth: 1000, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Collation", comment: "table structure collation column"), key: "collationName", width: 54.5, minWidth: 10, maxWidth: 1000, isBoolean: false, editable: true),
        StructureColumn(title: NSLocalizedString("Comment", comment: "table structure comment column"), key: "comment", width: 32.5, minWidth: 10, maxWidth: 1000, isBoolean: false, editable: true)
    ]

    private let indexColumns: [IndexColumn] = [
        IndexColumn(title: "Non_unique", key: "Non_unique", width: 73.5, minWidth: 40),
        IndexColumn(title: "Key_name", key: "Key_name", width: 64.5, minWidth: 40),
        IndexColumn(title: "Seq_in_index", key: "Seq_in_index", width: 77, minWidth: 10),
        IndexColumn(title: "Column_name", key: "Column_name", width: 85, minWidth: 10),
        IndexColumn(title: "Collation", key: "Collation", width: 55.5, minWidth: 10),
        IndexColumn(title: "Cardinality", key: "Cardinality", width: 65.5, minWidth: 10),
        IndexColumn(title: "Sub_part", key: "Sub_part", width: 56, minWidth: 10),
        IndexColumn(title: "Packed", key: "Packed", width: 43, minWidth: 10),
        IndexColumn(title: "Comment", key: "Comment", width: 106, minWidth: 56)
    ]

    private let typeSuggestions = ["TINYINT", "SMALLINT", "MEDIUMINT", "INT", "BIGINT", "FLOAT", "DOUBLE", "DOUBLE PRECISION", "REAL", "DECIMAL", "BIT", "SERIAL", "BOOL", "BOOLEAN", "DEC", "FIXED", "NUMERIC", "CHAR", "VARCHAR", "TINYTEXT", "TEXT", "MEDIUMTEXT", "LONGTEXT", "TINYBLOB", "MEDIUMBLOB", "BLOB", "LONGBLOB", "BINARY", "VARBINARY", "JSON", "ENUM", "SET", "DATE", "DATETIME", "TIMESTAMP", "TIME", "YEAR", "GEOMETRY", "POINT", "LINESTRING", "POLYGON", "MULTIPOINT", "MULTILINESTRING", "MULTIPOLYGON", "GEOMETRYCOLLECTION"]
    private let extraSuggestions = ["None", "auto_increment", "on update CURRENT_TIMESTAMP", "SERIAL DEFAULT VALUE"]
    private let encodingSuggestions = ["", "armscii8", "ascii", "big5", "binary", "cp1250", "cp1251", "cp1256", "cp1257", "cp850", "cp852", "cp866", "cp932", "dec8", "eucjpms", "euckr", "gb18030", "gb2312", "gbk", "geostd8", "greek", "hebrew", "hp8", "keybcs2", "koi8r", "koi8u", "latin1", "latin2", "latin5", "latin7", "macce", "macroman", "sjis", "swe7", "tis620", "ucs2", "ujis", "utf8", "utf8mb4", "utf16", "utf16le", "utf32"]
    private let collationSuggestions = ["", "utf8_general_ci", "utf8_unicode_ci", "utf8_bin", "utf8mb4_general_ci", "utf8mb4_unicode_ci", "utf8mb4_bin", "latin1_swedish_ci", "latin1_general_ci", "latin1_bin"]

    private weak var connection: SPMySQLConnection?
    private var database = ""
    private var table = ""
    private var rows: [StructureRow] = []
    private var filteredRows: [StructureRow]?
    private var indexes: [[String: String]] = []
    private var loadToken = UUID()
    private var isSaving = false
    private var didSetInitialTablesIndexesSplitPosition = false
    private var didRegisterPreferenceObservers = false
    private var isApplyingProgrammaticColumnWidths = false
    private var structureSortKey: String?
    private var structureSortAscending = true
    private var indexSortKey: String?
    private var indexSortAscending = true
    private var structureCache: [String: StructureCacheEntry] = [:]
    private var structureCacheOrder: [String] = []
    private let maximumStructureCacheEntries = 12
    var tableStructureDidChange: (() -> Void)?

    private let tablesIndexesSplitView = SPSplitView(frame: .zero)
    private let indexesHeaderView = NSView(frame: .zero)

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
        let tableView = SPTableView(frame: .zero)
        tableView.identifier = NSUserInterfaceItemIdentifier("TableStructureColumnsTableView")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.style = .plain
        tableView.allowsExpansionToolTips = true
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.focusRingType = .none
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = Self.tableRowHeight(for: UserDefaults.getFont())

        for column in structureColumns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.key))
            tableColumn.title = column.title
            tableColumn.width = savedWidth(for: column.key, inIndexesTable: false) ?? column.width
            tableColumn.minWidth = column.minWidth
            tableColumn.maxWidth = column.maxWidth
            tableColumn.isEditable = column.editable
            tableColumn.resizingMask = .userResizingMask
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.key, ascending: true)

            if column.isBoolean {
                let cell = NSButtonCell()
                cell.setButtonType(.switch)
                cell.title = ""
                cell.allowsMixedState = false
                tableColumn.dataCell = cell
            } else if let comboCell = comboBoxCell(for: column.key) {
                tableColumn.dataCell = comboCell
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

    private lazy var indexesGrabberView: NSImageView = {
        let imageView = NSImageView(frame: .zero)
        imageView.image = NSImage(named: NSImage.Name("grabber-horizontal"))
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var indexesTableView: NSTableView = {
        let tableView = SPTableView(frame: .zero)
        tableView.identifier = NSUserInterfaceItemIdentifier("TableStructureIndexesTableView")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.style = .plain
        tableView.allowsExpansionToolTips = true
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.focusRingType = .none
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = Self.tableRowHeight(for: UserDefaults.getFont())

        for column in indexColumns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.key))
            tableColumn.title = column.title
            tableColumn.width = savedWidth(for: column.key, inIndexesTable: true) ?? column.width
            tableColumn.minWidth = column.minWidth
            tableColumn.maxWidth = 1000
            tableColumn.resizingMask = .userResizingMask
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.key, ascending: true)
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

    private lazy var addFieldButton = toolbarButton(imageName: "NSAddTemplate", toolTip: NSLocalizedString("Add field (⌥⌘A)", comment: "add field tooltip"), keyEquivalent: "a", modifierMask: [.command, .option], action: #selector(addField(_:)))
    private lazy var removeFieldButton = toolbarButton(imageName: "NSRemoveTemplate", toolTip: NSLocalizedString("Delete selected field (⌫)", comment: "remove field tooltip"), keyEquivalent: "\u{7F}", action: #selector(removeField(_:)))
    private lazy var duplicateFieldButton = toolbarButton(imageName: "button_duplicateTemplate", toolTip: NSLocalizedString("Duplicate selected field (⌘D)", comment: "duplicate field tooltip"), keyEquivalent: "d", modifierMask: .command, action: #selector(duplicateField(_:)))
    private lazy var reloadFieldsButton = toolbarButton(imageName: "NSRefreshTemplate", toolTip: NSLocalizedString("Refresh table structure (⌘R)", comment: "refresh structure tooltip"), keyEquivalent: "r", modifierMask: .command, action: #selector(reloadTable(_:)))
    private lazy var addIndexButton = toolbarButton(imageName: "NSAddTemplate", toolTip: NSLocalizedString("Add index", comment: "add index tooltip"), action: #selector(addIndex(_:)))
    private lazy var removeIndexButton = toolbarButton(imageName: "NSRemoveTemplate", toolTip: NSLocalizedString("Delete selected index", comment: "remove index tooltip"), action: #selector(removeIndex(_:)))
    private lazy var refreshIndexesButton = toolbarButton(imageName: "NSRefreshTemplate", toolTip: NSLocalizedString("Refresh table indexes (⌘R)", comment: "refresh indexes tooltip"), keyEquivalent: "r", modifierMask: .command, action: #selector(reloadTable(_:)))

    override func loadView() {
        let rootView = NSView(frame: .zero)

        tablesIndexesSplitView.dividerStyle = .thin
        tablesIndexesSplitView.isVertical = false
        tablesIndexesSplitView.delegate = self

        let structurePane = NSView(frame: .zero)
        let structureScrollView = NSScrollView(frame: .zero)
        structureScrollView.borderType = .noBorder
        structureScrollView.focusRingType = .none
        structureScrollView.hasVerticalScroller = true
        structureScrollView.hasHorizontalScroller = true
        structureScrollView.autohidesScrollers = true
        structureScrollView.verticalLineScroll = 27
        structureScrollView.horizontalLineScroll = 27
        structureScrollView.contentView.drawsBackground = false
        structureScrollView.documentView = structureTableView
        structureScrollView.translatesAutoresizingMaskIntoConstraints = false

        let structureToolbar = toolbarView(buttons: [addFieldButton, removeFieldButton, duplicateFieldButton, reloadFieldsButton])
        structurePane.addSubview(structureFilterField)
        structurePane.addSubview(structureScrollView)
        structurePane.addSubview(structureToolbar)
        tablesIndexesSplitView.addSubview(structurePane)

        let indexPane = NSView(frame: .zero)
        let indexScrollView = NSScrollView(frame: .zero)
        indexScrollView.borderType = .noBorder
        indexScrollView.focusRingType = .none
        indexScrollView.hasVerticalScroller = true
        indexScrollView.hasHorizontalScroller = true
        indexScrollView.autohidesScrollers = true
        indexScrollView.verticalLineScroll = 18
        indexScrollView.horizontalLineScroll = 18
        indexScrollView.contentView.drawsBackground = false
        indexScrollView.documentView = indexesTableView
        indexScrollView.translatesAutoresizingMaskIntoConstraints = false

        let indexToolbar = toolbarView(buttons: [addIndexButton, removeIndexButton, refreshIndexesButton])
        indexesHeaderView.addSubview(indexesLabel)
        indexesHeaderView.addSubview(indexesGrabberView)
        indexPane.addSubview(indexesHeaderView)
        indexPane.addSubview(indexScrollView)
        indexPane.addSubview(indexToolbar)
        tablesIndexesSplitView.addSubview(indexPane)
        rootView.addSubview(tablesIndexesSplitView)
        tablesIndexesSplitView.setMinSize(130, ofSubviewAt: 0)
        tablesIndexesSplitView.setMinSize(130, ofSubviewAt: 1)
        tablesIndexesSplitView.setAdditionalDragHandle(indexesHeaderView)

        tablesIndexesSplitView.translatesAutoresizingMaskIntoConstraints = false
        indexesHeaderView.translatesAutoresizingMaskIntoConstraints = false
        structureFilterField.translatesAutoresizingMaskIntoConstraints = false
        structureToolbar.translatesAutoresizingMaskIntoConstraints = false
        indexToolbar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tablesIndexesSplitView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            tablesIndexesSplitView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tablesIndexesSplitView.topAnchor.constraint(equalTo: rootView.topAnchor),
            tablesIndexesSplitView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

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

            indexesHeaderView.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor),
            indexesHeaderView.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor),
            indexesHeaderView.topAnchor.constraint(equalTo: indexPane.topAnchor),
            indexesHeaderView.heightAnchor.constraint(equalToConstant: 20),

            indexesLabel.leadingAnchor.constraint(equalTo: indexesHeaderView.leadingAnchor, constant: 6),
            indexesLabel.centerYAnchor.constraint(equalTo: indexesHeaderView.centerYAnchor),

            indexesGrabberView.trailingAnchor.constraint(equalTo: indexesHeaderView.trailingAnchor, constant: -7),
            indexesGrabberView.centerYAnchor.constraint(equalTo: indexesHeaderView.centerYAnchor),
            indexesGrabberView.widthAnchor.constraint(equalToConstant: 10),
            indexesGrabberView.heightAnchor.constraint(equalToConstant: 13),

            indexScrollView.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor),
            indexScrollView.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor),
            indexScrollView.topAnchor.constraint(equalTo: indexesHeaderView.bottomAnchor),
            indexScrollView.bottomAnchor.constraint(equalTo: indexToolbar.topAnchor),

            indexToolbar.leadingAnchor.constraint(equalTo: indexPane.leadingAnchor),
            indexToolbar.trailingAnchor.constraint(equalTo: indexPane.trailingAnchor),
            indexToolbar.bottomAnchor.constraint(equalTo: indexPane.bottomAnchor),
            indexToolbar.heightAnchor.constraint(equalToConstant: 26)
        ])

        applyTableFont()
        UserDefaults.standard.addObserver(self, forKeyPath: SPGlobalFontSettings, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: SPDisplayTableViewVerticalGridlines, options: .new, context: nil)
        didRegisterPreferenceObservers = true

        view = rootView
    }

    deinit {
        guard didRegisterPreferenceObservers else { return }

        UserDefaults.standard.removeObserver(self, forKeyPath: SPGlobalFontSettings)
        UserDefaults.standard.removeObserver(self, forKeyPath: SPDisplayTableViewVerticalGridlines)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        if !didSetInitialTablesIndexesSplitPosition && tablesIndexesSplitView.bounds.height > 0 {
            let initialDividerPosition = max(130, tablesIndexesSplitView.bounds.height - 202)
            tablesIndexesSplitView.setPosition(initialDividerPosition, ofDividerAt: 0)
            didSetInitialTablesIndexesSplitPosition = true
        }
    }

    func clearCachedTables() {
        structureCache.removeAll()
        structureCacheOrder.removeAll()
    }

    func loadStructure(for table: String, database: String, connection: SPMySQLConnection, useCache: Bool = true) {
        cacheCurrentStructureState()

        self.table = table
        self.database = database
        self.connection = connection
        applySavedColumnWidths()
        loadToken = UUID()
        let token = loadToken

        if useCache, restoreCachedStructure(for: structureCacheKey(database: database, table: table)) {
            return
        }

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
                self.applyIndexSort()
                self.structureTableView.reloadData()
                self.indexesTableView.reloadData()
                self.autosizeStructureColumns()
                self.autosizeIndexColumns()
                self.resetScrollPositionsAfterLayout()
                self.updateButtonState()
                self.cacheCurrentStructureState()

                DispatchQueue.main.async {
                    guard self.loadToken == token else { return }

                    self.autosizeStructureColumns()
                    self.autosizeIndexColumns()
                    self.resetScrollPositionsAfterLayout()
                }
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
        let result = connection.queryString("SHOW INDEX FROM \(Self.backtickQuoted(table)) FROM \(Self.backtickQuoted(database))")
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
        let id = displayedRows[displayedRow].id
        return rows.firstIndex { $0.id == id }
    }

    private func displayedIndex(forRowID rowID: UUID) -> Int? {
        return displayRows().firstIndex { $0.id == rowID }
    }

    private func applyFilter() {
        let filter = structureFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var displayedRows = rows

        if !filter.isEmpty {
            displayedRows = displayedRows.filter { row in
                structureColumns.contains { column in
                    (row.values[column.key] ?? "").range(of: filter, options: .caseInsensitive) != nil
                }
            }
        }

        if let structureSortKey = structureSortKey {
            displayedRows.sort { first, second in
                compare(first.values[structureSortKey] ?? "", second.values[structureSortKey] ?? "", ascending: structureSortAscending)
            }
        }

        guard !filter.isEmpty || structureSortKey != nil else {
            filteredRows = nil
            return
        }

        filteredRows = displayedRows
    }

    private func compare(_ first: String, _ second: String, ascending: Bool) -> Bool {
        let result = first.localizedStandardCompare(second)
        if result == .orderedSame {
            return false
        }

        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    private func resetStructureFilteringForInsertion() {
        structureFilterField.stringValue = ""
        structureSortKey = nil
        structureTableView.sortDescriptors = []
        filteredRows = nil
    }

    private func applyIndexSort() {
        guard let indexSortKey = indexSortKey else { return }

        indexes.sort { first, second in
            compare(first[indexSortKey] ?? "", second[indexSortKey] ?? "", ascending: indexSortAscending)
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
            query = "ALTER TABLE \(tableReference()) CHANGE \(Self.backtickQuoted(oldRow.originalName ?? oldRow.name)) \(columnDefinition(for: row))"
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
                self.invalidateCurrentStructureCache()
                self.tableStructureDidChange?()
                self.loadStructure(for: self.table, database: self.database, connection: connection, useCache: false)
            }
        }
    }

    private func addColumnQuery(for row: StructureRow, at index: Int) -> String {
        var query = "ALTER TABLE \(tableReference()) ADD \(columnDefinition(for: row))"
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
        autosizeStructureColumns()
        resetScrollPositionsAfterLayout()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == SPGlobalFontSettings {
            applyTableFont()
            structureTableView.reloadData()
            indexesTableView.reloadData()
            autosizeStructureColumns()
            autosizeIndexColumns()
            return
        }

        if keyPath == SPDisplayTableViewVerticalGridlines {
            let gridStyle: NSTableView.GridLineStyle = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
            structureTableView.gridStyleMask = gridStyle
            indexesTableView.gridStyleMask = gridStyle
            return
        }

        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }

    private func applyTableFont() {
        let tableFont = UserDefaults.getFont()
        let rowHeight = Self.tableRowHeight(for: tableFont)

        structureTableView.rowHeight = rowHeight
        indexesTableView.rowHeight = rowHeight

        for tableColumn in structureTableView.tableColumns {
            (tableColumn.dataCell as? NSCell)?.font = tableFont
        }

        for tableColumn in indexesTableView.tableColumns {
            (tableColumn.dataCell as? NSCell)?.font = tableFont
        }
    }

    private static func tableRowHeight(for font: NSFont) -> CGFloat {
        return 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: font]).height
    }

    private func autosizeStructureColumns() {
        isApplyingProgrammaticColumnWidths = true
        defer { isApplyingProgrammaticColumnWidths = false }

        let rowsToMeasure = displayRows()
        for column in structureColumns {
            guard let tableColumn = structureTableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(column.key)) else { continue }
            if savedWidth(for: column.key, inIndexesTable: false) != nil {
                continue
            }

            var targetWidth = measuredHeaderWidth(for: tableColumn)
            if column.isBoolean {
                targetWidth = max(targetWidth, 22)
            } else {
                for row in rowsToMeasure {
                    let value = row.values[column.key] ?? ""
                    targetWidth = max(targetWidth, measuredCellWidth(value, in: tableColumn))
                }
            }

            targetWidth += 18
            targetWidth = ceil(max(targetWidth, column.minWidth))
            tableColumn.maxWidth = max(tableColumn.maxWidth, targetWidth)
            tableColumn.width = targetWidth
        }
    }

    private func autosizeIndexColumns() {
        isApplyingProgrammaticColumnWidths = true
        defer { isApplyingProgrammaticColumnWidths = false }

        for column in indexColumns {
            guard let tableColumn = indexesTableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(column.key)) else { continue }
            if savedWidth(for: column.key, inIndexesTable: true) != nil {
                continue
            }

            var targetWidth = measuredHeaderWidth(for: tableColumn)
            for row in indexes {
                targetWidth = max(targetWidth, measuredCellWidth(row[column.key] ?? "", in: tableColumn))
            }

            targetWidth = ceil(max(targetWidth + 18, column.minWidth))
            tableColumn.maxWidth = max(tableColumn.maxWidth, targetWidth)
            tableColumn.width = targetWidth
        }
    }

    private func measuredHeaderWidth(for tableColumn: NSTableColumn) -> CGFloat {
        let headerCell = tableColumn.headerCell
        let title = headerCell.stringValue as NSString
        let font = headerCell.font ?? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)

        return max(headerCell.cellSize.width, title.size(withAttributes: [.font: font]).width)
    }

    private func measuredCellWidth(_ value: String, in tableColumn: NSTableColumn) -> CGFloat {
        guard let cell = (tableColumn.dataCell as? NSCell)?.copy() as? NSCell else {
            return (value as NSString).size(withAttributes: [.font: UserDefaults.getFont()]).width
        }

        cell.stringValue = value
        let font = cell.font ?? UserDefaults.getFont()

        return max(cell.cellSize.width, (value as NSString).size(withAttributes: [.font: font]).width)
    }

    private func resetScrollPositionsAfterLayout() {
        structureTableView.layoutSubtreeIfNeeded()
        indexesTableView.layoutSubtreeIfNeeded()
        structureTableView.scrollColumnToVisible(0)
        indexesTableView.scrollColumnToVisible(0)

        if structureTableView.numberOfRows > 0 {
            structureTableView.scrollRowToVisible(0)
        }

        if indexesTableView.numberOfRows > 0 {
            indexesTableView.scrollRowToVisible(0)
        }
    }

    private func updateButtonState() {
        let hasStructureSelection = structureTableView.selectedRow >= 0
        removeFieldButton.isEnabled = !isSaving && hasStructureSelection && rows.count > 1
        duplicateFieldButton.isEnabled = !isSaving && hasStructureSelection
        removeIndexButton.isEnabled = !isSaving && indexesTableView.selectedRow >= 0
        addIndexButton.isEnabled = !isSaving && !rows.isEmpty
    }

    private func isStructureTable(_ tableView: NSTableView) -> Bool {
        return tableView.identifier?.rawValue == "TableStructureColumnsTableView"
    }

    private func isIndexesTable(_ tableView: NSTableView) -> Bool {
        return tableView.identifier?.rawValue == "TableStructureIndexesTableView"
    }

    private func comboBoxCell(for key: String) -> NSComboBoxCell? {
        let values: [String]
        switch key {
        case "type":
            values = typeSuggestions
        case "Extra":
            values = extraSuggestions
        case "encodingName":
            values = encodingSuggestions
        case "collationName":
            values = collationSuggestions
        default:
            return nil
        }

        let cell = NSComboBoxCell(textCell: "")
        cell.addItems(withObjectValues: values)
        cell.isEditable = true
        cell.isSelectable = true
        cell.usesDataSource = false
        cell.completes = true
        cell.numberOfVisibleItems = key == "Extra" ? 4 : 10
        cell.isButtonBordered = false
        cell.lineBreakMode = .byTruncatingTail
        cell.font = UserDefaults.getFont()
        return cell
    }

    private func toolbarButton(imageName: String, toolTip: String, keyEquivalent: String = "", modifierMask: NSEvent.ModifierFlags = [], action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(named: NSImage.Name(imageName)) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .smallSquare
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = modifierMask
        button.contentTintColor = .labelColor
        button.widthAnchor.constraint(equalToConstant: 25).isActive = true
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

    private func savedWidthKey(for columnKey: String, inIndexesTable: Bool) -> String {
        return "\(inIndexesTable ? "indexes" : "structure").\(columnKey)"
    }

    private func savedWidth(for columnKey: String, inIndexesTable: Bool) -> CGFloat? {
        guard let host = connection?.host,
              !host.isEmpty,
              let savedWidths = UserDefaults.standard.dictionary(forKey: SPTableColumnWidths),
              let databaseWidths = savedWidths["\(database)@\(host)"] as? [String: Any],
              let tableWidths = databaseWidths[table] as? [String: Any],
              let width = tableWidths[savedWidthKey(for: columnKey, inIndexesTable: inIndexesTable)] as? NSNumber else { return nil }

        return CGFloat(truncating: width)
    }

    private func saveWidth(for tableColumn: NSTableColumn, inIndexesTable: Bool) {
        guard !isApplyingProgrammaticColumnWidths,
              let host = connection?.host,
              !host.isEmpty else { return }

        let databaseKey = "\(database)@\(host)"
        let columnKey = savedWidthKey(for: tableColumn.identifier.rawValue, inIndexesTable: inIndexesTable)
        var savedWidths = UserDefaults.standard.dictionary(forKey: SPTableColumnWidths) ?? [:]
        var databaseWidths = savedWidths[databaseKey] as? [String: Any] ?? [:]
        var tableWidths = databaseWidths[table] as? [String: Any] ?? [:]

        tableWidths[columnKey] = NSNumber(value: Double(tableColumn.width))
        databaseWidths[table] = tableWidths
        savedWidths[databaseKey] = databaseWidths
        UserDefaults.standard.set(savedWidths, forKey: SPTableColumnWidths)
    }

    private func applySavedColumnWidths() {
        isApplyingProgrammaticColumnWidths = true
        defer { isApplyingProgrammaticColumnWidths = false }

        for tableColumn in structureTableView.tableColumns {
            guard let width = savedWidth(for: tableColumn.identifier.rawValue, inIndexesTable: false) else { continue }
            tableColumn.width = width
        }

        for tableColumn in indexesTableView.tableColumns {
            guard let width = savedWidth(for: tableColumn.identifier.rawValue, inIndexesTable: true) else { continue }
            tableColumn.width = width
        }
    }

    private static func displayString(for value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "" }
        return String(describing: value)
    }

    private static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    private func tableReference() -> String {
        return "\(Self.backtickQuoted(database)).\(Self.backtickQuoted(table))"
    }
}

private extension SALightweightStructureViewController {
    @objc func filterChanged(_ sender: NSSearchField) {
        reloadVisibleRows()
        cacheCurrentStructureState()
    }

    @objc func addField(_ sender: Any?) {
        let selectedRow = structureTableView.selectedRow
        let selectedSourceIndex = sourceIndex(forDisplayedRow: selectedRow)
        let insertIndex = selectedSourceIndex.map { $0 + 1 } ?? rows.count
        resetStructureFilteringForInsertion()
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
        if let displayedIndex = displayedIndex(forRowID: row.id) {
            structureTableView.selectRowIndexes(IndexSet(integer: displayedIndex), byExtendingSelection: false)
            structureTableView.editColumn(0, row: displayedIndex, with: nil, select: true)
        }
        updateButtonState()
    }

    @objc func duplicateField(_ sender: Any?) {
        let selectedRow = structureTableView.selectedRow
        guard let sourceIndex = sourceIndex(forDisplayedRow: selectedRow) else { return }
        resetStructureFilteringForInsertion()
        var values = rows[sourceIndex].values
        values["name"] = rows[sourceIndex].name + "Copy"
        values["Key"] = ""
        values["Extra"] = "None"
        let row = StructureRow(values: values, originalName: nil, isNew: true)
        rows.insert(row, at: sourceIndex + 1)
        reloadVisibleRows()
        if let displayedIndex = displayedIndex(forRowID: row.id) {
            structureTableView.selectRowIndexes(IndexSet(integer: displayedIndex), byExtendingSelection: false)
            structureTableView.editColumn(0, row: displayedIndex, with: nil, select: true)
        }
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
            let query = "ALTER TABLE \(self.tableReference()) DROP \(Self.backtickQuoted(row.name))"
            connection.queryString(query)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error, !error.isEmpty {
                    self.showError(title: NSLocalizedString("Error deleting field", comment: "delete field error title"), message: error)
                    return
                }

                self.invalidateCurrentStructureCache()
                self.tableStructureDidChange?()
                self.loadStructure(for: self.table, database: self.database, connection: connection, useCache: false)
            }
        }
    }

    @objc func reloadTable(_ sender: Any?) {
        guard let connection = connection else { return }
        invalidateCurrentStructureCache()
        loadStructure(for: table, database: database, connection: connection, useCache: false)
    }

    private func structureCacheKey(database: String? = nil, table: String? = nil) -> String {
        return "\(database ?? self.database)\u{0}\(table ?? self.table)"
    }

    private func restoreCachedStructure(for key: String) -> Bool {
        guard let cached = structureCache[key] else { return false }

        rows = cached.rows
        indexes = cached.indexes
        structureFilterField.stringValue = cached.filterString
        structureSortKey = cached.structureSortKey
        structureSortAscending = cached.structureSortAscending
        indexSortKey = cached.indexSortKey
        indexSortAscending = cached.indexSortAscending
        structureTableView.sortDescriptors = cached.structureSortKey.map { [NSSortDescriptor(key: $0, ascending: cached.structureSortAscending)] } ?? []
        indexesTableView.sortDescriptors = cached.indexSortKey.map { [NSSortDescriptor(key: $0, ascending: cached.indexSortAscending)] } ?? []
        applyFilter()
        applyIndexSort()
        structureTableView.reloadData()
        indexesTableView.reloadData()
        autosizeStructureColumns()
        autosizeIndexColumns()
        resetScrollPositionsAfterLayout()
        updateButtonState()
        noteStructureCacheUse(for: key)
        return true
    }

    private func cacheCurrentStructureState() {
        guard !database.isEmpty, !table.isEmpty, !rows.isEmpty else { return }

        let key = structureCacheKey()
        structureCache[key] = StructureCacheEntry(rows: rows,
                                                 indexes: indexes,
                                                 filterString: structureFilterField.stringValue,
                                                 structureSortKey: structureSortKey,
                                                 structureSortAscending: structureSortAscending,
                                                 indexSortKey: indexSortKey,
                                                 indexSortAscending: indexSortAscending)
        noteStructureCacheUse(for: key)
    }

    private func noteStructureCacheUse(for key: String) {
        structureCacheOrder.removeAll { $0 == key }
        structureCacheOrder.append(key)

        while structureCacheOrder.count > maximumStructureCacheEntries {
            let oldKey = structureCacheOrder.removeFirst()
            structureCache.removeValue(forKey: oldKey)
        }
    }

    private func invalidateCurrentStructureCache() {
        let key = structureCacheKey()
        structureCache.removeValue(forKey: key)
        structureCacheOrder.removeAll { $0 == key }
    }

    @objc func addIndex(_ sender: Any?) {
        let selectedRow = structureTableView.selectedRow >= 0 ? structureTableView.selectedRow : 0
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
        var query = "ALTER TABLE \(tableReference()) ADD \(type)"
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

                self.invalidateCurrentStructureCache()
                self.tableStructureDidChange?()
                self.loadStructure(for: self.table, database: self.database, connection: connection, useCache: false)
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
            ? "ALTER TABLE \(tableReference()) DROP PRIMARY KEY"
            : "ALTER TABLE \(tableReference()) DROP INDEX \(Self.backtickQuoted(indexName))"

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

                self.invalidateCurrentStructureCache()
                self.tableStructureDidChange?()
                self.loadStructure(for: self.table, database: self.database, connection: connection, useCache: false)
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

    func tableViewColumnDidResize(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView,
              let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }

        if isStructureTable(tableView) {
            saveWidth(for: tableColumn, inIndexesTable: false)
        } else if isIndexesTable(tableView) {
            saveWidth(for: tableColumn, inIndexesTable: true)
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key else { return }

        if isStructureTable(tableView) {
            structureSortKey = key
            structureSortAscending = descriptor.ascending
            reloadVisibleRows()
            cacheCurrentStructureState()
        } else if isIndexesTable(tableView) {
            indexSortKey = key
            indexSortAscending = descriptor.ascending
            applyIndexSort()
            indexesTableView.reloadData()
            autosizeIndexColumns()
            cacheCurrentStructureState()
        }
    }

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
        guard isStructureTable(tableView),
              structureFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              structureSortKey == nil,
              let row = rowIndexes.first,
              let sourceIndex = sourceIndex(forDisplayedRow: row) else { return false }
        pasteboard.declareTypes([NSPasteboard.PasteboardType("SequelAceLightweightStructureRow")], owner: nil)
        pasteboard.setString(rows[sourceIndex].id.uuidString, forType: NSPasteboard.PasteboardType("SequelAceLightweightStructureRow"))
        return true
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard isStructureTable(tableView),
              dropOperation == .above,
              row >= 0,
              !isSaving,
              structureFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              structureSortKey == nil else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row destinationRow: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard isStructureTable(tableView),
              let connection = connection,
              let sourceIDString = info.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("SequelAceLightweightStructureRow")),
              let sourceID = UUID(uuidString: sourceIDString),
              let sourceIndex = rows.firstIndex(where: { $0.id == sourceID }),
              sourceIndex >= 0,
              sourceIndex < rows.count else { return false }

        let movingRow = rows[sourceIndex]
        let destinationIndex = max(0, min(destinationRow, rows.count))
        guard destinationIndex != sourceIndex, destinationIndex != sourceIndex + 1 else { return false }
        var query = "ALTER TABLE \(tableReference()) MODIFY COLUMN \(columnDefinition(for: movingRow))"
        if destinationIndex == 0 {
            query += " FIRST"
        } else {
            let afterIndex = destinationIndex - 1
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

                self.invalidateCurrentStructureCache()
                self.tableStructureDidChange?()
                self.loadStructure(for: self.table, database: self.database, connection: connection, useCache: false)
            }
        }

        return true
    }
}

extension SALightweightStructureViewController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return true
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMaximumPosition - 130
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMinimumPosition + 130
    }
}
