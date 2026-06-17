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
        let defaultExpression: String?
    }

    fileprivate struct ContentRow {
        var values: [ContentValue]
        var originalValues: [ContentValue]
        var isNew = false
    }

    private struct ContentCacheEntry {
        let columns: [String]
        let columnInfo: [ColumnInfo]
        let rows: [ContentRow]
        let pageIndex: Int
        let pageSize: Int
        let limitResults: Bool
        let tableObjectType: TableObjectType
        let totalRowCount: Int?
        let totalRowCountIsEstimate: Bool
        let hasNextPage: Bool
        let sortColumn: String?
        let sortAscending: Bool
        let isRuleFilterActive: Bool
        let serializedRuleFilter: NSDictionary?
        let columnFilter: String?
    }

    private enum MutationReloadPolicy {
        case reload
        case leaveCurrentRows
        case removeRows(IndexSet)
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

    private struct EditedContentSQLValue {
        let sql: String
        let localValue: ContentValue
        let requiresReload: Bool
    }

    private enum TableObjectType {
        case table
        case view
        case unknown
    }

    private weak var connection: SPMySQLConnection?
    private var database = ""
    private var table = ""
    private var columns: [String] = []
    private var columnInfo: [ColumnInfo] = []
    private var rows: [ContentRow] = []
    private let displayCache = SALightweightResultGridDisplayCache()
    private let columnWidthCache = SALightweightResultGridColumnWidthCache()
    private var filteredColumns: [Int] = []
    private var loadToken = UUID()
    private var pageIndex = 0
    private var totalRowCount: Int?
    private var totalRowCountIsEstimate = false
    private var hasNextPage = false
    private var isLoading = false
    private var isLoadingSortPreservingColumns = false
    private var sortColumn: String?
    private var sortAscending = true
    private var didRegisterPreferenceObservers = false
    private var isApplyingProgrammaticColumnWidths = false
    private let autosizeCoordinator = SALightweightResultGridAutosizeCoordinator()
    private var displayedColumnSignature: [String] = []
    private var isRuleFilterVisible = UserDefaults.standard.bool(forKey: SPRuleFilterEditorLastVisibilityChoice)
    private var isRuleFilterActive = false
    private var advancedFilterWhereClause: String?
    private var isAdvancedFilterDistinct = false
    private var columnFilterTerms: [String]?
    private var tableObjectType: TableObjectType = .unknown
    private var ruleFilterColumnsKey = ""
    private var filterRules: [FilterRule] = []
    private var defaultContentFilters: [String: [ContentFilterDefinition]] = [:]
    var sessionState = SALightweightSessionState()
    private var currentTableKey: SALightweightSessionState.TableKey?
    private var contentCache: [SALightweightSessionState.TableKey: ContentCacheEntry] = [:]
    private var contentCacheOrder: [SALightweightSessionState.TableKey] = []
    private var columnInfoCache: [SALightweightSessionState.TableKey: [ColumnInfo]] = [:]
    private let maximumContentCacheEntries = 6
    private let initialRowLoadPublishSize = 200
    private let remainingRowLoadPublishSize = 1_000
    private var ruleFilterHeightConstraint: NSLayoutConstraint?
    private var isRestoringCachedContent = false
    private lazy var fieldEditor = SPFieldEditorController()
    private var fieldEditorTextSelectedRange = NSRange(location: 0, length: 0)
    private var isFieldEditorPresented = false
    private var deferredFieldEditorRequestID = 0
    private lazy var paginationViewController = SALightweightContentPaginationViewController()
    private lazy var paginationPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = paginationViewController
        return popover
    }()
    var sessionStateDidChange: (() -> Void)?
    var tableContentDidChange: (() -> Void)?
    private var limitResults: Bool {
        UserDefaults.standard.bool(forKey: SPLimitResults)
    }

    private var pageSize: Int {
        let preferredPageSize = UserDefaults.standard.integer(forKey: SPLimitResultsValue)
        return max(1, preferredPageSize > 0 ? preferredPageSize : 1_000)
    }

    private var maximumPage: Int {
        if let totalRowCount = totalRowCount {
            return max(1, Int(ceil(Double(totalRowCount) / Double(pageSize))))
        }

        return max(1, pageIndex + (hasNextPage ? 2 : 1))
    }

    private func prewarmFieldEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, self.isViewLoaded else { return }
            _ = self.fieldEditor
        }
    }

    private var canModifyRows: Bool {
        tableObjectType == .table && !isLoading
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
    private lazy var editModeButton: NSButton = {
        let button = toolbarButton(imageName: "button_edit_modeTemplate", toolTip: NSLocalizedString("Toggle between editing simple text cells as a spreadsheet or in pop-up sheets", comment: "edit content mode tooltip"), action: #selector(toggleEditMode(_:)))
        button.alternateImage = NSImage(named: NSImage.Name("button_edit_mode_selectedTemplate"))
        button.setButtonType(.pushOnPushOff)
        return button
    }()
    private lazy var toggleRuleFilterButton: NSButton = {
        let button = toolbarButton(imageName: "button_filterTemplate", toolTip: NSLocalizedString("Show/Hide table content filters", comment: "table content filter toggle tooltip"), action: #selector(toggleRuleFilterVisible(_:)))
        button.alternateImage = NSImage(named: NSImage.Name("button_filter_activeTemplate"))
        button.setButtonType(.pushOnPushOff)
        return button
    }()
    private lazy var previousPageButton = toolbarButton(imageName: "NSLeftFacingTriangleTemplate",
                                                        toolTip: NSLocalizedString("View previous page of results", comment: "previous page tooltip"),
                                                        keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                                                        modifierMask: [.command, .shift],
                                                        action: #selector(loadPreviousPage(_:)))
    private lazy var paginationButton = toolbarButton(imageName: "NSActionTemplate", toolTip: NSLocalizedString("Jump to page (⌘J) or view pagination options", comment: "pagination options tooltip"), keyEquivalent: "j", modifierMask: .command, action: #selector(togglePagination(_:)))
    private lazy var nextPageButton = toolbarButton(imageName: "NSRightFacingTriangleTemplate",
                                                    toolTip: NSLocalizedString("View next page of results", comment: "next page tooltip"),
                                                    keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!),
                                                    modifierMask: [.command, .shift],
                                                    action: #selector(loadNextPage(_:)))

    private lazy var pageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    private lazy var columnFilterSearchField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = NSLocalizedString("Filter Columns", comment: "table content column filter placeholder")
        field.target = self
        field.action = #selector(columnFilterChanged(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return field
    }()

    private lazy var tableView: NSTableView = {
        let tableView = SALightweightResultGridTableView(frame: .zero)
        tableView.resultGridDelegate = self
        tableView.identifier = NSUserInterfaceItemIdentifier("TableContentTableView")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsExpansionToolTips = false
        SALightweightResultGrid.configureTableView(tableView, rowHeight: SALightweightResultGrid.rowHeight(for: UserDefaults.getFont()), columnAutoresizingStyle: .noColumnAutoresizing)
        tableView.style = .plain
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
        columnInfoCache.removeAll()
        displayCache.invalidateAll()
        columnWidthCache.invalidateAll()
    }

    func cacheColumnInfo(fromStructureRows structureRows: [[String: String]], for table: String, database: String, connection: SPMySQLConnection) {
        guard let tableKey = SALightweightSessionState.tableKey(database: database, table: table, connection: connection),
              !structureRows.isEmpty else { return }

        columnInfoCache[tableKey] = structureRows.compactMap { structureRow in
            guard let name = structureRow["name"], !name.isEmpty else { return nil }

            let rawType = Self.rawColumnType(fromStructureRow: structureRow)
            let parsedType = Self.parseColumnType(rawType)
            let key = (structureRow["Key"] ?? "").uppercased()
            let extra = (structureRow["Extra"] ?? "").lowercased()
            let defaultExpression = Self.defaultExpression(from: structureRow["default"])
            return ColumnInfo(
                name: name,
                type: parsedType.type,
                typeGrouping: parsedType.typeGrouping,
                length: parsedType.length,
                values: parsedType.values,
                comment: structureRow["comment"] ?? "",
                isNullable: structureRow["null"] == "1",
                isPrimary: key == "PRI",
                isAutoIncrement: extra.contains("auto_increment"),
                defaultExpression: defaultExpression
            )
        }
    }

    func saveCurrentSessionState() {
        cacheCurrentContentState()
        storeCurrentRuleFilterState()
    }

    override func loadView() {
        let rootView = NSView(frame: .zero)

        let scrollView = NSScrollView(frame: .zero)
        SALightweightResultGrid.configureResultScrollView(scrollView)
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(resultGridBoundsDidChange(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(resultGridWillStartLiveScroll(_:)), name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(resultGridDidEndLiveScroll(_:)), name: NSScrollView.didEndLiveScrollNotification, object: scrollView)

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
        toolbarView.addSubview(toggleRuleFilterButton)
        toolbarView.addSubview(columnFilterSearchField)
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
        toggleRuleFilterButton.translatesAutoresizingMaskIntoConstraints = false
        columnFilterSearchField.translatesAutoresizingMaskIntoConstraints = false
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

            toggleRuleFilterButton.leadingAnchor.constraint(equalTo: editModeButton.trailingAnchor, constant: 5),
            toggleRuleFilterButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            toggleRuleFilterButton.widthAnchor.constraint(equalToConstant: 25),
            toggleRuleFilterButton.heightAnchor.constraint(equalToConstant: 23),

            columnFilterSearchField.leadingAnchor.constraint(equalTo: toggleRuleFilterButton.trailingAnchor, constant: 5),
            columnFilterSearchField.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            columnFilterSearchField.widthAnchor.constraint(equalToConstant: 150),
            columnFilterSearchField.heightAnchor.constraint(equalToConstant: 22),

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

            statusLabel.leadingAnchor.constraint(equalTo: columnFilterSearchField.trailingAnchor, constant: 8),
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
        configureContentContextMenu()
        paginationViewController.onGo = { [weak self] page in
            self?.navigateToPage(page)
        }
        updateRuleFilterVisibility(animated: false)
        prewarmFieldEditor()
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        updateFilterRowsFrame()
    }

    deinit {
        autosizeCoordinator.cancel()
        NotificationCenter.default.removeObserver(self)
        if didRegisterPreferenceObservers {
            UserDefaults.standard.removeObserver(self, forKeyPath: SPDisplayTableViewVerticalGridlines)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPDisplayTableViewColumnTypes)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPGlobalFontSettings)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPDisplayBinaryDataAsHex)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPNullValue)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPLoadBlobsAsNeeded)
            UserDefaults.standard.removeObserver(self, forKeyPath: SPEditInSheetEnabled)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        switch keyPath {
        case SPDisplayTableViewVerticalGridlines:
            tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
            tableView.setNeedsDisplay(tableView.visibleRect)
        case SPGlobalFontSettings:
            applyTablePreferences(rebuildColumns: UserDefaults.standard.bool(forKey: SPDisplayTableViewColumnTypes), rebuildDisplayValues: false)
        case SPDisplayTableViewColumnTypes:
            rebuildColumns()
        case SPDisplayBinaryDataAsHex, SPNullValue:
            rebuildDisplayValues()
            SALightweightResultGrid.reloadVisibleCells(in: tableView, columnBuffer: SALightweightResultGrid.autosizeColumnBuffer)
            autosizeContentColumns()
            cacheCurrentContentState()
        case SPLoadBlobsAsNeeded:
            contentCache.removeAll()
            contentCacheOrder.removeAll()
            loadCurrentPage()
        case SPEditInSheetEnabled:
            updateControls()
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func loadContent(for table: String, database: String, connection: SPMySQLConnection) {
        let tableKey = SALightweightSessionState.tableKey(database: database, table: table, connection: connection)
        let tableChanged = currentTableKey != tableKey
        cacheCurrentContentState()
        storeCurrentRuleFilterState()

        self.table = table
        self.database = database
        self.connection = connection
        currentTableKey = tableKey
        loadToken = UUID()
        let restoredContentState = tableKey.flatMap { sessionState.contentState(for: $0) }
        isRuleFilterActive = restoredContentState?.isRuleFilterActive ?? false
        tableObjectType = .unknown
        ruleFilterColumnsKey = ""
        filterRules = []
        if tableChanged {
            advancedFilterWhereClause = nil
            isAdvancedFilterDistinct = false
        }
        restoreColumnFilter(restoredContentState?.columnFilter)

        if let tableKey = tableKey, restoreCachedContent(for: tableKey) {
            return
        }

        pageIndex = restoredContentState?.pageIndex ?? 0
        sortColumn = restoredContentState?.sortColumn
        sortAscending = restoredContentState?.sortAscending ?? true
        applySortDescriptorsFromCurrentState()

        loadCurrentPage()
    }

    func legacyFilterColumns() -> NSArray {
        return columnInfo.enumerated().map { index, column -> NSDictionary in
            let definition = NSMutableDictionary(dictionary: column.legacyDefinition)
            definition["datacolumnindex"] = "\(index)"
            return definition
        } as NSArray
    }

    func applyAdvancedFilter(whereClause: String?, distinct: Bool) {
        let trimmedFilter = whereClause?.trimmingCharacters(in: .whitespacesAndNewlines)
        advancedFilterWhereClause = trimmedFilter?.isEmpty == false ? trimmedFilter : nil
        isAdvancedFilterDistinct = distinct
        isRuleFilterActive = false
        pageIndex = 0
        invalidateCurrentContentCache()
        loadCurrentPage()
    }
}

private final class SALightweightContentPaginationViewController: NSViewController {
    var onGo: ((Int) -> Void)?

    var page: Int {
        get { pageField.integerValue }
        set {
            pageField.integerValue = max(1, newValue)
            pageStepper.integerValue = pageField.integerValue
        }
    }

    var maxPage: Int = 1 {
        didSet {
            let boundedMaxPage = max(1, maxPage)
            pageStepper.maxValue = Double(boundedMaxPage)
            pageField.placeholderString = String(format: NSLocalizedString("1 - %ld", comment: "pagination page range placeholder"), boundedMaxPage)
        }
    }

    private let pageField = NSTextField(frame: NSRect(x: 12, y: 12, width: 72, height: 22))
    private let pageStepper = NSStepper(frame: NSRect(x: 86, y: 9, width: 19, height: 27))
    private let goButton = NSButton(frame: NSRect(x: 112, y: 9, width: 52, height: 28))

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 176, height: 46))
        view = rootView

        pageField.controlSize = .small
        pageField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        pageField.alignment = .right
        pageField.target = self
        pageField.action = #selector(go(_:))
        rootView.addSubview(pageField)

        pageStepper.minValue = 1
        pageStepper.increment = 1
        pageStepper.target = self
        pageStepper.action = #selector(stepperChanged(_:))
        rootView.addSubview(pageStepper)

        goButton.title = NSLocalizedString("Go", comment: "pagination go button")
        goButton.bezelStyle = .rounded
        goButton.controlSize = .small
        goButton.target = self
        goButton.action = #selector(go(_:))
        rootView.addSubview(goButton)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(pageField)
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        pageField.integerValue = sender.integerValue
        go(sender)
    }

    @objc private func go(_ sender: Any) {
        let boundedPage = min(max(1, pageField.integerValue), max(1, maxPage))
        page = boundedPage
        onGo?(boundedPage)
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
    func loadCurrentPage(preservingColumns: Bool = false) {
        guard connection != nil else { return }

        cancelActiveContentEditBeforeReload()

        loadToken = UUID()
        let token = loadToken
        let pageSize = self.pageSize
        let limitResults = self.limitResults
        let offset = limitResults ? pageIndex * pageSize : 0
        let filter = ruleFilterStringForCurrentState(showError: true)
        guard !filter.failed else { return }
        let tableKey = currentTableKey
        let cachedColumnInfo = tableKey.flatMap { columnInfoCache[$0] }

        invalidateCurrentContentCache()
        loadCurrentPage(whereClause: filter.whereClause, token: token, pageSize: pageSize, offset: offset, limitResults: limitResults, tableKey: tableKey, cachedColumnInfo: cachedColumnInfo, preservingColumns: preservingColumns)
    }

    private func loadCurrentPage(whereClause: String?, token: UUID, pageSize: Int, offset: Int, limitResults: Bool, tableKey: SALightweightSessionState.TableKey?, cachedColumnInfo: [ColumnInfo]?, preservingColumns: Bool) {
        guard let connection = connection else { return }

        isLoading = true
        isLoadingSortPreservingColumns = preservingColumns
        rows = []
        displayCache.invalidateAll()
        if !preservingColumns {
            columns = []
            columnInfo = []
            columnWidthCache.invalidateAll()
            filteredColumns = []
            tableObjectType = .unknown
            rebuildColumns()
        } else {
            tableView.noteNumberOfRowsChanged()
            applySortDescriptorsFromCurrentState()
        }
        totalRowCount = nil
        totalRowCountIsEstimate = false
        hasNextPage = false
        statusLabel.stringValue = NSLocalizedString("Loading rows...", comment: "lightweight content loading rows")
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            _ = connection.selectDatabase(self.database)
            let tableObjectType = self.loadTableObjectType(connection: connection)
            let columnInfo = cachedColumnInfo ?? self.loadColumnInfo(connection: connection)
            if cachedColumnInfo == nil, let tableKey = tableKey, !columnInfo.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.loadToken == token else { return }
                    self.columnInfoCache[tableKey] = columnInfo
                }
            }
            let shouldLoadFirstBatch = limitResults && pageSize > self.initialRowLoadPublishSize
            let firstLimit = shouldLoadFirstBatch ? self.initialRowLoadPublishSize : pageSize + 1
            let firstQuery = self.contentQuery(offset: offset, limit: firstLimit, whereClause: whereClause, columnInfo: columnInfo, limitResults: limitResults)
            let result = connection.streamingQueryString(firstQuery)
            result?.defaultRowReturnType = SPMySQLResultRowAsArray

            let fieldNames = result?.fieldNames() as? [String] ?? []
            let orderedColumnInfo = Self.orderedColumnInfo(columnInfo, fieldNames: fieldNames)
            var pendingRows: [ContentRow] = []
            var loadedRowCount = 0
            var hasNextPage = false

            self.publishInitialContentLoad(
                token: token,
                fieldNames: fieldNames,
                columnInfo: orderedColumnInfo,
                tableObjectType: tableObjectType,
                rowCount: nil,
                limitResults: limitResults,
                preservingColumns: preservingColumns
            )

            while let row = result?.getRowAsArray() {
                loadedRowCount += 1
                if limitResults, loadedRowCount > pageSize {
                    hasNextPage = true
                    continue
                }

                let values = row.enumerated().map { index, value -> ContentValue in
                    if index < columnInfo.count, columnInfo[index].loadBlobAsNeeded {
                        return .notLoaded
                    }

                    return Self.contentValue(for: value)
                }
                pendingRows.append(ContentRow(values: values, originalValues: values))

                if pendingRows.count >= self.initialRowLoadPublishSize {
                    self.publishContentRows(pendingRows, token: token, final: false, hasNextPage: false)
                    pendingRows.removeAll(keepingCapacity: true)
                }
            }

            if !pendingRows.isEmpty {
                self.publishContentRows(pendingRows, token: token, final: false, hasNextPage: false)
                pendingRows.removeAll(keepingCapacity: true)
            }

            var error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            if error == nil, shouldLoadFirstBatch, loadedRowCount >= firstLimit {
                let remainingLimit = pageSize - loadedRowCount + 1
                let remainingOffset = offset + loadedRowCount
                let remainingQuery = self.contentQuery(offset: remainingOffset, limit: remainingLimit, whereClause: whereClause, columnInfo: columnInfo, limitResults: limitResults)
                let remainingResult = connection.streamingQueryString(remainingQuery)
                remainingResult?.defaultRowReturnType = SPMySQLResultRowAsArray

                while let row = remainingResult?.getRowAsArray() {
                    loadedRowCount += 1
                    if loadedRowCount > pageSize {
                        hasNextPage = true
                        continue
                    }

                    let values = row.enumerated().map { index, value -> ContentValue in
                        if index < columnInfo.count, columnInfo[index].loadBlobAsNeeded {
                            return .notLoaded
                        }

                        return Self.contentValue(for: value)
                    }
                    pendingRows.append(ContentRow(values: values, originalValues: values))

                    if pendingRows.count >= self.remainingRowLoadPublishSize {
                        self.publishContentRows(pendingRows, token: token, final: false, hasNextPage: false)
                        pendingRows.removeAll(keepingCapacity: true)
                    }
                }

                error = connection.queryErrored() ? connection.lastErrorMessage() : nil
            }

            let rowCount = limitResults ? self.rowCount(whereClause: whereClause, connection: connection) : nil

            DispatchQueue.main.async {
                guard self.loadToken == token else {
                    return
                }

                self.isLoading = false

                if let error = error, !error.isEmpty {
                    self.isLoadingSortPreservingColumns = false
                    self.columns = []
                    self.columnInfo = []
                    self.rows = []
                    self.displayCache.invalidateAll()
                    self.columnWidthCache.invalidateAll()
                    self.filteredColumns = []
                    self.totalRowCount = nil
                    self.totalRowCountIsEstimate = false
                    self.hasNextPage = false
                    self.rebuildColumns()
                    self.statusLabel.stringValue = error
                    self.updateControls()
                    return
                }

                self.appendContentRows(pendingRows, autosizeColumns: self.rows.count < self.initialRowLoadPublishSize)
                self.totalRowCount = rowCount?.count ?? (limitResults ? nil : self.rows.count)
                self.hasNextPage = hasNextPage
                self.finalizeContentLoad()
            }
        }
    }

    private func publishInitialContentLoad(token: UUID,
                                           fieldNames: [String],
                                           columnInfo: [ColumnInfo],
                                           tableObjectType: TableObjectType,
                                           rowCount: (count: Int, isEstimate: Bool)?,
                                           limitResults: Bool,
                                           preservingColumns: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.loadToken == token else {
                return
            }

            let canPreserveColumns = preservingColumns && fieldNames == self.columns
            self.columns = fieldNames
            self.columnInfo = columnInfo
            self.rows = []
            self.displayCache.invalidateAll()
            if !canPreserveColumns {
                self.columnWidthCache.invalidateAll()
            }
            self.tableObjectType = tableObjectType
            self.totalRowCount = rowCount?.count
            self.totalRowCountIsEstimate = limitResults ? (rowCount?.isEstimate ?? false) : false
            self.hasNextPage = false
            self.configureRuleFilterColumnsIfNeeded()
            self.applyColumnFilter()
            if canPreserveColumns {
                self.tableView.noteNumberOfRowsChanged()
            } else {
                self.rebuildColumns()
            }
            self.applySortDescriptorsFromCurrentState()
            self.updateStatus()
            self.updateControls()
        }
    }

    private func publishContentRows(_ rows: [ContentRow], token: UUID, final: Bool, hasNextPage: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.loadToken == token else {
                return
            }

            self.appendContentRows(rows, autosizeColumns: self.rows.isEmpty && !self.isLoadingSortPreservingColumns)

            if final {
                self.hasNextPage = hasNextPage
                self.finalizeContentLoad()
            }
        }
    }

    private func appendContentRows(_ newRows: [ContentRow], autosizeColumns shouldAutosizeColumns: Bool) {
        let benchmarkStart = CFAbsoluteTimeGetCurrent()
        defer {
            SALightweightResultGrid.logPerformance("Content append rows", start: benchmarkStart, details: "newRows=\(newRows.count) totalRows=\(rows.count) columns=\(filteredColumns.count)", minimumMilliseconds: 4)
        }

        guard !newRows.isEmpty else { return }

        rows.append(contentsOf: newRows)
        tableView.noteNumberOfRowsChanged()
        updateStatus()

        if shouldAutosizeColumns {
            scheduleVisibleColumnAutosize(delay: 0.01)
        }
    }

    private func finalizeContentLoad() {
        isLoadingSortPreservingColumns = false
        if totalRowCount == nil, !limitResults {
            totalRowCount = rows.count
        }

        isLoading = false
        updateStatus()
        updateControls()
        cacheCurrentContentState()
        prewarmFieldEditor()
    }

    private func contentQuery(offset: Int, limit: Int, whereClause: String?, columnInfo: [ColumnInfo], limitResults: Bool) -> String {
        let fields = columnInfo.isEmpty ? "*" : columnInfo.map { column -> String in
            if column.loadBlobAsNeeded {
                return "NULL AS \(Self.backtickQuoted(column.name))"
            }

            return Self.backtickQuoted(column.name)
        }.joined(separator: ", ")

        var query = "SELECT \(isAdvancedFilterDistinct ? "DISTINCT " : "")\(fields) FROM \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table))"

        if let whereClause = whereClause {
            query += " WHERE \(whereClause)"
        }

        if let sortColumn = sortColumn {
            query += " ORDER BY \(Self.backtickQuoted(sortColumn)) \(sortAscending ? "ASC" : "DESC")"
        }

        if limitResults {
            query += " LIMIT \(offset),\(limit)"
        }
        return query
    }

    private func loadTableObjectType(connection: SPMySQLConnection) -> TableObjectType {
        guard let quotedTable = connection.escapeAndQuoteString(table) else { return .unknown }

        let result = connection.queryString("SHOW FULL TABLES FROM \(Self.backtickQuoted(database)) LIKE \(quotedTable)")
        result?.returnDataAsStrings = true
        result?.defaultRowReturnType = SPMySQLResultRowAsDictionary

        guard let row = result?.getRowAsDictionary() as? [String: Any] else { return .unknown }
        let tableType = row.first { key, _ in
            String(describing: key).lowercased().contains("table_type")
        }.map { Self.displayString(for: $0.value).uppercased() } ?? ""

        if tableType.contains("VIEW") {
            return .view
        }

        return tableType.isEmpty ? .unknown : .table
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
            let defaultExpression = Self.defaultExpression(from: row["Default"])
            loadedColumns.append(ColumnInfo(
                name: name,
                type: parsedType.type,
                typeGrouping: parsedType.typeGrouping,
                length: parsedType.length,
                values: parsedType.values,
                comment: Self.displayString(for: row["Comment"]),
                isNullable: Self.displayString(for: row["Null"]).uppercased() == "YES",
                isPrimary: key == "PRI",
                isAutoIncrement: extra.contains("auto_increment"),
                defaultExpression: defaultExpression
            ))
        }

        return loadedColumns
    }

    private static func defaultExpression(from value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }

        let trimmed = displayString(for: value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let uppercased = trimmed.uppercased()
        let nullValue = UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        guard uppercased != "NULL", trimmed != nullValue else { return nil }

        if SALightweightResultGrid.currentTimestampSQLExpression(from: trimmed) != nil {
            return trimmed
        }

        if uppercased == "CURRENT_DATE" || uppercased == "CURRENT_TIME" {
            return trimmed
        }

        if trimmed.hasPrefix("'") || trimmed.hasPrefix("\"") {
            return nil
        }

        if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) || trimmed.hasSuffix(")") {
            return trimmed
        }

        return nil
    }

    private static func orderedColumnInfo(_ columnInfo: [ColumnInfo], fieldNames: [String]) -> [ColumnInfo] {
        return fieldNames.map { fieldName in
            columnInfo.first { $0.name == fieldName } ?? ColumnInfo(name: fieldName, type: "", typeGrouping: "", length: "", values: [], comment: "", isNullable: false, isPrimary: false, isAutoIncrement: false, defaultExpression: nil)
        }
    }

    @objc func applyRuleFilter(_ sender: Any?) {
        isRuleFilterActive = sender != nil
        storeCurrentRuleFilterState()
        sessionStateDidChange?()

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

    @objc func toggleEditMode(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: SPEditInSheetEnabled)
    }

    @objc func reloadContent(_ sender: Any?) {
        cancelActiveContentEditBeforeReload()
        invalidateCurrentContentCache()
        loadCurrentPage()
    }

    @objc func togglePagination(_ sender: NSButton) {
        guard limitResults, !isLoading else { return }

        if paginationPopover.isShown {
            paginationPopover.close()
            paginationButton.state = .off
            return
        }

        paginationViewController.page = pageIndex + 1
        paginationViewController.maxPage = maximumPage
        paginationPopover.show(relativeTo: paginationButton.bounds, of: paginationButton, preferredEdge: .minY)
        paginationButton.state = .on
    }

    @objc func toggleRuleFilterVisible(_ sender: NSButton) {
        setRuleFilterVisible(sender.state == .on, animate: true)
    }

    @objc func columnFilterChanged(_ sender: NSSearchField) {
        let terms = sender.stringValue
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let nextTerms = terms.isEmpty ? nil : terms

        guard columnFilterTerms != nextTerms else { return }

        columnFilterTerms = nextTerms
        storeCurrentRuleFilterState()
        sessionStateDidChange?()
        applyColumnFilter()
        rebuildColumns()
    }

    @objc func loadPreviousPage(_ sender: Any?) {
        guard pageIndex > 0, !isLoading else { return }

        pageIndex -= 1
        storeCurrentRuleFilterState()
        sessionStateDidChange?()
        loadCurrentPage()
    }

    @objc func loadNextPage(_ sender: Any?) {
        guard hasNextPage, !isLoading else { return }

        pageIndex += 1
        storeCurrentRuleFilterState()
        sessionStateDidChange?()
        loadCurrentPage()
    }

    func navigateToPage(_ page: Int) {
        guard limitResults, !isLoading else { return }

        let boundedPage = min(max(1, page), maximumPage)
        guard boundedPage != pageIndex + 1 else { return }

        pageIndex = boundedPage - 1
        storeCurrentRuleFilterState()
        sessionStateDidChange?()
        loadCurrentPage()
    }

    @objc func addRow(_ sender: Any?) {
        guard connection != nil, canModifyRows else { return }

        if let pendingNewRowIndex = rows.firstIndex(where: { $0.isNew }) {
            tableView.selectRowIndexes(IndexSet(integer: pendingNewRowIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(pendingNewRowIndex)
            tableView.editColumn(firstEditableContentColumnIndex(), row: pendingNewRowIndex, with: nil, select: true)
            return
        }

        let values = columnInfo.map(Self.defaultNewRowValue(for:))
        let newRow = ContentRow(values: values, originalValues: values, isNew: true)
        rows.append(newRow)
        tableView.reloadData()
        let rowIndex = rows.count - 1
        tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(rowIndex)
        tableView.editColumn(firstEditableContentColumnIndex(), row: rowIndex, with: nil, select: true)
        updateStatus()
        updateControls()
    }

    @objc func duplicateRow(_ sender: Any?) {
        guard let connection = connection, canModifyRows else { return }

        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < rows.count else { return }

        let row = rows[selectedRow]
        let columnsToInsert = columnInfo.enumerated().filter { !$0.element.isAutoIncrement && row.values[$0.offset].isLoaded }
        guard !columnsToInsert.isEmpty else {
            addRow(sender)
            return
        }

        let columnList = columnsToInsert.map { Self.backtickQuoted($0.element.name) }.joined(separator: ", ")
        let valueList = columnsToInsert.compactMap { Self.sqlValue(row.values[$0.offset], columnInfo: $0.element, connection: connection) }.joined(separator: ", ")
        let query = "INSERT INTO \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table)) (\(columnList)) VALUES (\(valueList))"
        guard confirmQueryWarningIfNeeded(query) else { return }

        let reloadPolicy: MutationReloadPolicy = UserDefaults.standard.bool(forKey: SPReloadAfterAddingRow) ? .reload : .leaveCurrentRows
        runMutation(status: NSLocalizedString("Duplicating row...", comment: "lightweight content duplicating row"), reloadPolicy: reloadPolicy) { connection in
            _ = connection.queryString(query)
        }
    }

    @objc func deleteRows(_ sender: Any?) {
        guard connection != nil, canModifyRows else { return }

        let selectedIndexes = tableView.selectedRowIndexes
        guard !selectedIndexes.isEmpty else { return }
        if selectedIndexes.count == 1,
           let selectedRow = selectedIndexes.first,
           selectedRow >= 0,
           selectedRow < rows.count,
           rows[selectedRow].isNew {
            cancelNewContentRow(selectedRow)
            return
        }

        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.alertStyle = .critical
        alert.messageText = selectedIndexes.count == 1
            ? NSLocalizedString("Delete selected row?", comment: "delete selected row message")
            : NSLocalizedString("Delete rows?", comment: "delete rows message")
        alert.informativeText = selectedIndexes.count == 1
            ? NSLocalizedString("Are you sure you want to delete the selected row from this table? This action cannot be undone.", comment: "delete selected row informative message")
            : String(format: NSLocalizedString("Are you sure you want to delete the selected %ld rows from this table? This action cannot be undone.", comment: "delete rows informative message"), selectedIndexes.count)
        alert.addButton(withTitle: selectedIndexes.count == 1
            ? NSLocalizedString("Delete Selected Row", comment: "delete selected row button")
            : NSLocalizedString("Delete Selected Rows", comment: "delete selected rows button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn else { return }

        if UserDefaults.standard.bool(forKey: SPQueryWarningEnabled),
           UserDefaults.standard.bool(forKey: SPShowWarningBeforeDeleteQuery) {
            let doubleCheckAlert = NSAlert()
            doubleCheckAlert.window.animationBehavior = .none
            doubleCheckAlert.messageText = NSLocalizedString("Double Check", comment: "Double Check")
            doubleCheckAlert.informativeText = NSLocalizedString("Double checking as you have 'Show warning before executing a query' set in Preferences", comment: "Double check delete query")
            doubleCheckAlert.addButton(withTitle: NSLocalizedString("Proceed", comment: "Proceed"))
            doubleCheckAlert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
            doubleCheckAlert.showsSuppressionButton = true
            doubleCheckAlert.suppressionButton?.title = NSLocalizedString("Do not show this message again", comment: "delete rows suppression button")

            guard doubleCheckAlert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn else { return }

            if doubleCheckAlert.suppressionButton?.state == .on {
                UserDefaults.standard.set(false, forKey: SPShowWarningBeforeDeleteQuery)
            }
        }

        let rowsToDelete = selectedIndexes.compactMap { index in index < rows.count ? rows[index] : nil }
        let reloadPolicy: MutationReloadPolicy = UserDefaults.standard.bool(forKey: SPReloadAfterRemovingRow) ? .reload : .removeRows(selectedIndexes)
        runMutation(status: NSLocalizedString("Deleting rows...", comment: "lightweight content deleting rows"), reloadPolicy: reloadPolicy) { [database, table, columnInfo] connection in
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

    @objc func copySelectedContentRows(_ sender: Any?) {
        let includeHeaders = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyWithColumnsTag
        guard let copyString = contentRowsAsTabString(includeHeaders: includeHeaders, rowIndexes: tableView.selectedRowIndexes) else {
            NSSound.beep()
            return
        }

        SALightweightResultGrid.copyStringToPasteboard(copyString)
    }

    @objc func copySelectedContentRowsAsSQL(_ sender: Any?) {
        let skipAutoIncrement = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLNoAutoIncTag
        guard let copyString = contentRowsAsSQLInserts(rowIndexes: tableView.selectedRowIndexes, skipAutoIncrement: skipAutoIncrement) else {
            NSSound.beep()
            return
        }

        SALightweightResultGrid.copySQLStringToPasteboard(copyString)
    }

    @objc func exportContentResultAsCSV(_ sender: Any?) {
        exportContentResult(fileExtension: "csv", content: csvStringForCurrentContent())
    }

    @objc func exportContentResultAsXML(_ sender: Any?) {
        exportContentResult(fileExtension: "xml", content: xmlStringForCurrentContent())
    }

    func configureContentContextMenu() {
        let menu = SALightweightResultGrid.contextMenu(target: self,
                                                       copyAction: #selector(copySelectedContentRows(_:)),
                                                       copySQLAction: #selector(copySelectedContentRowsAsSQL(_:)),
                                                       exportCSVAction: #selector(exportContentResultAsCSV(_:)),
                                                       exportXMLAction: #selector(exportContentResultAsXML(_:)),
                                                       copyCommentPrefix: "content",
                                                       exportCommentPrefix: "content")
        menu.addItem(.separator())

        let addRowItem = NSMenuItem(title: NSLocalizedString("Add New Row", comment: "content context add row menu item"),
                                    action: #selector(addRow(_:)),
                                    keyEquivalent: "")
        addRowItem.target = self
        menu.addItem(addRowItem)

        let duplicateRowItem = NSMenuItem(title: NSLocalizedString("Duplicate Row", comment: "content context duplicate row menu item"),
                                          action: #selector(duplicateRow(_:)),
                                          keyEquivalent: "")
        duplicateRowItem.target = self
        menu.addItem(duplicateRowItem)

        let deleteRowItem = NSMenuItem(title: NSLocalizedString("Delete Row", comment: "content context delete row menu item"),
                                       action: #selector(removeRow(_:)),
                                       keyEquivalent: "")
        deleteRowItem.target = self
        menu.addItem(deleteRowItem)

        tableView.menu = menu
    }

    func prepareContentContextMenu(for event: NSEvent) {
        SALightweightResultGrid.selectContextRow(in: tableView, event: event)
        updateStatus()
    }

    func exportContentResult(fileExtension: String, content: String) {
        guard !rows.isEmpty else {
            NSSound.beep()
            return
        }

        SALightweightResultGrid.exportResult(fileExtension: fileExtension, content: content, defaultName: "\(table).\(fileExtension)")
    }

    private func runMutation(status: String, reloadPolicy: MutationReloadPolicy = .reload, mutation: @escaping (SPMySQLConnection) -> Void) {
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

                self.finishSuccessfulMutation(reloadPolicy: reloadPolicy)
            }
        }
    }

    private func finishSuccessfulMutation(reloadPolicy: MutationReloadPolicy) {
        invalidateCurrentContentCache()
        tableContentDidChange?()

        switch reloadPolicy {
        case .reload:
            loadCurrentPage()
        case .leaveCurrentRows:
            statusLabel.stringValue = NSLocalizedString("Rows changed. Reload to view the latest data.", comment: "lightweight content mutation no reload status")
            updateControls()
        case .removeRows(let rowIndexes):
            removeRowsLocally(rowIndexes)
            statusLabel.stringValue = NSLocalizedString("Rows deleted.", comment: "lightweight content rows deleted status")
            updateControls()
        }
    }

    private func removeRowsLocally(_ rowIndexes: IndexSet) {
        let validIndexes = rowIndexes.filter { $0 >= 0 && $0 < rows.count }
        guard !validIndexes.isEmpty else { return }

        for index in validIndexes.sorted(by: >) {
            rows.remove(at: index)
        }

        if let totalRowCount = totalRowCount {
            self.totalRowCount = max(0, totalRowCount - validIndexes.count)
        }

        displayCache.invalidateAll()
        columnWidthCache.invalidateAll()
        tableView.reloadData()
        tableView.noteNumberOfRowsChanged()
    }

    func applyColumnFilter() {
        guard let columnFilterTerms = columnFilterTerms, !columnFilterTerms.isEmpty else {
            filteredColumns = Array(columns.indices)
            return
        }

        filteredColumns = columns.indices.filter { columnIndex in
            let columnName = columns[columnIndex].lowercased()
            return columnFilterTerms.contains { columnName.contains($0) }
        }
    }

    func rebuildColumns() {
        let benchmarkStart = CFAbsoluteTimeGetCurrent()
        defer {
            SALightweightResultGrid.logPerformance("Content rebuild columns", start: benchmarkStart, details: "columns=\(filteredColumns.count) rows=\(rows.count) table=\(table)", minimumMilliseconds: 4)
        }

        let tableFont = UserDefaults.getFont()
        let showColumnTypes = UserDefaults.standard.bool(forKey: SPDisplayTableViewColumnTypes)
        let columnSignature = currentColumnSignature()

        if columnSignature == displayedColumnSignature,
           tableView.tableColumns.count == filteredColumns.count {
            updateExistingColumns(font: tableFont, showColumnTypes: showColumnTypes)
            applySortDescriptorsFromCurrentState()
            tableView.headerView?.needsDisplay = true
            scheduleVisibleColumnAutosize(delay: 0.01)
            return
        }

        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }

        for columnIndex in filteredColumns {
            let columnName = columns[columnIndex]
            let column = columnIndex < columnInfo.count
                ? columnInfo[columnIndex]
                : ColumnInfo(name: columnName, type: "", typeGrouping: "", length: "", values: [], comment: "", isNullable: false, isPrimary: false, isAutoIncrement: false, defaultExpression: nil)
            let tableColumn = SALightweightResultGrid.configuredColumn(
                identifier: columnIndex,
                title: columnName,
                descriptor: Self.gridColumnDescriptor(columnName: columnName, column: column),
                font: tableFont,
                editable: tableObjectType == .table,
                headerToolTip: legacyHeaderToolTip(for: column),
                headerAttributedString: contentHeaderTitle(for: columnIndex, columnName: columnName, showColumnTypes: showColumnTypes),
                savedWidth: savedWidth(for: columnName),
                minWidth: 8
            )
            tableView.addTableColumn(tableColumn)
        }

        displayedColumnSignature = columnSignature
        tableView.reloadData()
        applySortDescriptorsFromCurrentState()
        scheduleVisibleColumnAutosize(delay: 0.01)
    }

    func cancelActiveContentEditBeforeReload() {
        guard tableView.editedRow >= 0 || tableView.editedColumn >= 0 else { return }

        tableView.abortEditing()
        tableView.window?.makeFirstResponder(tableView)
    }

    @objc func resultGridBoundsDidChange(_ notification: Notification) {
        // Keep horizontal scrolling smooth; column widths are stabilized at load time.
    }

    @objc func resultGridWillStartLiveScroll(_ notification: Notification) {
        autosizeCoordinator.willStartLiveScroll()
    }

    @objc func resultGridDidEndLiveScroll(_ notification: Notification) {
        autosizeCoordinator.didEndLiveScroll()
    }

    func scheduleVisibleColumnAutosize(delay: TimeInterval = 0.05) {
        autosizeCoordinator.schedule(delay: delay) { [weak self] in
            self?.autosizeContentColumns()
        }
    }

    func currentColumnSignature() -> [String] {
        return filteredColumns.map { columnIndex in
            guard columnIndex < columns.count else { return "\(columnIndex)" }
            let column = columnIndex < columnInfo.count ? columnInfo[columnIndex] : nil
            return [
                "\(columnIndex)",
                columns[columnIndex],
                column?.type ?? "",
                column?.typeGrouping ?? "",
                column?.length ?? "",
                column?.values.joined(separator: "\u{1f}") ?? "",
                column?.isNullable == true ? "1" : "0",
                String(describing: tableObjectType)
            ].joined(separator: "\u{1e}")
        }
    }

    func updateExistingColumns(font tableFont: NSFont, showColumnTypes: Bool) {
        for (displayIndex, columnIndex) in filteredColumns.enumerated() {
            guard displayIndex < tableView.tableColumns.count,
                  columnIndex < columns.count else { continue }

            let columnName = columns[columnIndex]
            let column = columnIndex < columnInfo.count
                ? columnInfo[columnIndex]
                : ColumnInfo(name: columnName, type: "", typeGrouping: "", length: "", values: [], comment: "", isNullable: false, isPrimary: false, isAutoIncrement: false, defaultExpression: nil)
            let tableColumn = tableView.tableColumns[displayIndex]
            SALightweightResultGrid.updateColumn(tableColumn,
                                                 identifier: columnIndex,
                                                 title: columnName,
                                                 descriptor: Self.gridColumnDescriptor(columnName: columnName, column: column),
                                                 font: tableFont,
                                                 editable: tableObjectType == .table,
                                                 headerToolTip: legacyHeaderToolTip(for: column),
                                                 headerAttributedString: contentHeaderTitle(for: columnIndex, columnName: columnName, showColumnTypes: showColumnTypes))
        }
        tableView.headerView?.needsDisplay = true
    }

    func reloadCell(row: Int, columnIndex: Int) {
        SALightweightResultGrid.reloadCell(in: tableView, row: row, columnIndex: columnIndex)
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

        let start = (limitResults ? pageIndex * pageSize : 0) + 1
        let end = start + rows.count - 1

        if let totalRowCount = totalRowCount {
            let countPrefix = totalRowCountIsEstimate ? "~" : ""
            statusLabel.stringValue = String(format: NSLocalizedString("Rows %@ - %@ of %@%@ from table", comment: "lightweight content row range of total"), Self.formattedCount(start), Self.formattedCount(end), countPrefix, Self.formattedCount(totalRowCount)) + selectionText
        } else {
            statusLabel.stringValue = String(format: NSLocalizedString("Rows %@ - %@ from table", comment: "lightweight content row range"), Self.formattedCount(start), Self.formattedCount(end)) + selectionText
        }
    }

    func updateControls() {
        let selectedRow = tableView.selectedRow
        let selectedRowIsNew = selectedRow >= 0 && selectedRow < rows.count && rows[selectedRow].isNew
        addRowButton.isEnabled = canModifyRows
        duplicateRowButton.isEnabled = canModifyRows && tableView.numberOfSelectedRows == 1 && !selectedRowIsNew
        deleteRowButton.isEnabled = canModifyRows && tableView.numberOfSelectedRows > 0
        reloadButton.isEnabled = !isLoading
        editModeButton.isEnabled = !isLoading
        editModeButton.state = UserDefaults.standard.bool(forKey: SPEditInSheetEnabled) ? .on : .off
        toggleRuleFilterButton.isEnabled = !isLoading && !columnInfo.isEmpty
        toggleRuleFilterButton.state = isRuleFilterVisible ? .on : .off
        columnFilterSearchField.isEnabled = !isLoading && !columns.isEmpty
        applyFilterButton.isEnabled = isRuleFilterVisible && !isLoading && !columnInfo.isEmpty && !filterRules.isEmpty
        addFilterButton.isEnabled = isRuleFilterVisible && !isLoading && !columnInfo.isEmpty
        filterRowsStackView.arrangedSubviews.forEach { $0.subviews.forEach { ($0 as? NSControl)?.isEnabled = !isLoading } }
        previousPageButton.isEnabled = limitResults && !isLoading && pageIndex > 0
        paginationButton.isEnabled = limitResults && !isLoading
        nextPageButton.isEnabled = limitResults && !isLoading && hasNextPage
        if !limitResults {
            pageLabel.stringValue = ""
        } else if totalRowCount != nil {
            pageLabel.stringValue = String(format: NSLocalizedString("Page %ld of %ld", comment: "lightweight content page label with total"), pageIndex + 1, maximumPage)
        } else {
            pageLabel.stringValue = String(format: NSLocalizedString("Page %ld", comment: "lightweight content page label"), pageIndex + 1)
        }
    }

    private func firstEditableContentColumnIndex() -> Int {
        return tableView.tableColumns.firstIndex(where: { !$0.isHidden }) ?? 0
    }

    private static func defaultNewRowValue(for column: ColumnInfo) -> ContentValue {
        if column.isAutoIncrement {
            return .null
        }

        if let defaultExpression = column.defaultExpression, !defaultExpression.isEmpty {
            return .object(defaultExpression)
        }

        if column.isNullable {
            return .null
        }

        if ["integer", "float", "bit"].contains(column.typeGrouping) {
            return .object("0")
        }

        return .object("")
    }

    func configureRuleFilterColumnsIfNeeded() {
        let key = columnInfo.map { "\($0.name):\($0.typeGrouping)" }.joined(separator: "\t")
        guard key != ruleFilterColumnsKey else {
            updateRuleFilterVisibility(animated: false)
            return
        }

        ruleFilterColumnsKey = key

        if let currentTableKey = currentTableKey,
           let restoredFilter = sessionState.contentState(for: currentTableKey)?.serializedRuleFilter as? [AnyHashable: Any] {
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
        toggleRuleFilterButton.state = visible ? .on : .off
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
        sessionStateDidChange?()
        updateRuleFilterVisibility(animated: false)
        focusValueField(for: newRule.id)
    }

    func removeFilterRule(id: UUID) {
        filterRules.removeAll { $0.id == id }
        rebuildFilterRows()
        storeCurrentRuleFilterState()
        sessionStateDidChange?()
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
        sessionStateDidChange?()
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
                self.sessionStateDidChange?()
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
        if let advancedFilterWhereClause = advancedFilterWhereClause {
            return (advancedFilterWhereClause, false)
        }

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
        guard let currentTableKey = currentTableKey else { return }

        sessionState.setContentState(
            SALightweightSessionState.ContentState(
                serializedRuleFilter: filterRules.isEmpty ? nil : serializedFilter() as NSDictionary,
                isRuleFilterActive: isRuleFilterActive,
                sortColumn: sortColumn,
                sortAscending: sortAscending,
                pageIndex: pageIndex,
                columnFilter: serializedColumnFilter()
            ),
            for: currentTableKey
        )
    }

    func restoreCachedContent(for key: SALightweightSessionState.TableKey) -> Bool {
        guard let cached = contentCache[key],
              cached.pageSize == pageSize,
              cached.limitResults == limitResults else {
            contentCache.removeValue(forKey: key)
            contentCacheOrder.removeAll { $0 == key }
            return false
        }

        isRestoringCachedContent = true
        defer { isRestoringCachedContent = false }

        columns = cached.columns
        columnInfo = cached.columnInfo
        rows = cached.rows
        displayCache.invalidateAll()
        columnWidthCache.invalidateAll()
        pageIndex = cached.pageIndex
        tableObjectType = cached.tableObjectType
        totalRowCount = cached.totalRowCount
        totalRowCountIsEstimate = cached.totalRowCountIsEstimate
        hasNextPage = cached.hasNextPage
        sortColumn = cached.sortColumn
        sortAscending = cached.sortAscending
        isRuleFilterActive = cached.isRuleFilterActive
        restoreColumnFilter(cached.columnFilter)

        sessionState.setContentState(
            SALightweightSessionState.ContentState(
                serializedRuleFilter: cached.serializedRuleFilter,
                isRuleFilterActive: cached.isRuleFilterActive,
                sortColumn: cached.sortColumn,
                sortAscending: cached.sortAscending,
                pageIndex: cached.pageIndex,
                columnFilter: cached.columnFilter
            ),
            for: key
        )
        applySortDescriptorsFromCurrentState()

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
        guard let currentTableKey = currentTableKey, !columns.isEmpty else { return }

        storeCurrentRuleFilterState()
        contentCache[currentTableKey] = ContentCacheEntry(
            columns: columns,
            columnInfo: columnInfo,
            rows: rows,
            pageIndex: pageIndex,
            pageSize: pageSize,
            limitResults: limitResults,
            tableObjectType: tableObjectType,
            totalRowCount: totalRowCount,
            totalRowCountIsEstimate: totalRowCountIsEstimate,
            hasNextPage: hasNextPage,
            sortColumn: sortColumn,
            sortAscending: sortAscending,
            isRuleFilterActive: isRuleFilterActive,
            serializedRuleFilter: sessionState.contentState(for: currentTableKey)?.serializedRuleFilter,
            columnFilter: serializedColumnFilter()
        )
        noteContentCacheUse(for: currentTableKey)
    }

    func serializedColumnFilter() -> String? {
        let filter = columnFilterSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return filter.isEmpty ? nil : filter
    }

    func restoreColumnFilter(_ filter: String?) {
        let filter = filter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        columnFilterSearchField.stringValue = filter
        let terms = filter
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        columnFilterTerms = terms.isEmpty ? nil : terms
    }

    func applySortDescriptorsFromCurrentState() {
        if let sortColumn = sortColumn, let columnIndex = columns.firstIndex(of: sortColumn) {
            SALightweightResultGrid.applySortIndicator(to: tableView, columnIndex: columnIndex, ascending: sortAscending)
        } else {
            SALightweightResultGrid.applySortIndicator(to: tableView, columnIndex: nil, ascending: true)
        }
    }

    func noteContentCacheUse(for key: SALightweightSessionState.TableKey) {
        contentCacheOrder.removeAll { $0 == key }
        contentCacheOrder.append(key)

        while contentCacheOrder.count > maximumContentCacheEntries {
            let oldKey = contentCacheOrder.removeFirst()
            contentCache.removeValue(forKey: oldKey)
        }
    }

    func invalidateCurrentContentCache() {
        guard let currentTableKey = currentTableKey else { return }

        contentCache.removeValue(forKey: currentTableKey)
        contentCacheOrder.removeAll { $0 == currentTableKey }
    }

    func showInvalidRuleFilterAlert(error: Error?) {
        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Invalid Filter", comment: "table content apply filter invalid filter message title")
        alert.informativeText = error?.localizedDescription ?? NSLocalizedString("No valid SQL expression could be generated.", comment: "lightweight content invalid filter fallback")

        alert.runModalCentered(over: view.window)
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
        UserDefaults.standard.addObserver(self, forKeyPath: SPEditInSheetEnabled, options: .new, context: nil)
        didRegisterPreferenceObservers = true
    }

    func applyTablePreferences(rebuildColumns shouldRebuildColumns: Bool, rebuildDisplayValues shouldRebuildDisplayValues: Bool = true) {
        let tableFont = UserDefaults.getFont()
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = SALightweightResultGrid.rowHeight(for: tableFont)

        for column in tableView.tableColumns {
            (column.dataCell as? NSCell)?.font = tableFont
            column.headerCell.font = SALightweightResultGrid.headerFont(for: tableFont)
        }

        if shouldRebuildColumns {
            rebuildColumns()
        } else {
            if shouldRebuildDisplayValues {
                rebuildDisplayValues()
            }
            tableView.headerView?.needsDisplay = true
            SALightweightResultGrid.reloadVisibleCells(in: tableView, columnBuffer: SALightweightResultGrid.autosizeColumnBuffer)
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

    func autosizeContentColumns(onlyVisibleColumns: Bool = true) {
        let benchmarkStart = CFAbsoluteTimeGetCurrent()
        defer {
            SALightweightResultGrid.logPerformance("Content autosize columns", start: benchmarkStart, details: "columns=\(tableView.tableColumns.count) rows=\(rows.count) visibleOnly=\(onlyVisibleColumns)", minimumMilliseconds: 4)
        }

        isApplyingProgrammaticColumnWidths = true
        defer { isApplyingProgrammaticColumnWidths = false }

        let displayColumnIndexes = onlyVisibleColumns
            ? SALightweightResultGrid.visibleColumnIndexes(in: tableView, buffer: SALightweightResultGrid.autosizeColumnBuffer)
            : IndexSet(integersIn: 0..<tableView.tableColumns.count)
        let visibleRows = visibleRowsForAutosizing(maxRows: 64)

        SALightweightResultGrid.autosizeColumns(in: tableView,
                                                displayColumnIndexes: displayColumnIndexes,
                                                visibleRows: visibleRows,
                                                columnWidthCache: columnWidthCache,
                                                shouldSkipColumn: { [weak self] columnIndex, _ in
                                                    guard let self = self else { return true }
                                                    if columnIndex < self.columnInfo.count,
                                                       SALightweightResultGrid.isWideTextColumn(typeGrouping: self.columnInfo[columnIndex].typeGrouping) {
                                                        return true
                                                    }
                                                    return columnIndex < self.columns.count && self.savedWidth(for: self.columns[columnIndex]) != nil
                                                },
                                                cacheKey: { [weak self] columnIndex, tableColumn, visibleRows in
                                                    self?.contentColumnWidthCacheKey(for: tableColumn, columnIndex: columnIndex, visibleRows: visibleRows) ?? tableColumn.identifier.rawValue
                                                },
                                                isEnumColumn: { [weak self] columnIndex in
                                                    guard let self = self, columnIndex < self.columnInfo.count else { return false }
                                                    return self.columnInfo[columnIndex].typeGrouping == "enum"
                                                },
                                                displayValue: { [weak self] row, columnIndex in
                                                    guard let self = self,
                                                          row < self.rows.count,
                                                          columnIndex < self.rows[row].values.count else { return "" }
                                                    return self.displayValue(row: row, column: columnIndex)
                                                })
    }

    func contentColumnWidthCacheKey(for tableColumn: NSTableColumn, columnIndex: Int, visibleRows: Range<Int>) -> String {
        let tableFont = UserDefaults.getFont()
        let columnName = columnIndex < columns.count ? columns[columnIndex] : tableColumn.identifier.rawValue
        let column = columnIndex < columnInfo.count ? columnInfo[columnIndex] : nil
        return [
            tableColumn.identifier.rawValue,
            columnName,
            column?.type ?? "",
            column?.typeGrouping ?? "",
            column?.length ?? "",
            UserDefaults.standard.bool(forKey: SPDisplayTableViewColumnTypes) ? "types" : "names",
            tableFont.fontName,
            "\(tableFont.pointSize)",
            "\(rows.count)",
            "\(visibleRows.lowerBound)-\(visibleRows.upperBound)"
        ].joined(separator: "\u{1e}")
    }

    func visibleRowsForAutosizing(maxRows: Int) -> Range<Int> {
        guard maxRows > 0, !rows.isEmpty else { return 0..<0 }

        let visibleRange = tableView.rows(in: tableView.visibleRect)
        let start = visibleRange.length > 0 ? visibleRange.location : 0
        let end = visibleRange.length > 0 ? min(rows.count, visibleRange.location + visibleRange.length) : min(rows.count, maxRows)
        guard start < end else { return 0..<min(rows.count, maxRows) }

        return start..<min(end, start + maxRows)
    }

    static func gridColumnDescriptor(columnName: String, column: ColumnInfo) -> SALightweightResultGrid.ColumnDescriptor {
        return SALightweightResultGrid.ColumnDescriptor(name: columnName,
                                                        type: column.type,
                                                        typeGrouping: column.typeGrouping,
                                                        length: column.length,
                                                        values: column.values,
                                                        isNullable: column.isNullable)
    }

    static func formattedCount(_ value: Int) -> String {
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    func shouldUseFieldEditor(row: Int, column columnIndex: Int) -> Bool {
        guard row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < columnInfo.count,
              columnIndex < rows[row].values.count else { return false }

        let column = columnInfo[columnIndex]
        let value: Any?
        switch rows[row].values[columnIndex] {
        case .null:
            value = NSNull()
        case .notLoaded:
            value = nil
        case .object(let object):
            value = object
        }
        return SALightweightResultGrid.shouldUseFieldEditor(typeGrouping: column.typeGrouping, value: value, displayValue: displayString(for: rows[row].values[columnIndex], columnIndex: columnIndex, truncate: false))
    }

    func openFieldEditor(row: Int, column columnIndex: Int) {
        guard !isFieldEditorPresented,
              row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < columnInfo.count,
              columnIndex < rows[row].values.count,
              let connection = connection,
              let window = view.window else { return }

        isFieldEditorPresented = true

        let column = columnInfo[columnIndex]
        let editor = fieldEditor
        editor.editedFieldInfo = [
            "usedQuery": contentQuery(offset: pageIndex * pageSize, limit: pageSize, whereClause: ruleFilterStringForCurrentState(showError: false).whereClause, columnInfo: columnInfo, limitResults: limitResults),
            "tableSource": "content",
            "tableName": table,
            "colName": column.name
        ]

        if let length = UInt64(column.length) {
            editor.textMaxLength = length
        }
        editor.fieldType = column.type
        editor.fieldEncoding = ""
        editor.allowNULL = !column.isNullable

        let originalData: Any
        switch rows[row].values[columnIndex] {
        case .null:
            originalData = UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        case .notLoaded:
            originalData = ""
        case .object(let object):
            originalData = object
        }

        fieldEditorTextSelectedRange = NSMakeRange(0, 0)

        editor.edit(with: originalData,
                    fieldName: column.name,
                    usingEncoding: connection.stringEncoding(),
                    isObjectBlob: column.typeGrouping == "textdata" || column.typeGrouping == "blobdata",
                    isEditable: canModifyRows,
                    with: window,
                    sender: self,
                    contextInfo: [
                        "rowIndex": NSNumber(value: row),
                        "columnIndex": NSNumber(value: columnIndex),
                        "isFieldEditable": NSNumber(value: canModifyRows),
                        "disableSheetAnimation": NSNumber(value: true),
                        "deferTextLoading": NSNumber(value: true)
                    ])
    }

    func displayString(for value: ContentValue, columnIndex: Int, truncate: Bool = true) -> String {
        let column = columnIndex < columnInfo.count ? columnInfo[columnIndex] : nil
        return Self.displayString(for: value, columnInfo: column, truncate: truncate)
    }

    func displayValue(row: Int, column columnIndex: Int) -> String {
        guard row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < rows[row].values.count else { return "" }

        return displayCache.value(row: row, column: columnIndex) {
            displayString(for: rows[row].values[columnIndex], columnIndex: columnIndex)
        }
    }

    static func displayString(for value: ContentValue, columnInfo: ColumnInfo?, truncate: Bool = true) -> String {
        switch value {
        case .null:
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        case .notLoaded:
            return NSLocalizedString("(not loaded)", comment: "value shown for hidden blob and text fields")
        case .object(let object):
            return SALightweightResultGrid.displayString(for: object,
                                                         descriptor: columnInfo.map { gridColumnDescriptor(columnName: $0.name, column: $0) },
                                                         truncate: truncate)
        }
    }

    static func displayString(for value: Any) -> String {
        return SALightweightResultGrid.displayString(for: value)
    }

    static func displayString(for value: Any?) -> String {
        return SALightweightResultGrid.displayString(for: value)
    }

    static func editedString(from object: Any?) -> String {
        if let string = object as? String {
            return string
        }

        if let attributedString = object as? NSAttributedString {
            return attributedString.string
        }

        return object.map { String(describing: $0) } ?? ""
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

    private static func sqlValue(forEditedString value: String, columnInfo: ColumnInfo, connection: SPMySQLConnection) -> EditedContentSQLValue? {
        if let expression = SALightweightResultGrid.editedSQLExpression(for: value,
                                                                        typeGrouping: columnInfo.typeGrouping,
                                                                        defaultExpression: columnInfo.defaultExpression,
                                                                        allowsStringUUIDFunction: true) {
            return EditedContentSQLValue(sql: expression, localValue: .object(value), requiresReload: true)
        }

        let localValue: ContentValue = value == (UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL") && columnInfo.isNullable
            ? .null
            : .object(value)
        guard let sqlValue = sqlValue(localValue, columnInfo: columnInfo, connection: connection) else { return nil }

        return EditedContentSQLValue(sql: sqlValue, localValue: localValue, requiresReload: false)
    }

    func csvStringForCurrentContent() -> String {
        return SALightweightResultGrid.csvString(rowCount: rows.count,
                                                 tableColumns: tableView.tableColumns,
                                                 columnName: { self.columnName(for: $0) },
                                                 value: { self.contentDisplayValue(row: $0, tableColumn: $1) })
    }

    @objc(currentResultRowCount)
    func currentResultRowCount() -> Int {
        return rows.count
    }

    @objc(currentDataResultWithNULLs:)
    func currentDataResult(withNULLs includeNULLs: Bool) -> [[Any]] {
        var result: [[Any]] = [tableView.tableColumns.map { columnName(for: $0) }]

        for row in rows {
            result.append(tableView.tableColumns.map { tableColumn in
                guard let columnIndex = Int(tableColumn.identifier.rawValue), columnIndex < row.values.count else { return "" }
                if includeNULLs, case .null = row.values[columnIndex] {
                    return NSNull()
                }

                return displayString(for: row.values[columnIndex], columnIndex: columnIndex, truncate: false)
            })
        }

        return result
    }

    @objc(usedQuery)
    func usedQuery() -> String {
        return contentQuery(offset: pageIndex * pageSize,
                            limit: pageSize,
                            whereClause: ruleFilterStringForCurrentState(showError: false).whereClause,
                            columnInfo: columnInfo,
                            limitResults: limitResults)
    }

    func xmlStringForCurrentContent() -> String {
        return SALightweightResultGrid.xmlString(rowCount: rows.count,
                                                 tableColumns: tableView.tableColumns,
                                                 columnName: { self.columnName(for: $0) },
                                                 value: { self.contentDisplayValue(row: $0, tableColumn: $1) })
    }

    func contentRowsAsTabString(includeHeaders: Bool, rowIndexes: IndexSet) -> String? {
        return SALightweightResultGrid.tabString(includeHeaders: includeHeaders,
                                                 rowIndexes: rowIndexes,
                                                 tableColumns: tableView.tableColumns,
                                                 rowCount: rows.count,
                                                 columnName: { self.columnName(for: $0) },
                                                 value: { self.contentDisplayValue(row: $0, tableColumn: $1) })
    }

    func contentRowsAsSQLInserts(rowIndexes: IndexSet, skipAutoIncrement: Bool) -> String? {
        guard !rowIndexes.isEmpty, let connection = connection else { return nil }

        let includedColumns = sqlInsertColumnIndexes(rowIndexes: rowIndexes, skipAutoIncrement: skipAutoIncrement)
        guard !includedColumns.isEmpty else { return nil }

        let columnList = includedColumns.map { Self.backtickQuoted(columns[$0]) }.joined(separator: ", ")
        var result = "INSERT INTO \(Self.backtickQuoted(table)) (\(columnList))\nVALUES\n"
        var valueBuffer = ""
        var copiedRows = 0

        rowIndexes.forEach { rowIndex in
            guard rowIndex < rows.count else { return }

            let row = rows[rowIndex]
            let values = includedColumns.map { columnIndex -> String in
                guard columnIndex < row.values.count else { return "NULL" }
                return sqlInsertValue(for: row.values[columnIndex], columnInfo: columnInfo[columnIndex], connection: connection)
            }

            if copiedRows > 0 {
                valueBuffer += "),\n"
            }
            valueBuffer += "\t(\(values.joined(separator: ", "))"
            copiedRows += 1
        }

        guard copiedRows > 0 else { return nil }

        result += valueBuffer + ");\n"
        return result
    }

    func sqlInsertColumnIndexes(rowIndexes: IndexSet, skipAutoIncrement: Bool) -> [Int] {
        return tableView.tableColumns.compactMap { tableColumn -> Int? in
            guard let columnIndex = Int(tableColumn.identifier.rawValue),
                  columnIndex < columns.count,
                  columnIndex < columnInfo.count else { return nil }

            if skipAutoIncrement, columnInfo[columnIndex].isAutoIncrement {
                return nil
            }

            let hasUnloadedValue = rowIndexes.contains { rowIndex in
                guard rowIndex < rows.count, columnIndex < rows[rowIndex].values.count else { return true }
                if case .notLoaded = rows[rowIndex].values[columnIndex] {
                    return true
                }
                return false
            }

            return hasUnloadedValue ? nil : columnIndex
        }
    }

    func sqlInsertValue(for value: ContentValue, columnInfo: ColumnInfo, connection: SPMySQLConnection) -> String {
        switch value {
        case .null, .notLoaded:
            return "NULL"
        case .object(let object):
            if let data = object as? Data {
                return connection.escapeAndQuoteData(data) ?? Self.singleQuoted(data.map { String(format: "%02X", $0) }.joined())
            }

            let displayValue = Self.displayString(for: value, columnInfo: columnInfo, truncate: false)
            if columnInfo.typeGrouping == "integer" || columnInfo.typeGrouping == "float" || columnInfo.type.uppercased() == "YEAR" {
                return displayValue
            }

            if columnInfo.typeGrouping == "bit" {
                return "b'\(displayValue)'"
            }

            return connection.escapeAndQuoteString(displayValue) ?? Self.singleQuoted(displayValue)
        }
    }

    func columnName(for tableColumn: NSTableColumn) -> String {
        guard let columnIndex = Int(tableColumn.identifier.rawValue), columnIndex < columns.count else {
            return tableColumn.headerCell.stringValue
        }

        return columns[columnIndex]
    }

    func contentDisplayValue(row: Int, tableColumn: NSTableColumn) -> String? {
        guard row < rows.count,
              let columnIndex = Int(tableColumn.identifier.rawValue),
              columnIndex < rows[row].values.count else { return nil }

        return displayString(for: rows[row].values[columnIndex], columnIndex: columnIndex, truncate: false)
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
        return SALightweightResultGrid.backtickQuoted(value)
    }

    static func singleQuoted(_ value: String) -> String {
        return SALightweightResultGrid.singleQuoted(value)
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

    func clearSavedWidth(for columnName: String) {
        guard let host = connection?.host,
              !host.isEmpty else { return }

        let databaseKey = "\(database)@\(host)"
        var savedWidths = UserDefaults.standard.dictionary(forKey: SPTableColumnWidths) ?? [:]
        var databaseWidths = savedWidths[databaseKey] as? [String: Any] ?? [:]
        var tableWidths = databaseWidths[table] as? [String: Any] ?? [:]

        tableWidths.removeValue(forKey: columnName)

        if tableWidths.isEmpty {
            databaseWidths.removeValue(forKey: table)
        } else {
            databaseWidths[table] = tableWidths
        }

        if databaseWidths.isEmpty {
            savedWidths.removeValue(forKey: databaseKey)
        } else {
            savedWidths[databaseKey] = databaseWidths
        }

        UserDefaults.standard.set(savedWidths, forKey: SPTableColumnWidths)
    }

    func loadDeferredCellValue(row: Int, columnIndex: Int, whereClause: String) {
        guard !isLoading,
              !isFieldEditorPresented,
              row >= 0,
              row < rows.count,
              columnIndex < columnInfo.count,
              let connection = connection else { return }

        deferredFieldEditorRequestID += 1
        let requestID = deferredFieldEditorRequestID
        isLoading = true
        updateControls()
        statusLabel.stringValue = NSLocalizedString("Loading cell...", comment: "lightweight content deferred cell loading")

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            _ = connection.selectDatabase(self.database)
            let query = "SELECT \(Self.backtickQuoted(self.columnInfo[columnIndex].name)) FROM \(Self.backtickQuoted(self.database)).\(Self.backtickQuoted(self.table)) WHERE \(whereClause) LIMIT 1"
            let result = connection.queryString(query)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil
            result?.defaultRowReturnType = SPMySQLResultRowAsArray
            let value: Any? = result?.getRowAsArray()?.first ?? nil

            DispatchQueue.main.async {
                guard requestID == self.deferredFieldEditorRequestID else { return }
                self.isLoading = false

                if let error = error, !error.isEmpty {
                    self.statusLabel.stringValue = error
                    self.updateControls()
                    return
                }

                guard row < self.rows.count else {
                    self.updateControls()
                    return
                }

                guard let currentWhereClause = Self.rowIdentityWhereClause(for: self.rows[row].originalValues, columnInfo: self.columnInfo, connection: connection),
                      currentWhereClause == whereClause else {
                    self.updateControls()
                    return
                }

                let contentValue = Self.contentValue(for: value)
                self.rows[row].values[columnIndex] = contentValue
                self.rows[row].originalValues[columnIndex] = contentValue
                self.displayCache.invalidate(row: row, column: columnIndex)
                self.cacheCurrentContentState()
                self.updateStatus()
                self.updateControls()
                self.openFieldEditor(row: row, column: columnIndex)
            }
        }
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

    static func rawColumnType(fromStructureRow row: [String: String]) -> String {
        let type = row["type"] ?? ""
        let length = row["length"] ?? ""
        guard !length.isEmpty else { return type }

        return "\(type)(\(length))"
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

    private func cancelNewContentRow(_ row: Int) {
        guard row >= 0, row < rows.count, rows[row].isNew else { return }

        rows.remove(at: row)
        tableView.reloadData()
        tableView.deselectAll(nil)
        tableView.window?.makeFirstResponder(tableView)
        updateStatus()
        updateControls()
    }

    private func saveNewContentRow(row: Int, editedColumnIndex: Int, updatedValue: EditedContentSQLValue, connection: SPMySQLConnection) {
        guard row >= 0, row < rows.count, rows[row].isNew else { return }

        var newValues = rows[row].values
        newValues[editedColumnIndex] = updatedValue.localValue

        var insertColumns: [String] = []
        var insertValues: [String] = []
        for (index, column) in columnInfo.enumerated() {
            guard index < newValues.count, !column.isAutoIncrement else { continue }

            let editedSQLValue: EditedContentSQLValue?
            if index == editedColumnIndex {
                editedSQLValue = updatedValue
            } else {
                let displayValue = displayString(for: newValues[index], columnIndex: index, truncate: false)
                editedSQLValue = Self.sqlValue(forEditedString: displayValue, columnInfo: column, connection: connection)
            }

            guard let sqlValue = editedSQLValue?.sql else { continue }
            insertColumns.append(Self.backtickQuoted(column.name))
            insertValues.append(sqlValue)
        }

        let tableReference = "\(Self.backtickQuoted(database)).\(Self.backtickQuoted(table))"
        let insertQuery: String
        if insertColumns.isEmpty {
            insertQuery = "INSERT INTO \(tableReference) () VALUES ()"
        } else {
            insertQuery = "INSERT INTO \(tableReference) (\(insertColumns.joined(separator: ", "))) VALUES (\(insertValues.joined(separator: ", ")))"
        }
        let reloadAfterAdd = UserDefaults.standard.bool(forKey: SPReloadAfterAddingRow)
        guard confirmQueryWarningIfNeeded(insertQuery) else {
            cancelNewContentRow(row)
            return
        }

        statusLabel.stringValue = NSLocalizedString("Adding row...", comment: "lightweight content adding row")
        isLoading = true
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            connection.queryString(insertQuery)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil
            let lastInsertID = connection.lastInsertID()

            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error, !error.isEmpty {
                    self.statusLabel.stringValue = error
                    self.showContentError(title: NSLocalizedString("Unable to add row", comment: "lightweight content add row error title"), message: error)
                    self.cancelNewContentRow(row)
                    return
                }

                guard row >= 0, row < self.rows.count else { return }
                if reloadAfterAdd {
                    self.loadCurrentPage()
                    return
                }

                for (index, column) in self.columnInfo.enumerated() where index < newValues.count && column.isAutoIncrement && lastInsertID > 0 {
                    newValues[index] = .object("\(lastInsertID)")
                }

                self.rows[row] = ContentRow(values: newValues, originalValues: newValues, isNew: false)
                self.tableView.reloadData()
                self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.statusLabel.stringValue = NSLocalizedString("Row added.", comment: "lightweight content row added status")
                self.updateStatus()
                self.updateControls()
            }
        }
    }

    private func showContentError(title: String, message: String) {
        NSAlert.createWarningAlert(title: title, message: message, callback: nil)
    }

    private func confirmQueryWarningIfNeeded(_ query: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: SPQueryWarningEnabled),
              !SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(query) else {
            return true
        }

        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = NSLocalizedString("Edit row?", comment: "Edit row?")
        alert.informativeText = queryWarningMessage(for: query)
        alert.addButton(withTitle: NSLocalizedString("Proceed", comment: "Proceed"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        return alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn
    }

    private func queryWarningMessage(for query: String) -> String {
        var queryText = query
        if queryText.count > SPMaxQueryLengthForWarning {
            queryText = String(queryText.prefix(Int(SPMaxQueryLengthForWarning))) + "..."
        }

        return String(format: NSLocalizedString("Do you really want to proceed with this query?\n\n %@", comment: "message of panel asking for confirmation for exec query"), queryText)
    }
}

extension SALightweightContentViewController {
    func canCopySelectedContentRows(_ sender: Any?) -> Bool {
        let skipAutoIncrement = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLNoAutoIncTag
        let copiesAsSQL = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLTag || skipAutoIncrement

        guard !isLoading, tableView.numberOfSelectedRows > 0 else { return false }
        guard copiesAsSQL else { return true }

        return !sqlInsertColumnIndexes(rowIndexes: tableView.selectedRowIndexes, skipAutoIncrement: skipAutoIncrement).isEmpty
    }

    @objc func copySelectedContentRowsForMenu(_ sender: Any?) {
        let copiesAsSQL = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLTag
            || (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLNoAutoIncTag

        if copiesAsSQL {
            copySelectedContentRowsAsSQL(sender)
        } else {
            copySelectedContentRows(sender)
        }
    }

    func exportResultRowCount() -> Int {
        return currentResultRowCount()
    }

    func exportDataResult(withNULLs includeNULLs: Bool) -> [[Any]] {
        return currentDataResult(withNULLs: includeNULLs)
    }

    func exportUsedQuery() -> String {
        return usedQuery()
    }

    @objc(processFieldEditorResult:contextInfo:)
    func processFieldEditorResult(_ data: Any?, contextInfo: NSDictionary?) {
        defer {
            isFieldEditorPresented = false
        }

        guard let data = data,
              let contextInfo = contextInfo,
              (contextInfo["isFieldEditable"] as? NSNumber)?.boolValue == true,
              let rowNumber = contextInfo["rowIndex"] as? NSNumber,
              let columnNumber = contextInfo["columnIndex"] as? NSNumber else { return }

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(columnNumber.intValue)))
        tableView(tableView, setObjectValue: data, for: tableColumn, row: rowNumber.intValue)
    }

    @objc(setFieldEditorSelectedRange:)
    func setFieldEditorSelectedRange(_ range: NSRange) {
        fieldEditorTextSelectedRange = range
    }

    @objc
    func fieldEditorSelectedRange() -> NSRange {
        return fieldEditorTextSelectedRange
    }
}

extension SALightweightContentViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return SALightweightResultGrid.objectValue(row: row,
                                                   rowCount: rows.count,
                                                   tableColumn: tableColumn,
                                                   columnCount: { self.rows[$0].values.count },
                                                   displayValue: { self.displayValue(row: $0, column: $1) })
    }

    func tableView(_ tableView: NSTableView,
                   toolTipFor cell: NSCell,
                   rect: UnsafeMutablePointer<NSRect>,
                   tableColumn: NSTableColumn?,
                   row: Int,
                   mouseLocation: NSPoint) -> String {
        return SALightweightResultGrid.emptyToolTip(row: row,
                                                    rowCount: rows.count,
                                                    tableColumn: tableColumn,
                                                    columnCount: { self.rows[$0].values.count })
    }

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
        guard let copyString = contentRowsAsTabString(includeHeaders: false, rowIndexes: rowIndexes) else { return false }

        return SALightweightResultGrid.writeRows(copyString, to: pasteboard)
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        guard !isFieldEditorPresented else { return false }

        guard row >= 0,
              row < rows.count,
              let connection = connection,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].values.count,
              columnIndex < columnInfo.count,
              canModifyRows else { return false }

        guard case .notLoaded = rows[row].values[columnIndex] else {
            if shouldUseFieldEditor(row: row, column: columnIndex) {
                openFieldEditor(row: row, column: columnIndex)
                return false
            }

            return true
        }

        guard let whereClause = Self.rowIdentityWhereClause(for: rows[row].originalValues, columnInfo: columnInfo, connection: connection) else {
            statusLabel.stringValue = NSLocalizedString("Cannot load cell without identifiable columns", comment: "lightweight content blob load no identity")
            return false
        }

        loadDeferredCellValue(row: row, columnIndex: columnIndex, whereClause: whereClause)
        return false
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard row >= 0,
              row < rows.count,
              let connection = connection,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].values.count,
              columnIndex < columnInfo.count,
              canModifyRows else { return }

        let oldRowValues = rows[row].originalValues
        let newValue = Self.editedString(from: object)
        let currentDisplayValue = displayString(for: rows[row].values[columnIndex], columnIndex: columnIndex, truncate: false)
        guard newValue != currentDisplayValue else {
            if rows[row].isNew {
                cancelNewContentRow(row)
            }
            return
        }

        let columnName = columnInfo[columnIndex].name
        guard let updatedValue = Self.sqlValue(forEditedString: newValue, columnInfo: columnInfo[columnIndex], connection: connection) else { return }

        if rows[row].isNew {
            saveNewContentRow(row: row, editedColumnIndex: columnIndex, updatedValue: updatedValue, connection: connection)
            return
        }

        guard let whereClause = Self.rowIdentityWhereClause(for: oldRowValues, columnInfo: columnInfo, connection: connection) else {
            statusLabel.stringValue = NSLocalizedString("Cannot edit row without identifiable columns", comment: "lightweight content edit no identity")
            return
        }

        let tableReference = "\(Self.backtickQuoted(database)).\(Self.backtickQuoted(table))"
        let countQuery = "SELECT COUNT(1) FROM \(tableReference) WHERE \(whereClause)"
        let updateQuery = "UPDATE \(tableReference) SET \(Self.backtickQuoted(columnName)) = \(updatedValue.sql) WHERE \(whereClause)"
        let refreshQuery = "SELECT \(Self.backtickQuoted(columnName)) FROM \(tableReference) WHERE \(whereClause) LIMIT 1"
        let reloadAfterEdit = UserDefaults.standard.bool(forKey: SPReloadAfterEditingRow)
        guard confirmQueryWarningIfNeeded(updateQuery) else {
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: columnIndex))
            return
        }

        statusLabel.stringValue = NSLocalizedString("Saving cell...", comment: "lightweight content saving cell")
        isLoading = true
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            _ = connection.selectDatabase(self.database)
            let matchingRows = SALightweightResultGrid.matchingRowCount(for: countQuery, connection: connection)
            let error = connection.queryErrored() ? connection.lastErrorMessage() : nil
            if error == nil, matchingRows == 1 {
                _ = connection.queryString(updateQuery)
            }
            let updateError = connection.queryErrored() ? connection.lastErrorMessage() : error
            var refreshedValue: ContentValue?
            if updateError == nil, matchingRows == 1, updatedValue.requiresReload, !reloadAfterEdit {
                let result = connection.queryString(refreshQuery)
                result?.defaultRowReturnType = SPMySQLResultRowAsArray
                if !connection.queryErrored(),
                   let row = result?.getRowAsArray(),
                   !row.isEmpty {
                    refreshedValue = Self.contentValue(for: row.first ?? nil)
                }
            }

            DispatchQueue.main.async {
                self.isLoading = false

                if let updateError = updateError, !updateError.isEmpty {
                    self.statusLabel.stringValue = updateError
                    self.updateControls()
                    self.reloadCell(row: row, columnIndex: columnIndex)
                    return
                }

                guard matchingRows == 1 else {
                    self.statusLabel.stringValue = NSLocalizedString("Cannot edit row without identifying exactly one matching row", comment: "lightweight content edit no unique row")
                    self.updateControls()
                    self.reloadCell(row: row, columnIndex: columnIndex)
                    return
                }

                if reloadAfterEdit || (updatedValue.requiresReload && refreshedValue == nil) {
                    self.invalidateCurrentContentCache()
                    self.loadCurrentPage()
                    return
                }

                let localValue = refreshedValue ?? updatedValue.localValue
                self.rows[row].values[columnIndex] = localValue
                self.rows[row].originalValues[columnIndex] = localValue
                self.displayCache.invalidate(row: row, column: columnIndex)
                self.tableContentDidChange?()

                self.updateStatus()
                self.updateControls()
                self.reloadCell(row: row, columnIndex: columnIndex)
                self.cacheCurrentContentState()
            }
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateStatus()
        updateControls()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === tableView else { return false }
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        let row = tableView.editedRow
        let column = tableView.editedColumn
        guard row >= 0, row < rows.count else { return false }

        tableView.abortEditing()
        if rows[row].isNew {
            cancelNewContentRow(row)
            return true
        }

        if column >= 0,
           column < tableView.numberOfColumns,
           let columnIndex = Int(tableView.tableColumns[column].identifier.rawValue) {
            reloadCell(row: row, columnIndex: columnIndex)
        }
        tableView.window?.makeFirstResponder(tableView)
        return true
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        guard let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        saveWidth(for: tableColumn)
    }

    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        guard tableView === self.tableView,
              column >= 0,
              column < tableView.tableColumns.count,
              let columnIndex = Int(tableView.tableColumns[column].identifier.rawValue),
              columnIndex < columnInfo.count else { return 0 }

        clearSavedWidth(for: columnInfo[columnIndex].name)
        return SALightweightResultGrid.sizeToFitWidthOfColumn(in: tableView,
                                                              displayColumn: column,
                                                              visibleRows: visibleRowsForAutosizing(maxRows: 128),
                                                              isEnumColumn: columnInfo[columnIndex].typeGrouping == "enum") { [weak self] row, columnIndex in
            guard let self = self,
                  row < self.rows.count,
                  columnIndex < self.rows[row].values.count else { return "" }
            return self.displayValue(row: row, column: columnIndex)
        }
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard row >= 0,
              row < rows.count,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].values.count else { return }

        switch rows[row].values[columnIndex] {
        case .null, .notLoaded:
            SALightweightResultGrid.configureDisplayCell(cell, isNullOrPlaceholder: true)
        case .object:
            SALightweightResultGrid.configureDisplayCell(cell, isNullOrPlaceholder: false)
        }
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard !isLoading,
              !isRestoringCachedContent,
              let columnIndex = Int(tableColumn.identifier.rawValue),
              columnIndex < columns.count else { return }

        let clickedColumn = columns[columnIndex]
        let shiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        if sortColumn == clickedColumn {
            sortAscending.toggle()
        } else {
            sortColumn = clickedColumn
            sortAscending = !shiftPressed
        }
        applySortDescriptorsFromCurrentState()
        pageIndex = 0
        storeCurrentRuleFilterState()
        sessionStateDidChange?()
        invalidateCurrentContentCache()
        loadCurrentPage(preservingColumns: true)
    }

    func rebuildDisplayValues() {
        displayCache.invalidateAll()
        columnWidthCache.invalidateAll()
    }
}

