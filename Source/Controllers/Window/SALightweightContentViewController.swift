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

    fileprivate struct ColumnInfo {
        let name: String
        let type: String
        let typeGrouping: String
        let length: String
        let values: [String]
        let comment: String
        let isNullable: Bool
        let isPrimary: Bool
        let isAutoIncrement: Bool
    }

    fileprivate struct ContentRow {
        var values: [ContentValue]
        var originalValues: [ContentValue]
    }

    private struct ContentCacheEntry {
        let columns: [String]
        let columnInfo: [ColumnInfo]
        let rows: [ContentRow]
        let pageIndex: Int
        let pageSize: Int
        let totalRowCount: Int?
        let totalRowCountIsEstimate: Bool
        let hasNextPage: Bool
        let sortColumn: String?
        let sortAscending: Bool
        let isRuleFilterActive: Bool
        let serializedRuleFilter: NSDictionary?
    }

    fileprivate struct ContentFilterDefinition {
        let title: String
        let clause: String
        let numberOfArguments: Int
        let conjunctionLabels: [String]
        let suppressLeadingFieldPlaceholder: Bool
        let filterType: String
        let rawDefinition: NSDictionary
    }

    fileprivate struct FilterRule {
        let id: UUID
        var isEnabled: Bool
        var columnName: String
        var operatorTitle: String
        var values: [String]

        init(id: UUID = UUID(), isEnabled: Bool = true, columnName: String, operatorTitle: String, values: [String] = []) {
            self.id = id
            self.isEnabled = isEnabled
            self.columnName = columnName
            self.operatorTitle = operatorTitle
            self.values = values
        }
    }

    fileprivate enum ContentValue {
        case null
        case notLoaded
        case object(Any)
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
    private var totalRowCount: Int?
    private var totalRowCountIsEstimate = false
    private var hasNextPage = false
    private var isLoading = false
    private var sortColumn: String?
    private var sortAscending = true
    private var didRegisterPreferenceObservers = false
    private var isApplyingProgrammaticColumnWidths = false
    private var isRuleFilterVisible = true
    private var isRuleFilterActive = false
    private var ruleFilterColumnsKey = ""
    private var filterRules: [FilterRule] = []
    private var defaultContentFilters: [String: [ContentFilterDefinition]] = [:]
    private var restoredRuleFilters: [String: NSDictionary] = [:]
    private var restoredActiveRuleFilters = Set<String>()
    private var contentCache: [String: ContentCacheEntry] = [:]
    private var contentCacheOrder: [String] = []
    private let maximumContentCacheEntries = 6
    private var ruleFilterHeightConstraint: NSLayoutConstraint?
    private var isRestoringCachedContent = false
    var requestLegacyContentFallback: (() -> Void)?
    private var pageSize: Int {
        let preferredPageSize = UserDefaults.standard.integer(forKey: SPLimitResultsValue)
        return max(1, preferredPageSize > 0 ? preferredPageSize : 1_000)
    }

    private lazy var statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }()

    private lazy var addRowButton = toolbarButton(imageName: "NSAddTemplate", toolTip: NSLocalizedString("Add row (⌥⌘A)", comment: "add row tooltip"), keyEquivalent: "a", modifierMask: [.command, .option], action: #selector(addRow(_:)))
    private lazy var duplicateRowButton = toolbarButton(imageName: "button_duplicateTemplate", toolTip: NSLocalizedString("Duplicate selected row (⌘D)", comment: "duplicate row tooltip"), keyEquivalent: "d", modifierMask: .command, action: #selector(duplicateRow(_:)))
    private lazy var deleteRowButton = toolbarButton(imageName: "NSRemoveTemplate", toolTip: NSLocalizedString("Delete selected row(s) (⌫)", comment: "delete row tooltip"), keyEquivalent: "\u{7F}", action: #selector(deleteRows(_:)))
    private lazy var reloadButton = toolbarButton(imageName: "NSRefreshTemplate", toolTip: NSLocalizedString("Refresh table contents (⌘R)", comment: "refresh content tooltip"), keyEquivalent: "r", modifierMask: .command, action: #selector(reloadContent(_:)))
    private lazy var editModeButton = toolbarButton(imageName: "button_edit_modeTemplate", toolTip: NSLocalizedString("Edit table content", comment: "edit content mode tooltip"), action: #selector(showLegacyContentFeature(_:)))
    private lazy var previousPageButton = toolbarButton(imageName: "NSLeftFacingTriangleTemplate", toolTip: NSLocalizedString("View previous page of results", comment: "previous page tooltip"), action: #selector(loadPreviousPage(_:)))
    private lazy var paginationButton = toolbarButton(imageName: "NSActionTemplate", toolTip: NSLocalizedString("Show pagination options", comment: "pagination options tooltip"), keyEquivalent: "j", modifierMask: .command, action: #selector(showLegacyContentFeature(_:)))
    private lazy var nextPageButton = toolbarButton(imageName: "NSRightFacingTriangleTemplate", toolTip: NSLocalizedString("View next page of results", comment: "next page tooltip"), action: #selector(loadNextPage(_:)))

    private lazy var pageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    private lazy var tableView: NSTableView = {
        let tableView = SPCopyTable(frame: .zero)
        tableView.identifier = NSUserInterfaceItemIdentifier("TableContentTableView")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.allowsExpansionToolTips = true
        tableView.focusRingType = .none
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.style = .plain
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = Self.tableRowHeight(for: UserDefaults.getFont())
        return tableView
    }()

    private lazy var ruleFilterContainer: NSView = {
        let container = NSView(frame: .zero)
        container.isHidden = !isRuleFilterVisible
        return container
    }()

    private lazy var filterRowsStackView: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        return stackView
    }()

    private lazy var filterRowsScrollView: NSScrollView = {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.horizontalLineScroll = 10
        scrollView.verticalLineScroll = 10
        scrollView.usesPredominantAxisScrolling = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = filterRowsStackView
        return scrollView
    }()

    private lazy var applyFilterButton: NSButton = {
        let button = NSButton(title: NSLocalizedString("Apply Filter(s)", comment: "apply content filters button"), target: self, action: #selector(applyRuleFilter(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 11)
        return button
    }()

    private lazy var addFilterButton: NSButton = {
        let button = NSButton(title: NSLocalizedString("Add Filter", comment: "add content filter button"), target: self, action: #selector(addFilterRule(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 11)
        return button
    }()

    override func deleteBackward(_ sender: Any?) {
        deleteRows(sender)
    }

    override func deleteForward(_ sender: Any?) {
        deleteRows(sender)
    }

    func focusRowFilter() {
        setRuleFilterVisible(true, animate: false)
        focusFirstFilterValueField()
    }

    func clearCachedTables() {
        contentCache.removeAll()
        contentCacheOrder.removeAll()
    }

    override func loadView() {
        let rootView = NSView(frame: .zero)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .none
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.verticalLineScroll = 18
        scrollView.horizontalLineScroll = 18
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = tableView

        let toolbarView = NSView(frame: .zero)

        rootView.addSubview(ruleFilterContainer)
        rootView.addSubview(scrollView)
        rootView.addSubview(toolbarView)
        ruleFilterContainer.addSubview(filterRowsScrollView)
        ruleFilterContainer.addSubview(applyFilterButton)
        ruleFilterContainer.addSubview(addFilterButton)
        toolbarView.addSubview(addRowButton)
        toolbarView.addSubview(duplicateRowButton)
        toolbarView.addSubview(deleteRowButton)
        toolbarView.addSubview(reloadButton)
        toolbarView.addSubview(editModeButton)
        toolbarView.addSubview(previousPageButton)
        toolbarView.addSubview(paginationButton)
        toolbarView.addSubview(pageLabel)
        toolbarView.addSubview(nextPageButton)
        toolbarView.addSubview(statusLabel)

        ruleFilterContainer.translatesAutoresizingMaskIntoConstraints = false
        filterRowsScrollView.translatesAutoresizingMaskIntoConstraints = false
        filterRowsStackView.translatesAutoresizingMaskIntoConstraints = false
        applyFilterButton.translatesAutoresizingMaskIntoConstraints = false
        addFilterButton.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        addRowButton.translatesAutoresizingMaskIntoConstraints = false
        duplicateRowButton.translatesAutoresizingMaskIntoConstraints = false
        deleteRowButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        editModeButton.translatesAutoresizingMaskIntoConstraints = false
        previousPageButton.translatesAutoresizingMaskIntoConstraints = false
        paginationButton.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        nextPageButton.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let ruleFilterHeightConstraint = ruleFilterContainer.heightAnchor.constraint(equalToConstant: isRuleFilterVisible ? 29 : 0)
        self.ruleFilterHeightConstraint = ruleFilterHeightConstraint

        NSLayoutConstraint.activate([
            ruleFilterContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 7),
            ruleFilterContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -7),
            ruleFilterContainer.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 7),
            ruleFilterHeightConstraint,

            filterRowsScrollView.leadingAnchor.constraint(equalTo: ruleFilterContainer.leadingAnchor, constant: 2),
            filterRowsScrollView.topAnchor.constraint(equalTo: ruleFilterContainer.topAnchor),
            filterRowsScrollView.bottomAnchor.constraint(equalTo: ruleFilterContainer.bottomAnchor),
            filterRowsScrollView.trailingAnchor.constraint(equalTo: applyFilterButton.leadingAnchor, constant: -6),

            applyFilterButton.trailingAnchor.constraint(equalTo: ruleFilterContainer.trailingAnchor, constant: -5),
            applyFilterButton.centerYAnchor.constraint(equalTo: ruleFilterContainer.centerYAnchor),
            applyFilterButton.widthAnchor.constraint(equalToConstant: 111),

            addFilterButton.trailingAnchor.constraint(equalTo: ruleFilterContainer.trailingAnchor, constant: -5),
            addFilterButton.centerYAnchor.constraint(equalTo: ruleFilterContainer.centerYAnchor),
            addFilterButton.widthAnchor.constraint(equalToConstant: 111),

            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 7),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -7),
            scrollView.topAnchor.constraint(equalTo: ruleFilterContainer.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: toolbarView.topAnchor),

            toolbarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 7),
            toolbarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -7),
            toolbarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 25),

            addRowButton.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 1),
            addRowButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            addRowButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            addRowButton.widthAnchor.constraint(equalToConstant: 25),

            deleteRowButton.leadingAnchor.constraint(equalTo: addRowButton.trailingAnchor, constant: 4),
            deleteRowButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            deleteRowButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            deleteRowButton.widthAnchor.constraint(equalToConstant: 25),

            duplicateRowButton.leadingAnchor.constraint(equalTo: deleteRowButton.trailingAnchor, constant: 5),
            duplicateRowButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            duplicateRowButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            duplicateRowButton.widthAnchor.constraint(equalToConstant: 25),

            reloadButton.leadingAnchor.constraint(equalTo: duplicateRowButton.trailingAnchor, constant: 5),
            reloadButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            reloadButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 25),

            editModeButton.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 5),
            editModeButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            editModeButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            editModeButton.widthAnchor.constraint(equalToConstant: 25),

            nextPageButton.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -10),
            nextPageButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            nextPageButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            nextPageButton.widthAnchor.constraint(equalToConstant: 25),

            paginationButton.trailingAnchor.constraint(equalTo: nextPageButton.leadingAnchor, constant: -5),
            paginationButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            paginationButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            paginationButton.widthAnchor.constraint(equalToConstant: 25),

            pageLabel.trailingAnchor.constraint(equalTo: paginationButton.leadingAnchor, constant: -5),
            pageLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

            previousPageButton.trailingAnchor.constraint(equalTo: pageLabel.leadingAnchor, constant: -5),
            previousPageButton.topAnchor.constraint(equalTo: toolbarView.topAnchor),
            previousPageButton.bottomAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            previousPageButton.widthAnchor.constraint(equalToConstant: 25),

            statusLabel.leadingAnchor.constraint(equalTo: editModeButton.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: previousPageButton.leadingAnchor, constant: -8)
        ])

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        loadDefaultContentFilters()
        NotificationCenter.default.addObserver(self, selector: #selector(contentFiltersHaveBeenUpdated(_:)), name: .SPContentFiltersHaveBeenUpdated, object: nil)
        registerPreferenceObserversIfNeeded()
        applyTablePreferences(rebuildColumns: false)
        updateRuleFilterVisibility(animated: false)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        updateFilterRowsFrame()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if didRegisterPreferenceObservers {
            UserDefaults.standard.removeObserver(self, forKeyPath: SPDisplayTableViewVerticalGridlines)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPDisplayTableViewColumnTypes)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPGlobalFontSettings)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPDisplayBinaryDataAsHex)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPNullValue)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPLoadBlobsAsNeeded)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        switch keyPath {
        case SPDisplayTableViewVerticalGridlines:
            tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
            tableView.reloadData()
            autosizeContentColumns()
        case SPGlobalFontSettings:
            applyTablePreferences(rebuildColumns: UserDefaults.standard.bool(forKey: SPDisplayTableViewColumnTypes))
        case SPDisplayTableViewColumnTypes:
            rebuildColumns()
        case SPDisplayBinaryDataAsHex, SPNullValue:
            tableView.reloadData()
            autosizeContentColumns()
            cacheCurrentContentState()
        case SPLoadBlobsAsNeeded:
            contentCache.removeAll()
            contentCacheOrder.removeAll()
            loadCurrentPage()
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func loadContent(for table: String, database: String, connection: SPMySQLConnection) {
        cacheCurrentContentState()
        storeCurrentRuleFilterState()

        self.table = table
        self.database = database
        self.connection = connection
        loadToken = UUID()
        isRuleFilterActive = restoredActiveRuleFilters.contains(ruleFilterStorageKey(database: database, table: table))
        ruleFilterColumnsKey = ""
        filterRules = []

        if restoreCachedContent(for: contentCacheKey(database: database, table: table)) {
            return
        }

        pageIndex = 0
        sortColumn = nil
        sortAscending = true
        tableView.sortDescriptors = []

        loadCurrentPage()
    }
}

