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

    private struct EncodingOption {
        let title: String
        let name: String
        let maxLength: UInt
    }

    private struct ForeignKeyConstraint {
        let name: String
        let columns: [String]
        let referencedTable: String
    }

    fileprivate struct IndexField {
        var name: String
        var type: String
        var size: String
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

    private let typeSuggestions = ["TINYINT", "SMALLINT", "MEDIUMINT", "INT", "BIGINT", "FLOAT", "DOUBLE", "DOUBLE PRECISION", "REAL", "DECIMAL", "BIT", "SERIAL", "BOOL", "BOOLEAN", "DEC", "FIXED", "NUMERIC", "--------", "CHAR", "VARCHAR", "TINYTEXT", "TEXT", "MEDIUMTEXT", "LONGTEXT", "TINYBLOB", "MEDIUMBLOB", "BLOB", "LONGBLOB", "BINARY", "VARBINARY", "JSON", "ENUM", "SET", "--------", "DATE", "DATETIME", "TIMESTAMP", "TIME", "YEAR", "--------", "GEOMETRY", "POINT", "LINESTRING", "POLYGON", "MULTIPOINT", "MULTILINESTRING", "MULTIPOLYGON", "GEOMETRYCOLLECTION"]
    private let extraSuggestions = ["None", "auto_increment", "on update CURRENT_TIMESTAMP", "SERIAL DEFAULT VALUE"]
    private var encodingOptions: [EncodingOption] = []
    private var collationOptionsByEncoding: [String: [String]] = [:]
    private var allCollationOptions: [String] = []
    private var tableEncoding = ""
    private var tableCollation = ""
    private var tableEngine = ""
    private var foreignKeyConstraints: [ForeignKeyConstraint] = []
    private var pendingAutoIncrementIndex: String?
    private var indexSheetController: SALightweightStructureIndexSheetController?

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
    var requestTableInfoView: (() -> Void)?

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
        tableView.menu = structureContextMenu()
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

        tableView.menu = indexesContextMenu()
        return tableView
    }()

    private lazy var addFieldButton = toolbarButton(imageName: "NSAddTemplate", toolTip: NSLocalizedString("Add field (⌥⌘A)", comment: "add field tooltip"), keyEquivalent: "a", modifierMask: [.command, .option], action: #selector(addField(_:)))
    private lazy var removeFieldButton = toolbarButton(imageName: "NSRemoveTemplate", toolTip: NSLocalizedString("Delete selected field (⌫)", comment: "remove field tooltip"), keyEquivalent: "\u{7F}", action: #selector(removeField(_:)))
    private lazy var duplicateFieldButton = toolbarButton(imageName: "button_duplicateTemplate", toolTip: NSLocalizedString("Duplicate selected field (⌘D)", comment: "duplicate field tooltip"), keyEquivalent: "d", modifierMask: .command, action: #selector(duplicateField(_:)))
    private lazy var reloadFieldsButton = toolbarButton(imageName: "NSRefreshTemplate", toolTip: NSLocalizedString("Refresh table structure (⌘R)", comment: "refresh structure tooltip"), keyEquivalent: "r", modifierMask: .command, action: #selector(reloadTable(_:)))
    private lazy var showIndexesButton: NSButton = {
        let button = toolbarButton(imageName: "NSQuickLookTemplate", toolTip: NSLocalizedString("Reveal indexes", comment: "show indexes tooltip"), action: #selector(showIndexes(_:)))
        button.isHidden = true
        return button
    }()
    private lazy var editTableDetailsButton = toolbarButton(imageName: "NSSmartBadgeTemplate", toolTip: NSLocalizedString("Edit Table Details (⌘4)", comment: "edit table details tooltip"), keyEquivalent: "4", modifierMask: .command, action: #selector(showTableDetails(_:)))
    private lazy var viewColumnsButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .regularSquare
        button.controlSize = .small
        button.image = NSImage(named: NSImage.Name("NSActionTemplate"))
        button.imagePosition = .imageOnly
        button.toolTip = NSLocalizedString("View Columns", comment: "view structure columns tooltip")

        let menu = NSMenu(title: "")
        let imageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        imageItem.image = NSImage(named: NSImage.Name("NSActionTemplate"))
        menu.addItem(imageItem)

        let submenuItem = NSMenuItem(title: NSLocalizedString("View Columns", comment: "view structure columns menu title"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: submenuItem.title)
        for column in structureColumns where ["Key", "encodingName", "collationName", "comment"].contains(column.key) {
            let item = NSMenuItem(title: column.title, action: #selector(toggleStructureColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.key
            item.state = .on
            submenu.addItem(item)
        }
        submenuItem.submenu = submenu
        menu.addItem(submenuItem)
        button.menu = menu
        return button
    }()
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

        let structureToolbar = toolbarView(buttons: [addFieldButton, removeFieldButton, duplicateFieldButton, reloadFieldsButton, showIndexesButton])
        structureToolbar.addSubview(editTableDetailsButton)
        structureToolbar.addSubview(viewColumnsButton)
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
        editTableDetailsButton.translatesAutoresizingMaskIntoConstraints = false
        viewColumnsButton.translatesAutoresizingMaskIntoConstraints = false
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

            viewColumnsButton.trailingAnchor.constraint(equalTo: structureToolbar.trailingAnchor, constant: -6),
            viewColumnsButton.topAnchor.constraint(equalTo: structureToolbar.topAnchor),
            viewColumnsButton.bottomAnchor.constraint(equalTo: structureToolbar.bottomAnchor),
            viewColumnsButton.widthAnchor.constraint(equalToConstant: 35),

            editTableDetailsButton.trailingAnchor.constraint(equalTo: viewColumnsButton.leadingAnchor, constant: -5),
            editTableDetailsButton.topAnchor.constraint(equalTo: structureToolbar.topAnchor),
            editTableDetailsButton.bottomAnchor.constraint(equalTo: structureToolbar.bottomAnchor),

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

    func cachedColumnMetadata(for table: String, database: String) -> [[String: String]]? {
        let key = structureCacheKey(database: database, table: table)
        if let cached = structureCache[key], !cached.rows.isEmpty {
            return cached.rows.map { $0.values }
        }

        guard self.database == database, self.table == table, !rows.isEmpty else { return nil }
        return rows.map { $0.values }
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
            let tableMetadata = self.loadTableMetadata(table: table, database: database, connection: connection)
            let encodingOptions = self.loadEncodingOptions(connection: connection)
            let collationOptionsByEncoding = self.loadCollationOptions(connection: connection)
            let foreignKeyConstraints = self.loadForeignKeyConstraints(table: table, database: database, connection: connection)
            let fields = self.loadFields(table: table, database: database, connection: connection)
            let indexes = self.loadIndexes(table: table, connection: connection)

            DispatchQueue.main.async {
                guard self.loadToken == token else { return }

                self.tableEncoding = tableMetadata.encoding
                self.tableCollation = tableMetadata.collation
                self.tableEngine = tableMetadata.engine
                self.encodingOptions = encodingOptions
                self.collationOptionsByEncoding = collationOptionsByEncoding
                self.allCollationOptions = Self.uniqueStrings(collationOptionsByEncoding.values.flatMap { $0 })
                self.foreignKeyConstraints = foreignKeyConstraints
                self.refreshStructureComboCells()
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

    private func loadTableMetadata(table: String, database: String, connection: SPMySQLConnection) -> (engine: String, encoding: String, collation: String) {
        let query = "SHOW TABLE STATUS FROM \(Self.backtickQuoted(database)) WHERE Name = \(Self.sqlString(table, connection: connection))"
        guard let result = connection.queryString(query) else { return ("", "", "") }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return ("", "", "") }

        let engine = Self.displayString(for: row["Engine"] ?? row["Type"])
        let collation = Self.displayString(for: row["Collation"])
        return (engine, Self.encodingName(from: collation), collation)
    }

    private func loadEncodingOptions(connection: SPMySQLConnection) -> [EncodingOption] {
        let queries = [
            "SELECT CHARACTER_SET_NAME, DESCRIPTION, MAXLEN FROM information_schema.character_sets ORDER BY character_set_name ASC",
            "SHOW CHARACTER SET"
        ]

        for query in queries {
            guard let result = connection.queryString(query) else { continue }

            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            var encodings: [EncodingOption] = []

            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = Self.displayString(for: row["CHARACTER_SET_NAME"] ?? row["Charset"])
                guard !name.isEmpty else { continue }
                let description = Self.displayString(for: row["DESCRIPTION"] ?? row["Description"])
                let title = description.isEmpty ? name : "\(description) (\(name))"
                let maxLengthString = Self.displayString(for: row["MAXLEN"] ?? row["Maxlen"])
                encodings.append(EncodingOption(title: title, name: name, maxLength: UInt(maxLengthString) ?? 1))
            }

            if !encodings.isEmpty {
                return encodings
            }
        }

        return []
    }

    private func loadCollationOptions(connection: SPMySQLConnection) -> [String: [String]] {
        let queries = [
            "SELECT COLLATION_NAME, CHARACTER_SET_NAME FROM information_schema.collations ORDER BY collation_name ASC",
            "SHOW COLLATION"
        ]

        for query in queries {
            guard let result = connection.queryString(query) else { continue }

            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            var collationsByEncoding: [String: [String]] = [:]

            while let row = result.getRowAsDictionary() as? [String: Any] {
                let collation = Self.displayString(for: row["COLLATION_NAME"] ?? row["Collation"])
                let encoding = Self.displayString(for: row["CHARACTER_SET_NAME"] ?? row["Charset"])
                guard !collation.isEmpty, !encoding.isEmpty else { continue }
                collationsByEncoding[encoding, default: []].append(collation)
            }

            if !collationsByEncoding.isEmpty {
                return collationsByEncoding.mapValues { Self.uniqueStrings($0).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
            }
        }

        return [:]
    }

    private func loadForeignKeyConstraints(table: String, database: String, connection: SPMySQLConnection) -> [ForeignKeyConstraint] {
        let query = """
            SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, ORDINAL_POSITION
            FROM information_schema.KEY_COLUMN_USAGE
            WHERE TABLE_SCHEMA = \(Self.sqlString(database, connection: connection))
              AND TABLE_NAME = \(Self.sqlString(table, connection: connection))
              AND REFERENCED_TABLE_NAME IS NOT NULL
            ORDER BY CONSTRAINT_NAME, ORDINAL_POSITION
            """
        guard let result = connection.queryString(query) else { return [] }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        var grouped: [String: (columns: [String], referencedTable: String)] = [:]

        while let row = result.getRowAsDictionary() as? [String: Any] {
            let name = Self.displayString(for: row["CONSTRAINT_NAME"])
            let column = Self.displayString(for: row["COLUMN_NAME"])
            let referencedTable = Self.displayString(for: row["REFERENCED_TABLE_NAME"])
            guard !name.isEmpty, !column.isEmpty else { continue }
            var entry = grouped[name] ?? ([], referencedTable)
            entry.columns.append(column)
            if entry.referencedTable.isEmpty {
                entry.referencedTable = referencedTable
            }
            grouped[name] = entry
        }

        return grouped.map { ForeignKeyConstraint(name: $0.key, columns: $0.value.columns, referencedTable: $0.value.referencedTable) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
            var changeQuery = "ALTER TABLE \(tableReference()) CHANGE \(Self.backtickQuoted(oldRow.originalName ?? oldRow.name)) \(columnDefinition(for: row))"
            if let autoIncrementIndex = pendingAutoIncrementIndex {
                if autoIncrementIndex == "PRIMARY KEY" {
                    changeQuery += ", ADD PRIMARY KEY (\(Self.backtickQuoted(row.name)))"
                } else {
                    changeQuery += ", ADD \(autoIncrementIndex) (\(Self.backtickQuoted(row.name)))"
                }
            }
            query = changeQuery
        }
        pendingAutoIncrementIndex = nil

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
        if let autoIncrementIndex = pendingAutoIncrementIndex {
            if autoIncrementIndex == "PRIMARY KEY" {
                query += ", ADD PRIMARY KEY (\(Self.backtickQuoted(row.name)))"
            } else {
                query += ", ADD \(autoIncrementIndex) (\(Self.backtickQuoted(row.name)))"
            }
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

    fileprivate static func tableRowHeight(for font: NSFont) -> CGFloat {
        return 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: font]).height
    }

    private static let automaticColumnMaximumWidth: CGFloat = 420

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
            tableColumn.width = min(targetWidth, Self.automaticColumnMaximumWidth)
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
            tableColumn.width = min(targetWidth, Self.automaticColumnMaximumWidth)
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
            values = [""] + encodingOptions.map { $0.name }
        case "collationName":
            values = [""] + allCollationOptions
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

    private func updateCollationCell(for encoding: String) {
        guard let tableColumn = structureTableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("collationName")) else { return }

        let values = [""] + (collationOptionsByEncoding[encoding] ?? allCollationOptions)
        let cell = NSComboBoxCell(textCell: "")
        cell.addItems(withObjectValues: values)
        cell.isEditable = true
        cell.isSelectable = true
        cell.usesDataSource = false
        cell.completes = true
        cell.numberOfVisibleItems = 10
        cell.isButtonBordered = false
        cell.lineBreakMode = .byTruncatingTail
        cell.font = UserDefaults.getFont()
        tableColumn.dataCell = cell
    }

    private func defaultCollation(forEncoding encoding: String) -> String? {
        guard !encoding.isEmpty else { return nil }
        if tableEncoding.caseInsensitiveCompare(encoding) == .orderedSame, !tableCollation.isEmpty {
            return tableCollation
        }
        return collationOptionsByEncoding[encoding]?.first { $0.range(of: "_\(encoding)_", options: .caseInsensitive) == nil && $0.hasSuffix("_ci") }
            ?? collationOptionsByEncoding[encoding]?.first
    }

    private func typeDisallowsDefaultOrLength(_ type: String) -> Bool {
        let upper = type.uppercased()
        return upper.hasSuffix("TEXT") || upper.hasSuffix("BLOB") || upper == "JSON" || isGeometryType(upper) || (isDateType(upper) && upper != "YEAR")
    }

    private func isDateType(_ type: String) -> Bool {
        return ["DATE", "DATETIME", "TIMESTAMP", "TIME", "YEAR"].contains(type.uppercased())
    }

    private func isGeometryType(_ type: String) -> Bool {
        return ["GEOMETRY", "POINT", "LINESTRING", "POLYGON", "MULTIPOINT", "MULTILINESTRING", "MULTIPOLYGON", "GEOMETRYCOLLECTION"].contains(type.uppercased())
    }

    private func promptForAutoIncrementIndex(completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Field must be indexed to support auto_increment.", comment: "auto increment index title")
        alert.informativeText = NSLocalizedString("Choose the index to add for this auto_increment field.", comment: "auto increment index message")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        popup.addItems(withTitles: ["PRIMARY KEY", "INDEX", "UNIQUE"])
        alert.accessoryView = popup
        alert.addButton(withTitle: NSLocalizedString("Add", comment: "add button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        completion(alert.runModal() == .alertFirstButtonReturn ? popup.titleOfSelectedItem : nil)
    }

    @objc private func showIndexes(_ sender: Any?) {
        guard tablesIndexesSplitView.subviews.count > 1 else { return }

        let splitHeight = tablesIndexesSplitView.bounds.height
        tablesIndexesSplitView.setPosition(max(130, splitHeight - 180), ofDividerAt: 0)
        showIndexesButton.isHidden = true
    }

    @objc private func showTableDetails(_ sender: Any?) {
        requestTableInfoView?()
    }

    @objc private func toggleStructureColumn(_ sender: NSMenuItem) {
        guard let columnKey = sender.representedObject as? String,
              let tableColumn = structureTableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(columnKey)) else { return }

        tableColumn.isHidden.toggle()
        sender.state = tableColumn.isHidden ? .off : .on
        autosizeStructureColumns()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(addField(_:)):
            return !isSaving
        case #selector(duplicateField(_:)), #selector(removeField(_:)), #selector(showOptimizedFieldType(_:)):
            return !isSaving && structureTableView.selectedRow >= 0
        case #selector(addIndex(_:)):
            return !isSaving && !rows.isEmpty
        case #selector(removeIndex(_:)):
            return !isSaving && indexesTableView.selectedRow >= 0
        case #selector(resetAutoIncrement(_:)):
            let selectedRow = indexesTableView.selectedRow
            return !isSaving && selectedRow >= 0 && selectedRow < indexes.count && (indexes[selectedRow]["Key_name"] ?? "") == "PRIMARY"
        default:
            return true
        }
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

    private func structureContextMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.addItem(NSMenuItem(title: NSLocalizedString("Add Field", comment: "add field menu item"), action: #selector(addField(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Duplicate Field", comment: "duplicate field menu item"), action: #selector(duplicateField(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Delete Field", comment: "delete field menu item"), action: #selector(removeField(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Add Index", comment: "add index menu item"), action: #selector(addIndex(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Show Optimized Field Type", comment: "show optimized field type menu item"), action: #selector(showOptimizedFieldType(_:)), keyEquivalent: ""))
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    private func indexesContextMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.addItem(NSMenuItem(title: NSLocalizedString("Add Index", comment: "add index menu item"), action: #selector(addIndex(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Delete Index", comment: "delete index menu item"), action: #selector(removeIndex(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Reset AUTO_INCREMENT", comment: "reset auto increment menu item"), action: #selector(resetAutoIncrement(_:)), keyEquivalent: ""))
        for item in menu.items {
            item.target = self
        }
        return menu
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

    private static func sqlString(_ value: String, connection: SPMySQLConnection) -> String {
        return connection.escapeAndQuoteString(value) ?? "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard seen.insert(value).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private func tableReference() -> String {
        return "\(Self.backtickQuoted(database)).\(Self.backtickQuoted(table))"
    }

    private func refreshStructureComboCells() {
        for columnKey in ["type", "Extra", "encodingName", "collationName"] {
            guard let tableColumn = structureTableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(columnKey)),
                  let cell = comboBoxCell(for: columnKey) else { continue }
            tableColumn.dataCell = cell
        }
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
        let fieldConstraints = foreignKeyConstraints.filter { $0.columns.contains(row.name) }

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Delete field '%@'?", comment: "delete field title"), row.name)
        if let constraint = fieldConstraints.first {
            alert.informativeText = String(format: NSLocalizedString("This field is part of a foreign key relationship with the table '%@'. This relationship must be removed before the field can be deleted.\n\nAre you sure you want to continue to delete the relationship and the field? This action cannot be undone.", comment: "delete field and foreign key informative message"), constraint.referencedTable)
            alert.addButton(withTitle: NSLocalizedString("Delete Both", comment: "delete field and relation button"))
        } else {
            alert.informativeText = String(format: NSLocalizedString("Are you sure you want to delete the field '%@'? This action cannot be undone.", comment: "delete field informative message"), row.name)
            alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            var error: String?

            for constraint in fieldConstraints {
                let relationQuery = "ALTER TABLE \(self.tableReference()) DROP FOREIGN KEY \(Self.backtickQuoted(constraint.name))"
                connection.queryString(relationQuery)
                if connection.queryErrored() {
                    error = String(format: NSLocalizedString("An error occurred while trying to delete the relation '%@'.\n\nMySQL said: %@", comment: "error deleting relation informative message"), constraint.name, connection.lastErrorMessage() ?? "")
                    break
                }
            }

            if error == nil {
                let query = "ALTER TABLE \(self.tableReference()) DROP \(Self.backtickQuoted(row.name))"
                connection.queryString(query)
                if connection.queryErrored() {
                    error = String(format: NSLocalizedString("Couldn't delete field %@.\nMySQL said: %@", comment: "message of panel when field cannot be deleted"), row.name, connection.lastErrorMessage() ?? "")
                }
            }

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

    @objc func resetAutoIncrement(_ sender: Any?) {
        guard let connection = connection else { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Reset AUTO_INCREMENT", comment: "reset auto increment title")
        alert.informativeText = String(format: NSLocalizedString("Reset AUTO_INCREMENT for table '%@'.", comment: "reset auto increment informative text"), table)
        let valueField = NSTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        valueField.stringValue = "1"
        alert.accessoryView = valueField
        alert.addButton(withTitle: NSLocalizedString("Reset", comment: "reset button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let value = max(valueField.integerValue, 1)
        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            connection.queryString("ALTER TABLE \(self.tableReference()) AUTO_INCREMENT = \(value)")
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error, !error.isEmpty {
                    self.showError(title: NSLocalizedString("Error", comment: "error"), message: String(format: NSLocalizedString("An error occurred while trying to reset AUTO_INCREMENT of table '%@'.\n\nMySQL said: %@", comment: "error resetting auto_increment informative message"), self.table, error))
                    return
                }
                self.tableStructureDidChange?()
            }
        }
    }

    @objc func showOptimizedFieldType(_ sender: Any?) {
        let selectedRow = structureTableView.selectedRow
        guard let sourceIndex = sourceIndex(forDisplayedRow: selectedRow), let connection = connection else { return }
        let row = rows[sourceIndex]
        let fieldName = row.name

        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            var message: String?

            if let result = connection.queryString("SELECT \(Self.backtickQuoted(fieldName)) FROM \(self.tableReference()) PROCEDURE ANALYSE(0,8192)"), !connection.queryErrored() {
                result.returnDataAsStrings = true
                result.defaultRowReturnType = SPMySQLResultRowAsDictionary
                if let analysis = result.getRowAsDictionary() as? [String: Any] {
                    message = Self.displayString(for: analysis["Optimal_fieldtype"])
                }
            }

            if message?.isEmpty != false {
                message = self.estimatedOptimizedFieldType(for: row, connection: connection)
                    ?? NSLocalizedString("No optimized field type found.", comment: "no optimized field type found message")
            }

            DispatchQueue.main.async {
                self.isSaving = false
                self.showError(title: String(format: NSLocalizedString("Optimized type for field '%@'", comment: "Optimized type for field %@"), fieldName), message: message)
            }
        }
    }

    private func estimatedOptimizedFieldType(for row: StructureRow, connection: SPMySQLConnection) -> String? {
        let fieldType = (row.values["type"] ?? "").uppercased()
        let fieldName = row.name

        if ["TINYINT", "SMALLINT", "MEDIUMINT", "INT", "INTEGER", "BIGINT"].contains(fieldType) {
            guard let stats = columnStats(for: fieldName, lengthFunction: nil, connection: connection),
                  nonNullRows(in: stats),
                  let minimum = SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: stats["min_value"]),
                  let maximum = SPOptimizedFieldTypeEstimator.decimalNumber(fromStatValue: stats["max_value"]) else { return nil }
            return SPOptimizedFieldTypeEstimator.estimatedIntegerType(forMinimum: minimum, maximum: maximum)
        }

        if ["BINARY", "VARBINARY", "TINYBLOB", "BLOB", "MEDIUMBLOB", "LONGBLOB"].contains(fieldType) {
            guard let stats = columnStats(for: fieldName, lengthFunction: "OCTET_LENGTH", connection: connection),
                  nonNullRows(in: stats) else { return nil }
            let minLength = SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: stats["min_length"])
            let maxLength = max(UInt(1), SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: stats["max_length"]))
            if minLength == maxLength, maxLength <= 255 { return "BINARY(\(maxLength))" }
            if maxLength <= 65_535 { return "VARBINARY(\(maxLength))" }
            if maxLength <= 16_777_215 { return "MEDIUMBLOB" }
            return "LONGBLOB"
        }

        if ["CHAR", "VARCHAR", "NCHAR", "NVARCHAR", "TINYTEXT", "TEXT", "MEDIUMTEXT", "LONGTEXT"].contains(fieldType) {
            guard let stats = columnStats(for: fieldName, lengthFunction: "CHAR_LENGTH", connection: connection),
                  let byteStats = columnStats(for: fieldName, lengthFunction: "OCTET_LENGTH", connection: connection),
                  nonNullRows(in: stats) else { return nil }
            let minLength = SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: stats["min_length"])
            let maxLength = max(UInt(1), SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: stats["max_length"]))
            let maxByteLength = max(UInt(1), SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: byteStats["max_length"]))
            if minLength == maxLength, maxLength <= 255 { return "CHAR(\(maxLength))" }
            let maxBytesPerCharacter = encodingOptions.first(where: { $0.name == (row.values["encodingName"] ?? tableEncoding) })?.maxLength ?? 1
            let maxSafeVarcharLength = 65_535 / max(maxBytesPerCharacter, 1)
            if maxByteLength <= 65_535, maxLength <= maxSafeVarcharLength { return "VARCHAR(\(maxLength))" }
            if maxByteLength <= 65_535 { return "TEXT" }
            if maxByteLength <= 16_777_215 { return "MEDIUMTEXT" }
            return "LONGTEXT"
        }

        return nil
    }

    private func columnStats(for fieldName: String, lengthFunction: String?, connection: SPMySQLConnection) -> [String: Any]? {
        let quotedField = Self.backtickQuoted(fieldName)
        let query: String
        if let lengthFunction = lengthFunction {
            let expression = "\(lengthFunction)(\(quotedField))"
            query = "SELECT COUNT(*) AS row_count, SUM(\(quotedField) IS NULL) AS null_count, MIN(\(expression)) AS min_length, MAX(\(expression)) AS max_length FROM \(tableReference())"
        } else {
            query = "SELECT COUNT(*) AS row_count, SUM(\(quotedField) IS NULL) AS null_count, MIN(\(quotedField)) AS min_value, MAX(\(quotedField)) AS max_value FROM \(tableReference())"
        }
        guard let result = connection.queryString(query), !connection.queryErrored() else { return nil }
        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        return result.getRowAsDictionary() as? [String: Any]
    }

    private func nonNullRows(in stats: [String: Any]) -> Bool {
        let rowCount = SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: stats["row_count"])
        let nullCount = SPOptimizedFieldTypeEstimator.unsignedIntegerValue(fromStatValue: stats["null_count"])
        return rowCount > nullCount
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
        let primaryKeyExists = indexes.contains { ($0["Key_name"] ?? "") == "PRIMARY" }
        let indexedColumnNames = Set(indexes.compactMap { $0["Column_name"] })
        let initialField = rows.indices.contains(sourceIndex) ? rows[sourceIndex] : rows[0]
        let fields = rows.map { IndexField(name: $0.name, type: $0.values["type"] ?? "", size: "") }
        let selectedFieldName = indexedColumnNames.contains(initialField.name)
            ? (rows.first { !indexedColumnNames.contains($0.name) }?.name ?? initialField.name)
            : initialField.name
        let sheetController = SALightweightStructureIndexSheetController(fields: fields,
                                                                        selectedFieldName: selectedFieldName,
                                                                        tableEngine: tableEngine,
                                                                        primaryKeyExists: primaryKeyExists,
                                                                        supportsFullTextOnInnoDB: supportsFullTextOnInnoDB(connection: connection))
        guard let parentWindow = view.window else { return }
        indexSheetController = sheetController

        parentWindow.beginSheet(sheetController.window!) { [weak self, weak connection] response in
            guard let self = self else { return }
            defer { self.indexSheetController = nil }
            guard response == .OK, let connection = connection else { return }
            let query = sheetController.indexQuery(tableReference: self.tableReference(), quoteIdentifier: Self.backtickQuoted)
            self.runIndexQuery(query, connection: connection, errorTitle: NSLocalizedString("Unable to add index", comment: "add index error title"))
        }
    }

    private func supportsFullTextOnInnoDB(connection: SPMySQLConnection) -> Bool {
        let major = Int(connection.serverMajorVersion())
        let minor = Int(connection.serverMinorVersion())
        let release = Int(connection.serverReleaseVersion())
        if major > 5 { return true }
        if major == 5, minor > 6 { return true }
        if major == 5, minor == 6, release >= 4 { return true }
        return false
    }

    private func runIndexQuery(_ query: String, connection: SPMySQLConnection, errorTitle: String) {
        guard !query.isEmpty else { return }

        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            connection.queryString(query)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error, !error.isEmpty {
                    self.showError(title: errorTitle, message: error)
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
            let errorID = connection.queryErrored() ? connection.lastErrorID() : 0

            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error, !error.isEmpty {
                    if errorID == 1553, let foreignKey = self.foreignKeyDepending(onIndex: indexName) {
                        self.confirmRemoveIndex(indexName, foreignKey: foreignKey, connection: connection, originalError: error)
                        return
                    }
                    self.showError(title: NSLocalizedString("Unable to delete index", comment: "delete index error title"), message: error)
                    return
                }

                self.invalidateCurrentStructureCache()
                self.tableStructureDidChange?()
                self.loadStructure(for: self.table, database: self.database, connection: connection, useCache: false)
            }
        }
    }

    private func foreignKeyDepending(onIndex indexName: String) -> ForeignKeyConstraint? {
        let indexColumns = indexes.filter { ($0["Key_name"] ?? "") == indexName }.compactMap { $0["Column_name"] }.sorted()
        guard !indexColumns.isEmpty else { return nil }

        let matches = foreignKeyConstraints.filter { $0.columns.sorted() == indexColumns }
        return matches.count == 1 ? matches.first : nil
    }

    private func confirmRemoveIndex(_ indexName: String, foreignKey: ForeignKeyConstraint, connection: SPMySQLConnection, originalError: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("A foreign key needs this index", comment: "foreign key needs index title")
        alert.informativeText = String(format: NSLocalizedString("The foreign key relationship '%@' has a dependency on index '%@'. This relationship must be removed before the index can be deleted.\n\nAre you sure you want to continue to delete the relationship and the index? This action cannot be undone.", comment: "foreign key needs index message"), foreignKey.name, indexName)
        alert.addButton(withTitle: NSLocalizedString("Delete Both", comment: "delete both button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let dropForeignKeyQuery = "ALTER TABLE \(tableReference()) DROP FOREIGN KEY \(Self.backtickQuoted(foreignKey.name))"
        let dropIndexQuery = indexName == "PRIMARY"
            ? "ALTER TABLE \(tableReference()) DROP PRIMARY KEY"
            : "ALTER TABLE \(tableReference()) DROP INDEX \(Self.backtickQuoted(indexName))"

        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            connection.queryString(dropForeignKeyQuery)
            var error = connection.queryErrored() ? String(format: NSLocalizedString("An error occurred while trying to delete the relation '%@'.\n\nMySQL said: %@", comment: "error deleting relation informative message"), foreignKey.name, connection.lastErrorMessage() ?? "") : nil
            if error == nil {
                connection.queryString(dropIndexQuery)
                error = connection.queryErrored() ? (connection.lastErrorMessage() ?? originalError) : nil
            }

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

private final class SALightweightStructureIndexSheetController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private let allFields: [SALightweightStructureViewController.IndexField]
    private var indexedFields: [SALightweightStructureViewController.IndexField]
    private let supportsLength = Set(["CHAR", "VARCHAR", "TINYTEXT", "TEXT", "MEDIUMTEXT", "LONGTEXT", "BINARY", "VARBINARY", "TINYBLOB", "BLOB", "MEDIUMBLOB", "LONGBLOB"])
    private let requiresLength = Set(["TINYTEXT", "TEXT", "MEDIUMTEXT", "LONGTEXT", "TINYBLOB", "BLOB", "MEDIUMBLOB", "LONGBLOB"])
    private let tableEngine: String
    private let primaryKeyExists: Bool
    private let supportsFullTextOnInnoDB: Bool

    private let typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField(frame: .zero)
    private let columnsTableView = NSTableView(frame: .zero)
    private let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
    private let addColumnButton = NSButton(image: NSImage(named: NSImage.Name("NSAddTemplate")) ?? NSImage(), target: nil, action: nil)
    private let removeColumnButton = NSButton(image: NSImage(named: NSImage.Name("NSRemoveTemplate")) ?? NSImage(), target: nil, action: nil)
    private let advancedDisclosure = NSButton(checkboxWithTitle: NSLocalizedString("Advanced Options", comment: "advanced index options label"), target: nil, action: nil)
    private let advancedView = NSView(frame: .zero)
    private let storagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let keyBlockSizeField = NSTextField(frame: .zero)
    private let addButton = NSButton(title: NSLocalizedString("Add", comment: "add button"), target: nil, action: nil)

    init(fields: [SALightweightStructureViewController.IndexField], selectedFieldName: String, tableEngine: String, primaryKeyExists: Bool, supportsFullTextOnInnoDB: Bool) {
        self.allFields = fields
        self.indexedFields = fields.first(where: { $0.name == selectedFieldName }).map { [$0] } ?? Array(fields.prefix(1))
        self.tableEngine = tableEngine
        self.primaryKeyExists = primaryKeyExists
        self.supportsFullTextOnInnoDB = supportsFullTextOnInnoDB

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 310),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("Add Index", comment: "add index sheet title")
        super.init(window: window)
        buildInterface()
        updateTypeControls()
        updateButtonState()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func indexQuery(tableReference: String, quoteIdentifier: (String) -> String) -> String {
        let indexType = selectedIndexType()
        var queryType = indexType
        if indexType != "INDEX", indexType != "PRIMARY KEY" {
            queryType += " INDEX"
        }

        var query = "ALTER TABLE \(tableReference) ADD \(queryType)"
        let indexName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if indexType != "PRIMARY KEY", !indexName.isEmpty {
            query += " \(quoteIdentifier(indexName))"
        }

        if storagePopup.indexOfSelectedItem > 0, indexType != "SPATIAL" {
            query += " USING \(storagePopup.titleOfSelectedItem ?? "")"
        }

        let columns = indexedFields.compactMap { field -> String? in
            guard !field.name.isEmpty else { return nil }
            let type = field.type.uppercased()
            let size = field.size.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isFullTextSelected(), supportsLength.contains(type), !size.isEmpty {
                return "\(quoteIdentifier(field.name)) (\(size))"
            }
            if !isFullTextSelected(), requiresLength.contains(type), size.isEmpty {
                return nil
            }
            return quoteIdentifier(field.name)
        }
        guard !columns.isEmpty else { return "" }
        query += " (\(columns.joined(separator: ", ")))"

        let keyBlockSize = keyBlockSizeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyBlockSize.isEmpty {
            query += " KEY_BLOCK_SIZE = \(keyBlockSize)"
        }

        return query
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let typeLabel = NSTextField(labelWithString: NSLocalizedString("Index Type:", comment: "index type label"))
        let nameLabel = NSTextField(labelWithString: NSLocalizedString("Index Name:", comment: "index name label"))
        typePopup.addItems(withTitles: availableIndexTypes())
        storagePopup.addItems(withTitles: ["", "BTREE", "HASH"])
        keyBlockSizeField.placeholderString = NSLocalizedString("Key Block Size", comment: "index key block size placeholder")

        let fieldColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        fieldColumn.title = NSLocalizedString("Column", comment: "indexed column title")
        fieldColumn.width = 320
        let fieldCell = NSComboBoxCell(textCell: "")
        fieldCell.addItems(withObjectValues: allFields.map { $0.name })
        fieldCell.completes = true
        fieldColumn.dataCell = fieldCell

        sizeColumn.title = NSLocalizedString("Size", comment: "index size column title")
        sizeColumn.width = 90
        let sizeCell = NSTextFieldCell(textCell: "")
        sizeCell.placeholderString = NSLocalizedString("optional", comment: "optional placeholder string")
        sizeColumn.dataCell = sizeCell

        columnsTableView.addTableColumn(fieldColumn)
        columnsTableView.addTableColumn(sizeColumn)
        columnsTableView.dataSource = self
        columnsTableView.delegate = self
        columnsTableView.usesAlternatingRowBackgroundColors = true
        columnsTableView.rowHeight = SALightweightStructureViewController.tableRowHeight(for: UserDefaults.getFont())

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = columnsTableView

        addColumnButton.bezelStyle = .smallSquare
        removeColumnButton.bezelStyle = .smallSquare
        addColumnButton.target = self
        removeColumnButton.target = self
        addColumnButton.action = #selector(addIndexedField(_:))
        removeColumnButton.action = #selector(removeIndexedField(_:))

        advancedDisclosure.target = self
        advancedDisclosure.action = #selector(toggleAdvancedOptions(_:))
        advancedView.isHidden = true

        let storageLabel = NSTextField(labelWithString: NSLocalizedString("Storage Type:", comment: "index storage type label"))
        let keyBlockSizeLabel = NSTextField(labelWithString: NSLocalizedString("Key Block Size:", comment: "index key block size label"))
        advancedView.addSubview(storageLabel)
        advancedView.addSubview(storagePopup)
        advancedView.addSubview(keyBlockSizeLabel)
        advancedView.addSubview(keyBlockSizeField)

        let cancelButton = NSButton(title: NSLocalizedString("Cancel", comment: "cancel button"), target: self, action: #selector(cancel(_:)))
        addButton.target = self
        addButton.action = #selector(confirm(_:))
        addButton.keyEquivalent = "\r"

        [typeLabel, typePopup, nameLabel, nameField, scrollView, addColumnButton, removeColumnButton, advancedDisclosure, advancedView, cancelButton, addButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        [storageLabel, storagePopup, keyBlockSizeLabel, keyBlockSizeField].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            typeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            typeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            typeLabel.widthAnchor.constraint(equalToConstant: 85),
            typePopup.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 8),
            typePopup.centerYAnchor.constraint(equalTo: typeLabel.centerYAnchor),
            typePopup.widthAnchor.constraint(equalToConstant: 180),

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 14),
            nameLabel.widthAnchor.constraint(equalTo: typeLabel.widthAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.widthAnchor.constraint(equalToConstant: 260),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -56),
            scrollView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 18),
            scrollView.heightAnchor.constraint(equalToConstant: 105),

            addColumnButton.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 6),
            addColumnButton.topAnchor.constraint(equalTo: scrollView.topAnchor),
            addColumnButton.widthAnchor.constraint(equalToConstant: 25),
            removeColumnButton.leadingAnchor.constraint(equalTo: addColumnButton.leadingAnchor),
            removeColumnButton.topAnchor.constraint(equalTo: addColumnButton.bottomAnchor, constant: 4),
            removeColumnButton.widthAnchor.constraint(equalToConstant: 25),

            advancedDisclosure.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            advancedDisclosure.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),

            advancedView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            advancedView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            advancedView.topAnchor.constraint(equalTo: advancedDisclosure.bottomAnchor, constant: 6),
            advancedView.heightAnchor.constraint(equalToConstant: 48),

            storageLabel.leadingAnchor.constraint(equalTo: advancedView.leadingAnchor),
            storageLabel.topAnchor.constraint(equalTo: advancedView.topAnchor),
            storageLabel.widthAnchor.constraint(equalToConstant: 90),
            storagePopup.leadingAnchor.constraint(equalTo: storageLabel.trailingAnchor, constant: 8),
            storagePopup.centerYAnchor.constraint(equalTo: storageLabel.centerYAnchor),
            storagePopup.widthAnchor.constraint(equalToConstant: 115),

            keyBlockSizeLabel.leadingAnchor.constraint(equalTo: advancedView.leadingAnchor),
            keyBlockSizeLabel.topAnchor.constraint(equalTo: storageLabel.bottomAnchor, constant: 10),
            keyBlockSizeLabel.widthAnchor.constraint(equalTo: storageLabel.widthAnchor),
            keyBlockSizeField.leadingAnchor.constraint(equalTo: keyBlockSizeLabel.trailingAnchor, constant: 8),
            keyBlockSizeField.centerYAnchor.constraint(equalTo: keyBlockSizeLabel.centerYAnchor),
            keyBlockSizeField.widthAnchor.constraint(equalToConstant: 115),

            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor)
        ])

        typePopup.target = self
        typePopup.action = #selector(indexTypeChanged(_:))
    }

    private func availableIndexTypes() -> [String] {
        var types = primaryKeyExists ? ["INDEX", "UNIQUE"] : ["PRIMARY KEY", "INDEX", "UNIQUE"]
        let engine = tableEngine.uppercased()
        if engine == "MYISAM" {
            types.append("SPATIAL")
        }
        if engine == "MYISAM" || (engine == "INNODB" && supportsFullTextOnInnoDB) {
            types.append("FULLTEXT")
        }
        return types
    }

    private func selectedIndexType() -> String {
        return typePopup.titleOfSelectedItem ?? "INDEX"
    }

    private func isFullTextSelected() -> Bool {
        return selectedIndexType() == "FULLTEXT"
    }

    private func updateTypeControls() {
        let isPrimary = selectedIndexType() == "PRIMARY KEY"
        nameField.isEnabled = !isPrimary
        nameField.stringValue = isPrimary ? "PRIMARY" : (nameField.stringValue == "PRIMARY" ? "" : nameField.stringValue)
        storagePopup.isEnabled = selectedIndexType() != "SPATIAL" && tableEngine.uppercased() != "MYISAM" && tableEngine.uppercased() != "INNODB"
        updateButtonState()
    }

    private func updateButtonState() {
        removeColumnButton.isEnabled = indexedFields.count > 1 && columnsTableView.selectedRow >= 0
        addColumnButton.isEnabled = indexedFields.count < allFields.count
        addButton.isEnabled = !indexedFields.isEmpty && !indexedFields.contains { requiresSize($0) && $0.size.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        sizeColumn.isHidden = isFullTextSelected() || !indexedFields.contains { requiresLength.contains($0.type.uppercased()) || !$0.size.isEmpty }
    }

    private func requiresSize(_ field: SALightweightStructureViewController.IndexField) -> Bool {
        return !isFullTextSelected() && requiresLength.contains(field.type.uppercased())
    }

    @objc private func indexTypeChanged(_ sender: Any?) {
        updateTypeControls()
        columnsTableView.reloadData()
    }

    @objc private func addIndexedField(_ sender: Any?) {
        guard let field = allFields.first(where: { candidate in !indexedFields.contains(where: { $0.name == candidate.name }) }) else { return }
        indexedFields.append(field)
        columnsTableView.reloadData()
        columnsTableView.selectRowIndexes(IndexSet(integer: indexedFields.count - 1), byExtendingSelection: false)
        updateButtonState()
    }

    @objc private func removeIndexedField(_ sender: Any?) {
        guard columnsTableView.selectedRow >= 0, indexedFields.count > 1 else { return }
        indexedFields.remove(at: columnsTableView.selectedRow)
        columnsTableView.reloadData()
        updateButtonState()
    }

    @objc private func toggleAdvancedOptions(_ sender: Any?) {
        advancedView.isHidden = advancedDisclosure.state != .on
    }

    @objc private func confirm(_ sender: Any?) {
        window?.sheetParent?.endSheet(window!, returnCode: .OK)
    }

    @objc private func cancel(_ sender: Any?) {
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return indexedFields.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0, row < indexedFields.count else { return nil }
        if tableColumn?.identifier.rawValue == "Size" {
            return indexedFields[row].size
        }
        return indexedFields[row].name
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard row >= 0, row < indexedFields.count else { return }
        if tableColumn?.identifier.rawValue == "Size" {
            indexedFields[row].size = "\(object ?? "")"
        } else if let field = allFields.first(where: { $0.name == "\(object ?? "")" }) {
            var replacement = field
            replacement.size = indexedFields[row].size
            indexedFields[row] = replacement
        }
        columnsTableView.reloadData()
        updateButtonState()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonState()
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard tableColumn?.identifier.rawValue == "Size",
              row >= 0,
              row < indexedFields.count,
              let textCell = cell as? NSTextFieldCell else { return }
        textCell.placeholderString = requiresSize(indexedFields[row])
            ? NSLocalizedString("required", comment: "required placeholder string")
            : NSLocalizedString("optional", comment: "optional placeholder string")
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

        if key == "type" {
            let uppercasedType = newValue.uppercased()
            guard !uppercasedType.hasPrefix("--") else {
                reloadVisibleRows()
                return
            }
            rows[sourceIndex].values[key] = uppercasedType
            if typeDisallowsDefaultOrLength(uppercasedType) {
                rows[sourceIndex].values["default"] = ""
                rows[sourceIndex].values["length"] = ""
            }
        } else {
            rows[sourceIndex].values[key] = newValue
        }
        if key == "Extra", extraIsAutoIncrement(newValue) {
            rows[sourceIndex].values["null"] = "0"
            if (rows[sourceIndex].values["Key"] ?? "").isEmpty {
                promptForAutoIncrementIndex { [weak self] indexType in
                    guard let self = self else { return }
                    self.pendingAutoIncrementIndex = indexType
                    if indexType == nil {
                        self.rows[sourceIndex].values["Extra"] = "None"
                        self.reloadVisibleRows()
                        return
                    }
                    self.saveRow(at: sourceIndex, oldRow: oldRow)
                }
                return
            }
        } else if key == "Extra" {
            pendingAutoIncrementIndex = nil
        }
        if key == "encodingName" {
            rows[sourceIndex].values["collationName"] = defaultCollation(forEncoding: newValue) ?? ""
            updateCollationCell(for: newValue)
        }
        if key == "binary", rows[sourceIndex].values[key] != oldRow.values[key] {
            rows[sourceIndex].values["collationName"] = ""
        }

        saveRow(at: sourceIndex, oldRow: oldRow)
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        guard isStructureTable(tableView), !isSaving, let key = tableColumn?.identifier.rawValue else { return false }
        if key == "collationName", let sourceIndex = sourceIndex(forDisplayedRow: row) {
            updateCollationCell(for: rows[sourceIndex].values["encodingName"] ?? "")
        }
        return structureColumns.first(where: { $0.key == key })?.editable == true
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard isStructureTable(tableView),
              let key = tableColumn?.identifier.rawValue,
              let sourceIndex = sourceIndex(forDisplayedRow: row),
              let cell = cell as? NSCell else { return }

        let rowType = (rows[sourceIndex].values["type"] ?? "").uppercased()
        switch key {
        case "encodingName":
            cell.isEnabled = rowType != "JSON" && isStringType(rowType)
        case "collationName":
            cell.isEnabled = isStringType(rowType) && !boolValue(rows[sourceIndex].values["binary"])
        case "unsigned", "zerofill":
            cell.isEnabled = isNumericType(rowType) && rowType != "BIT"
        case "binary":
            cell.isEnabled = rowType != "JSON" && isStringType(rowType)
        case "default":
            cell.isEnabled = !typeDisallowsDefaultOrLength(rowType)
        case "length":
            cell.isEnabled = !typeDisallowsDefaultOrLength(rowType)
        case "null":
            cell.isEnabled = rows[sourceIndex].values["Key"] != "PRI" && !extraIsAutoIncrement(rows[sourceIndex].values["Extra"])
        default:
            cell.isEnabled = true
        }
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