extension SALightweightContentViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }

        switch action {
        case #selector(copySelectedContentRows(_:)):
            return canCopySelectedContentRows(menuItem)

        case #selector(copySelectedContentRowsAsSQL(_:)):
            return canCopySelectedContentRows(menuItem)

        case #selector(exportContentResultAsCSV(_:)), #selector(exportContentResultAsXML(_:)):
            return !isLoading && !rows.isEmpty

        case #selector(removeRow(_:)), #selector(deleteRows(_:)), #selector(deleteBackward(_:)), #selector(deleteForward(_:)):
            menuItem.title = tableView.numberOfSelectedRows > 1
                ? NSLocalizedString("Delete Rows", comment: "delete rows menu item plural")
                : NSLocalizedString("Delete Row", comment: "delete row menu item singular")
            return canModifyRows && tableView.numberOfSelectedRows > 0

        case #selector(duplicateRow(_:)):
            let selectedRow = tableView.selectedRow
            let selectedRowIsNew = selectedRow >= 0 && selectedRow < rows.count && rows[selectedRow].isNew
            return canModifyRows && tableView.numberOfSelectedRows == 1 && !selectedRowIsNew

        case #selector(addRow(_:)):
            return canModifyRows

        case #selector(reloadContent(_:)):
            return !isLoading

        default:
            return true
        }
    }
}

extension SALightweightContentViewController: SALightweightResultGridTableViewDelegate {
    func resultGridTableViewCopyRows(_ sender: Any?) {
        copySelectedContentRows(sender)
    }

    func resultGridTableViewCopyRowsAsSQL(_ sender: Any?) {
        copySelectedContentRowsAsSQL(sender)
    }

    func resultGridTableView(_ tableView: NSTableView, canCopyRowsFor item: NSValidatedUserInterfaceItem) -> Bool {
        return canCopySelectedContentRows(item as? NSMenuItem)
    }

    func resultGridTableViewPrepareContextMenu(_ tableView: NSTableView, for event: NSEvent) {
        prepareContentContextMenu(for: event)
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