private extension SALightweightContentViewController.ColumnInfo {
    var loadBlobAsNeeded: Bool {
        return UserDefaults.standard.bool(forKey: SPLoadBlobsAsNeeded)
            && (typeGrouping == "textdata" || typeGrouping == "blobdata")
    }

    var displaysBinaryAsHex: Bool {
        return typeGrouping == "binary" || typeGrouping == "blobdata"
    }

    var legacyDefinition: NSDictionary {
        let definition = NSMutableDictionary()
        definition["name"] = name
        definition["type"] = type
        definition["typegrouping"] = typeGrouping
        definition["null"] = isNullable ? "1" : "0"

        if !length.isEmpty {
            definition["length"] = length
            definition["char_length"] = NSNumber(value: Int(length) ?? 0)
        }

        if !values.isEmpty {
            definition["values"] = values
        }

        if !comment.isEmpty {
            definition["comment"] = comment
        }

        return definition
    }
}

private extension SALightweightContentViewController.ContentValue {
    var isLoaded: Bool {
        if case .notLoaded = self {
            return false
        }

        return true
    }
}

private extension SALightweightContentViewController {
    func loadCurrentPage() {
        guard connection != nil else { return }

        loadToken = UUID()
        let token = loadToken
        let pageSize = self.pageSize
        let offset = pageIndex * pageSize
        let filter = ruleFilterStringForCurrentState(showError: true)
        guard !filter.failed else { return }

        invalidateCurrentContentCache()
        loadCurrentPage(whereClause: filter.whereClause, token: token, pageSize: pageSize, offset: offset)
    }

    private func loadCurrentPage(whereClause: String?, token: UUID, pageSize: Int, offset: Int) {
        guard let connection = connection else { return }

        isLoading = true
        columns = []
        columnInfo = []
        rows = []
        filteredColumns = []
        totalRowCount = nil
        totalRowCountIsEstimate = false
        hasNextPage = false
        rebuildColumns()
        statusLabel.stringValue = NSLocalizedString("Loading rows...", comment: "lightweight content loading rows")
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            _ = connection.selectDatabase(self.database)
            let columnInfo = self.loadColumnInfo(connection: connection)
            let rowCount = self.rowCount(whereClause: whereClause, connection: connection)
            let query = self.contentQuery(offset: offset, limit: pageSize + 1, whereClause: whereClause, columnInfo: columnInfo)
            let result = connection.queryString(query)
            result?.defaultRowReturnType = SPMySQLResultRowAsArray

            let fieldNames = result?.fieldNames() as? [String] ?? []
            var loadedRows: [ContentRow] = []

            while let row = result?.getRowAsArray() {
                let values = row.enumerated().map { index, value -> ContentValue in
                    if index < columnInfo.count, columnInfo[index].loadBlobAsNeeded {
                        return .notLoaded
                    }

                    return Self.contentValue(for: value)
                }
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
                    self.totalRowCount = nil
                    self.totalRowCountIsEstimate = false
                    self.hasNextPage = false
                    self.rebuildColumns()
                    self.statusLabel.stringValue = error
                    self.updateControls()
                    return
                }

                self.columns = fieldNames
                self.columnInfo = Self.orderedColumnInfo(columnInfo, fieldNames: fieldNames)
                self.rows = loadedRows
                self.totalRowCount = rowCount?.count
                self.totalRowCountIsEstimate = rowCount?.isEstimate ?? false
                self.hasNextPage = hasNextPage
                self.configureRuleFilterColumnsIfNeeded()
                self.applyColumnFilter()
                self.rebuildColumns()
                self.updateStatus()
                self.updateControls()
                self.cacheCurrentContentState()
            }
        }
    }

    private func contentQuery(offset: Int, limit: Int, whereClause: String?, columnInfo: [ColumnInfo]) -> String {
        let fields = columnInfo.isEmpty ? "*" : columnInfo.map { column -> String in
            if column.loadBlobAsNeeded {
                return "NULL AS \(Self.backtickQuoted(column.name))"
            }

            return Self.backtickQuoted(column.name)
        }.joined(separator: ", ")

        var query = "SELECT \(fields) FROM \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table))"

        if let whereClause = whereClause {
            query += " WHERE \(whereClause)"
        }

        if let sortColumn = sortColumn {
            query += " ORDER BY \(Self.backtickQuoted(sortColumn)) \(sortAscending ? "ASC" : "DESC")"
        }

        query += " LIMIT \(offset),\(limit)"
        return query
    }

    private func rowCount(whereClause: String?, connection: SPMySQLConnection) -> (count: Int, isEstimate: Bool)? {
        if whereClause == nil,
           let tableName = connection.escapeAndQuoteString(table),
           let result = connection.queryString("SHOW TABLE STATUS FROM \(Self.backtickQuoted(database)) LIKE \(tableName)") {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary

            if let row = result.getRowAsDictionary() as? [String: Any],
               let count = Int(Self.displayString(for: row["Rows"])) {
                return (count, true)
            }
        }

        var query = "SELECT COUNT(1) FROM \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table))"

        if let whereClause = whereClause {
            query += " WHERE \(whereClause)"
        }

        guard let result = connection.queryString(query),
              let row = result.getRowAsArray(),
              let value = row.first else { return nil }

        guard let count = Int(Self.displayString(for: value)) else { return nil }
        return (count, false)
    }

    private func loadColumnInfo(connection: SPMySQLConnection) -> [ColumnInfo] {
        let result = connection.queryString("SHOW FULL COLUMNS FROM \(Self.backtickQuoted(table)) FROM \(Self.backtickQuoted(database))")
        result?.returnDataAsStrings = true
        result?.defaultRowReturnType = SPMySQLResultRowAsDictionary

        var loadedColumns: [ColumnInfo] = []
        while let row = result?.getRowAsDictionary() as? [String: Any] {
            let name = Self.displayString(for: row["Field"])
            let type = Self.displayString(for: row["Type"])
            let parsedType = Self.parseColumnType(type)
            let key = Self.displayString(for: row["Key"]).uppercased()
            let extra = Self.displayString(for: row["Extra"]).lowercased()
            loadedColumns.append(ColumnInfo(
                name: name,
                type: parsedType.type,
                typeGrouping: parsedType.typeGrouping,
                length: parsedType.length,
                values: parsedType.values,
                comment: Self.displayString(for: row["Comment"]),
                isNullable: Self.displayString(for: row["Null"]).uppercased() == "YES",
                isPrimary: key == "PRI",
                isAutoIncrement: extra.contains("auto_increment")
            ))
        }

        return loadedColumns
    }

    private static func orderedColumnInfo(_ columnInfo: [ColumnInfo], fieldNames: [String]) -> [ColumnInfo] {
        return fieldNames.map { fieldName in
            columnInfo.first { $0.name == fieldName } ?? ColumnInfo(name: fieldName, type: "", typeGrouping: "", length: "", values: [], comment: "", isNullable: false, isPrimary: false, isAutoIncrement: false)
        }
    }

    @objc func applyRuleFilter(_ sender: Any?) {
        isRuleFilterActive = sender != nil
        storeCurrentRuleFilterState()

        pageIndex = 0
        loadCurrentPage()
    }

    @objc func addFilterRule(_ sender: Any?) {
        addFilterRule(after: filterRules.last?.id)
    }

    @objc func contentFiltersHaveBeenUpdated(_ notification: Notification) {
        defaultContentFilters.removeAll()
        loadDefaultContentFilters()
        configureRuleFilterColumnsIfNeeded()
    }

    @objc func showLegacyContentFeature(_ sender: Any?) {
        requestLegacyContentFallback?()
    }

    @objc func reloadContent(_ sender: Any?) {
        invalidateCurrentContentCache()
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
        let columnsToInsert = columnInfo.enumerated().filter { !$0.element.isAutoIncrement && row.values[$0.offset].isLoaded }
        guard !columnsToInsert.isEmpty else {
            addRow(sender)
            return
        }

        runMutation(status: NSLocalizedString("Duplicating row...", comment: "lightweight content duplicating row")) { [database, table] connection in
            let columnList = columnsToInsert.map { Self.backtickQuoted($0.element.name) }.joined(separator: ", ")
            let valueList = columnsToInsert.compactMap { Self.sqlValue(row.values[$0.offset], columnInfo: $0.element, connection: connection) }.joined(separator: ", ")
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

    @objc func removeRow(_ sender: Any?) {
        deleteRows(sender)
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

                self.invalidateCurrentContentCache()
                self.loadCurrentPage()
            }
        }
    }

    func applyColumnFilter() {
        filteredColumns = Array(columns.indices)
    }

    func rebuildColumns() {
        let tableFont = UserDefaults.getFont()
        let showColumnTypes = UserDefaults.standard.bool(forKey: SPDisplayTableViewColumnTypes)

        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }

        for columnIndex in filteredColumns {
            let columnName = columns[columnIndex]
            let column = columnIndex < columnInfo.count
                ? columnInfo[columnIndex]
                : ColumnInfo(name: columnName, type: "", typeGrouping: "", length: "", values: [], comment: "", isNullable: false, isPrimary: false, isAutoIncrement: false)
            let identifier = NSUserInterfaceItemIdentifier("\(columnIndex)")
            let tableColumn = NSTableColumn(identifier: identifier)
            tableColumn.title = columnName
            tableColumn.width = savedWidth(for: columnName) ?? 90
            tableColumn.minWidth = 8
            tableColumn.maxWidth = 20_000
            tableColumn.resizingMask = [.autoresizingMask, .userResizingMask]
            tableColumn.headerToolTip = legacyHeaderToolTip(for: column)
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: "\(columnIndex)", ascending: true)
            tableColumn.headerCell.attributedStringValue = contentHeaderTitle(for: columnIndex, columnName: columnName, showColumnTypes: showColumnTypes)
            tableColumn.dataCell = dataCell(for: column, font: tableFont)
            tableView.addTableColumn(tableColumn)
        }

        tableView.reloadData()
        autosizeContentColumns()
    }

    func updateStatus() {
        let selectedRows = tableView.numberOfSelectedRows
        let selectionText: String

        if selectedRows == 1 {
            selectionText = NSLocalizedString("; 1 row selected", comment: "lightweight content one row selected")
        } else if selectedRows > 1 {
            selectionText = String(format: NSLocalizedString("; %ld rows selected", comment: "lightweight content rows selected"), selectedRows)
        } else {
            selectionText = ""
        }

        guard !rows.isEmpty else {
            statusLabel.stringValue = NSLocalizedString("No rows in table", comment: "lightweight content no rows") + selectionText
            return
        }

        let start = pageIndex * pageSize + 1
        let end = start + rows.count - 1

        if let totalRowCount = totalRowCount {
            let countPrefix = totalRowCountIsEstimate ? "~" : ""
            statusLabel.stringValue = String(format: NSLocalizedString("Rows %@ - %@ of %@%@ from table", comment: "lightweight content row range of total"), Self.formattedCount(start), Self.formattedCount(end), countPrefix, Self.formattedCount(totalRowCount)) + selectionText
        } else {
            statusLabel.stringValue = String(format: NSLocalizedString("Rows %@ - %@ from table", comment: "lightweight content row range"), Self.formattedCount(start), Self.formattedCount(end)) + selectionText
        }
    }

    func updateControls() {
        addRowButton.isEnabled = !isLoading
        duplicateRowButton.isEnabled = !isLoading && tableView.numberOfSelectedRows == 1
        deleteRowButton.isEnabled = !isLoading && tableView.numberOfSelectedRows > 0
        reloadButton.isEnabled = !isLoading
        editModeButton.isEnabled = !isLoading
        applyFilterButton.isEnabled = isRuleFilterVisible && !isLoading && !columnInfo.isEmpty && !filterRules.isEmpty
        addFilterButton.isEnabled = isRuleFilterVisible && !isLoading && !columnInfo.isEmpty
        filterRowsStackView.arrangedSubviews.forEach { $0.subviews.forEach { ($0 as? NSControl)?.isEnabled = !isLoading } }
        previousPageButton.isEnabled = !isLoading && pageIndex > 0
        paginationButton.isEnabled = !isLoading
        nextPageButton.isEnabled = !isLoading && hasNextPage
        if let totalRowCount = totalRowCount {
            let maxPage = max(1, Int(ceil(Double(totalRowCount) / Double(pageSize))))
            pageLabel.stringValue = String(format: NSLocalizedString("Page %ld of %ld", comment: "lightweight content page label with total"), pageIndex + 1, maxPage)
        } else {
            pageLabel.stringValue = String(format: NSLocalizedString("Page %ld", comment: "lightweight content page label"), pageIndex + 1)
        }
    }

    func configureRuleFilterColumnsIfNeeded() {
        let key = columnInfo.map { "\($0.name):\($0.typeGrouping)" }.joined(separator: "\t")
        guard key != ruleFilterColumnsKey else {
            updateRuleFilterVisibility(animated: false)
            return
        }

        ruleFilterColumnsKey = key

        if let restoredFilter = restoredRuleFilters[ruleFilterStorageKey()] as? [AnyHashable: Any] {
            filterRules = filterRules(from: restoredFilter)
        } else {
            filterRules = []
        }

        if isRuleFilterVisible, filterRules.isEmpty, !columnInfo.isEmpty {
            filterRules = [defaultFilterRule()]
        }

        rebuildFilterRows()
        updateRuleFilterVisibility(animated: false)
    }

    func setRuleFilterVisible(_ visible: Bool, animate: Bool) {
        isRuleFilterVisible = visible
        UserDefaults.standard.set(visible, forKey: SPRuleFilterEditorLastVisibilityChoice)

        if visible {
            configureRuleFilterColumnsIfNeeded()
            if !columnInfo.isEmpty, filterRules.isEmpty {
                filterRules = [defaultFilterRule()]
                rebuildFilterRows()
            }
            focusFirstFilterValueField()
        } else {
            if isRuleFilterActive {
                isRuleFilterActive = false
                storeCurrentRuleFilterState()
            }
            view.window?.makeFirstResponder(tableView)
        }

        updateRuleFilterVisibility(animated: animate)
    }

    func updateRuleFilterVisibility(animated: Bool) {
        let preferredHeight = max(29, CGFloat(max(filterRules.count, 1)) * LightweightFilterRuleRowView.rowHeight)
        let maximumHeight = max(29, view.bounds.height / 3)
        let targetHeight = isRuleFilterVisible ? min(preferredHeight, maximumHeight) : 0

        ruleFilterContainer.isHidden = false
        ruleFilterHeightConstraint?.constant = targetHeight
        filterRowsScrollView.hasVerticalScroller = preferredHeight > targetHeight
        applyFilterButton.isHidden = filterRules.isEmpty
        addFilterButton.isHidden = !filterRules.isEmpty
        updateControls()

        let layout = {
            self.view.layoutSubtreeIfNeeded()
            self.updateFilterRowsFrame()
            if targetHeight == 0 {
                self.ruleFilterContainer.isHidden = true
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                layout()
            }
        } else {
            layout()
        }
    }

    func updateFilterRowsFrame() {
        guard isViewLoaded else { return }

        let visibleBounds = filterRowsScrollView.contentView.bounds
        let preferredHeight = max(29, CGFloat(max(filterRules.count, 1)) * LightweightFilterRuleRowView.rowHeight)
        let width = max(visibleBounds.width, 760)
        let height = max(visibleBounds.height, preferredHeight)
        let frame = NSRect(x: 0, y: 0, width: width, height: height)

        if filterRowsStackView.frame != frame {
            filterRowsStackView.frame = frame
            filterRowsStackView.needsLayout = true
            filterRowsStackView.needsDisplay = true
        }

        if visibleBounds.origin != .zero {
            filterRowsScrollView.contentView.scroll(to: .zero)
            filterRowsScrollView.reflectScrolledClipView(filterRowsScrollView.contentView)
        }
    }

    func loadDefaultContentFilters() {
        guard defaultContentFilters.isEmpty else { return }

        let path = Bundle.main.path(forResource: "ContentFilters", ofType: "plist")
            ?? Bundle.main.path(forResource: "ContentFilters.plist", ofType: nil)
        guard let path = path,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let filters = plist as? [String: [NSDictionary]] else { return }

        defaultContentFilters = filters.mapValues { definitions in
            definitions.compactMap { contentFilterDefinition(from: $0, filterType: "") }
        }
    }

    func contentFilterDefinition(from dictionary: NSDictionary, filterType: String) -> ContentFilterDefinition? {
        guard let title = dictionary["MenuLabel"] as? String,
              let clause = dictionary["Clause"] as? String else { return nil }

        return ContentFilterDefinition(
            title: title,
            clause: clause,
            numberOfArguments: (dictionary["NumberOfArguments"] as? NSNumber)?.intValue ?? 0,
            conjunctionLabels: dictionary["ConjunctionLabels"] as? [String] ?? [],
            suppressLeadingFieldPlaceholder: (dictionary["SuppressLeadingFieldPlaceholder"] as? NSNumber)?.boolValue ?? false,
            filterType: filterType,
            rawDefinition: dictionary
        )
    }

    func contentFilters(for filterType: String) -> [ContentFilterDefinition] {
        var filters = defaultContentFilters[filterType] ?? []

        if let userFilters = UserDefaults.standard.object(forKey: SPContentFilters) as? [String: Any],
           let typedUserFilters = userFilters[filterType] as? [NSDictionary] {
            filters.append(contentsOf: typedUserFilters.compactMap { contentFilterDefinition(from: $0, filterType: filterType) })
        }

        return filters.map {
            ContentFilterDefinition(
                title: $0.title,
                clause: $0.clause,
                numberOfArguments: $0.numberOfArguments,
                conjunctionLabels: $0.conjunctionLabels,
                suppressLeadingFieldPlaceholder: $0.suppressLeadingFieldPlaceholder,
                filterType: filterType,
                rawDefinition: $0.rawDefinition
            )
        }
    }

    func filterType(for column: ColumnInfo) -> String {
        switch column.typeGrouping {
        case "date":
            return "date"
        case "string", "binary", "textdata", "blobdata", "enum":
            return "string"
        case "bit", "integer", "float":
            return "number"
        case "geometry":
            return "spatial"
        default:
            return "string"
        }
    }

    func columnInfo(named name: String) -> ColumnInfo? {
        return columnInfo.first { $0.name == name }
    }

    func operators(for columnName: String) -> [ContentFilterDefinition] {
        guard let column = columnInfo(named: columnName) else { return [] }
        return contentFilters(for: filterType(for: column))
    }

    func operatorDefinition(for rule: FilterRule) -> ContentFilterDefinition? {
        let operators = operators(for: rule.columnName)
        return operators.first { $0.title == rule.operatorTitle } ?? operators.first
    }

    func defaultFilterRule() -> FilterRule {
        let columnName = columnInfo.first?.name ?? ""
        let operatorTitle = operators(for: columnName).first?.title ?? "="
        return FilterRule(columnName: columnName, operatorTitle: operatorTitle)
    }

    func addFilterRule(after id: UUID?) {
        guard !columnInfo.isEmpty else { return }

        let newRule = defaultFilterRule()
        if let id = id, let index = filterRules.firstIndex(where: { $0.id == id }) {
            filterRules.insert(newRule, at: index + 1)
        } else {
            filterRules.append(newRule)
        }

        rebuildFilterRows()
        storeCurrentRuleFilterState()
        updateRuleFilterVisibility(animated: false)
        focusValueField(for: newRule.id)
    }

    func removeFilterRule(id: UUID) {
        filterRules.removeAll { $0.id == id }
        rebuildFilterRows()
        storeCurrentRuleFilterState()
        updateRuleFilterVisibility(animated: false)

        if filterRules.isEmpty {
            applyRuleFilter(nil)
        }
    }

    func updateFilterRule(id: UUID, update: (inout FilterRule) -> Void) {
        guard let index = filterRules.firstIndex(where: { $0.id == id }) else { return }

        update(&filterRules[index])
        normalizeFilterRule(at: index)
        rebuildFilterRows()
        storeCurrentRuleFilterState()
        updateRuleFilterVisibility(animated: false)
    }

    func normalizeFilterRule(at index: Int) {
        guard filterRules.indices.contains(index) else { return }

        if columnInfo(named: filterRules[index].columnName) == nil {
            filterRules[index].columnName = columnInfo.first?.name ?? ""
        }

        let operators = operators(for: filterRules[index].columnName)
        if !operators.contains(where: { $0.title == filterRules[index].operatorTitle }) {
            filterRules[index].operatorTitle = operators.first?.title ?? "="
        }

        let argumentCount = operatorDefinition(for: filterRules[index])?.numberOfArguments ?? 0
        if filterRules[index].values.count > argumentCount {
            filterRules[index].values = Array(filterRules[index].values.prefix(argumentCount))
        }
        while filterRules[index].values.count < argumentCount {
            filterRules[index].values.append("")
        }
    }

    func rebuildFilterRows() {
        filterRowsStackView.arrangedSubviews.forEach { view in
            filterRowsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for rule in filterRules {
            guard let definition = operatorDefinition(for: rule) else { continue }
            let rowView = LightweightFilterRuleRowView()
            rowView.configure(
                rule: rule,
                columnNames: columnInfo.map { $0.name },
                operators: operators(for: rule.columnName),
                selectedOperator: definition
            )
            rowView.onEnabledChanged = { [weak self] id, isEnabled in
                self?.updateFilterRule(id: id) { $0.isEnabled = isEnabled }
            }
            rowView.onColumnChanged = { [weak self] id, columnName in
                self?.updateFilterRule(id: id) {
                    $0.columnName = columnName
                    $0.operatorTitle = self?.operators(for: columnName).first?.title ?? "="
                    $0.values = []
                }
            }
            rowView.onOperatorChanged = { [weak self] id, operatorTitle in
                self?.updateFilterRule(id: id) {
                    $0.operatorTitle = operatorTitle
                    $0.values = []
                }
            }
            rowView.onValuesChanged = { [weak self] id, values in
                guard let self = self, let index = self.filterRules.firstIndex(where: { $0.id == id }) else { return }
                self.filterRules[index].values = values
                self.normalizeFilterRule(at: index)
                self.storeCurrentRuleFilterState()
            }
            rowView.onAdd = { [weak self] id in
                self?.addFilterRule(after: id)
            }
            rowView.onRemove = { [weak self] id in
                self?.removeFilterRule(id: id)
            }
            rowView.onApply = { [weak self] in
                self?.applyRuleFilter(self)
            }

            filterRowsStackView.addArrangedSubview(rowView)
            rowView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                rowView.heightAnchor.constraint(equalToConstant: LightweightFilterRuleRowView.rowHeight),
                rowView.widthAnchor.constraint(equalTo: filterRowsStackView.widthAnchor)
            ])
        }

        updateFilterRowsFrame()
    }

    func focusFirstFilterValueField() {
        guard let firstRule = filterRules.first else { return }
        focusValueField(for: firstRule.id)
    }

    func focusValueField(for id: UUID) {
        guard let rowView = filterRowsStackView.arrangedSubviews.compactMap({ $0 as? LightweightFilterRuleRowView }).first(where: { $0.ruleID == id }) else { return }
        rowView.focusValueField()
    }

    func sqlWhereExpressionForCurrentFilter(binary: Bool) throws -> String {
        let expressions = try filterRules.compactMap { rule -> String? in
            guard rule.isEnabled else { return nil }
            guard let definition = operatorDefinition(for: rule) else { return nil }
            guard let parser = SPTableFilterParser(filterClause: definition.clause, numberOfArguments: UInt(definition.numberOfArguments)) else {
                throw filterError(NSLocalizedString("No valid SQL expression could be generated.", comment: "lightweight content invalid filter fallback"))
            }

            parser.currentField = rule.columnName
            parser.suppressLeadingTablePlaceholder = definition.suppressLeadingFieldPlaceholder
            parser.caseSensitive = binary

            if definition.numberOfArguments > 0 {
                parser.argument = rule.values.indices.contains(0) ? rule.values[0] : ""
            }
            if definition.numberOfArguments > 1 {
                parser.firstBetweenArgument = rule.values.indices.contains(0) ? rule.values[0] : ""
                parser.secondBetweenArgument = rule.values.indices.contains(1) ? rule.values[1] : ""
            }

            guard let filterString = parser.filterString(), !filterString.isEmpty else {
                throw filterError(NSLocalizedString("No valid SQL expression could be generated.", comment: "lightweight content invalid filter fallback"))
            }

            return filterString
        }

        return expressions.joined(separator: " AND ")
    }

    func filterError(_ message: String) -> NSError {
        return NSError(domain: "SALightweightContentFilter", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func serializedFilter() -> NSDictionary {
        let children = filterRules.map { rule -> NSDictionary in
            let definition = operatorDefinition(for: rule)
            let filterType = definition?.filterType ?? columnInfo(named: rule.columnName).map(filterType(for:)) ?? ""
            return [
                "filterClass": "expressionNode",
                "column": rule.columnName,
                "filterType": filterType,
                "filterComparison": rule.operatorTitle,
                "filterValues": rule.values,
                "enabled": rule.isEnabled
            ]
        }

        if children.count == 1 {
            return children[0]
        }

        return [
            "filterClass": "groupNode",
            "isConjunction": true,
            "children": children
        ]
    }

    func filterRules(from serialized: [AnyHashable: Any]) -> [FilterRule] {
        let filterClass = serialized["filterClass"] as? String
        if filterClass == "groupNode", (serialized["isConjunction"] as? NSNumber)?.boolValue ?? (serialized["isConjunction"] as? Bool ?? false),
           let children = serialized["children"] as? [[AnyHashable: Any]] {
            return children.flatMap { filterRules(from: $0) }
        }

        guard filterClass == "expressionNode" else { return [] }
        guard let columnName = serialized["column"] as? String,
              columnInfo(named: columnName) != nil else { return [] }

        let operatorTitle = serialized["filterComparison"] as? String ?? operators(for: columnName).first?.title ?? "="
        let values = serialized["filterValues"] as? [String] ?? []
        let isEnabled = (serialized["enabled"] as? NSNumber)?.boolValue ?? (serialized["enabled"] as? Bool ?? true)
        return [normalizedFilterRule(FilterRule(isEnabled: isEnabled, columnName: columnName, operatorTitle: operatorTitle, values: values))]
    }

    func normalizedFilterRule(_ rule: FilterRule) -> FilterRule {
        var normalizedRule = rule
        if columnInfo(named: normalizedRule.columnName) == nil {
            normalizedRule.columnName = columnInfo.first?.name ?? ""
        }

        let operators = operators(for: normalizedRule.columnName)
        if !operators.contains(where: { $0.title == normalizedRule.operatorTitle }) {
            normalizedRule.operatorTitle = operators.first?.title ?? "="
        }

        let argumentCount = operators.first(where: { $0.title == normalizedRule.operatorTitle })?.numberOfArguments ?? 0
        if normalizedRule.values.count > argumentCount {
            normalizedRule.values = Array(normalizedRule.values.prefix(argumentCount))
        }
        while normalizedRule.values.count < argumentCount {
            normalizedRule.values.append("")
        }
        return normalizedRule
    }

    func ruleFilterStringForCurrentState(showError: Bool) -> (whereClause: String?, failed: Bool) {
        guard isRuleFilterActive, isRuleFilterVisible else { return (nil, false) }

        let caseSensitive = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        let filter: String
        do {
            filter = try sqlWhereExpressionForCurrentFilter(binary: caseSensitive)
        } catch {
            if showError {
                showInvalidRuleFilterAlert(error: error)
            }
            return (nil, true)
        }

        let trimmedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedFilter.isEmpty ? nil : trimmedFilter, false)
    }

    func storeCurrentRuleFilterState() {
        guard !database.isEmpty, !table.isEmpty else { return }

        let key = ruleFilterStorageKey()
        if filterRules.isEmpty {
            restoredRuleFilters.removeValue(forKey: key)
        } else {
            restoredRuleFilters[key] = serializedFilter() as NSDictionary
        }

        if isRuleFilterActive {
            restoredActiveRuleFilters.insert(key)
        } else {
            restoredActiveRuleFilters.remove(key)
        }
    }

    func ruleFilterStorageKey(database: String? = nil, table: String? = nil) -> String {
        return "\(database ?? self.database)\u{0}\(table ?? self.table)"
    }

    func contentCacheKey(database: String? = nil, table: String? = nil) -> String {
        return "\(database ?? self.database)\u{0}\(table ?? self.table)"
    }

    func restoreCachedContent(for key: String) -> Bool {
        guard let cached = contentCache[key], cached.pageSize == pageSize else {
            contentCache.removeValue(forKey: key)
            contentCacheOrder.removeAll { $0 == key }
            return false
        }

        isRestoringCachedContent = true
        defer { isRestoringCachedContent = false }

        columns = cached.columns
        columnInfo = cached.columnInfo
        rows = cached.rows
        pageIndex = cached.pageIndex
        totalRowCount = cached.totalRowCount
        totalRowCountIsEstimate = cached.totalRowCountIsEstimate
        hasNextPage = cached.hasNextPage
        sortColumn = cached.sortColumn
        sortAscending = cached.sortAscending
        isRuleFilterActive = cached.isRuleFilterActive

        if let serializedRuleFilter = cached.serializedRuleFilter {
            restoredRuleFilters[ruleFilterStorageKey()] = serializedRuleFilter
        } else {
            restoredRuleFilters.removeValue(forKey: ruleFilterStorageKey())
        }

        if isRuleFilterActive {
            restoredActiveRuleFilters.insert(ruleFilterStorageKey())
        } else {
            restoredActiveRuleFilters.remove(ruleFilterStorageKey())
        }

        if let sortColumn = sortColumn, let columnIndex = columns.firstIndex(of: sortColumn) {
            tableView.sortDescriptors = [NSSortDescriptor(key: "\(columnIndex)", ascending: sortAscending)]
        } else {
            tableView.sortDescriptors = []
        }

        isLoading = false
        filteredColumns = []
        configureRuleFilterColumnsIfNeeded()
        applyColumnFilter()
        rebuildColumns()
        updateStatus()
        updateControls()
        noteContentCacheUse(for: key)
        return true
    }

    func cacheCurrentContentState() {
        guard !database.isEmpty, !table.isEmpty, !columns.isEmpty else { return }

        storeCurrentRuleFilterState()
        let key = contentCacheKey()
        contentCache[key] = ContentCacheEntry(
            columns: columns,
            columnInfo: columnInfo,
            rows: rows,
            pageIndex: pageIndex,
            pageSize: pageSize,
            totalRowCount: totalRowCount,
            totalRowCountIsEstimate: totalRowCountIsEstimate,
            hasNextPage: hasNextPage,
            sortColumn: sortColumn,
            sortAscending: sortAscending,
            isRuleFilterActive: isRuleFilterActive,
            serializedRuleFilter: restoredRuleFilters[ruleFilterStorageKey()]
        )
        noteContentCacheUse(for: key)
    }

    func noteContentCacheUse(for key: String) {
        contentCacheOrder.removeAll { $0 == key }
        contentCacheOrder.append(key)

        while contentCacheOrder.count > maximumContentCacheEntries {
            let oldKey = contentCacheOrder.removeFirst()
            contentCache.removeValue(forKey: oldKey)
        }
    }

    func invalidateCurrentContentCache() {
        let key = contentCacheKey()
        contentCache.removeValue(forKey: key)
        contentCacheOrder.removeAll { $0 == key }
    }

    func showInvalidRuleFilterAlert(error: Error?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Invalid Filter", comment: "table content apply filter invalid filter message title")
        alert.informativeText = error?.localizedDescription ?? NSLocalizedString("No valid SQL expression could be generated.", comment: "lightweight content invalid filter fallback")

        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    func toolbarButton(imageName: String, toolTip: String, keyEquivalent: String = "", modifierMask: NSEvent.ModifierFlags = [], action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(named: NSImage.Name(imageName)) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .smallSquare
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        button.keyEquivalent = keyEquivalent
        button.keyEquivalentModifierMask = modifierMask
        button.contentTintColor = .labelColor
        return button
    }

    func registerPreferenceObserversIfNeeded() {
        guard !didRegisterPreferenceObservers else { return }

        UserDefaults.standard.addObserver(self, forKeyPath: SPDisplayTableViewVerticalGridlines, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: SPDisplayTableViewColumnTypes, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: SPGlobalFontSettings, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: SPDisplayBinaryDataAsHex, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: SPNullValue, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: SPLoadBlobsAsNeeded, options: .new, context: nil)
        didRegisterPreferenceObservers = true
    }

    func applyTablePreferences(rebuildColumns shouldRebuildColumns: Bool) {
        let tableFont = UserDefaults.getFont()
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = Self.tableRowHeight(for: tableFont)

        for column in tableView.tableColumns {
            (column.dataCell as? NSCell)?.font = tableFont
            column.headerCell.font = Self.headerFont(for: tableFont)
        }

        if shouldRebuildColumns {
            rebuildColumns()
        } else {
            tableView.headerView?.needsDisplay = true
            tableView.reloadData()
            autosizeContentColumns()
        }
    }

    func contentHeaderTitle(for columnIndex: Int, columnName: String, showColumnTypes: Bool) -> NSAttributedString {
        let definition = columnIndex < columnInfo.count
            ? columnInfo[columnIndex].legacyDefinition
            : ["name": columnName]
        return definition.tableContentColumnHeaderAttributedString(columnTypesVisible: showColumnTypes)
    }

    func legacyHeaderToolTip(for column: ColumnInfo) -> String {
        var tooltip = "\(column.name) - \(column.type)"
        if !column.length.isEmpty {
            tooltip += "(\(column.length))"
        }
        if !column.values.isEmpty {
            tooltip += "(\n- \(column.values.joined(separator: "\n- "))\n)"
        }
        if !column.comment.isEmpty {
            tooltip += "\n\(column.comment.replacingOccurrences(of: "\\n", with: "\n"))"
        }
        return tooltip
    }

    func dataCell(for column: ColumnInfo, font: NSFont) -> NSCell {
        let cell: NSCell
        if column.typeGrouping == "enum" {
            let comboCell = SPComboBoxCell(textCell: "")
            comboCell.isButtonBordered = false
            comboCell.isBezeled = false
            comboCell.drawsBackground = false
            comboCell.completes = true
            comboCell.controlSize = .small
            comboCell.usesSingleLineMode = true
            if column.isNullable {
                comboCell.addItem(withObjectValue: UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL")
            }
            comboCell.addItems(withObjectValues: column.values)
            cell = comboCell
        } else {
            cell = SPTextAndLinkCell(textCell: "")
        }

        cell.isEditable = true
        cell.isSelectable = true
        cell.lineBreakMode = .byTruncatingTail
        cell.font = font

        if column.typeGrouping == "integer" || column.typeGrouping == "float" {
            cell.alignment = .right
        }

        let formatter = SPDataCellFormatter()
        formatter.fieldType = column.type
        if (column.typeGrouping == "string" || column.typeGrouping == "bit"),
           let limit = Int(column.length) {
            formatter.textLimit = limit
        }
        cell.formatter = formatter

        return cell
    }

    func autosizeContentColumns() {
        isApplyingProgrammaticColumnWidths = true
        defer { isApplyingProgrammaticColumnWidths = false }

        var widthsByIdentifier: [String: CGFloat] = [:]

        for tableColumn in tableView.tableColumns {
            guard let columnIndex = Int(tableColumn.identifier.rawValue) else { continue }
            if columnIndex < columns.count, savedWidth(for: columns[columnIndex]) != nil {
                continue
            }

            let width = autodetectedWidth(for: tableColumn, columnIndex: columnIndex)
            widthsByIdentifier[tableColumn.identifier.rawValue] = width
        }

        for tableColumn in tableView.tableColumns {
            guard let targetWidth = widthsByIdentifier[tableColumn.identifier.rawValue] else { continue }
            tableColumn.maxWidth = max(tableColumn.maxWidth, targetWidth)
            tableColumn.width = ceil(max(targetWidth, tableColumn.minWidth))
        }
    }

    func autodetectedWidth(for tableColumn: NSTableColumn, columnIndex: Int) -> CGFloat {
        var maxCellWidth: CGFloat = 0
        for row in visibleRowsForAutosizing(maxRows: 160) {
            guard columnIndex < row.values.count else { continue }
            let cellWidth = measuredCellWidth(displayString(for: row.values[columnIndex], columnIndex: columnIndex), in: tableColumn)
            maxCellWidth = max(maxCellWidth, cellWidth)
        }

        if columnIndex < columnInfo.count, columnInfo[columnIndex].typeGrouping == "enum" {
            maxCellWidth += 8
        }

        let headerWidth = measuredHeaderWidth(for: tableColumn) + 10
        return ceil(max(maxCellWidth + 24, headerWidth, tableColumn.minWidth))
    }

    func visibleRowsForAutosizing(maxRows: Int) -> [ContentRow] {
        guard maxRows > 0, !rows.isEmpty else { return [] }

        let visibleRange = tableView.rows(in: tableView.visibleRect)
        let start = visibleRange.length > 0 ? visibleRange.location : 0
        let end = visibleRange.length > 0 ? min(rows.count, visibleRange.location + visibleRange.length) : min(rows.count, maxRows)
        guard start < end else { return Array(rows.prefix(maxRows)) }

        return Array(rows[start..<min(end, start + maxRows)])
    }

    func measuredHeaderWidth(for tableColumn: NSTableColumn) -> CGFloat {
        let headerCell = tableColumn.headerCell

        if headerCell.attributedStringValue.length > 0 {
            return max(headerCell.cellSize.width, headerCell.attributedStringValue.size().width)
        }

        let title = headerCell.stringValue as NSString
        let font = headerCell.font ?? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        return max(headerCell.cellSize.width, title.size(withAttributes: [.font: font]).width)
    }

    func measuredCellWidth(_ value: String, in tableColumn: NSTableColumn) -> CGFloat {
        guard let cell = (tableColumn.dataCell as? NSCell)?.copy() as? NSCell else {
            return (value as NSString).size(withAttributes: [.font: UserDefaults.getFont()]).width
        }

        cell.stringValue = value
        let font = cell.font ?? UserDefaults.getFont()
        return max(cell.cellSize.width, (value as NSString).size(withAttributes: [.font: font]).width)
    }

    static func tableRowHeight(for font: NSFont) -> CGFloat {
        return 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: font]).height
    }

    static func headerFont(for font: NSFont) -> NSFont {
        return NSFontManager.shared.convert(font, toSize: max(font.pointSize * 0.75, 11.0))
    }

    static func formattedCount(_ value: Int) -> String {
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    func displayString(for value: ContentValue, columnIndex: Int, truncate: Bool = true) -> String {
        switch value {
        case .null:
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        case .notLoaded:
            return NSLocalizedString("(not loaded)", comment: "value shown for hidden blob and text fields")
        case .object(let object):
            guard let data = object as? Data else {
                return String(describing: object)
            }

            let column = columnIndex < columnInfo.count ? columnInfo[columnIndex] : nil
            if let column = column,
               UserDefaults.standard.bool(forKey: SPDisplayBinaryDataAsHex),
               column.displaysBinaryAsHex {
                if truncate && data.count > 255 {
                    return "0x" + data.prefix(255).map { String(format: "%02X", $0) }.joined() + "..."
                }
                return "0x" + data.map { String(format: "%02X", $0) }.joined()
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    static func displayString(for value: Any) -> String {
        if value is NSNull {
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        return String(describing: value)
    }

    static func displayString(for value: Any?) -> String {
        guard let value = value else {
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        return displayString(for: value)
    }

    static func contentValue(for value: Any?) -> ContentValue {
        guard let value = value, !(value is NSNull) else { return .null }
        return .object(value)
    }

    static func sqlValue(_ value: ContentValue, columnInfo: ColumnInfo, connection: SPMySQLConnection) -> String? {
        switch value {
        case .null:
            return "NULL"
        case .notLoaded:
            return nil
        case .object(let object):
            if let data = object as? Data {
                return connection.escapeAndQuoteData(data) ?? "'\(data.map { String(format: "%02X", $0) }.joined())'"
            }

            let value = String(describing: object)
            if columnInfo.typeGrouping == "bit" {
                return "b'\(value)'"
            }

            return connection.escapeAndQuoteString(value) ?? "'\(value.replacingOccurrences(of: "'", with: "''"))'"
        }
    }

    static func quotedLikePattern(_ value: String, connection: SPMySQLConnection) -> String {
        let escapedValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let value = "%\(escapedValue)%"
        return connection.escapeAndQuoteString(value) ?? "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func rowIdentityWhereClause(for values: [ContentValue], columnInfo: [ColumnInfo], connection: SPMySQLConnection) -> String? {
        let primaryColumns = columnInfo.enumerated().filter { $0.element.isPrimary }
        let identityColumns = primaryColumns.isEmpty ? Array(columnInfo.enumerated()) : primaryColumns

        guard !identityColumns.isEmpty else { return nil }

        let parts = identityColumns.compactMap { index, column -> String? in
            guard index < values.count else { return nil }

            if case .null = values[index] {
                return "\(backtickQuoted(column.name)) IS NULL"
            }

            guard let sqlValue = sqlValue(values[index], columnInfo: column, connection: connection) else { return nil }
            return "\(backtickQuoted(column.name)) = \(sqlValue)"
        }

        guard !parts.isEmpty else { return nil }

        return parts.joined(separator: " AND ")
    }

    static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    func savedWidth(for columnName: String) -> CGFloat? {
        guard let host = connection?.host,
              !host.isEmpty,
              let savedWidths = UserDefaults.standard.dictionary(forKey: SPTableColumnWidths),
              let databaseWidths = savedWidths["\(database)@\(host)"] as? [String: Any],
              let tableWidths = databaseWidths[table] as? [String: Any],
              let width = tableWidths[columnName] as? NSNumber else { return nil }

        return CGFloat(truncating: width)
    }

    func saveWidth(for tableColumn: NSTableColumn) {
        guard !isApplyingProgrammaticColumnWidths,
              let columnIndex = Int(tableColumn.identifier.rawValue),
              columnIndex < columns.count,
              let host = connection?.host,
              !host.isEmpty else { return }

        let databaseKey = "\(database)@\(host)"
        let columnName = columns[columnIndex]
        var savedWidths = UserDefaults.standard.dictionary(forKey: SPTableColumnWidths) ?? [:]
        var databaseWidths = savedWidths[databaseKey] as? [String: Any] ?? [:]
        var tableWidths = databaseWidths[table] as? [String: Any] ?? [:]

        tableWidths[columnName] = NSNumber(value: Double(tableColumn.width))
        databaseWidths[table] = tableWidths
        savedWidths[databaseKey] = databaseWidths
        UserDefaults.standard.set(savedWidths, forKey: SPTableColumnWidths)
    }

    static func parseColumnType(_ rawType: String) -> (type: String, typeGrouping: String, length: String, values: [String]) {
        let lower = rawType.lowercased()
        let baseType = lower.split { !$0.isLetter && !$0.isNumber }.first.map(String.init) ?? lower
        let length = Self.parenthesizedContent(in: rawType) ?? ""
        let values = (baseType == "enum" || baseType == "set") ? Self.enumValues(from: length) : []
        let typeGrouping: String

        if baseType == "bit" {
            typeGrouping = "bit"
        } else if ["tinyint", "smallint", "mediumint", "int", "integer", "bigint"].contains(baseType) {
            typeGrouping = "integer"
        } else if ["decimal", "numeric", "float", "double", "real"].contains(baseType) {
            typeGrouping = "float"
        } else if ["date", "datetime", "timestamp", "time", "year"].contains(baseType) {
            typeGrouping = "date"
        } else if ["char", "varchar"].contains(baseType) {
            typeGrouping = lower.contains("binary") ? "binary" : "string"
        } else if ["binary", "varbinary"].contains(baseType) {
            typeGrouping = "binary"
        } else if baseType == "enum" || baseType == "set" {
            typeGrouping = "enum"
        } else if ["tinytext", "text", "mediumtext", "longtext", "json"].contains(baseType) {
            typeGrouping = "textdata"
        } else if ["tinyblob", "blob", "mediumblob", "longblob"].contains(baseType) {
            typeGrouping = "blobdata"
        } else if ["geometry", "point", "linestring", "polygon", "multipoint", "multilinestring", "multipolygon", "geometrycollection"].contains(baseType) {
            typeGrouping = "geometry"
        } else {
            typeGrouping = "string"
        }

        return (baseType.uppercased(), typeGrouping, length, values)
    }

    static func parenthesizedContent(in value: String) -> String? {
        guard let open = value.firstIndex(of: "("),
              let close = value.lastIndex(of: ")"),
              open < close else { return nil }

        return String(value[value.index(after: open)..<close])
    }

    static func enumValues(from value: String) -> [String] {
        return value.split(separator: ",").map { item in
            item.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
        }
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

        return displayString(for: rows[row].values[columnIndex], columnIndex: columnIndex)
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        guard row >= 0,
              row < rows.count,
              let connection = connection,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].values.count,
              columnIndex < columnInfo.count,
              !isLoading else { return false }

        guard case .notLoaded = rows[row].values[columnIndex] else { return true }

        guard let whereClause = Self.rowIdentityWhereClause(for: rows[row].originalValues, columnInfo: columnInfo, connection: connection) else {
            statusLabel.stringValue = NSLocalizedString("Cannot load cell without identifiable columns", comment: "lightweight content blob load no identity")
            return false
        }

        let query = "SELECT \(Self.backtickQuoted(columnInfo[columnIndex].name)) FROM \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table)) WHERE \(whereClause) LIMIT 1"
        guard let result = connection.queryString(query),
              let rowValues = result.getRowAsArray(),
              let value = rowValues.first else { return false }

        rows[row].values[columnIndex] = Self.contentValue(for: value)
        rows[row].originalValues[columnIndex] = Self.contentValue(for: value)
        tableView.reloadData()
        autosizeContentColumns()
        cacheCurrentContentState()
        return true
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
        guard newValue != displayString(for: rows[row].values[columnIndex], columnIndex: columnIndex, truncate: false) else { return }

        guard let whereClause = Self.rowIdentityWhereClause(for: oldRowValues, columnInfo: columnInfo, connection: connection) else {
            statusLabel.stringValue = NSLocalizedString("Cannot edit row without identifiable columns", comment: "lightweight content edit no identity")
            return
        }

        let columnName = columnInfo[columnIndex].name
        let updatedValue: ContentValue = newValue == (UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL") && columnInfo[columnIndex].isNullable
            ? .null
            : .object(newValue)
        guard let sqlValue = Self.sqlValue(updatedValue, columnInfo: columnInfo[columnIndex], connection: connection) else { return }
        let limit = columnInfo.contains { $0.isPrimary } ? "" : " LIMIT 1"
        let query = "UPDATE \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table)) SET \(Self.backtickQuoted(columnName)) = \(sqlValue) WHERE \(whereClause)\(limit)"

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
                    self.autosizeContentColumns()
                    return
                }

                self.rows[row].values[columnIndex] = updatedValue
                self.rows[row].originalValues[columnIndex] = updatedValue
                self.updateStatus()
                self.updateControls()
                self.tableView.reloadData()
                self.autosizeContentColumns()
                self.cacheCurrentContentState()
            }
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateStatus()
        updateControls()
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        guard let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        saveWidth(for: tableColumn)
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard row >= 0,
              row < rows.count,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].values.count,
              let textCell = cell as? NSTextFieldCell else { return }

        switch rows[row].values[columnIndex] {
        case .null, .notLoaded:
            textCell.textColor = .secondaryLabelColor
        case .object:
            textCell.textColor = .labelColor
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isLoading, !isRestoringCachedContent, let descriptor = tableView.sortDescriptors.first, let key = descriptor.key, let columnIndex = Int(key), columnIndex < columns.count else { return }

        sortColumn = columns[columnIndex]
        sortAscending = descriptor.ascending
        pageIndex = 0
        invalidateCurrentContentCache()
        loadCurrentPage()
    }
}

extension SALightweightContentViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }

        switch action {
        case #selector(removeRow(_:)), #selector(deleteRows(_:)), #selector(deleteBackward(_:)), #selector(deleteForward(_:)):
            menuItem.title = tableView.numberOfSelectedRows > 1
                ? NSLocalizedString("Delete Rows", comment: "delete rows menu item plural")
                : NSLocalizedString("Delete Row", comment: "delete row menu item singular")
            return !isLoading && tableView.numberOfSelectedRows > 0

        case #selector(duplicateRow(_:)):
            return !isLoading && tableView.numberOfSelectedRows == 1

        case #selector(addRow(_:)):
            return !isLoading

        case #selector(reloadContent(_:)):
            return !isLoading

        default:
            return true
        }
    }
}

fileprivate final class LightweightFilterRuleRowView: NSView, NSTextFieldDelegate {
    static let rowHeight: CGFloat = 29

    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let columnPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let operatorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let firstValueField = NSTextField(frame: .zero)
    private let conjunctionLabel = NSTextField(labelWithString: "")
    private let secondValueField = NSTextField(frame: .zero)
    private let addButton = NSButton(image: NSImage(named: NSImage.Name("NSAddTemplate")) ?? NSImage(), target: nil, action: nil)
    private let removeButton = NSButton(image: NSImage(named: NSImage.Name("NSRemoveTemplate")) ?? NSImage(), target: nil, action: nil)

    var ruleID: UUID?
    var onEnabledChanged: ((UUID, Bool) -> Void)?
    var onColumnChanged: ((UUID, String) -> Void)?
    var onOperatorChanged: ((UUID, String) -> Void)?
    var onValuesChanged: ((UUID, [String]) -> Void)?
    var onAdd: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onApply: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        checkbox.toolTip = NSLocalizedString("When unchecked this filter expression will not be applied", comment: "table Content : rule filter editor : row : enable filter expression checkbox : tooltip")
        checkbox.target = self
        checkbox.action = #selector(enabledChanged(_:))

        [columnPopup, operatorPopup].forEach { popup in
            popup.controlSize = .small
            popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            popup.target = self
        }
        columnPopup.action = #selector(columnChanged(_:))
        operatorPopup.action = #selector(operatorChanged(_:))

        [firstValueField, secondValueField].forEach { field in
            field.controlSize = .small
            field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            field.usesSingleLineMode = true
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.delegate = self
            field.target = self
            field.action = #selector(valueAction(_:))
            field.toolTip = NSLocalizedString("Enter the value to apply the filter condition with.\nPress ↩ to apply the filter.", comment: "table content : lightweight filter editor : text input field : tooltip")
        }

        conjunctionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        conjunctionLabel.textColor = .secondaryLabelColor
        conjunctionLabel.alignment = .center

        [addButton, removeButton].forEach { button in
            button.bezelStyle = .smallSquare
            button.imagePosition = .imageOnly
            button.contentTintColor = .labelColor
            button.target = self
        }
        addButton.toolTip = NSLocalizedString("Add filter", comment: "lightweight content add filter row tooltip")
        addButton.action = #selector(addRule(_:))
        removeButton.toolTip = NSLocalizedString("Remove filter", comment: "lightweight content remove filter row tooltip")
        removeButton.action = #selector(removeRule(_:))

        addSubview(checkbox)
        addSubview(columnPopup)
        addSubview(operatorPopup)
        addSubview(firstValueField)
        addSubview(conjunctionLabel)
        addSubview(secondValueField)
        addSubview(removeButton)
        addSubview(addButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        rule: SALightweightContentViewController.FilterRule,
        columnNames: [String],
        operators: [SALightweightContentViewController.ContentFilterDefinition],
        selectedOperator: SALightweightContentViewController.ContentFilterDefinition
    ) {
        ruleID = rule.id
        checkbox.state = rule.isEnabled ? .on : .off

        columnPopup.removeAllItems()
        columnPopup.addItems(withTitles: columnNames)
        columnPopup.selectItem(withTitle: rule.columnName)

        operatorPopup.removeAllItems()
        operatorPopup.addItems(withTitles: operators.map { $0.title })
        operatorPopup.selectItem(withTitle: selectedOperator.title)

        let values = rule.values
        firstValueField.stringValue = values.indices.contains(0) ? values[0] : ""
        secondValueField.stringValue = values.indices.contains(1) ? values[1] : ""

        let numberOfArguments = selectedOperator.numberOfArguments
        firstValueField.isHidden = numberOfArguments == 0
        conjunctionLabel.isHidden = numberOfArguments < 2
        secondValueField.isHidden = numberOfArguments < 2
        conjunctionLabel.stringValue = selectedOperator.conjunctionLabels.first ?? NSLocalizedString("AND", comment: "lightweight content filter conjunction")

        needsLayout = true
    }

    override func layout() {
        super.layout()

        let rowHeight = Self.rowHeight
        let controlHeight: CGFloat = 22
        let y = floor((rowHeight - controlHeight) / 2)
        let buttonSize: CGFloat = 22
        let gap: CGFloat = 5

        checkbox.frame = NSRect(x: 0, y: y + 2, width: 20, height: 18)
        columnPopup.frame = NSRect(x: checkbox.frame.maxX + gap, y: y, width: 260, height: controlHeight)
        operatorPopup.frame = NSRect(x: columnPopup.frame.maxX + gap, y: y, width: 92, height: controlHeight)
        addButton.frame = NSRect(x: bounds.width - buttonSize, y: y, width: buttonSize, height: controlHeight)
        removeButton.frame = NSRect(x: addButton.frame.minX - buttonSize - 3, y: y, width: buttonSize, height: controlHeight)

        let valueX = operatorPopup.frame.maxX + gap
        let valueWidth = max(80, removeButton.frame.minX - valueX - gap)
        if secondValueField.isHidden {
            firstValueField.frame = NSRect(x: valueX, y: y, width: valueWidth, height: controlHeight)
        } else {
            let labelWidth: CGFloat = 34
            let fieldWidth = max(60, floor((valueWidth - labelWidth - gap * 2) / 2))
            firstValueField.frame = NSRect(x: valueX, y: y, width: fieldWidth, height: controlHeight)
            conjunctionLabel.frame = NSRect(x: firstValueField.frame.maxX + gap, y: y + 3, width: labelWidth, height: controlHeight - 4)
            secondValueField.frame = NSRect(x: conjunctionLabel.frame.maxX + gap, y: y, width: fieldWidth, height: controlHeight)
        }
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 760, height: Self.rowHeight)
    }

    func focusValueField() {
        if !firstValueField.isHidden {
            window?.makeFirstResponder(firstValueField)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    @objc private func enabledChanged(_ sender: Any?) {
        guard let ruleID = ruleID else { return }
        onEnabledChanged?(ruleID, checkbox.state == .on)
    }

    @objc private func columnChanged(_ sender: Any?) {
        guard let ruleID = ruleID, let title = columnPopup.selectedItem?.title else { return }
        onColumnChanged?(ruleID, title)
    }

    @objc private func operatorChanged(_ sender: Any?) {
        guard let ruleID = ruleID, let title = operatorPopup.selectedItem?.title else { return }
        onOperatorChanged?(ruleID, title)
    }

    @objc private func valueAction(_ sender: Any?) {
        sendValuesChanged()
        onApply?()
    }

    func controlTextDidChange(_ obj: Notification) {
        sendValuesChanged()
    }

    private func sendValuesChanged() {
        guard let ruleID = ruleID else { return }
        var values: [String] = []
        if !firstValueField.isHidden {
            values.append(firstValueField.stringValue)
        }
        if !secondValueField.isHidden {
            values.append(secondValueField.stringValue)
        }
        onValuesChanged?(ruleID, values)
    }

    @objc private func addRule(_ sender: Any?) {
        guard let ruleID = ruleID else { return }
        onAdd?(ruleID)
    }

    @objc private func removeRule(_ sender: Any?) {
        guard let ruleID = ruleID else { return }
        onRemove?(ruleID)
    }
}
