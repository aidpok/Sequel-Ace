//
//  SALightweightQueryViewController.swift
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
import UniformTypeIdentifiers

@objcMembers
private final class SALightweightQueryFavoriteDocumentProxy: NSObject {
    weak var queryController: SALightweightQueryViewController?

    init(queryController: SALightweightQueryViewController) {
        self.queryController = queryController
    }

    var fileURL: URL? {
        return queryController?.documentURLForLegacyQueryConsumers
    }

    var isUntitled: Bool {
        return queryController?.isUntitledQueryDocument ?? true
    }

    var customQueryInstance: Any? {
        return queryController
    }
}

private final class SALightweightMenuSearchFieldView: NSView {
    private let searchField: NSSearchField
    private let searchFrame = NSRect(x: 20, y: 1, width: 176, height: 19)

    init(searchField: NSSearchField) {
        self.searchField = searchField
        super.init(frame: NSRect(x: 0, y: 0, width: 217, height: 20))
        autoresizingMask = [.maxXMargin, .minYMargin]
        addSubview(searchField)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        searchField.frame = searchFrame
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.makeFirstResponder(self.searchField)
        }
    }
}

@objcMembers
private final class SALightweightQueryTablesListProxy: NSObject {
    private(set) var selectedDatabase: String?
    private(set) var tableName: String?
    private(set) var allTableAndViewNames: [String] = []
    private(set) var allTableNames: [String] = []
    private(set) var allViewNames: [String] = []
    private(set) var allProcedureNames: [String] = []
    private(set) var allFunctionNames: [String] = []
    private(set) var allDatabaseNames: [String] = []
    private(set) var allSystemDatabaseNames: [String] = []
    private(set) var allFieldNames: [String] = []

    func update(database: String?,
                table: String?,
                databases: [String],
                tables: [String],
                tableTypes: [String: SALightweightTableObjectType],
                fieldNames: [String]) {
        selectedDatabase = database
        tableName = table
        allTableNames = tables.filter { (tableTypes[$0] ?? .table) == .table }
        allViewNames = tables.filter { tableTypes[$0] == .view }
        allProcedureNames = tables.filter { tableTypes[$0] == .procedure }
        allFunctionNames = tables.filter { tableTypes[$0] == .function }
        allTableAndViewNames = allTableNames + allViewNames
        updateFieldNames(fieldNames)

        let partition = SADatabaseListManager.partition(databases: databases)
        allDatabaseNames = partition.userDatabases
        allSystemDatabaseNames = partition.systemDatabases
    }

    func updateFieldNames(_ fieldNames: [String]) {
        allFieldNames = fieldNames
    }

    func selectedTableAndViewNames() -> [String] {
        guard let tableName,
              allTableAndViewNames.contains(tableName) else { return [] }

        return [tableName]
    }
}

@objcMembers
final class SALightweightQueryViewController: NSViewController {

    struct QueryResult {
        let columnDefinitions: [NSDictionary]
        let rows: [[Any]]
        let affectedRows: UInt64
        let executionTime: TimeInterval
        let fatalError: String?
        let errorText: String?
        let firstErrorQueryNumber: Int?
        let executedQuery: String
        let resultQuery: String
        let lastErrorID: UInt
        let queriesRun: Int
        let truncated: Bool
        var wasCancelled = false
    }

    private enum MultiQueryErrorChoice {
        case runAll
        case continueQueries
        case stopQueries
    }

    private struct ResultColumnOrigin {
        let database: String
        let table: String
        let column: String
    }

    private struct CellUpdate {
        let countQuery: String
        let updateQuery: String
        let refreshQuery: String?
        let fallbackCountQuery: String?
        let fallbackUpdateQuery: String?
        let fallbackRefreshQuery: String?
        let localValue: Any
        let requiresReload: Bool
    }

    private struct ResultGridViewState {
        let selectedRows: IndexSet
        let firstVisibleRow: Int?
        let columnDefinitions: [NSDictionary]
        let rows: [[Any]]
        let lastExecutedQuery: String
        let lastResultQuery: String
    }

    private weak var connection: SPMySQLConnection?
    private var documentURL: URL?
    private var database = ""
    private var table: String?
    private var columnDefinitions: [NSDictionary] = []
    private var rows: [[Any]] = []
    private let displayCache = SALightweightResultGridDisplayCache()
    private let columnWidthCache = SALightweightResultGridColumnWidthCache()
    private var lastExecutedQuery = ""
    private var lastResultQuery = ""
    private var queryToken = UUID()
    private var isRunning = false
    private var isCancellationRequested = false
    private var runningQueryCount = 0
    private var isApplyingProgrammaticQueryText = false
    private var editorWasConfigured = false
    private var didInstallObservers = false
    private var preferenceObserver: SALightweightPreferenceObserver?
    private var isApplyingProgrammaticColumnWidths = false
    private let autosizeCoordinator = SALightweightResultGridAutosizeCoordinator()
    private var displayedColumnSignature: [String] = []
    private var isApplyingQuerySort = false
    private var querySortColumnIndex: Int?
    private var querySortAscending = true
    private var pendingResultGridViewState: ResultGridViewState?
    private var pendingSortFailureRestore: (columnIndex: Int?, ascending: Bool)?
    private var primaryKeyColumnCache: [String: Set<String>] = [:]
    private var bracketHighlighter: SPBracketHighlighter?
    private let helpViewerClient = SPHelpViewerClient()
    private lazy var fieldEditor = SPFieldEditorController()
    private var favoritesManager: SPQueryFavoriteManager?
    private var fieldEditorTextSelectedRange = NSRange(location: 0, length: 0)
    private var isFieldEditorPresented = false
    private lazy var favoriteDocumentProxy = SALightweightQueryFavoriteDocumentProxy(queryController: self)
    private let completionTablesListProxy = SALightweightQueryTablesListProxy()
    private let maxDisplayedRows = 10_000
    private let initialQueryRowPublishSize = 40
    private let remainingQueryRowPublishSize = 1_000
    private let bundleBlobHandlingInclude = 2
    private let bundleBlobHandlingFileReference = 3
    private let bundleBlobHandlingImageFileReference = 4
    private var baseStatusText = NSLocalizedString("Ready", comment: "lightweight query ready status")
    private var resultColumnWidths: [String: CGFloat] = [:]
    private static let observedPreferenceKeys = [
        SPDisplayTableViewVerticalGridlines,
        SPGlobalFontSettings,
        SPDisplayTableViewColumnTypes,
        SPDisplayBinaryDataAsHex,
        SPNullValue,
        SPCustomQueryAutoIndent,
        SPCustomQueryAutoPairCharacters,
        SPCustomQueryAutoComplete,
        SPCustomQueryAutoUppercaseKeywords,
        SPCustomQueryUpdateAutoHelp,
        SPCustomQueryEnableBracketHighlighting
    ]

    private var currentHistoryOffsetIndex = -1
    private var historyItemWasJustInserted = false
    var textViewWasChanged = false
    var sessionState = SALightweightSessionState()
    var sessionStateDidChange: (() -> Void)?
    private var shouldPersistCurrentQueryText = false
    private var currentQueryTableKey: SALightweightSessionState.TableKey?
    private var currentQueryBeforeCaret = false
    var currentQueryRange = NSRange(location: 0, length: 0)
    private var currentQueryRanges: [NSRange] = []
    private var didCacheCurrentQueryRanges = false
    var documentURLForLegacyQueryConsumers: URL? { documentURL }
    var isUntitledQueryDocument: Bool {
        guard let documentURL else { return true }
        return documentURL.absoluteString.hasPrefix(NSLocalizedString("Untitled", comment: "Title of a new Sequel Ace Document"))
    }
    var queryExecutionWillBegin: (() -> Void)?
    var queryExecutionDidEnd: (() -> Void)?
    var tableDocumentInstance: Any { favoriteDocumentProxy }
    var tablesListInstance: Any { completionTablesListProxy }
    var textView: SPTextView { queryTextView }

    private func prewarmFieldEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, self.isViewLoaded else { return }
            _ = self.fieldEditor
        }
    }

    private let queryInfoPaneSplitView = SPSplitView(frame: .zero)
    private let queryMainView = NSView(frame: .zero)
    private let queryEditorSplitView = SPSplitView(frame: .zero)
    private let queryScrollView = NSScrollView(frame: .zero)
    private let resultContainerView = NSView(frame: .zero)
    private let resultScrollView = NSScrollView(frame: .zero)
    private let controlBarView = NSView(frame: .zero)
    private let bottomBarView = NSView(frame: .zero)
    private let infoPaneView = NSView(frame: .zero)
    private let infoTextScrollView = NSScrollView(frame: .zero)
    private var queryProgressWindow: NSWindow?
    private var queryProgressView: NSBox?
    private var queryProgressIndicator: YRKSpinningProgressIndicator?
    private var queryProgressDescriptionLabel: NSTextField?
    private var queryProgressDurationLabel: NSTextField?
    private var queryProgressCancelButton: NSButton?
    private var queryProgressFadeTimer: Timer?
    private var queryProgressDurationTimer: Timer?
    private var queryProgressFadeStartDate: Date?
    private var queryProgressStartDate: Date?
    private var didSetInitialQueryEditorSplitPosition = false
    private var didSetInitialQueryInfoSplitPosition = false
    private static let queryEditorInitialHeightRatio: CGFloat = 142.0 / 387.0
    private static let queryEditorMinimumInitialHeight: CGFloat = 143.0
    private static let queryEditorMaximumInitialHeight: CGFloat = 360.0
    private let queryMenuDynamicStartIndex = 7
    private var favoritesSearchMenuItem: NSMenuItem?
    private var historySearchMenuItem: NSMenuItem?
    private var favoritesMenu: NSMenu?
    private var historyMenu: NSMenu?
    private lazy var actionButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 35, height: 25), pullsDown: true)
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryPushIn)
        button.image = NSImage(named: NSImage.actionTemplateName)
        button.imagePosition = .imageOnly
        button.cell?.controlSize = .small
        button.menu?.autoenablesItems = false
        return button
    }()

    private lazy var historySearchField: NSSearchField = {
        let field = makeMenuSearchField(placeholder: NSLocalizedString("Filter", comment: "query history filter placeholder"),
                                        recentsAutosaveName: "SPQueryHistorySearchField")
        field.target = self
        field.action = #selector(filterQueryHistory(_:))
        return field
    }()

    private lazy var favoriteSearchField: NSSearchField = {
        let field = makeMenuSearchField(placeholder: NSLocalizedString("Filter", comment: "query favorite filter placeholder"),
                                        recentsAutosaveName: "SPQueryFavoriteSearchField")
        field.target = self
        field.action = #selector(filterQueryFavorites(_:))
        return field
    }()

    private lazy var historySearchFieldView: NSView = {
        makeMenuSearchFieldView(for: historySearchField)
    }()

    private lazy var favoriteSearchFieldView: NSView = {
        makeMenuSearchFieldView(for: favoriteSearchField)
    }()

    private lazy var queryTextView: SPTextView = {
        let textView = SPTextView(frame: .zero)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.usesFindPanel = true
        textView.isIncrementalSearchingEnabled = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        return textView
    }()

    private lazy var tableView: SALightweightResultGridTableView = {
        let tableView = SALightweightResultGridTableView(frame: .zero)
        tableView.identifier = NSUserInterfaceItemIdentifier("LightweightQueryTable")
        tableView.resultGridDelegate = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true
        tableView.allowsExpansionToolTips = false
        SALightweightResultGrid.configureTableView(tableView,
                                                   rowHeight: SALightweightResultGrid.rowHeight(for: UserDefaults.getFont()),
                                                   columnAutoresizingStyle: .lastColumnOnlyAutoresizingStyle)
        return tableView
    }()

    private lazy var favoritesButton: NSButton = {
        let button = NSButton(frame: .zero)
        button.setButtonType(.momentaryPushIn)
        button.title = NSLocalizedString("Query Favorites", comment: "query favorites button title")
        button.target = self
        button.action = #selector(showQueryFavoritesMenu(_:))
        button.toolTip = NSLocalizedString("Choose a favorite from the menu or save queries to the favorites (⌥⌘F)", comment: "query favorites tooltip")
        button.keyEquivalent = "f"
        button.keyEquivalentModifierMask = [.option, .command]
        button.bezelStyle = .recessed
        button.cell?.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.lineBreakMode = .byTruncatingTail
        return button
    }()

    private lazy var historyButton: NSButton = {
        let button = NSButton(frame: .zero)
        button.setButtonType(.momentaryPushIn)
        button.title = NSLocalizedString("Query History", comment: "query history button title")
        button.target = self
        button.action = #selector(showQueryHistoryMenu(_:))
        button.toolTip = NSLocalizedString("Choose a query from your recent queries (⌥⌘Y)", comment: "query history tooltip")
        button.keyEquivalent = "y"
        button.keyEquivalentModifierMask = [.option, .command]
        button.bezelStyle = .recessed
        button.cell?.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.lineBreakMode = .byTruncatingTail
        return button
    }()

    private lazy var runButton: SPComboPopupButton = {
        let button = SPComboPopupButton(frame: NSRect(x: 0, y: 0, width: 180, height: 22), pullsDown: true)
        button.target = self
        button.action = #selector(runPrimaryQuery(_:))
        button.keyEquivalent = "r"
        button.keyEquivalentModifierMask = [.command]
        button.cell?.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.cell?.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    private lazy var statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: NSLocalizedString("Ready", comment: "lightweight query ready status"))
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private lazy var queryInfoButton: NSButton = {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 25, height: 25))
        button.bezelStyle = .smallSquare
        button.image = NSImage(named: NSImage.quickLookTemplateName)
        button.imagePosition = .imageOnly
        button.setButtonType(.pushOnPushOff)
        button.target = self
        button.action = #selector(toggleQueryInfoPane(_:))
        button.keyEquivalent = "a"
        button.keyEquivalentModifierMask = [.option, .command]
        button.toolTip = NSLocalizedString("Toggle the visibility of the Query Information Pane", comment: "query info pane toggle tooltip")
        return button
    }()

    private lazy var exportButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 35, height: 25), pullsDown: true)
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryPushIn)
        button.image = NSImage(named: NSImage.actionTemplateName)
        button.imagePosition = .imageOnly
        button.cell?.controlSize = .small
        button.menu?.autoenablesItems = false
        return button
    }()

    private lazy var infoTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: NSLocalizedString("Query Status", comment: "lightweight query info pane status title"))
        label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor
        return label
    }()

    private lazy var infoTextView: NSTextView = {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        textView.textColor = .labelColor
        textView.string = NSLocalizedString("There were no errors.", comment: "lightweight query info pane no errors text")
        return textView
    }()

    override func loadView() {
        let rootView = NSView(frame: .zero)

        queryInfoPaneSplitView.dividerStyle = .thin
        queryInfoPaneSplitView.isVertical = false
        queryInfoPaneSplitView.addSubview(queryMainView)
        queryInfoPaneSplitView.addSubview(infoPaneView)

        queryEditorSplitView.dividerStyle = .thin
        queryEditorSplitView.isVertical = false
        queryEditorSplitView.addSubview(queryScrollView)
        queryEditorSplitView.addSubview(resultContainerView)

        queryScrollView.borderType = .noBorder
        queryScrollView.focusRingType = .none
        queryScrollView.hasVerticalScroller = true
        queryScrollView.hasHorizontalScroller = false
        queryScrollView.autohidesScrollers = true
        queryScrollView.contentView.drawsBackground = false
        queryScrollView.documentView = queryTextView

        SALightweightResultGrid.configureResultScrollView(resultScrollView)
        resultScrollView.documentView = tableView
        resultScrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(resultGridBoundsDidChange(_:)), name: NSView.boundsDidChangeNotification, object: resultScrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(resultGridWillStartLiveScroll(_:)), name: NSScrollView.willStartLiveScrollNotification, object: resultScrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(resultGridDidEndLiveScroll(_:)), name: NSScrollView.didEndLiveScrollNotification, object: resultScrollView)

        infoTextScrollView.borderType = .noBorder
        infoTextScrollView.hasVerticalScroller = true
        infoTextScrollView.hasHorizontalScroller = false
        infoTextScrollView.autohidesScrollers = true
        infoTextScrollView.documentView = infoTextView

        rootView.addSubview(queryInfoPaneSplitView)
        rootView.addSubview(bottomBarView)
        queryMainView.addSubview(queryEditorSplitView)
        resultContainerView.addSubview(controlBarView)
        resultContainerView.addSubview(resultScrollView)
        controlBarView.addSubview(actionButton)
        controlBarView.addSubview(favoritesButton)
        controlBarView.addSubview(historyButton)
        controlBarView.addSubview(runButton)
        bottomBarView.addSubview(queryInfoButton)
        bottomBarView.addSubview(exportButton)
        bottomBarView.addSubview(statusLabel)
        infoPaneView.addSubview(infoTitleLabel)
        infoPaneView.addSubview(infoTextScrollView)

        queryInfoPaneSplitView.translatesAutoresizingMaskIntoConstraints = false
        queryEditorSplitView.translatesAutoresizingMaskIntoConstraints = false
        resultScrollView.translatesAutoresizingMaskIntoConstraints = false
        controlBarView.translatesAutoresizingMaskIntoConstraints = false
        bottomBarView.translatesAutoresizingMaskIntoConstraints = false
        infoTextScrollView.translatesAutoresizingMaskIntoConstraints = false
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        favoritesButton.translatesAutoresizingMaskIntoConstraints = false
        historyButton.translatesAutoresizingMaskIntoConstraints = false
        runButton.translatesAutoresizingMaskIntoConstraints = false
        queryInfoButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        infoTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            queryInfoPaneSplitView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 7),
            queryInfoPaneSplitView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -4),
            queryInfoPaneSplitView.topAnchor.constraint(equalTo: rootView.topAnchor),
            queryInfoPaneSplitView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor),

            queryEditorSplitView.leadingAnchor.constraint(equalTo: queryMainView.leadingAnchor),
            queryEditorSplitView.trailingAnchor.constraint(equalTo: queryMainView.trailingAnchor),
            queryEditorSplitView.topAnchor.constraint(equalTo: queryMainView.topAnchor),
            queryEditorSplitView.bottomAnchor.constraint(equalTo: queryMainView.bottomAnchor),

            controlBarView.leadingAnchor.constraint(equalTo: resultContainerView.leadingAnchor),
            controlBarView.trailingAnchor.constraint(equalTo: resultContainerView.trailingAnchor),
            controlBarView.topAnchor.constraint(equalTo: resultContainerView.topAnchor),
            controlBarView.heightAnchor.constraint(equalToConstant: 25),

            resultScrollView.leadingAnchor.constraint(equalTo: resultContainerView.leadingAnchor),
            resultScrollView.trailingAnchor.constraint(equalTo: resultContainerView.trailingAnchor),
            resultScrollView.topAnchor.constraint(equalTo: controlBarView.bottomAnchor),
            resultScrollView.bottomAnchor.constraint(equalTo: resultContainerView.bottomAnchor),

            bottomBarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            bottomBarView.heightAnchor.constraint(equalToConstant: 33),

            actionButton.leadingAnchor.constraint(equalTo: controlBarView.leadingAnchor),
            actionButton.topAnchor.constraint(equalTo: controlBarView.topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: controlBarView.bottomAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 35),

            favoritesButton.leadingAnchor.constraint(equalTo: controlBarView.leadingAnchor, constant: 40),
            favoritesButton.topAnchor.constraint(equalTo: controlBarView.topAnchor),
            favoritesButton.bottomAnchor.constraint(equalTo: controlBarView.bottomAnchor),
            favoritesButton.widthAnchor.constraint(equalToConstant: 130),

            historyButton.leadingAnchor.constraint(equalTo: controlBarView.leadingAnchor, constant: 175),
            historyButton.topAnchor.constraint(equalTo: controlBarView.topAnchor),
            historyButton.bottomAnchor.constraint(equalTo: controlBarView.bottomAnchor),
            historyButton.widthAnchor.constraint(equalToConstant: 145),

            runButton.trailingAnchor.constraint(equalTo: controlBarView.trailingAnchor, constant: -8),
            runButton.centerYAnchor.constraint(equalTo: controlBarView.centerYAnchor),
            runButton.widthAnchor.constraint(equalToConstant: 180),

            queryInfoButton.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: 10),
            queryInfoButton.topAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 4),
            queryInfoButton.widthAnchor.constraint(equalToConstant: 25),
            queryInfoButton.heightAnchor.constraint(equalToConstant: 25),

            exportButton.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: 35),
            exportButton.topAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 4),
            exportButton.widthAnchor.constraint(equalToConstant: 35),
            exportButton.heightAnchor.constraint(equalToConstant: 25),

            statusLabel.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: 103),
            statusLabel.centerYAnchor.constraint(equalTo: queryInfoButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: bottomBarView.trailingAnchor, constant: -17),

            infoTitleLabel.leadingAnchor.constraint(equalTo: infoPaneView.leadingAnchor, constant: 15),
            infoTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: infoPaneView.trailingAnchor, constant: -15),
            infoTitleLabel.topAnchor.constraint(equalTo: infoPaneView.topAnchor, constant: 12),

            infoTextScrollView.leadingAnchor.constraint(equalTo: infoPaneView.leadingAnchor, constant: 12),
            infoTextScrollView.trailingAnchor.constraint(equalTo: infoPaneView.trailingAnchor, constant: -12),
            infoTextScrollView.topAnchor.constraint(equalTo: infoTitleLabel.bottomAnchor, constant: 7),
            infoTextScrollView.bottomAnchor.constraint(equalTo: infoPaneView.bottomAnchor, constant: -12)
        ])

        configureEditorIfNeeded()
        configureControlsIfNeeded()
        installObserversIfNeeded()
        updateAppearanceFromPreferences()
        rebuildMenus()
        configureExportMenu()
        configureResultContextMenu()
        updateControls()
        view = rootView
        prewarmFieldEditor()
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        guard editorWasConfigured else { return }

        if !didSetInitialQueryEditorSplitPosition && queryEditorSplitView.bounds.height > 0 {
            let availableHeight = max(0, queryEditorSplitView.bounds.height - queryEditorSplitView.dividerThickness)
            let proportionalHeight = availableHeight * Self.queryEditorInitialHeightRatio
            let clampedHeight = min(Self.queryEditorMaximumInitialHeight, max(Self.queryEditorMinimumInitialHeight, proportionalHeight))
            let initialDividerPosition = min(availableHeight, clampedHeight)
            queryEditorSplitView.setPosition(initialDividerPosition, ofDividerAt: 0)
            didSetInitialQueryEditorSplitPosition = true
        }

        if !didSetInitialQueryInfoSplitPosition && queryInfoPaneSplitView.bounds.height > 0 {
            setQueryInfoPaneVisible(false)
            didSetInitialQueryInfoSplitPosition = true
        }

        let contentSize = queryScrollView.contentSize
        queryTextView.frame = NSRect(origin: .zero, size: contentSize)
        queryTextView.minSize = contentSize
        queryTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        queryTextView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    }

    deinit {
        autosizeCoordinator.cancel()
        hideQueryProgressPanel()
        NotificationCenter.default.removeObserver(self)
        preferenceObserver?.invalidate()
        if let documentURL = documentURL {
            SPQueryController.shared().removeRegisteredDocument(withFileURL: documentURL)
        }
    }

    private func preferenceDidChange(_ keyPath: String) {
        switch keyPath {
        case SPDisplayTableViewVerticalGridlines:
            tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
            tableView.setNeedsDisplay(tableView.visibleRect)
        case SPGlobalFontSettings:
            updateAppearanceFromPreferences()
        case SPDisplayTableViewColumnTypes:
            rebuildColumns()
        case SPDisplayBinaryDataAsHex,
             SPNullValue:
            rebuildDisplayRows()
            SALightweightResultGrid.reloadVisibleCells(in: tableView, columnBuffer: SALightweightResultGrid.autosizeColumnBuffer)
            autosizeResultColumns()
        case SPCustomQueryAutoIndent,
             SPCustomQueryAutoPairCharacters,
             SPCustomQueryAutoComplete,
             SPCustomQueryAutoUppercaseKeywords,
             SPCustomQueryUpdateAutoHelp,
             SPCustomQueryEnableBracketHighlighting:
            applyEditorPreferences()
            rebuildMenus()
            updateActionMenuState()
        default:
            break
        }
    }

    func loadQuery(database: String?,
                   table: String?,
                   connection: SPMySQLConnection,
                   databases: [String] = [],
                   tables: [String] = [],
                   tableTypes: [String: SALightweightTableObjectType] = [:],
                   fieldNames: [String] = []) {
        let queryKey = SALightweightSessionState.queryKey(database: database, table: nil, connection: connection)
        let legacyTableKey = SALightweightSessionState.tableKey(database: database, table: table, connection: connection)
        saveCurrentQueryTextIfNeeded()

        self.connection = connection
        self.database = database ?? ""
        self.table = table
        completionTablesListProxy.update(database: database,
                                         table: table,
                                         databases: databases,
                                         tables: tables,
                                         tableTypes: tableTypes,
                                         fieldNames: fieldNames)

        if documentURL == nil {
            documentURL = SPQueryController.shared().registerDocument(withFileURL: nil, andContextInfo: nil)
        }

        configureEditorIfNeeded()
        queryTextView.setConnection(connection, withVersion: Int(connection.serverMajorVersion()))
        helpViewerClient.setConnection(connection)

        if currentQueryTableKey != queryKey || queryTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            currentQueryTableKey = queryKey
            restoreUserQueryText(for: queryKey, fallbackTableKey: legacyTableKey)
        }

        updateCurrentQueryRange()
        rebuildMenus()
        updateControls()
    }

    func doPerformQueryService(_ query: String) {
        doPerformLoadQueryService(query)
        runQueries(splitQueries(in: queryTextView.string))
    }

    func doPerformLoadQueryService(_ query: String) {
        replaceEditorText(query)
    }

    func saveCurrentSessionState() {
        saveCurrentQueryTextIfNeeded()
    }
}

private extension SALightweightQueryViewController {
    func showQueryProgressPanel(description: String, cancelButtonTitle: String) {
        guard let parentWindow = view.window else { return }

        queryProgressFadeTimer?.invalidate()
        queryProgressDurationTimer?.invalidate()

        let progressWindow = queryProgressWindow ?? makeQueryProgressWindow()
        queryProgressWindow = progressWindow
        if progressWindow.parent == nil {
            parentWindow.addChildWindow(progressWindow, ordered: .above)
        }
        progressWindow.orderFront(nil)

        queryProgressStartDate = Date()
        queryProgressFadeStartDate = Date()
        queryProgressCancelButton?.isEnabled = true
        setQueryProgressCancelButtonTitle(cancelButtonTitle)
        setQueryProgressDescription(description)
        updateQueryProgressDuration()
        centerQueryProgressWindow()
        progressWindow.alphaValue = 0
        queryProgressIndicator?.startAnimation(self)

        queryProgressFadeTimer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(fadeInQueryProgressPanel(_:)), userInfo: nil, repeats: true)
        queryProgressDurationTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateQueryProgressDurationTimerFired(_:)), userInfo: nil, repeats: true)
    }

    func hideQueryProgressPanel() {
        queryProgressFadeTimer?.invalidate()
        queryProgressFadeTimer = nil
        queryProgressDurationTimer?.invalidate()
        queryProgressDurationTimer = nil
        queryProgressFadeStartDate = nil
        queryProgressStartDate = nil
        queryProgressIndicator?.stopAnimation(self)
        queryProgressWindow?.alphaValue = 0
        queryProgressWindow?.orderOut(self)
        if let queryProgressWindow, let parent = queryProgressWindow.parent {
            parent.removeChildWindow(queryProgressWindow)
        }
    }

    func makeQueryProgressWindow() -> NSWindow {
        let layer = NSBox(frame: NSRect(x: 0, y: 0, width: 437, height: 90))
        layer.boxType = .custom
        layer.borderType = .noBorder
        layer.titlePosition = .noTitle
        layer.isTransparent = false
        layer.fillColor = NSColor(calibratedWhite: 0, alpha: 0.7)
        layer.borderColor = NSColor(calibratedWhite: 0, alpha: 0.42)
        layer.cornerRadius = 15

        let innerBox = NSBox(frame: .zero)
        innerBox.boxType = .custom
        innerBox.borderType = .noBorder
        innerBox.titlePosition = .noTitle
        innerBox.fillColor = NSColor(calibratedWhite: 0.2540322542, alpha: 0.8)
        innerBox.borderColor = NSColor(calibratedWhite: 0, alpha: 0.42)
        innerBox.cornerRadius = 9

        let indicator = YRKSpinningProgressIndicator(frame: .zero)
        indicator.setForeColor(.white)
        indicator.shadow = queryProgressTextShadow(blurRadius: 1)

        let descriptionLabel = NSTextField(labelWithString: "")
        descriptionLabel.attributedStringValue = queryProgressAttributedString("")
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.maximumNumberOfLines = 1

        let durationLabel = NSTextField(labelWithString: "")
        durationLabel.attributedStringValue = queryProgressAttributedString("")

        let cancelButton = NSButton(title: NSLocalizedString("Cancel", comment: "cancel button"), target: self, action: #selector(cancelQueryProgressPanel(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "."
        cancelButton.keyEquivalentModifierMask = .command

        layer.contentView?.addSubview(innerBox)
        innerBox.contentView?.addSubview(indicator)
        innerBox.contentView?.addSubview(descriptionLabel)
        innerBox.contentView?.addSubview(durationLabel)
        innerBox.contentView?.addSubview(cancelButton)

        [innerBox, indicator, descriptionLabel, durationLabel, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        guard let layerContentView = layer.contentView,
              let innerContentView = innerBox.contentView else {
            return NSWindow(contentRect: layer.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        }

        NSLayoutConstraint.activate([
            innerBox.leadingAnchor.constraint(equalTo: layerContentView.leadingAnchor),
            innerBox.trailingAnchor.constraint(equalTo: layerContentView.trailingAnchor, constant: -1),
            innerBox.topAnchor.constraint(equalTo: layerContentView.topAnchor),
            innerBox.bottomAnchor.constraint(equalTo: layerContentView.bottomAnchor),

            indicator.leadingAnchor.constraint(equalTo: innerContentView.leadingAnchor, constant: 20),
            indicator.centerYAnchor.constraint(equalTo: innerContentView.centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 70),
            indicator.heightAnchor.constraint(equalToConstant: 70),

            descriptionLabel.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 10),
            descriptionLabel.trailingAnchor.constraint(equalTo: innerContentView.trailingAnchor, constant: -20),
            descriptionLabel.topAnchor.constraint(equalTo: innerContentView.topAnchor, constant: 11),

            durationLabel.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 10),
            durationLabel.bottomAnchor.constraint(equalTo: innerContentView.bottomAnchor, constant: -11),
            durationLabel.widthAnchor.constraint(equalToConstant: 180),

            cancelButton.leadingAnchor.constraint(equalTo: durationLabel.trailingAnchor, constant: 8),
            cancelButton.trailingAnchor.constraint(equalTo: innerContentView.trailingAnchor, constant: -20),
            cancelButton.bottomAnchor.constraint(equalTo: innerContentView.bottomAnchor, constant: -11),
            cancelButton.heightAnchor.constraint(equalToConstant: 19)
        ])

        queryProgressView = layer
        queryProgressIndicator = indicator
        queryProgressDescriptionLabel = descriptionLabel
        queryProgressDurationLabel = durationLabel
        queryProgressCancelButton = cancelButton

        let window = NSWindow(contentRect: layer.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.contentView = layer
        return window
    }

    func centerQueryProgressWindow() {
        guard let parentWindow = view.window, let queryProgressWindow else { return }

        let parentFrame = parentWindow.frame
        let progressFrame = queryProgressWindow.frame
        let origin = NSPoint(x: round(parentFrame.origin.x + parentFrame.width / 2 - progressFrame.width / 2),
                             y: round(parentFrame.origin.y + parentFrame.height / 2 - progressFrame.height / 2))
        queryProgressWindow.setFrameOrigin(origin)
    }

    func setQueryProgressDescription(_ description: String) {
        queryProgressDescriptionLabel?.attributedStringValue = queryProgressAttributedString(description)
    }

    func setQueryProgressCancelButtonTitle(_ title: String) {
        queryProgressCancelButton?.attributedTitle = NSAttributedString(string: title,
                                                                        attributes: [.foregroundColor: NSColor.white])
    }

    func updateQueryProgressDuration() {
        let duration = queryProgressStartDate.map { Date().timeIntervalSince($0) } ?? 0
        let durationString = DateComponentsFormatter.hourMinSecFormatter.string(from: duration) ?? "00:00"
        queryProgressDurationLabel?.attributedStringValue = queryProgressAttributedString(durationString)
    }

    func queryProgressAttributedString(_ string: String) -> NSAttributedString {
        return NSAttributedString(string: string,
                                  attributes: [.font: NSFont.boldSystemFont(ofSize: 13),
                                               .foregroundColor: NSColor.white,
                                               .shadow: queryProgressTextShadow(blurRadius: 3)])
    }

    func queryProgressTextShadow(blurRadius: CGFloat) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.75)
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = blurRadius
        return shadow
    }

    @objc func fadeInQueryProgressPanel(_ timer: Timer) {
        guard let startDate = queryProgressFadeStartDate, let queryProgressWindow else { return }

        let elapsed = Date().timeIntervalSince(startDate)
        guard elapsed >= 0.5 else { return }

        centerQueryProgressWindow()
        let alphaValue = min(1, CGFloat((elapsed - 0.5) / 0.6))
        queryProgressWindow.alphaValue = alphaValue
        if alphaValue >= 1 {
            queryProgressFadeTimer?.invalidate()
            queryProgressFadeTimer = nil
        }
    }

    @objc func updateQueryProgressDurationTimerFired(_ timer: Timer) {
        updateQueryProgressDuration()
    }

    @objc func cancelQueryProgressPanel(_ sender: Any?) {
        cancelRunningQuery()
    }

    func restoreUserQueryText(for tableKey: SALightweightSessionState.TableKey?, fallbackTableKey: SALightweightSessionState.TableKey?) {
        guard let restoredQueryText = tableKey.flatMap({ sessionState.queryState(for: $0)?.text })
            ?? fallbackTableKey.flatMap({ sessionState.queryState(for: $0)?.text }) else {
            replaceEditorText("", marksUserEdited: false)
            return
        }

        replaceEditorText(restoredQueryText, marksUserEdited: true)
        if let tableKey = tableKey {
            sessionState.setQueryText(restoredQueryText, for: tableKey)
        }
    }

    func saveCurrentQueryTextIfNeeded() {
        guard let currentQueryTableKey,
              shouldPersistCurrentQueryText else { return }

        sessionState.setQueryText(queryTextView.string, for: currentQueryTableKey)
    }

    func configureEditorIfNeeded() {
        guard !editorWasConfigured else { return }

        queryTextView.delegate = self
        queryTextView.setValue(queryScrollView, forKey: "scrollView")
        queryTextView.setValue(self, forKey: "customQueryInstance")
        queryTextView.setValue(completionTablesListProxy, forKey: "tablesListInstance")
        queryTextView.awakeFromNib()
        queryTextView.textContainerInset = NSSize(width: 4, height: 0)
        bracketHighlighter = SPBracketHighlighter(textView: queryTextView)
        applyEditorPreferences()
        queryTextView.frame = NSRect(origin: .zero, size: queryScrollView.contentSize)
        editorWasConfigured = true
    }

    func applyEditorPreferences() {
        queryTextView.setAutoindent(UserDefaults.standard.bool(forKey: SPCustomQueryAutoIndent))
        queryTextView.setAutopair(UserDefaults.standard.bool(forKey: SPCustomQueryAutoPairCharacters))
        queryTextView.setAutoComplete(UserDefaults.standard.bool(forKey: SPCustomQueryAutoComplete))
        queryTextView.setAutouppercaseKeywords(UserDefaults.standard.bool(forKey: SPCustomQueryAutoUppercaseKeywords))
        queryTextView.setAutohelp(UserDefaults.standard.bool(forKey: SPCustomQueryUpdateAutoHelp))
        bracketHighlighter?.enabled = UserDefaults.standard.bool(forKey: SPCustomQueryEnableBracketHighlighting)
    }

    func installObserversIfNeeded() {
        guard !didInstallObservers else { return }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(queryFavoritesHaveBeenUpdated(_:)),
                                               name: .SPQueryFavoritesHaveBeenUpdated,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(historyItemsHaveBeenUpdated(_:)),
                                               name: .SPHistoryItemsHaveBeenUpdated,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(helpWindowClosedByUser(_:)),
                                               name: NSNotification.Name("SPUserClosedHelpViewer"),
                                               object: helpViewerClient)
        preferenceObserver = SALightweightPreferenceObserver(keys: Self.observedPreferenceKeys) { [weak self] keyPath in
            self?.preferenceDidChange(keyPath)
        }
        preferenceObserver?.start()
        didInstallObservers = true
    }

    @objc func queryFavoritesHaveBeenUpdated(_ notification: Notification?) {
        rebuildFavoritesMenu()
    }

    @objc func historyItemsHaveBeenUpdated(_ notification: Notification?) {
        rebuildHistoryMenu()
    }

    @objc func helpWindowClosedByUser(_ notification: Notification?) {
        UserDefaults.standard.set(false, forKey: SPCustomQueryUpdateAutoHelp)
        queryTextView.setAutohelp(false)
        updateActionMenuState()
    }

    func updateAppearanceFromPreferences() {
        let tableFont = UserDefaults.getFont()
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = SALightweightResultGrid.rowHeight(for: tableFont)
        for column in tableView.tableColumns {
            (column.dataCell as? NSCell)?.font = tableFont
            column.headerCell.font = SALightweightResultGrid.headerFont(for: tableFont)
        }
        updateQueryInteractionInterface()
        rebuildColumns()
    }

    func configureControlsIfNeeded() {
        configureActionMenu()
        configureRunMenu()
    }

    func configureExportMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let placeholderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        placeholderItem.image = NSImage(named: NSImage.actionTemplateName)
        placeholderItem.isHidden = true
        menu.addItem(placeholderItem)

        let exportItem = NSMenuItem(title: NSLocalizedString("Export Result", comment: "export result menu item"), action: nil, keyEquivalent: "")
        let exportMenu = NSMenu()

        let csvItem = NSMenuItem(title: NSLocalizedString("As CSV file...", comment: "export result as csv menu item"),
                                 action: #selector(exportQueryResultAsCSV(_:)),
                                 keyEquivalent: "")
        csvItem.target = self
        csvItem.tag = 1
        exportMenu.addItem(csvItem)

        let xmlItem = NSMenuItem(title: NSLocalizedString("As XML file...", comment: "export result as xml menu item"),
                                 action: #selector(exportQueryResultAsXML(_:)),
                                 keyEquivalent: "")
        xmlItem.target = self
        xmlItem.tag = 2
        exportMenu.addItem(xmlItem)

        exportItem.submenu = exportMenu
        menu.addItem(exportItem)
        exportButton.menu = menu
    }

    func configureResultContextMenu() {
        tableView.menu = SALightweightResultGrid.contextMenu(target: self,
                                                             copyAction: #selector(copySelectedResultRows(_:)),
                                                             copySQLAction: #selector(copySelectedResultRowsAsSQL(_:)),
                                                             exportCSVAction: #selector(exportQueryResultAsCSV(_:)),
                                                             exportXMLAction: #selector(exportQueryResultAsXML(_:)),
                                                             copyCommentPrefix: "query",
                                                             exportCommentPrefix: "query")
    }

    func configureActionMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let actionPlaceholderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        actionPlaceholderItem.image = NSImage(named: NSImage.actionTemplateName)
        actionPlaceholderItem.isHidden = true
        menu.addItem(actionPlaceholderItem)

        let previousHistoryItem = NSMenuItem(title: NSLocalizedString("Previous Query from History", comment: "previous history menu item"),
                                             action: #selector(insertPreviousHistoryQuery(_:)),
                                             keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        previousHistoryItem.keyEquivalentModifierMask = [.control]
        previousHistoryItem.target = self
        previousHistoryItem.toolTip = NSLocalizedString("Replaces the current query by the previous one coming from the history.", comment: "previous history tooltip")
        menu.addItem(previousHistoryItem)

        let nextHistoryItem = NSMenuItem(title: NSLocalizedString("Next Query from History", comment: "next history menu item"),
                                         action: #selector(insertNextHistoryQuery(_:)),
                                         keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        nextHistoryItem.keyEquivalentModifierMask = [.control]
        nextHistoryItem.target = self
        nextHistoryItem.toolTip = NSLocalizedString("Replaces the current query by the next one coming from the history.", comment: "next history tooltip")
        menu.addItem(nextHistoryItem)

        let historyReplacesContentItem = NSMenuItem(title: NSLocalizedString("History Replaces Editor Content", comment: "history replaces editor content menu item"),
                                                    action: #selector(toggleHistoryReplacesContent(_:)),
                                                    keyEquivalent: "")
        historyReplacesContentItem.target = self
        menu.addItem(historyReplacesContentItem)

        menu.addItem(.separator())

        let favoriteReplacesContentItem = NSMenuItem(title: NSLocalizedString("Favorite Replaces Editor Content", comment: "favorite replaces editor content menu item"),
                                                     action: #selector(toggleFavoriteReplacesContent(_:)),
                                                     keyEquivalent: "")
        favoriteReplacesContentItem.target = self
        menu.addItem(favoriteReplacesContentItem)

        menu.addItem(.separator())

        let shiftRightItem = NSMenuItem(title: NSLocalizedString("Shift Right", comment: "shift right menu item"),
                                        action: #selector(shiftSelectionRight(_:)),
                                        keyEquivalent: "]")
        shiftRightItem.target = self
        menu.addItem(shiftRightItem)

        let shiftLeftItem = NSMenuItem(title: NSLocalizedString("Shift Left", comment: "shift left menu item"),
                                       action: #selector(shiftSelectionLeft(_:)),
                                       keyEquivalent: "[")
        shiftLeftItem.target = self
        menu.addItem(shiftLeftItem)

        let commentLineItem = NSMenuItem(title: NSLocalizedString("Comment Line", comment: "comment line menu item"),
                                         action: #selector(commentLineOrSelection(_:)),
                                         keyEquivalent: "/")
        commentLineItem.target = self
        menu.addItem(commentLineItem)

        let commentCurrentQueryItem = NSMenuItem(title: NSLocalizedString("Comment Current Query", comment: "comment current query menu item"),
                                                 action: #selector(commentCurrentQuery(_:)),
                                                 keyEquivalent: "/")
        commentCurrentQueryItem.keyEquivalentModifierMask = [.option, .command]
        commentCurrentQueryItem.target = self
        commentCurrentQueryItem.isEnabled = currentQueryRange.length > 0
        menu.addItem(commentCurrentQueryItem)

        let completionListItem = NSMenuItem(title: NSLocalizedString("Completion List", comment: "completion list menu item"),
                                            action: #selector(showCompletionList(_:)),
                                            keyEquivalent: "\u{1b}")
        completionListItem.target = self
        menu.addItem(completionListItem)

        let databasesCompletionItem = NSMenuItem(title: NSLocalizedString("All Databases Names", comment: "all database completion menu item"),
                                                 action: #selector(showAllDatabaseCompletions(_:)),
                                                 keyEquivalent: "1")
        databasesCompletionItem.keyEquivalentModifierMask = [.option, .command]
        databasesCompletionItem.target = self

        let tablesCompletionItem = NSMenuItem(title: NSLocalizedString("All Table and View Names", comment: "all table completion menu item"),
                                              action: #selector(showAllTableCompletions(_:)),
                                              keyEquivalent: "2")
        tablesCompletionItem.keyEquivalentModifierMask = [.option, .command]
        tablesCompletionItem.target = self

        let fieldsCompletionItem = NSMenuItem(title: NSLocalizedString("All Field Names From Current Table", comment: "all field completion menu item"),
                                              action: #selector(showAllFieldCompletions(_:)),
                                              keyEquivalent: "3")
        fieldsCompletionItem.keyEquivalentModifierMask = [.option, .command]
        fieldsCompletionItem.target = self

        let completionSubmenuItem = NSMenuItem(title: NSLocalizedString("Show Completion List", comment: "show completion list submenu item"),
                                               action: nil,
                                               keyEquivalent: "")
        let completionMenu = NSMenu()
        completionMenu.addItem(databasesCompletionItem)
        completionMenu.addItem(tablesCompletionItem)
        completionMenu.addItem(fieldsCompletionItem)
        completionSubmenuItem.submenu = completionMenu
        menu.addItem(completionSubmenuItem)

        menu.addItem(.separator())

        let editorFontItem = NSMenuItem(title: NSLocalizedString("Editor Font...", comment: "editor font menu item"),
                                        action: #selector(showEditorFontPanel(_:)),
                                        keyEquivalent: "")
        editorFontItem.target = self
        menu.addItem(editorFontItem)

        let autoindentItem = NSMenuItem(title: NSLocalizedString("Indent New Lines", comment: "auto indent menu item"),
                                        action: #selector(toggleAutoindent(_:)),
                                        keyEquivalent: "")
        autoindentItem.target = self
        menu.addItem(autoindentItem)

        let autopairItem = NSMenuItem(title: NSLocalizedString("Auto-pair Characters", comment: "auto pair menu item"),
                                      action: #selector(toggleAutopair(_:)),
                                      keyEquivalent: "")
        autopairItem.target = self
        menu.addItem(autopairItem)

        let autouppercaseItem = NSMenuItem(title: NSLocalizedString("Auto-uppercase Keywords", comment: "auto uppercase keywords menu item"),
                                           action: #selector(toggleAutouppercaseKeywords(_:)),
                                           keyEquivalent: "")
        autouppercaseItem.target = self
        menu.addItem(autouppercaseItem)

        let autocompleteItem = NSMenuItem(title: NSLocalizedString("Auto-completion", comment: "auto completion menu item"),
                                          action: #selector(toggleAutocomplete(_:)),
                                          keyEquivalent: "")
        autocompleteItem.target = self
        menu.addItem(autocompleteItem)

        let autohelpItem = NSMenuItem(title: NSLocalizedString("Update Help while typing", comment: "auto help menu item"),
                                      action: #selector(toggleAutohelp(_:)),
                                      keyEquivalent: "")
        autohelpItem.target = self
        menu.addItem(autohelpItem)

        actionButton.menu = menu
        updateActionMenuState()
    }

    func configureRunMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: NSLocalizedString("Run Current", comment: "run button title"), action: nil, keyEquivalent: "")
        titleItem.isHidden = true
        menu.addItem(titleItem)

        let primaryItem = NSMenuItem(title: NSLocalizedString("Run Current Query", comment: "run current query menu item"),
                                     action: #selector(runPrimaryQuery(_:)),
                                     keyEquivalent: "r")
        primaryItem.target = self
        menu.addItem(primaryItem)

        menu.addItem(.separator())

        let secondaryItem = NSMenuItem(title: NSLocalizedString("Run All Queries", comment: "run all queries menu item"),
                                       action: #selector(runSecondaryQuery(_:)),
                                       keyEquivalent: "r")
        secondaryItem.keyEquivalentModifierMask = [.option, .command]
        secondaryItem.target = self
        menu.addItem(secondaryItem)

        let switchDefaultItem = NSMenuItem(title: NSLocalizedString("Switch Default", comment: "switch query default menu item"),
                                           action: #selector(switchDefaultQueryAction(_:)),
                                           keyEquivalent: "")
        switchDefaultItem.target = self
        menu.addItem(switchDefaultItem)

        menu.addItem(.separator())

        let explainCurrentQueryItem = NSMenuItem(title: NSLocalizedString("Explain Current Query", comment: "explain current query menu item"),
                                                 action: #selector(runExplainQueryAction(_:)),
                                                 keyEquivalent: "e")
        explainCurrentQueryItem.keyEquivalentModifierMask = [.option, .command]
        explainCurrentQueryItem.target = self
        explainCurrentQueryItem.isEnabled = canRunExplainQueryAction()
        menu.addItem(explainCurrentQueryItem)

        menu.delegate = runButton
        runButton.menu = menu
        runButton.selectItem(at: 0)
    }

    func updateQueryInteractionInterface() {
        guard let menu = runButton.menu, menu.items.count >= 4 else { return }

        let primaryActionIsRunAll = UserDefaults.standard.bool(forKey: SPQueryPrimaryControlRunsAll)
        let titleItem = menu.items[0]
        let primaryItem = menu.items[1]
        let secondaryItem = menu.items[3]

        if primaryActionIsRunAll {
            titleItem.title = NSLocalizedString("Run All", comment: "run all button")
            primaryItem.title = NSLocalizedString("Run All Queries", comment: "run all menu item title")
        } else {
            secondaryItem.title = NSLocalizedString("Run All Queries", comment: "run all menu item title")
        }

        updateContextualRunInterface()
        runButton.selectItem(at: 0)
    }

    func updateContextualRunInterface() {
        guard let menu = runButton.menu, menu.items.count >= 4 else { return }

        let primaryActionIsRunAll = UserDefaults.standard.bool(forKey: SPQueryPrimaryControlRunsAll)
        let titleItem = menu.items[0]
        let primaryItem = menu.items[1]
        let secondaryItem = menu.items[3]
        let contextualItem = primaryActionIsRunAll ? secondaryItem : primaryItem

        if queryTextView.selectedRange().length == 0 {
            if currentQueryBeforeCaret {
                if !primaryActionIsRunAll {
                    titleItem.title = NSLocalizedString("Run Previous", comment: "run previous button")
                }
                contextualItem.title = NSLocalizedString("Run Previous Query", comment: "run previous query menu item")
            } else {
                if !primaryActionIsRunAll {
                    titleItem.title = NSLocalizedString("Run Current", comment: "run current button")
                }
                contextualItem.title = NSLocalizedString("Run Current Query", comment: "run current query menu item")
            }
        } else {
            if !primaryActionIsRunAll {
                titleItem.title = NSLocalizedString("Run Selection", comment: "run selection button")
            }
            contextualItem.title = NSLocalizedString("Run Selected Text", comment: "run selected text menu item")
        }

        runButton.selectItem(at: 0)
        updateRunMenuState()
    }

    func updateRunMenuState() {
        guard let menu = runButton.menu else { return }

        for item in menu.items {
            switch item.action {
            case #selector(runExplainQueryAction(_:)):
                item.isEnabled = canRunExplainQueryAction()
            default:
                break
            }
        }
    }

    @objc func runPrimaryQuery(_ sender: Any?) {
        if isRunning {
            cancelRunningQuery()
            return
        }

        if NSApp.currentEvent?.type == .keyUp { return }

        if UserDefaults.standard.bool(forKey: SPQueryPrimaryControlRunsAll) {
            runQueries(splitQueries(in: queryTextView.string))
        } else {
            guard let queries = queriesForCurrentAction() else { return }
            runQueries(queries)
        }
    }

    @objc func runSecondaryQuery(_ sender: Any?) {
        if isRunning {
            cancelRunningQuery()
            return
        }

        if NSApp.currentEvent?.type == .keyUp { return }

        if UserDefaults.standard.bool(forKey: SPQueryPrimaryControlRunsAll) {
            guard let queries = queriesForCurrentAction() else { return }
            runQueries(queries)
        } else {
            runQueries(splitQueries(in: queryTextView.string))
        }
    }

    @objc func runExplainQueryAction(_ sender: Any?) {
        guard !isRunning else { return }

        // Fixes bug in key equivalents (mirrors the legacy query action guard).
        if NSApp.currentEvent?.type == .keyUp { return }

        guard let query = queryForExplainCurrentAction() else { return }
        guard SPCustomQuerySQLClassifier.isQueryExplainable(query) else {
            reportUnsupportedExplain()
            return
        }

        runQueries(["EXPLAIN \(query)"])
    }

    func cancelRunningQuery() {
        isCancellationRequested = true
        connection?.cancelCurrentQuery()
        queryProgressCancelButton?.isEnabled = false
        setStatusText(NSLocalizedString("Cancelling query...", comment: "lightweight query cancelling status"))
        setQueryProgressDescription(NSLocalizedString("Cancelling query...", comment: "lightweight query cancelling status"))
    }

    @objc func switchDefaultQueryAction(_ sender: Any?) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: SPQueryPrimaryControlRunsAll), forKey: SPQueryPrimaryControlRunsAll)
        updateQueryInteractionInterface()
    }

    @objc func insertPreviousHistoryQuery(_ sender: Any?) {
        replaceEditorSelectionWithHistory(direction: 1)
    }

    @objc func insertNextHistoryQuery(_ sender: Any?) {
        replaceEditorSelectionWithHistory(direction: -1)
    }

    @objc func shiftSelectionRight(_ sender: Any?) {
        _ = queryTextView.shiftSelectionRight()
    }

    @objc func shiftSelectionLeft(_ sender: Any?) {
        _ = queryTextView.shiftSelectionLeft()
    }

    @objc func commentLineOrSelection(_ sender: Any?) {
        if queryTextView.selectedRange().length > 0 {
            commentOutCurrentQuery(takingSelection: true)
            return
        }

        let oldRange = queryTextView.selectedRange()
        let lineRange = (queryTextView.string as NSString).lineRange(for: oldRange)
        guard lineRange.length > 0 else { return }

        var replacement = "-- " + (queryTextView.string as NSString).substring(with: lineRange)
        var offsetForPointer = 3
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedReplacement.hasPrefix("-- --") || trimmedReplacement.hasPrefix("-- #") {
            offsetForPointer = oldRange.location - lineRange.location < 3 ? lineRange.location - oldRange.location : -3
            replacement = replacement.replacingOccurrences(of: #"^-- (\s*)(--\s|#)"#,
                                                            with: "$1",
                                                            options: .regularExpression)
        } else if trimmedReplacement.hasPrefix("-- /*"), trimmedReplacement.hasSuffix("*/") {
            offsetForPointer = oldRange.location - lineRange.location < 3 ? lineRange.location - oldRange.location : -3
            replacement = replacement.replacingOccurrences(of: #"^-- (\s*)/\* ?"#,
                                                            with: "$1",
                                                            options: .regularExpression)
            replacement = replacement.replacingOccurrences(of: #" ?\*/\s*$"#,
                                                            with: "",
                                                            options: .regularExpression)
        }

        queryTextView.insertText(replacement, replacementRange: lineRange)
        queryTextView.setSelectedRange(NSRange(location: max(0, oldRange.location + offsetForPointer), length: 0))
        updateCurrentQueryRange()
    }

    @objc func commentCurrentQuery(_ sender: Any?) {
        commentOutCurrentQuery(takingSelection: false)
    }

    @objc func showCompletionList(_ sender: Any?) {
        let fuzzySearch = NSApp.currentEvent?.modifierFlags.contains(.control) == true
        performTextViewCompletion(fuzzySearch: fuzzySearch)
    }

    @objc func showEditorFontPanel(_ sender: Any?) {
        queryTextView.window?.makeFirstResponder(queryTextView)
        NSFontPanel.shared.setPanelFont(queryTextView.font ?? UserDefaults.getFont(), isMultiple: false)
        NSFontPanel.shared.makeKeyAndOrderFront(sender)
    }

    @objc func toggleAutoindent(_ sender: NSMenuItem) {
        togglePreference(SPCustomQueryAutoIndent, sender: sender) { queryTextView.setAutoindent($0) }
    }

    @objc func toggleHistoryReplacesContent(_ sender: NSMenuItem) {
        togglePreference(SPQueryHistoryReplacesContent, sender: sender, apply: { _ in })
    }

    @objc func toggleFavoriteReplacesContent(_ sender: NSMenuItem) {
        togglePreference(SPQueryFavoriteReplacesContent, sender: sender, apply: { _ in })
    }

    @objc func toggleAutopair(_ sender: NSMenuItem) {
        togglePreference(SPCustomQueryAutoPairCharacters, sender: sender) { queryTextView.setAutopair($0) }
    }

    @objc func toggleAutocomplete(_ sender: NSMenuItem) {
        togglePreference(SPCustomQueryAutoComplete, sender: sender) { queryTextView.setAutoComplete($0) }
    }

    @objc func toggleAutouppercaseKeywords(_ sender: NSMenuItem) {
        togglePreference(SPCustomQueryAutoUppercaseKeywords, sender: sender) { queryTextView.setAutouppercaseKeywords($0) }
    }

    @objc func toggleAutohelp(_ sender: NSMenuItem) {
        togglePreference(SPCustomQueryUpdateAutoHelp, sender: sender) { queryTextView.setAutohelp($0) }
    }

    @objc func toggleQueryInfoPane(_ sender: Any?) {
        setQueryInfoPaneVisible(queryInfoButton.state != .off)
    }

    @objc func showAllDatabaseCompletions(_ sender: Any?) {
        queryTextView.showCompletionList(for: "$SP_ASLIST_ALL_DATABASES", at: NSRange(location: queryTextView.selectedRange().location, length: 0), fuzzySearch: false)
    }

    @objc func showAllTableCompletions(_ sender: Any?) {
        queryTextView.showCompletionList(for: "$SP_ASLIST_ALL_TABLES", at: NSRange(location: queryTextView.selectedRange().location, length: 0), fuzzySearch: false)
    }

    @objc func showAllFieldCompletions(_ sender: Any?) {
        refreshCompletionFieldNamesIfNeeded()
        queryTextView.showCompletionList(for: "$SP_ASLIST_ALL_FIELDS", at: NSRange(location: queryTextView.selectedRange().location, length: 0), fuzzySearch: false)
    }

    @objc func refreshCompletionFieldNamesIfNeeded() {
        guard completionTablesListProxy.allFieldNames.isEmpty,
              let connection,
              !database.isEmpty,
              let table,
              completionTablesListProxy.allTableAndViewNames.contains(table) else { return }

        guard let result = connection.queryString("SHOW FULL COLUMNS FROM \(Self.backtickQuoted(table)) FROM \(Self.backtickQuoted(database))") else { return }
        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary

        let rows = result.getAllRows() as? [[String: Any]] ?? []
        let fieldNames = rows.compactMap { row -> String? in
            if let field = row["Field"] as? String, !field.isEmpty {
                return field
            }

            if let field = row["field"] as? String, !field.isEmpty {
                return field
            }

            return nil
        }

        completionTablesListProxy.updateFieldNames(fieldNames)
    }

    func performTextViewCompletion(fuzzySearch: Bool) {
        refreshCompletionFieldNamesIfNeeded()

        let selector = NSSelectorFromString("doCompletionByUsingSpellChecker:fuzzyMode:autoCompleteMode:")
        guard queryTextView.responds(to: selector),
              let implementation = queryTextView.method(for: selector) else {
            queryTextView.complete(nil)
            return
        }

        typealias CompletionFunction = @convention(c) (AnyObject, Selector, Bool, Bool, Bool) -> Void
        let completionFunction = unsafeBitCast(implementation, to: CompletionFunction.self)
        completionFunction(queryTextView, selector, false, fuzzySearch, false)
    }

    func runQueries(_ queries: [String], preservingResultGridState: Bool = false, recordsHistory: Bool = true) {
        guard let connection, !isRunning else { return }

        let runnableQueries = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !runnableQueries.isEmpty else {
            NSSound.beep()
            return
        }

        if UserDefaults.standard.bool(forKey: SPQueryWarningEnabled),
           queriesContainDestructiveSQL(runnableQueries) {
            let alert = NSAlert()
            alert.window.animationBehavior = .none
            alert.messageText = NSLocalizedString("Execute SQL?", comment: "execute sql alert title")
            alert.informativeText = destructiveQueryWarning(for: runnableQueries)
            alert.addButton(withTitle: NSLocalizedString("Proceed", comment: "execute sql proceed button"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
            guard alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn else { return }
        }

        queryToken = UUID()
        let token = queryToken
        isCancellationRequested = false

        if preservingResultGridState {
            pendingResultGridViewState = captureResultGridViewState()
        } else {
            pendingResultGridViewState = nil
            pendingSortFailureRestore = nil
        }

        let preservingColumnsForSort = preservingResultGridState && !columnDefinitions.isEmpty
        if !isApplyingQuerySort {
            querySortColumnIndex = nil
            querySortAscending = true
            applyQuerySortIndicator()
        }

        isRunning = true
        runningQueryCount = runnableQueries.count
        updateDataTableBundleSupport()
        if preservingColumnsForSort {
            displayCache.invalidateAll()
            tableView.noteNumberOfRowsChanged()
        } else {
            rows = []
            displayCache.invalidateAll()
            columnDefinitions = []
            columnWidthCache.invalidateAll()
            rebuildColumns()
            lastExecutedQuery = ""
            lastResultQuery = ""
        }
        let runningStatus = runnableQueries.count > 1
            ? String(format: NSLocalizedString("Running query 1 of %ld...", comment: "lightweight query running multiple status"), runnableQueries.count)
            : NSLocalizedString("Running query...", comment: "lightweight query running status")
        setStatusText(runningStatus)
        showQueryProgressPanel(description: runningStatus,
                               cancelButtonTitle: runnableQueries.count > 1
                                   ? NSLocalizedString("Stop queries", comment: "Stop queries string")
                                   : NSLocalizedString("Stop query", comment: "Stop query string"))
        updateControls()
        queryExecutionWillBegin?()
        let queryExecutionDidEnd = queryExecutionDidEnd

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self, let connection else { return }
            defer {
                DispatchQueue.main.async {
                    queryExecutionDidEnd?()
                }
            }

            if !self.database.isEmpty {
                _ = connection.selectDatabase(self.database)
            }

            let retriesWereEnabled = connection.retryQueriesOnConnectionFailure
            connection.retryQueriesOnConnectionFailure = false
            defer {
                connection.retryQueriesOnConnectionFailure = retriesWereEnabled
            }

            var totalAffectedRows: UInt64 = 0
            var totalExecutionTime: TimeInterval = 0
            var queriesRun = 0
            var executedQueries: [String] = []
            var resultQuery = ""
            var errors: [String] = []
            var firstErrorQueryNumber: Int?
            var suppressErrorSheet = false
            var didPublishRows = false
            var finalResult = QueryResult(columnDefinitions: [], rows: [], affectedRows: 0, executionTime: 0, fatalError: nil, errorText: nil, firstErrorQueryNumber: nil, executedQuery: "", resultQuery: "", lastErrorID: 0, queriesRun: 0, truncated: false)

            for (index, query) in runnableQueries.enumerated() {
                if token != self.queryToken || self.isCancellationRequested {
                    let error = NSLocalizedString("Query cancelled.", comment: "lightweight query cancelled status")
                    if errors.isEmpty {
                        errors.append(error)
                    }
                    finalResult = QueryResult(columnDefinitions: finalResult.columnDefinitions, rows: finalResult.rows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: nil, errorText: errors.joined(separator: "\n"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: resultQuery, lastErrorID: 0, queriesRun: max(queriesRun, 1), truncated: finalResult.truncated, wasCancelled: true)
                    break
                }

                if runnableQueries.count > 1 {
                    DispatchQueue.main.async {
                        guard self.queryToken == token else { return }
                        let runningStatus = String(format: NSLocalizedString("Running query %ld of %ld...", comment: "lightweight query running multiple status"), index + 1, runnableQueries.count)
                        self.setStatusText(runningStatus)
                        self.setQueryProgressDescription(runningStatus)
                    }
                }

                let executionQuery = self.queryByApplyingDisplayLimit(to: query)
                executedQueries.append(query)
                let queryStart = CFAbsoluteTimeGetCurrent()
                guard let result = connection.streamingQueryString(executionQuery) else {
                    queriesRun += 1
                    if connection.lastQueryWasCancelled || self.isCancellationRequested {
                        let error = NSLocalizedString("Query cancelled.", comment: "lightweight query cancelled status")
                        if firstErrorQueryNumber == nil {
                            firstErrorQueryNumber = index + 1
                        }
                        if runnableQueries.count > 1 {
                            errors.append(String(format: NSLocalizedString("[ERROR in query %ld] %@", comment: "error text when multiple custom query failed"), index + 1, error))
                        } else {
                            errors.append(error)
                        }
                        finalResult = QueryResult(columnDefinitions: finalResult.columnDefinitions, rows: finalResult.rows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: nil, errorText: errors.joined(separator: "\n"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: resultQuery, lastErrorID: 0, queriesRun: queriesRun, truncated: finalResult.truncated, wasCancelled: true)
                        break
                    }
                    let error = self.displayErrorMessage(for: connection)
                    finalResult = self.queryResultAfterError(error,
                                                             errorID: connection.lastErrorID(),
                                                             queryNumber: index + 1,
                                                             queryCount: runnableQueries.count,
                                                             finalResult: finalResult,
                                                             totalAffectedRows: totalAffectedRows,
                                                             totalExecutionTime: totalExecutionTime,
                                                             executedQueries: executedQueries,
                                                             queriesRun: queriesRun,
                                                             errors: &errors,
                                                             firstErrorQueryNumber: &firstErrorQueryNumber,
                                                             suppressErrorSheet: &suppressErrorSheet)
                    if finalResult.fatalError != nil || finalResult.errorText != nil && runnableQueries.count == 1 {
                        break
                    }
                    if errors.last == NSLocalizedString("Execution stopped!", comment: "execution stopped message") {
                        break
                    }
                    continue
                }
                SALightweightResultGrid.logPerformance("Query execute", start: queryStart, details: "queryNumber=\(index + 1)", minimumMilliseconds: 1)

                queriesRun += 1

                result.returnDataAsStrings = false
                result.defaultRowReturnType = SPMySQLResultRowAsArray

                totalExecutionTime += result.queryExecutionTime()

                let affectedRows = connection.rowsAffectedByLastQuery()
                if affectedRows != UInt64.max {
                    totalAffectedRows += affectedRows
                }

                if connection.queryErrored() {
                    if connection.lastQueryWasCancelled || self.isCancellationRequested {
                        let error = NSLocalizedString("Query cancelled.", comment: "lightweight query cancelled status")
                        if firstErrorQueryNumber == nil {
                            firstErrorQueryNumber = index + 1
                        }
                        if runnableQueries.count > 1 {
                            errors.append(String(format: NSLocalizedString("[ERROR in query %ld] %@", comment: "error text when multiple custom query failed"), index + 1, error))
                        } else {
                            errors.append(error)
                        }
                        finalResult = QueryResult(columnDefinitions: finalResult.columnDefinitions, rows: finalResult.rows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: nil, errorText: errors.joined(separator: "\n"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: resultQuery, lastErrorID: 0, queriesRun: queriesRun, truncated: finalResult.truncated, wasCancelled: true)
                        break
                    }
                    let error = self.displayErrorMessage(for: connection)
                    finalResult = self.queryResultAfterError(error,
                                                             errorID: connection.lastErrorID(),
                                                             queryNumber: index + 1,
                                                             queryCount: runnableQueries.count,
                                                             finalResult: finalResult,
                                                             totalAffectedRows: totalAffectedRows,
                                                             totalExecutionTime: totalExecutionTime,
                                                             executedQueries: executedQueries,
                                                             queriesRun: queriesRun,
                                                             errors: &errors,
                                                             firstErrorQueryNumber: &firstErrorQueryNumber,
                                                             suppressErrorSheet: &suppressErrorSheet)
                    if finalResult.fatalError != nil || finalResult.errorText != nil && runnableQueries.count == 1 {
                        break
                    }
                    if errors.last == NSLocalizedString("Execution stopped!", comment: "execution stopped message") {
                        break
                    }
                    continue
                }

                let definitions = result.fieldDefinitions() as? [NSDictionary] ?? []
                var loadedRows: [[Any]] = []
                var pendingPublishedRows: [[Any]] = []
                var didPublishRowsForCurrentResult = false
                var truncated = false
                var fetchWasCancelled = false
                resultQuery = definitions.isEmpty ? resultQuery : executionQuery

                if !definitions.isEmpty {
                    didPublishRows = true
                    DispatchQueue.main.sync {
                        self.publishQueryColumns(definitions, token: token)
                    }
                }

                let fetchStart = CFAbsoluteTimeGetCurrent()
                while let row = result.getRowAsArray() {
                    if token != self.queryToken || self.isCancellationRequested {
                        fetchWasCancelled = true
                        let error = NSLocalizedString("Query cancelled.", comment: "lightweight query cancelled status")
                        if firstErrorQueryNumber == nil {
                            firstErrorQueryNumber = index + 1
                        }
                        if runnableQueries.count > 1 {
                            errors.append(String(format: NSLocalizedString("[ERROR in query %ld] %@", comment: "error text when multiple custom query failed"), index + 1, error))
                        } else {
                            errors.append(error)
                        }
                        finalResult = QueryResult(columnDefinitions: finalResult.columnDefinitions, rows: finalResult.rows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: nil, errorText: errors.joined(separator: "\n"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: resultQuery, lastErrorID: 0, queriesRun: queriesRun, truncated: finalResult.truncated, wasCancelled: true)
                        break
                    }
                    if loadedRows.count < self.maxDisplayedRows {
                        loadedRows.append(row)
                        pendingPublishedRows.append(row)

                        if !definitions.isEmpty {
                            let publishLimit = didPublishRowsForCurrentResult ? self.remainingQueryRowPublishSize : self.initialQueryRowPublishSize
                            if pendingPublishedRows.count >= publishLimit {
                                let rowsToPublish = pendingPublishedRows
                                pendingPublishedRows.removeAll(keepingCapacity: true)
                                let shouldPublishSynchronously = !didPublishRowsForCurrentResult
                                didPublishRowsForCurrentResult = true
                                let publish = {
                                    self.publishQueryRows(rowsToPublish,
                                                          token: token,
                                                          forceDisplay: shouldPublishSynchronously)
                                }
                                if shouldPublishSynchronously {
                                    DispatchQueue.main.sync(execute: publish)
                                } else {
                                    DispatchQueue.main.async(execute: publish)
                                }
                            }
                        }
                    } else {
                        truncated = true
                        break
                    }
                }
                if fetchWasCancelled {
                    break
                }
                if !pendingPublishedRows.isEmpty, !definitions.isEmpty {
                    let rowsToPublish = pendingPublishedRows
                    pendingPublishedRows.removeAll(keepingCapacity: true)
                    let shouldPublishSynchronously = !didPublishRowsForCurrentResult
                    didPublishRowsForCurrentResult = true
                    let publish = {
                        self.publishQueryRows(rowsToPublish,
                                              token: token,
                                              forceDisplay: shouldPublishSynchronously)
                    }
                    if shouldPublishSynchronously {
                        DispatchQueue.main.sync(execute: publish)
                    } else {
                        DispatchQueue.main.async(execute: publish)
                    }
                }
                SALightweightResultGrid.logPerformance("Query fetch displayed rows", start: fetchStart, details: "rows=\(loadedRows.count) truncated=\(truncated)", minimumMilliseconds: 1)

                finalResult = QueryResult(columnDefinitions: definitions, rows: loadedRows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: nil, errorText: errors.isEmpty ? nil : errors.joined(separator: "\n"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: resultQuery, lastErrorID: 0, queriesRun: queriesRun, truncated: truncated)
            }

            if finalResult.executedQuery.isEmpty, !executedQueries.isEmpty {
                finalResult = QueryResult(columnDefinitions: finalResult.columnDefinitions, rows: finalResult.rows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: finalResult.fatalError, errorText: errors.isEmpty ? finalResult.errorText : errors.joined(separator: "\n"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: resultQuery, lastErrorID: finalResult.lastErrorID, queriesRun: queriesRun, truncated: finalResult.truncated)
            }

            DispatchQueue.main.async {
                let publishStart = CFAbsoluteTimeGetCurrent()
                defer {
                    SALightweightResultGrid.logPerformance("Query publish result", start: publishStart, details: "columns=\(finalResult.columnDefinitions.count) rows=\(finalResult.rows.count)", minimumMilliseconds: 1)
                }

                guard self.queryToken == token else { return }

                self.hideQueryProgressPanel()
                self.isRunning = false
                self.isCancellationRequested = false
                self.runningQueryCount = 0
                self.lastExecutedQuery = finalResult.executedQuery
                self.lastResultQuery = finalResult.resultQuery

                if recordsHistory, !self.lastExecutedQuery.isEmpty {
                    self.addHistoryEntry(self.lastExecutedQuery)
                }

                if let error = finalResult.fatalError, !error.isEmpty {
                    let sortRestore = self.isApplyingQuerySort ? self.pendingSortFailureRestore : nil
                    self.isApplyingQuerySort = false
                    if let state = self.pendingResultGridViewState {
                        self.columnDefinitions = state.columnDefinitions
                        self.rows = state.rows
                        self.lastExecutedQuery = state.lastExecutedQuery
                        self.lastResultQuery = state.lastResultQuery
                        if let sortRestore {
                            self.querySortColumnIndex = sortRestore.columnIndex
                            self.querySortAscending = sortRestore.ascending
                        }
                    } else {
                        self.columnDefinitions = []
                        self.rows = []
                    }
                    self.displayCache.invalidateAll()
                    self.columnWidthCache.invalidateAll()
                    self.rebuildColumns()
                    self.updateDataTableBundleSupport()
                    let displayedError = sortRestore == nil ? error : NSLocalizedString("Couldn't sort column.", comment: "text shown if an error occurred while sorting the result table")
                    if sortRestore == nil {
                        self.selectQueryForError(number: finalResult.firstErrorQueryNumber, errorText: finalResult.errorText ?? error, errorID: finalResult.lastErrorID)
                    }
                    self.updateQueryInfo(title: NSLocalizedString("Last Error Message", comment: "lightweight query error info title"), message: displayedError, isError: true)
                    self.setStatusText(displayedError)
                    self.rebuildMenus()
                    self.updateControls()
                    self.restorePendingResultGridViewState()
                    self.pendingSortFailureRestore = nil
                    return
                }

                if didPublishRows, self.columnDefinitions.count == finalResult.columnDefinitions.count, self.rows.count == finalResult.rows.count {
                    SALightweightResultGrid.reloadVisibleCells(in: self.tableView, columnBuffer: SALightweightResultGrid.autosizeColumnBuffer)
                } else {
                    self.columnDefinitions = finalResult.columnDefinitions
                    self.rows = finalResult.rows
                    self.displayCache.invalidateAll()
                    self.columnWidthCache.invalidateAll()
                    self.rebuildColumns()
                }
                self.updateDataTableBundleSupport()
                self.updateStatus(for: finalResult, queryCount: max(finalResult.queriesRun, runnableQueries.count))
                self.prewarmFieldEditor()
                if let errorText = finalResult.errorText, !errorText.isEmpty {
                    self.selectQueryForError(number: finalResult.firstErrorQueryNumber, errorText: errorText, errorID: finalResult.lastErrorID)
                    self.updateQueryInfo(title: NSLocalizedString("Last Error Message", comment: "lightweight query error info title"), message: errorText, isError: true)
                } else {
                    self.updateQueryInfo(title: NSLocalizedString("Query Status", comment: "lightweight query info pane status title"),
                                         message: NSLocalizedString("There were no errors.", comment: "lightweight query info pane no errors text"),
                                         isError: false)
                }
                self.rebuildMenus()
                self.updateControls()
                self.restorePendingResultGridViewState()
                self.pendingSortFailureRestore = nil
                self.isApplyingQuerySort = false
            }
        }
    }

    func queryResultAfterError(_ error: String,
                               errorID: UInt,
                               queryNumber: Int,
                               queryCount: Int,
                               finalResult: QueryResult,
                               totalAffectedRows: UInt64,
                               totalExecutionTime: TimeInterval,
                               executedQueries: [String],
                               queriesRun: Int,
                               errors: inout [String],
                               firstErrorQueryNumber: inout Int?,
                               suppressErrorSheet: inout Bool) -> QueryResult {
        let errorString = error.isEmpty ? NSLocalizedString("Query failed.", comment: "lightweight query failed status") : error

        guard queryCount > 1 else {
            firstErrorQueryNumber = queryNumber
            return QueryResult(columnDefinitions: [], rows: [], affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: errorString, errorText: errorString, firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: finalResult.resultQuery, lastErrorID: errorID, queriesRun: queriesRun, truncated: false)
        }

        if firstErrorQueryNumber == nil {
            firstErrorQueryNumber = queryNumber
        }

        errors.append(String(format: NSLocalizedString("[ERROR in query %ld] %@", comment: "error text when multiple custom query failed"), queryNumber, errorString))

        if !suppressErrorSheet {
            let choice = DispatchQueue.main.sync {
                self.multiQueryErrorChoice(for: errorString)
            }

            switch choice {
            case .runAll:
                suppressErrorSheet = true
            case .continueQueries:
                break
            case .stopQueries:
                if queryNumber < queryCount {
                    errors.append(NSLocalizedString("Execution stopped!", comment: "execution stopped message"))
                }
            }
        }

        return QueryResult(columnDefinitions: finalResult.columnDefinitions, rows: finalResult.rows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: nil, errorText: errors.joined(separator: "\n"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: finalResult.resultQuery, lastErrorID: errorID, queriesRun: queriesRun, truncated: finalResult.truncated)
    }

    func displayErrorMessage(for connection: SPMySQLConnection) -> String {
        if connection.lastQueryWasCancelled {
            return NSLocalizedString("Query cancelled.", comment: "lightweight query cancelled status")
        }

        let message = connection.lastErrorMessage() ?? ""
        guard connection.lastErrorID() == 2006 else { return message }

        return String(format: "%@.\n\n%@", message, NSLocalizedString("(This usually indicates that the connection has been closed by the server after inactivity, but can also occur due to other conditions.  The connection has been restored; please try again if the query is safe to re-run.)", comment: "Explanation for MySQL server has gone away error"))
    }

    private func multiQueryErrorChoice(for error: String) -> MultiQueryErrorChoice {
        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = NSLocalizedString("MySQL Error", comment: "mysql error message")
        alert.informativeText = error
        alert.addButton(withTitle: NSLocalizedString("Run All", comment: "run all button"))
        alert.addButton(withTitle: NSLocalizedString("Continue", comment: "continue button"))
        alert.addButton(withTitle: NSLocalizedString("Stop", comment: "stop button"))

        switch alert.runModalCenteredInKeyWindow() {
        case .alertFirstButtonReturn:
            return .runAll
        case .alertSecondButtonReturn:
            return .continueQueries
        default:
            return .stopQueries
        }
    }

    func queriesForCurrentAction() -> [String]? {
        let selection = queryTextView.selectedRange()
        if selection.length > 0 {
            return splitQueries(in: (queryTextView.string as NSString).substring(with: selection))
        }

        let editorString = queryTextView.string as NSString
        guard isValidQueryRange(currentQueryRange, in: editorString),
              let query = editorString.safeSubstring(with: currentQueryRange) else {
            reportNoCurrentQueryRangeForRun()
            return nil
        }

        return [SPSQLParser.normaliseQuery(forExecution: query)]
    }

    func isValidQueryRange(_ range: NSRange, in string: NSString) -> Bool {
        return range.location != NSNotFound
            && range.length > 0
            && range.location <= string.length
            && NSMaxRange(range) <= string.length
    }

    func reportNoCurrentQueryRangeForRun() {
        NSSound.beep()
        NSLog("Could not find a query range suitable to run query")
    }

    func queryForExplainCurrentAction() -> String? {
        let editorString = queryTextView.string as NSString
        let selectedRange = queryTextView.selectedRange()

        if selectedRange.length == 0 {
            let range = currentQueryRange
            guard range.length > 0, NSMaxRange(range) <= editorString.length else {
                NSSound.beep()
                NSLog("runExplainQueryAction: no query under caret")
                return nil
            }

            let rawQuery = editorString.safeSubstring(with: range) ?? ""
            return SPSQLParser.normaliseQuery(forExecution: rawQuery)
        }

        // Selected text may contain multiple statements separated by ';' —
        // EXPLAIN does not support multi-statement input, so split delimiter-
        // aware and reject when >1 non-empty. Comment-only fragments are
        // ignored so `SELECT 1; -- foo` counts as a single statement.
        let selectionText = editorString.safeSubstring(with: selectedRange) ?? ""
        let parser = SPSQLParser(string: selectionText)
        parser.setDelimiterSupport(true)
        let semicolon = UInt16(UnicodeScalar(";").value)
        let parts = (parser.splitString(byCharacter: semicolon) as? [String]) ?? []

        let nonEmpty = parts.compactMap { part -> String? in
            let probe = SPCustomQuerySQLClassifier.stripSQLComments(part)
            guard !probe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return part.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard nonEmpty.count == 1 else {
            reportUnsupportedExplain()
            return nil
        }

        return SPSQLParser.normaliseQuery(forExecution: nonEmpty[0])
    }

    func splitQueries(in text: String) -> [String] {
        let parser = SPSQLParser(string: text)
        parser.setDelimiterSupport(true)
        guard let queries = parser.splitString(byCharacter: Character(";").utf16.first!) as? [String] else { return [] }

        if parser.containsCarriageReturns() {
            return queries.map { SPSQLParser.normaliseQuery(forExecution: $0) }
        }

        return queries
    }

    func updateCurrentQueryRange() {
        let selection = queryTextView.selectedRange()
        let caretPosition = selection.location
        let previousQueryRange = currentQueryRange
        currentQueryBeforeCaret = true
        currentQueryRange = queryRange(at: caretPosition, lookBehind: &currentQueryBeforeCaret)
        queryTextView.queryRange = currentQueryRange
        if previousQueryRange != currentQueryRange {
            queryTextView.setNeedsDisplay(queryTextView.visibleRect)
        }
        updateActionMenuState()

        if !historyItemWasJustInserted {
            currentHistoryOffsetIndex = -1
        }

        if currentQueryRange.length < 1000 {
            bracketHighlighter?.bracketHighlight(caretPosition - 1, in: currentQueryRange)
        } else {
            bracketHighlighter?.highlightOff()
        }
    }

    func queryRange(at position: Int, lookBehind: inout Bool) -> NSRange {
        let text = queryTextView.string as NSString
        guard position <= text.length else { return NSRange(location: 0, length: 0) }

        let whitespaceAndNewlineSet = CharacterSet.whitespacesAndNewlines as NSCharacterSet
        let whitespaceSet = CharacterSet.whitespaces as NSCharacterSet
        let fullRange = NSRange(location: 0, length: text.length)
        let ranges = cachedCurrentQueryRanges()
        var selectedRange = NSRange(location: NSNotFound, length: 0)

        for (index, rangeValue) in ranges.enumerated() {
            let range = NSIntersectionRange(rangeValue, fullRange)
            if range.location == NSNotFound || range.length == 0 {
                continue
            }

            let queryPosition = NSMaxRange(range)
            let queryStartPosition = range.location

            if queryPosition >= position {
                if lookBehind {
                    var positionAssociatedWithPreviousQuery = false

                    if position == queryStartPosition {
                        positionAssociatedWithPreviousQuery = true
                    }

                    if !positionAssociatedWithPreviousQuery, index > 0 {
                        let previousRange = NSIntersectionRange(ranges[index - 1], fullRange)
                        if previousRange.location != NSNotFound,
                           NSMaxRange(previousRange) < position,
                           position < queryStartPosition {
                            positionAssociatedWithPreviousQuery = true
                        }
                    }

                    if !positionAssociatedWithPreviousQuery,
                       queryStartPosition <= position,
                       position <= queryPosition {
                        let stringToPreviousRange = NSRange(location: queryStartPosition,
                                                            length: position - queryStartPosition)
                        let stringToEndRange = NSRange(location: position,
                                                       length: queryPosition - position)
                        let stringToPrevious = text.substring(with: stringToPreviousRange)
                        let stringToEnd = text.substring(with: stringToEndRange) as NSString

                        if stringToPrevious.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            for characterIndex in 0..<stringToEnd.length {
                                let character = stringToEnd.character(at: characterIndex)
                                if whitespaceSet.characterIsMember(character) {
                                    continue
                                }
                                if whitespaceAndNewlineSet.characterIsMember(character) {
                                    positionAssociatedWithPreviousQuery = true
                                }
                                break
                            }
                        }
                    }

                    if index > 0, positionAssociatedWithPreviousQuery {
                        let previousRange = NSIntersectionRange(ranges[index - 1], fullRange)
                        if previousRange.location != NSNotFound,
                           let previousQuery = text.safeSubstring(with: previousRange),
                           !previousQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            selectedRange = previousRange
                            break
                        }
                    }

                    lookBehind = false
                }

                selectedRange = range
                break
            }
        }

        if lookBehind, position == text.length, let lastRange = ranges.last {
            selectedRange = NSIntersectionRange(lastRange, fullRange)
        }

        if selectedRange.location == NSNotFound || selectedRange.length == 0 {
            return NSRange(location: 0, length: 0)
        }

        let trimmedRange = trimmedQueryRange(selectedRange, in: text)
        return trimmedRange.length > 0 ? trimmedRange : NSRange(location: 0, length: 0)
    }

    func trimmedQueryRange(_ range: NSRange, in text: NSString) -> NSRange {
        var trimmedRange = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        let whitespace = CharacterSet.whitespacesAndNewlines

        while trimmedRange.length > 0,
              let scalar = UnicodeScalar(text.character(at: trimmedRange.location)),
              whitespace.contains(scalar) {
            trimmedRange.location += 1
            trimmedRange.length -= 1
        }

        while trimmedRange.length > 0,
              let scalar = UnicodeScalar(text.character(at: NSMaxRange(trimmedRange) - 1)),
              whitespace.contains(scalar) {
            trimmedRange.length -= 1
        }

        return trimmedRange
    }

    func queryTextRange(forQueryNumber queryNumber: Int) -> NSRange {
        let text = queryTextView.string as NSString
        guard queryNumber > 0 else { return NSRange(location: 0, length: 0) }

        var currentQueryNumber = 0
        for range in cachedCurrentQueryRanges() {
            let trimmedRange = trimmedQueryRange(range, in: text)
            if trimmedRange.length == 0 {
                continue
            }

            currentQueryNumber += 1
            if currentQueryNumber == queryNumber {
                return trimmedRange
            }
        }

        return NSRange(location: 0, length: 0)
    }

    func cachedCurrentQueryRanges() -> [NSRange] {
        if textViewWasChanged || !didCacheCurrentQueryRanges {
            let parser = SPSQLParser(string: queryTextView.string)
            parser.setDelimiterSupport(true)
            let values = parser.splitStringIntoRanges(byCharacter: Character(";").utf16.first!) as? [NSValue]
            currentQueryRanges = values?.map(\.rangeValue) ?? []
            textViewWasChanged = false
            didCacheCurrentQueryRanges = true
        }

        return currentQueryRanges
    }

    func selectQueryForError(number queryNumber: Int?, errorText: String, errorID: UInt) {
        guard let queryNumber else { return }

        let range = queryTextRange(forQueryNumber: queryNumber)
        guard range.length > 0 else { return }

        if errorID == 1064,
           let lineNumber = syntaxErrorLineNumber(from: errorText) {
            let queryStartLine = queryTextView.getLineNumber(forCharacterIndex: UInt(range.location))
            queryTextView.selectLineNumber(queryStartLine + UInt(max(0, lineNumber - 1)), ignoreLeadingNewLines: true)
            return
        }

        if let nearRange = syntaxErrorNearRange(from: errorText, queryRange: range) {
            queryTextView.setSelectedRange(nearRange)
            queryTextView.scrollRangeToVisible(nearRange)
            return
        }

        queryTextView.setSelectedRange(range)
        queryTextView.scrollRangeToVisible(range)
    }

    func syntaxErrorLineNumber(from errorText: String) -> Int? {
        guard let match = errorText.range(of: #"([0-9]+)[^0-9]*$"#, options: .regularExpression) else { return nil }
        let digits = errorText[match].filter(\.isNumber)
        return Int(String(digits))
    }

    func syntaxErrorNearRange(from errorText: String, queryRange: NSRange) -> NSRange? {
        guard let nearCapture = errorText.range(of: #"[( ]'(.+)'[ -]"#, options: [.regularExpression]) else { return nil }

        var nearText = String(errorText[nearCapture])
        if let firstQuote = nearText.firstIndex(of: "'"),
           let lastQuote = nearText.lastIndex(of: "'"),
           firstQuote < lastQuote {
            nearText = String(nearText[nearText.index(after: firstQuote)..<lastQuote])
        }

        guard !nearText.isEmpty else { return nil }

        let fullText = queryTextView.string as NSString
        let boundedRange = NSIntersectionRange(NSRange(location: 0, length: fullText.length), queryRange)
        guard boundedRange.length > 0 else { return nil }

        let queryText = fullText.substring(with: boundedRange) as NSString
        let localRange = queryText.range(of: nearText, options: .literal)
        guard localRange.location != NSNotFound, localRange.length > 0 else { return nil }

        return NSRange(location: boundedRange.location + localRange.location, length: localRange.length)
    }

    func queriesContainDestructiveSQL(_ queries: [String]) -> Bool {
        for query in queries {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                continue
            }

            if SPCustomQuerySQLClassifier.isQuerySafeWithoutDestructiveWarning(trimmedQuery) {
                continue
            }

            return true
        }

        return false
    }

    func destructiveQueryWarning(for queries: [String]) -> String {
        var queryText = queries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
        if queryText.count > SPMaxQueryLengthForWarning {
            queryText = String(queryText.prefix(Int(SPMaxQueryLengthForWarning))) + "..."
        }

        return queries.count == 1
            ? String(format: NSLocalizedString("Do you really want to proceed with this query?\n\n %@", comment: "message of panel asking for confirmation for exec query"), queryText)
            : String(format: NSLocalizedString("Do you really want to proceed with these queries?\n\n %@", comment: "message of panel asking for confirmation for exec query"), queryText)
    }

    func addHistoryEntry(_ query: String) {
        guard let documentURL else { return }
        SPQueryController.shared().addHistory(query, forFileURL: documentURL)
    }

    func buildHistoryString() -> String {
        guard let documentURL else { return "" }
        let history = SPQueryController.shared().history(forFileURL: documentURL) as? [String] ?? []
        return history.joined(separator: ";\n")
    }

    func replaceEditorSelectionWithHistory(direction: Int) {
        guard let documentURL else { return }

        let history = SPQueryController.shared().history(forFileURL: documentURL) as? [String] ?? []
        currentHistoryOffsetIndex += direction

        if !history.isEmpty, currentHistoryOffsetIndex >= 0, currentHistoryOffsetIndex < history.count {
            historyItemWasJustInserted = true
            queryTextView.breakUndoCoalescing()

            let historyString = history[currentHistoryOffsetIndex]
            let insertionRange = queryTextView.selectedRange()
            queryTextView.insertText(historyString, replacementRange: insertionRange)
            queryTextView.setSelectedRange(NSRange(location: insertionRange.location, length: historyString.count))
            historyItemWasJustInserted = false
            return
        }

        currentHistoryOffsetIndex -= direction
        historyItemWasJustInserted = false
        NSSound.beep()
    }

    func rebuildMenus() {
        rebuildFavoritesMenu()
        rebuildHistoryMenu()
    }

    func makeMenuSearchField(placeholder: String, recentsAutosaveName: String) -> NSSearchField {
        let field = NSSearchField(frame: NSRect(x: 20, y: 2, width: 176, height: 19))
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = .controlTextColor
        field.focusRingType = .none
        field.refusesFirstResponder = false
        field.isEnabled = true
        field.isEditable = true
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = placeholder
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = self

        if let cell = field.cell as? NSSearchFieldCell {
            cell.controlSize = .small
            cell.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.focusRingType = .none
            cell.isBordered = false
            cell.isBezeled = false
            cell.drawsBackground = false
            cell.textColor = .controlTextColor
            cell.sendsActionOnEndEditing = true
            cell.recentsAutosaveName = recentsAutosaveName
            cell.maximumRecents = 10
        }

        return field
    }

    func focusMenuSearchField(_ searchField: NSSearchField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak searchField] in
            guard let searchField, let window = searchField.window else { return }
            window.makeFirstResponder(searchField)
            searchField.selectText(nil)
        }
    }

    func makeMenuSearchFieldView(for searchField: NSSearchField) -> NSView {
        SALightweightMenuSearchFieldView(searchField: searchField)
    }

    func configureFavoritesMenuShellIfNeeded() {
        guard favoritesSearchMenuItem == nil else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let titleItem = NSMenuItem(title: NSLocalizedString("Query Favorites", comment: "query favorites menu title"), action: nil, keyEquivalent: "")
        titleItem.isHidden = true
        menu.addItem(titleItem)

        let saveQueryItem = NSMenuItem(title: titleForSaveCurrentFavoriteMenuItem(),
                                       action: #selector(saveCurrentQueryToFavorites(_:)),
                                       keyEquivalent: "")
        saveQueryItem.target = self
        saveQueryItem.toolTip = NSLocalizedString("Save current query, selection, or - if no selection or current query could be found - the entire content to Favorite.", comment: "save query to favorites tooltip")
        menu.addItem(saveQueryItem)

        let saveAllItem = NSMenuItem(title: NSLocalizedString("Save All to Favorites", comment: "save all to favorites menu item"),
                                     action: #selector(saveAllQueriesToFavorites(_:)),
                                     keyEquivalent: "")
        saveAllItem.target = self
        saveAllItem.toolTip = NSLocalizedString("Save editor content to Favorite. Press ⌥ to restrict for current query or selection.", comment: "save all to favorites tooltip")
        menu.addItem(saveAllItem)

        let editItem = NSMenuItem(title: NSLocalizedString("Edit Favorites...", comment: "edit favorites menu item"),
                                  action: #selector(editQueryFavorites(_:)),
                                  keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem(title: "..placeholder for seachfield..",
                                    action: nil,
                                    keyEquivalent: "")
        searchItem.isEnabled = true
        searchItem.view = favoriteSearchFieldView
        menu.addItem(searchItem)
        menu.addItem(.separator())

        favoritesSearchMenuItem = searchItem
        favoritesMenu = menu
    }

    func rebuildFavoritesMenu() {
        configureFavoritesMenuShellIfNeeded()
        guard let menu = favoritesMenu else { return }

        while menu.numberOfItems > queryMenuDynamicStartIndex {
            menu.removeItem(at: menu.numberOfItems - 1)
        }

        favoritesSearchMenuItem?.view = favoriteSearchFieldView

        if let documentURL {
            let documentHeader = NSMenuItem(title: documentURL.lastPathComponent, action: nil, keyEquivalent: "")
            documentHeader.isEnabled = false
            menu.addItem(documentHeader)

            for favorite in SPQueryController.shared().favorites(forFileURL: documentURL) as? [[String: Any]] ?? [] {
                addFavorite(favorite, to: menu)
            }
        }

        let globalHeader = NSMenuItem(title: NSLocalizedString("Global", comment: "query favorites global header"), action: nil, keyEquivalent: "")
        globalHeader.isEnabled = false
        menu.addItem(globalHeader)

        for favorite in UserDefaults.standard.array(forKey: SPQueryFavorites) as? [[String: Any]] ?? [] {
            addFavorite(favorite, to: menu)
        }

        configureFavoritesMenuItems(menu)
        applyFavoritesFilter()
    }

    func titleForSaveCurrentFavoriteMenuItem() -> String {
        if queryTextView.selectedRange().length > 0 {
            return NSLocalizedString("Save Selection to Favorites", comment: "save selection to favorites menu item")
        }

        if currentQueryRange.length > 0 {
            return NSLocalizedString("Save Current Query to Favorites", comment: "save current query to favorites menu item")
        }

        return NSLocalizedString("Save All to Favorites", comment: "save all to favorites menu item")
    }

    func favoriteMatchesFilter(_ favorite: [String: Any], filterText: String) -> Bool {
        guard !filterText.isEmpty else { return true }
        let name = favorite["name"] as? String ?? ""
        let query = favorite["query"] as? String ?? ""
        let tabTrigger = favorite["tabtrigger"] as? String ?? ""
        return name.localizedCaseInsensitiveContains(filterText)
            || query.localizedCaseInsensitiveContains(filterText)
            || tabTrigger.localizedCaseInsensitiveContains(filterText)
    }

    func addFavorite(_ favorite: [String: Any], to menu: NSMenu) {
        guard let name = favorite["name"] as? String else { return }

        let item = NSMenuItem(title: name, action: #selector(chooseQueryFavorite(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = favorite
        item.toolTip = favorite["query"] as? String
        item.indentationLevel = 1

        if let tabTrigger = favorite["tabtrigger"] as? String, !tabTrigger.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = []
            paragraph.addTabStop(NSTextTab(type: .rightTabStopType, location: 190))
            item.attributedTitle = NSAttributedString(string: "\(name)\t\(tabTrigger)\u{21E5}",
                                                      attributes: [.paragraphStyle: paragraph, .font: NSFont.systemFont(ofSize: 11)])
        }

        menu.addItem(item)
    }

    func configureHistoryMenuShellIfNeeded() {
        guard historySearchMenuItem == nil else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let titleItem = NSMenuItem(title: NSLocalizedString("Query History", comment: "query history menu title"), action: nil, keyEquivalent: "")
        titleItem.isHidden = true
        menu.addItem(titleItem)

        let copyItem = NSMenuItem(title: NSLocalizedString("Copy History", comment: "copy query history menu item"), action: #selector(copyQueryHistory(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let saveItem = NSMenuItem(title: NSLocalizedString("Save History...", comment: "save query history menu item"), action: #selector(saveQueryHistory(_:)), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        let clearItem = NSMenuItem(title: clearHistoryMenuTitle(), action: #selector(clearQueryHistory(_:)), keyEquivalent: "")
        clearItem.target = self
        configureClearHistoryMenuItem(clearItem)
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem(title: "..placeholder for seachfield..",
                                    action: nil,
                                    keyEquivalent: "")
        searchItem.isEnabled = true
        searchItem.view = historySearchFieldView
        menu.addItem(searchItem)
        menu.addItem(.separator())

        historySearchMenuItem = searchItem
        historyMenu = menu
    }

    func rebuildHistoryMenu() {
        configureHistoryMenuShellIfNeeded()
        guard let menu = historyMenu else { return }

        while menu.numberOfItems > queryMenuDynamicStartIndex {
            menu.removeItem(at: menu.numberOfItems - 1)
        }

        historySearchMenuItem?.view = historySearchFieldView

        if let documentURL {
            for history in SPQueryController.shared().history(forFileURL: documentURL) as? [String] ?? [] {
                let title = history.count > 64 ? "\(history.prefix(63))..." : history
                let item = NSMenuItem(title: title, action: #selector(chooseQueryHistory(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = history
                item.toolTip = history.count > 256 ? "\(history.prefix(255))..." : history
                menu.addItem(item)
            }
        }

        configureHistoryMenuItems(menu)
        applyHistoryFilter()
    }

    @objc func chooseQueryFavorite(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        let query = (item.representedObject as? [String: Any])?["query"] as? String
            ?? item.representedObject as? String
        guard let query else { return }
        insertQuery(query, replacingContentByDefault: UserDefaults.standard.bool(forKey: SPQueryFavoriteReplacesContent))
    }

    @objc func showQueryFavoritesMenu(_ sender: Any?) {
        rebuildFavoritesMenu()
        popUpQueryMenu(favoritesMenu, from: favoritesButton)
    }

    @objc func showQueryHistoryMenu(_ sender: Any?) {
        rebuildHistoryMenu()
        popUpQueryMenu(historyMenu, from: historyButton)
    }

    func popUpQueryMenu(_ menu: NSMenu?, from button: NSButton) {
        guard let menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    func configureFavoritesMenuItems(_ menu: NSMenu) {
        let canSave = !isRunning && !queryTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        for item in menu.items {
            switch item.action {
            case #selector(saveCurrentQueryToFavorites(_:)):
                item.title = titleForSaveCurrentFavoriteMenuItem()
                item.isEnabled = canSave
            case #selector(saveAllQueriesToFavorites(_:)):
                item.isEnabled = canSave
            case #selector(editQueryFavorites(_:)), #selector(chooseQueryFavorite(_:)):
                item.isEnabled = !isRunning
            default:
                break
            }
        }
    }

    func configureHistoryMenuItems(_ menu: NSMenu) {
        let hasHistory: Bool
        if let documentURL {
            hasHistory = !(SPQueryController.shared().history(forFileURL: documentURL) as? [String] ?? []).isEmpty
        } else {
            hasHistory = false
        }

        for item in menu.items {
            switch item.action {
            case #selector(copyQueryHistory(_:)), #selector(saveQueryHistory(_:)), #selector(clearQueryHistory(_:)):
                if item.action == #selector(clearQueryHistory(_:)) {
                    configureClearHistoryMenuItem(item)
                }
                item.isEnabled = !isRunning && hasHistory
            case #selector(chooseQueryHistory(_:)):
                item.isEnabled = !isRunning
            default:
                break
            }
        }
    }

    func applyFavoritesFilter() {
        guard let menu = favoritesMenu else { return }
        let filterText = favoriteSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        for item in menu.items where item.action == #selector(chooseQueryFavorite(_:)) {
            guard let favorite = item.representedObject as? [String: Any] else { continue }
            item.isHidden = !favoriteMatchesFilter(favorite, filterText: filterText)
        }
    }

    func applyHistoryFilter() {
        guard let menu = historyMenu else { return }
        let filterText = historySearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        for item in menu.items where item.action == #selector(chooseQueryHistory(_:)) {
            guard let history = item.representedObject as? String else { continue }
            item.isHidden = !filterText.isEmpty && !history.localizedCaseInsensitiveContains(filterText)
        }
    }

    @objc func filterQueryFavorites(_ sender: Any?) {
        applyFavoritesFilter()
    }

    @objc func filterQueryHistory(_ sender: Any?) {
        applyHistoryFilter()
    }

    @objc func saveCurrentQueryToFavorites(_ sender: Any?) {
        saveQueryToFavorites(queryTextForCurrentFavoriteAction())
    }

    @objc func saveAllQueriesToFavorites(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            saveQueryToFavorites(queryTextForCurrentFavoriteAction())
            return
        }

        saveQueryToFavorites(queryTextView.string)
    }

    @objc func editQueryFavorites(_ sender: Any?) {
        guard let window = view.window,
              let manager = SPQueryFavoriteManager(delegate: self),
              let managerWindow = manager.window else {
            NSSound.beep()
            return
        }

        favoritesManager = manager
        window.beginSheet(managerWindow) { [weak self] _ in
            self?.favoritesManager = nil
        }
    }

    @objc func exportQueryResultAsCSV(_ sender: Any?) {
        exportQueryResult(fileExtension: "csv", content: csvStringForCurrentResult())
        exportButton.selectItem(at: 0)
    }

    @objc func exportQueryResultAsXML(_ sender: Any?) {
        exportQueryResult(fileExtension: "xml", content: xmlStringForCurrentResult())
        exportButton.selectItem(at: 0)
    }

    @objc func chooseQueryHistory(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let query = item.representedObject as? String else { return }
        insertQuery(query, replacingContentByDefault: UserDefaults.standard.bool(forKey: SPQueryHistoryReplacesContent))
    }

    @objc func copyQueryHistory(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(buildHistoryString(), forType: .string)
    }

    @objc func saveQueryHistory(_ sender: Any?) {
        let prefs = UserDefaults.standard
        if prefs.integer(forKey: SPLastSQLFileEncoding) == 0 {
            prefs.set(String.Encoding.utf8.rawValue, forKey: SPLastSQLFileEncoding)
        }

        let selectedEncoding = String.Encoding(rawValue: UInt(prefs.integer(forKey: SPLastSQLFileEncoding)))
        let encodingAccessory = SALightweightSQLImportEncodingAccessory(selectedEncoding: selectedEncoding)
        let panel = NSSavePanel()
        if let contentType = UTType(filenameExtension: SPFileExtensionSQL as String) {
            panel.allowedContentTypes = [contentType]
        }
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = true
        panel.canSelectHiddenExtension = true
        panel.canCreateDirectories = true
        panel.accessoryView = encodingAccessory.view
        panel.nameFieldStringValue = "history"
        if panel.runModal() == .OK, let url = panel.url {
            let encoding = encodingAccessory.selectedEncoding
            prefs.set(encoding.rawValue, forKey: SPLastSQLFileEncoding)

            do {
                try buildHistoryString().write(to: url, atomically: true, encoding: encoding)
            } catch {
                NSAlert(error: error).runModalCenteredInKeyWindow()
            }
        }
    }

    @objc func clearQueryHistory(_ sender: Any?) {
        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = NSLocalizedString("Clear History?", comment: "clear history message")
        alert.informativeText = clearHistoryConfirmationMessage()
        alert.addButton(withTitle: NSLocalizedString("Clear", comment: "clear button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn, let documentURL else { return }
        SPQueryController.shared().replaceHistory(by: [], forFileURL: documentURL)
    }

    func configureClearHistoryMenuItem(_ menuItem: NSMenuItem) {
        menuItem.title = clearHistoryMenuTitle()
        menuItem.toolTip = clearHistoryMenuToolTip()
    }

    func clearHistoryMenuTitle() -> String {
        if isUntitledQueryDocument {
            return NSLocalizedString("Clear Global History", comment: "clear global history menu item title")
        }

        return String(format: NSLocalizedString("Clear History for “%@”", comment: "clear history for “%@” menu title"), historyDocumentDisplayName())
    }

    func clearHistoryMenuToolTip() -> String {
        if isUntitledQueryDocument {
            return NSLocalizedString("Clear the global history list", comment: "clear the global history list tooltip message")
        }

        return NSLocalizedString("Clear the document-based history list", comment: "clear the document-based history list tooltip message")
    }

    func clearHistoryConfirmationMessage() -> String {
        if isUntitledQueryDocument {
            return NSLocalizedString("Are you sure you want to clear the global history list? This action cannot be undone.", comment: "clear global history list informative message")
        }

        return String(format: NSLocalizedString("Are you sure you want to clear the history list for “%@”? This action cannot be undone.", comment: "clear history list for “%@” informative message"), historyDocumentDisplayName())
    }

    func historyDocumentDisplayName() -> String {
        guard let documentURL else {
            return NSLocalizedString("Untitled", comment: "Name for an untitled connection")
        }

        let displayName = documentURL.isFileURL ? documentURL.lastPathComponent : documentURL.absoluteString
        return displayName.removingPercentEncoding ?? displayName
    }

    func queryTextForCurrentFavoriteAction() -> String {
        let selection = queryTextView.selectedRange()
        if selection.length > 0 {
            return (queryTextView.string as NSString).substring(with: selection)
        }

        if currentQueryRange.length > 0 {
            return (queryTextView.string as NSString).substring(with: currentQueryRange)
        }

        return queryTextView.string
    }

    func saveQueryToFavorites(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            let alert = NSAlert()
            alert.window.animationBehavior = .none
            alert.messageText = NSLocalizedString("Empty query", comment: "empty query message")
            alert.informativeText = NSLocalizedString("Cannot save an empty query.", comment: "empty query informative message")
            alert.runModalCenteredInKeyWindow()
            return
        }

        let nameField = NSTextField(frame: NSRect(x: 0, y: 24, width: 260, height: 22))
        nameField.placeholderString = NSLocalizedString("Favorite Name", comment: "query favorite name placeholder")

        let globalCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Save Globally", comment: "save query favorite globally checkbox"),
                                      target: nil,
                                      action: nil)
        globalCheckbox.frame = NSRect(x: 0, y: 0, width: 260, height: 18)
        globalCheckbox.state = .on
        globalCheckbox.isEnabled = !isUntitledQueryDocument

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 50))
        accessoryView.addSubview(nameField)
        accessoryView.addSubview(globalCheckbox)

        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = NSLocalizedString("Save Query to Favorites", comment: "save query favorite alert title")
        alert.informativeText = NSLocalizedString("Enter a name for the query favorite.", comment: "save query favorite alert message")
        alert.accessoryView = accessoryView
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "save button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NSSound.beep()
            return
        }

        let favorite: [String: Any] = ["name": name, "query": query]
        if globalCheckbox.state == .on || documentURL == nil || isUntitledQueryDocument {
            var favorites = UserDefaults.standard.array(forKey: SPQueryFavorites) as? [[String: Any]] ?? []
            favorites.append(favorite)
            UserDefaults.standard.set(favorites, forKey: SPQueryFavorites)
        } else if let documentURL {
            SPQueryController.shared().addFavorite(favorite, forFileURL: documentURL)
        }

        NotificationCenter.default.post(name: .SPQueryFavoritesHaveBeenUpdated, object: self)
    }

    func insertQuery(_ query: String, replacingContentByDefault replaceContent: Bool) {
        var shouldReplaceContent = replaceContent
        if NSApp.currentEvent?.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty == false {
            shouldReplaceContent.toggle()
        }

        queryTextView.breakUndoCoalescing()

        if shouldReplaceContent {
            replaceEditorText(query)
        } else {
            var insertedQuery = query
            if !queryTextView.string.isEmpty {
                insertedQuery = "\n" + insertedQuery
            }

            var selectedRange = queryTextView.selectedRange()
            if selectedRange.length == 0 {
                selectedRange = NSRange(location: queryTextView.textStorage?.length ?? queryTextView.string.count, length: 0)
            }

            queryTextView.insert(asSnippet: insertedQuery, at: selectedRange)
            queryTextView.doSyntaxHighlighting(withForce: true)
        }
    }

    func replaceEditorText(_ query: String, marksUserEdited: Bool = true) {
        isApplyingProgrammaticQueryText = true
        if queryTextView.shouldChangeText(in: NSRange(location: 0, length: queryTextView.string.count), replacementString: query) {
            queryTextView.string = query
            textViewWasChanged = true
            didCacheCurrentQueryRanges = false
            queryTextView.didChangeText()
            queryTextView.scrollRangeToVisible(NSRange(location: query.count, length: 0))
            if query.count < SP_TEXT_SIZE_MAX_PASTE_LENGTH {
                queryTextView.doSyntaxHighlighting(withForce: true)
            }
        }
        isApplyingProgrammaticQueryText = false
        shouldPersistCurrentQueryText = marksUserEdited && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        updateCurrentQueryRange()
    }

    func publishQueryColumns(_ definitions: [NSDictionary], token: UUID) {
        guard queryToken == token, !definitions.isEmpty else { return }

        let canPreserveColumns = isApplyingQuerySort && definitions.count == columnDefinitions.count
        columnDefinitions = definitions
        rows = []
        displayCache.invalidateAll()
        if canPreserveColumns {
            tableView.noteNumberOfRowsChanged()
            applyQuerySortIndicator()
        } else {
            columnWidthCache.invalidateAll()
            rebuildColumns()
        }
        setStatusText(NSLocalizedString("Loading rows...", comment: "lightweight query loading rows status"))
    }

    func publishQueryRows(_ newRows: [[Any]], token: UUID, forceDisplay: Bool = false) {
        let publishStart = CFAbsoluteTimeGetCurrent()
        defer {
            SALightweightResultGrid.logPerformance("Query publish rows", start: publishStart, details: "newRows=\(newRows.count) totalRows=\(rows.count) columns=\(columnDefinitions.count)", minimumMilliseconds: 1)
        }

        guard queryToken == token, !newRows.isEmpty else { return }

        rows.append(contentsOf: newRows)
        tableView.noteNumberOfRowsChanged()
        if !isApplyingQuerySort {
            scheduleVisibleColumnAutosize(delay: 0.05)
        }

        if forceDisplay {
            tableView.layoutSubtreeIfNeeded()
            tableView.enclosingScrollView?.displayIfNeeded()
            tableView.displayIfNeeded()
        }

        setStatusText(String(format: NSLocalizedString("Loading rows... %ld loaded", comment: "lightweight query loading rows status"), rows.count))
    }

    func rebuildColumns() {
        let benchmarkStart = CFAbsoluteTimeGetCurrent()
        defer {
            updateDataTableBundleSupport()
            SALightweightResultGrid.logPerformance("Query rebuild columns", start: benchmarkStart, details: "columns=\(columnDefinitions.count) rows=\(rows.count)", minimumMilliseconds: 4)
        }

        let showColumnTypes = UserDefaults.standard.bool(forKey: SPDisplayTableViewColumnTypes)
        let tableFont = UserDefaults.getFont()
        preserveResultColumnWidths()
        let columnSignature = currentColumnSignature()

        if columnSignature == displayedColumnSignature,
           tableView.tableColumns.count == columnDefinitions.count {
            updateExistingColumns(font: tableFont, showColumnTypes: showColumnTypes)
            applyQuerySortIndicator()
            tableView.headerView?.needsDisplay = true
            scheduleVisibleColumnAutosize(delay: 0.01)
            return
        }

        tableView.tableColumns.forEach {
            $0.headerToolTip = nil
            tableView.removeTableColumn($0)
        }

        for (index, columnDefinition) in columnDefinitions.enumerated() {
            let columnName = (columnDefinition["name"] as? String) ?? ""
            let tableColumn = SALightweightResultGrid.configuredColumn(
                identifier: index,
                title: columnName,
                descriptor: Self.gridColumnDescriptor(columnDefinition, fallbackName: columnName),
                font: tableFont,
                editable: true,
                headerToolTip: headerToolTip(for: columnDefinition),
                headerAttributedString: columnDefinition.tableContentColumnHeaderAttributedString(columnTypesVisible: showColumnTypes),
                savedWidth: savedResultColumnWidth(for: columnDefinition) ?? resultColumnWidths[resultColumnWidthKey(for: columnDefinition, fallbackIndex: index)],
                minWidth: 40,
                resizingMask: .userResizingMask
            )
            tableView.addTableColumn(tableColumn)
        }

        displayedColumnSignature = columnSignature
        tableView.reloadData()
        applyQuerySortIndicator()
        scheduleVisibleColumnAutosize(delay: 0.01)
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

    func applyQuerySortIndicator() {
        SALightweightResultGrid.applySortIndicator(to: tableView, columnIndex: querySortColumnIndex, ascending: querySortAscending)
    }

    private func captureResultGridViewState() -> ResultGridViewState {
        let firstVisibleRow: Int?
        if let clipView = tableView.enclosingScrollView?.contentView {
            let visibleRect = clipView.documentVisibleRect
            let visibleRow = tableView.row(at: NSPoint(x: visibleRect.minX, y: visibleRect.minY))
            firstVisibleRow = visibleRow >= 0 ? visibleRow : nil
        } else {
            firstVisibleRow = nil
        }

        return ResultGridViewState(selectedRows: tableView.selectedRowIndexes,
                                   firstVisibleRow: firstVisibleRow,
                                   columnDefinitions: columnDefinitions,
                                   rows: rows,
                                   lastExecutedQuery: lastExecutedQuery,
                                   lastResultQuery: lastResultQuery)
    }

    private func restorePendingResultGridViewState() {
        guard let state = pendingResultGridViewState else { return }
        pendingResultGridViewState = nil
        restoreResultGridViewState(state)
    }

    private func restoreResultGridViewState(_ state: ResultGridViewState) {
        guard !rows.isEmpty else { return }

        var validSelection = IndexSet()
        state.selectedRows.forEach { row in
            if row < rows.count {
                validSelection.insert(row)
            }
        }
        tableView.selectRowIndexes(validSelection, byExtendingSelection: false)

        if let firstVisibleRow = state.firstVisibleRow {
            tableView.scrollRowToVisible(min(max(firstVisibleRow, 0), rows.count - 1))
        } else if let firstSelection = validSelection.first {
            tableView.scrollRowToVisible(firstSelection)
        }

        updateStatusSelectionSuffix()
    }

    func scheduleVisibleColumnAutosize(delay: TimeInterval = 0.05) {
        autosizeCoordinator.schedule(delay: delay) { [weak self] in
            self?.autosizeResultColumns()
        }
    }

    func currentColumnSignature() -> [String] {
        return columnDefinitions.enumerated().map { index, definition in
            [
                "\(index)",
                (definition["name"] as? String) ?? "",
                (definition["org_name"] as? String) ?? "",
                (definition["org_table"] as? String) ?? "",
                (definition["db"] as? String) ?? "",
                (definition["type"] as? String) ?? "",
                (definition["typegrouping"] as? String) ?? "",
                String(describing: definition["char_length"] ?? "")
            ].joined(separator: "\u{1e}")
        }
    }

    func updateExistingColumns(font tableFont: NSFont, showColumnTypes: Bool) {
        for (index, columnDefinition) in columnDefinitions.enumerated() {
            guard index < tableView.tableColumns.count else { continue }

            let tableColumn = tableView.tableColumns[index]
            let columnName = (columnDefinition["name"] as? String) ?? ""
            SALightweightResultGrid.updateColumn(tableColumn,
                                                 identifier: index,
                                                 title: columnName,
                                                 descriptor: Self.gridColumnDescriptor(columnDefinition, fallbackName: columnName),
                                                 font: tableFont,
                                                 editable: true,
                                                 headerToolTip: headerToolTip(for: columnDefinition),
                                                 headerAttributedString: columnDefinition.tableContentColumnHeaderAttributedString(columnTypesVisible: showColumnTypes))
        }
        tableView.headerView?.needsDisplay = true
    }

    func autosizeResultColumns(onlyVisibleColumns: Bool = true) {
        let benchmarkStart = CFAbsoluteTimeGetCurrent()
        defer {
            SALightweightResultGrid.logPerformance("Query autosize columns", start: benchmarkStart, details: "columns=\(tableView.tableColumns.count) rows=\(rows.count) visibleOnly=\(onlyVisibleColumns)", minimumMilliseconds: 4)
        }

        isApplyingProgrammaticColumnWidths = true
        defer { isApplyingProgrammaticColumnWidths = false }

        let displayColumnIndexes = onlyVisibleColumns
            ? SALightweightResultGrid.visibleColumnIndexes(in: tableView, buffer: SALightweightResultGrid.autosizeColumnBuffer)
            : IndexSet(integersIn: 0..<tableView.tableColumns.count)
        let visibleRows = visibleDisplayRowsForResultAutosizing(maxRows: 64)

        SALightweightResultGrid.autosizeColumns(in: tableView,
                                                displayColumnIndexes: displayColumnIndexes,
                                                visibleRows: visibleRows,
                                                columnWidthCache: columnWidthCache,
                                                shouldSkipColumn: { [weak self] columnIndex, _ in
                                                    guard let self = self, columnIndex < self.columnDefinitions.count else { return true }
                                                    let columnDefinition = self.columnDefinitions[columnIndex]
                                                    let typeGrouping = (self.columnDefinitions[columnIndex]["typegrouping"] as? String) ?? ""
                                                    return SALightweightResultGrid.isWideTextColumn(typeGrouping: typeGrouping)
                                                        || self.savedResultColumnWidth(for: columnDefinition) != nil
                                                        || self.resultColumnWidths[self.resultColumnWidthKey(for: columnDefinition, fallbackIndex: columnIndex)] != nil
                                                },
                                                cacheKey: { [weak self] columnIndex, tableColumn, visibleRows in
                                                    self?.resultColumnWidthCacheKey(for: tableColumn, columnIndex: columnIndex, visibleRows: visibleRows) ?? tableColumn.identifier.rawValue
                                                },
                                                isEnumColumn: { _ in false },
                                                displayValue: { [weak self] row, columnIndex in
                                                    guard let self = self,
                                                          row < self.rows.count,
                                                          columnIndex < self.rows[row].count else { return "" }
                                                    return self.displayValue(row: row, column: columnIndex)
                                                })
    }

    func reloadCell(row: Int, columnIndex: Int) {
        SALightweightResultGrid.reloadCell(in: tableView, row: row, columnIndex: columnIndex)
    }

    func resultColumnWidthCacheKey(for tableColumn: NSTableColumn, columnIndex: Int, visibleRows: Range<Int>) -> String {
        let tableFont = UserDefaults.getFont()
        let definition = columnIndex < columnDefinitions.count ? columnDefinitions[columnIndex] : nil
        return [
            tableColumn.identifier.rawValue,
            (definition?["name"] as? String) ?? "",
            (definition?["org_name"] as? String) ?? "",
            (definition?["org_table"] as? String) ?? "",
            (definition?["type"] as? String) ?? "",
            (definition?["typegrouping"] as? String) ?? "",
            UserDefaults.standard.bool(forKey: SPDisplayTableViewColumnTypes) ? "types" : "names",
            tableFont.fontName,
            "\(tableFont.pointSize)",
            "\(rows.count)",
            "\(visibleRows.lowerBound)-\(visibleRows.upperBound)"
        ].joined(separator: "\u{1e}")
    }

    func visibleDisplayRowsForResultAutosizing(maxRows: Int) -> Range<Int> {
        guard maxRows > 0, !rows.isEmpty else { return 0..<0 }

        let visibleRange = tableView.rows(in: tableView.visibleRect)
        let start = visibleRange.length > 0 ? visibleRange.location : 0
        let end = visibleRange.length > 0 ? min(rows.count, visibleRange.location + visibleRange.length) : min(rows.count, maxRows)
        guard start < end else { return 0..<min(rows.count, maxRows) }

        return start..<min(end, start + maxRows)
    }

    static func gridColumnDescriptor(_ columnDefinition: NSDictionary, fallbackName: String) -> SALightweightResultGrid.ColumnDescriptor {
        return SALightweightResultGrid.ColumnDescriptor(name: (columnDefinition["name"] as? String) ?? fallbackName,
                                                        type: (columnDefinition["type"] as? String) ?? "",
                                                        typeGrouping: (columnDefinition["typegrouping"] as? String) ?? "",
                                                        length: String(describing: columnDefinition["char_length"] ?? ""))
    }

    func headerToolTip(for columnDefinition: NSDictionary) -> String? {
        guard let name = columnDefinition["name"] as? String,
              let type = columnDefinition["type"] as? String else { return nil }

        let lengthSuffix = columnDefinition["char_length"].map { "(\($0))" } ?? ""
        return "\(name) - \(type)\(lengthSuffix)"
    }

    func updateStatus(for result: QueryResult, queryCount: Int) {
        let time = String(format: "%.3fs", result.executionTime)
        let statusTitle = result.errorText?.isEmpty == false
            ? NSLocalizedString("Errors", comment: "Errors title")
            : NSLocalizedString("No errors", comment: "No errors title")

        if result.wasCancelled {
            if result.queriesRun > 1 {
                setStatusText(String(format: NSLocalizedString("%@; Cancelled in query %ld, after %@", comment: "text showing multiple queries were cancelled"), statusTitle, result.queriesRun, time))
            } else {
                setStatusText(String(format: NSLocalizedString("%@; Cancelled after %@", comment: "text showing a query was cancelled"), statusTitle, time))
            }
        } else if result.columnDefinitions.isEmpty {
            setStatusText(queryCount > 1
                ? String(format: NSLocalizedString("%@; %llu rows affected by %ld queries, taking %@", comment: "lightweight query multiple affected rows status"), statusTitle, result.affectedRows, queryCount, time)
                : String(format: NSLocalizedString("%@; %llu rows affected, taking %@", comment: "lightweight query affected rows status"), statusTitle, result.affectedRows, time))
        } else {
            let suffix = result.truncated
                ? String(format: NSLocalizedString("; showing first %ld rows", comment: "lightweight query truncated rows suffix"), maxDisplayedRows)
                : ""
            setStatusText(String(format: NSLocalizedString("%@; %ld rows loaded%@, first row available after %@", comment: "lightweight query rows loaded status"), statusTitle, result.rows.count, suffix, time))
        }
    }

    func queryByApplyingDisplayLimit(to query: String) -> String {
        let maskedQuery = queryMaskedForClauseSearch(query)
        guard firstRegexRange(in: maskedQuery, pattern: #"(?is)^\s*\(?\s*SELECT\b"#) != nil,
              firstRegexRange(in: maskedQuery, pattern: #"(?is)\s+LIMIT\b"#) == nil else {
            return query
        }

        let limitClause = " LIMIT \(maxDisplayedRows + 1)"
        let queryNSString = query as NSString
        let mutableQuery = NSMutableString(string: query)
        let trailingSemicolonRange = firstRegexRange(in: maskedQuery, pattern: #"(?s);\s*$"#)
        let insertionLimit = trailingSemicolonRange?.location ?? queryNSString.length
        let prefix = (maskedQuery as NSString).substring(to: insertionLimit)

        if let suffixRange = firstRegexRange(in: prefix, pattern: #"(?is)\s+(?:PROCEDURE|INTO|FOR|LOCK)\b"#) {
            mutableQuery.insert(limitClause, at: suffixRange.location)
        } else {
            mutableQuery.insert(limitClause, at: insertionLimit)
        }

        return mutableQuery as String
    }

    func queryByApplyingSort(to query: String, columnIndex: Int, descending: Bool) -> String {
        let orderClause = " ORDER BY \(columnIndex + 1) \(descending ? "DESC" : "ASC") "
        let maskedQuery = queryMaskedForClauseSearch(query)
        let queryNSString = query as NSString
        let mutableQuery = NSMutableString(string: query)
        let trailingSemicolonRange = firstRegexRange(in: maskedQuery, pattern: #"(?s);\s*$"#)
        let insertionLimit = trailingSemicolonRange?.location ?? queryNSString.length
        let prefix = (maskedQuery as NSString).substring(to: insertionLimit)

        if let existingOrderRange = firstRegexRange(in: prefix, pattern: #"(?is)\s+ORDER\s+BY\s+[\s\S]+?(?:\s+(?:DESC|ASC))?(?=\s+(?:LIMIT|PROCEDURE|INTO|FOR|LOCK)\b)"#) {
            mutableQuery.replaceCharacters(in: existingOrderRange, with: orderClause)
            return mutableQuery as String
        }

        if let trailingOrderRange = firstRegexRange(in: prefix, pattern: #"(?is)\s+ORDER\s+BY\s+[\s\S]*$"#) {
            mutableQuery.replaceCharacters(in: trailingOrderRange, with: orderClause)
            return mutableQuery as String
        }

        if let suffixRange = firstRegexRange(in: prefix, pattern: #"(?is)\s+(?:LIMIT|PROCEDURE|INTO|FOR|LOCK)\b"#),
           firstRegexRange(in: prefix, pattern: #"(?is)^\s*\(?\s*SELECT\b"#) != nil {
            mutableQuery.insert(orderClause, at: suffixRange.location)
            return mutableQuery as String
        }

        mutableQuery.insert(orderClause, at: insertionLimit)
        return mutableQuery as String
    }

    func queryMaskedForClauseSearch(_ query: String) -> String {
        let maskedQuery = NSMutableString(string: query)
        let quotedPatterns = [
            #"(?s)"(?:[^"\\]|\\.)*""#,
            #"(?s)'(?:[^'\\]|\\.)*'"#,
            #"(?s)`(?:[^`\\]|\\.)*`"#
        ]

        for pattern in quotedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            while true {
                let range = regex.rangeOfFirstMatch(in: maskedQuery as String, range: NSRange(location: 0, length: maskedQuery.length))
                if range.location == NSNotFound { break }
                maskedQuery.replaceCharacters(in: range, with: String(repeating: "_", count: range.length))
            }
        }

        let commentPatterns = [
            #"(?m)--(?=$|[ \t\r\n\f\v])[^\r\n]*(?:\r?\n|$)"#,
            #"(?m)#[^\r\n]*(?:\r?\n|$)"#,
            #"(?s)/\*.*?\*/"#
        ]

        for pattern in commentPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            while true {
                let range = regex.rangeOfFirstMatch(in: maskedQuery as String, range: NSRange(location: 0, length: maskedQuery.length))
                if range.location == NSNotFound { break }
                maskedQuery.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
            }
        }

        return maskedQuery as String
    }

    func firstRegexRange(in string: String, pattern: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = regex.rangeOfFirstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
        return range.location == NSNotFound ? nil : range
    }

    func updateControls() {
        let hasConnection = connection != nil
        runButton.isEnabled = hasConnection
        actionButton.isEnabled = !isRunning
        exportButton.isEnabled = !isRunning && !rows.isEmpty
        favoritesButton.isEnabled = !isRunning
        historyButton.isEnabled = !isRunning
        queryTextView.isEditable = !isRunning
        if isRunning {
            runButton.menu?.items.first?.title = runningQueryCount > 1
                ? NSLocalizedString("Stop queries", comment: "Stop queries string")
                : NSLocalizedString("Stop query", comment: "Stop query string")
        } else {
            updateContextualRunInterface()
        }
        updateRunMenuState()
    }

    @objc(currentResult)
    func currentResult() -> [[Any]] {
        return currentDataResult(withNULLs: false, truncateDataFields: true)
    }

    @objc(currentResultRowCount)
    func currentResultRowCount() -> Int {
        return rows.count
    }

    @objc(currentDataResultWithNULLs:truncateDataFields:)
    func currentDataResult(withNULLs includeNULLs: Bool, truncateDataFields truncate: Bool) -> [[Any]] {
        var result: [[Any]] = [tableView.tableColumns.enumerated().map { columnName(forVisibleColumn: $0.offset, tableColumn: $0.element) }]

        for row in rows {
            result.append(tableView.tableColumns.map { tableColumn in
                guard let columnIndex = Int(tableColumn.identifier.rawValue), columnIndex < row.count else { return "" }
                let value = row[columnIndex]
                if includeNULLs, value is NSNull {
                    return value
                }

                return displayString(for: value, columnDefinition: columnDefinition(at: columnIndex), truncate: truncate)
            })
        }

        return result
    }

    @objc(usedQuery)
    func usedQuery() -> String {
        return lastExecutedQuery
    }

    @objc(dataColumnDefinitions)
    func dataColumnDefinitionsForLegacyConsumers() -> [NSDictionary] {
        return columnDefinitions
    }

    @objc func copySelectedResultRows(_ sender: Any?) {
        let includeHeaders = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyWithColumnsTag
        guard let copyString = resultRowsAsTabString(includeHeaders: includeHeaders, rowIndexes: tableView.selectedRowIndexes) else {
            NSSound.beep()
            return
        }

        SALightweightResultGrid.copyStringToPasteboard(copyString)
    }

    @objc func copySelectedResultRowsAsSQL(_ sender: Any?) {
        let skipAutoIncrement = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLNoAutoIncTag
        guard let copyString = resultRowsAsSQLInserts(rowIndexes: tableView.selectedRowIndexes, skipAutoIncrement: skipAutoIncrement) else {
            NSSound.beep()
            return
        }

        SALightweightResultGrid.copySQLStringToPasteboard(copyString)
    }

    func exportQueryResult(fileExtension: String, content: String) {
        guard !rows.isEmpty else {
            NSSound.beep()
            return
        }

        SALightweightResultGrid.exportResult(fileExtension: fileExtension, content: content, defaultName: "query_result.\(fileExtension)")
    }

    func csvStringForCurrentResult() -> String {
        return SALightweightResultGrid.csvString(rowCount: rows.count,
                                                 tableColumns: tableView.tableColumns,
                                                 columnName: { self.columnName(for: $0) },
                                                 value: { self.resultDisplayValue(row: $0, tableColumn: $1) })
    }

    func xmlStringForCurrentResult() -> String {
        return SALightweightResultGrid.xmlString(rowCount: rows.count,
                                                 tableColumns: tableView.tableColumns,
                                                 columnName: { self.columnName(for: $0) },
                                                 value: { self.resultDisplayValue(row: $0, tableColumn: $1) })
    }

    func columnName(for index: Int, definition: NSDictionary) -> String {
        return (definition["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Column \(index + 1)"
    }

    func columnName(forVisibleColumn visibleColumn: Int, tableColumn: NSTableColumn) -> String {
        guard let columnIndex = Int(tableColumn.identifier.rawValue), columnIndex < columnDefinitions.count else {
            return "Column \(visibleColumn + 1)"
        }

        return columnName(for: columnIndex, definition: columnDefinitions[columnIndex])
    }

    func columnName(for tableColumn: NSTableColumn) -> String {
        let visibleColumn = tableView.tableColumns.firstIndex(of: tableColumn) ?? 0
        return columnName(forVisibleColumn: visibleColumn, tableColumn: tableColumn)
    }

    func resultDisplayValue(row: Int, tableColumn: NSTableColumn) -> String? {
        guard row < rows.count,
              let columnIndex = Int(tableColumn.identifier.rawValue),
              columnIndex < rows[row].count else { return nil }

        return displayString(for: rows[row][columnIndex], columnDefinition: columnDefinition(at: columnIndex))
    }

    func resultRowsAsTabString(includeHeaders: Bool, rowIndexes: IndexSet) -> String? {
        return SALightweightResultGrid.tabString(includeHeaders: includeHeaders,
                                                 rowIndexes: rowIndexes,
                                                 tableColumns: tableView.tableColumns,
                                                 rowCount: rows.count,
                                                 columnName: { self.columnName(for: $0) },
                                                 value: { self.resultDisplayValue(row: $0, tableColumn: $1) })
    }

    func resultRowsAsTabStringForBundle(includeHeaders: Bool, rowIndexes: IndexSet, requireRows: Bool, blobHandling: Int, blobFileDirectory: String?) -> String? {
        guard !requireRows || !rowIndexes.isEmpty else { return nil }

        var lines: [String] = []
        if includeHeaders {
            lines.append(tableView.tableColumns.map { SALightweightResultGrid.copyEscaped(columnName(for: $0)) }.joined(separator: "\t"))
        }

        for (displayRow, rowIndex) in rowIndexes.enumerated() where rowIndex < rows.count {
            lines.append(tableView.tableColumns.map { tableColumn in
                guard let value = bundleDisplayValue(row: rowIndex, displayRow: displayRow, tableColumn: tableColumn, blobHandling: blobHandling, blobFileDirectory: blobFileDirectory) else { return "" }
                return SALightweightResultGrid.copyEscaped(value)
            }.joined(separator: "\t"))
        }

        return lines.joined(separator: "\n")
    }

    func resultRowsAsCSVStringForBundle(includeHeaders: Bool, rowIndexes: IndexSet, requireRows: Bool, blobHandling: Int, blobFileDirectory: String?) -> String? {
        guard !requireRows || !rowIndexes.isEmpty else { return nil }

        var lines: [String] = []
        if includeHeaders {
            lines.append(tableView.tableColumns.map { SALightweightResultGrid.csvEscaped(columnName(for: $0)) }.joined(separator: ","))
        }

        for (displayRow, rowIndex) in rowIndexes.enumerated() where rowIndex < rows.count {
            lines.append(tableView.tableColumns.map { tableColumn in
                SALightweightResultGrid.csvEscaped(bundleDisplayValue(row: rowIndex,
                                                                     displayRow: displayRow,
                                                                     tableColumn: tableColumn,
                                                                     blobHandling: blobHandling,
                                                                     blobFileDirectory: blobFileDirectory) ?? "")
            }.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    func bundleDisplayValue(row rowIndex: Int, displayRow: Int, tableColumn: NSTableColumn, blobHandling: Int, blobFileDirectory: String?) -> String? {
        guard rowIndex >= 0,
              rowIndex < rows.count,
              let columnIndex = Int(tableColumn.identifier.rawValue),
              columnIndex < rows[rowIndex].count else { return nil }

        let value = rows[rowIndex][columnIndex]
        if value is NSNull {
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        if let data = value as? Data {
            switch blobHandling {
            case bundleBlobHandlingInclude:
                return displayString(for: data, columnDefinition: columnDefinition(at: columnIndex))
            case bundleBlobHandlingFileReference:
                return writeBundleBlob(data, row: displayRow, column: columnIndex, fileExtension: "dat", blobFileDirectory: blobFileDirectory)
            case bundleBlobHandlingImageFileReference:
                let imageData = NSImage(data: data)?.tiffRepresentation ?? Data()
                return writeBundleBlob(imageData, row: displayRow, column: columnIndex, fileExtension: "tif", blobFileDirectory: blobFileDirectory)
            default:
                return "BLOB"
            }
        }

        return displayString(for: value, columnDefinition: columnDefinition(at: columnIndex))
    }

    func writeBundleBlob(_ data: Data, row: Int, column: Int, fileExtension: String, blobFileDirectory: String?) -> String {
        guard let blobFileDirectory, !blobFileDirectory.isEmpty else { return "" }

        do {
            try FileManager.default.createDirectory(atPath: blobFileDirectory, withIntermediateDirectories: true)
            let path = (blobFileDirectory as NSString).appendingPathComponent("\(row)_\(column).\(fileExtension)")
            try data.write(to: URL(fileURLWithPath: path), options: [])
            return path
        } catch {
            return ""
        }
    }

    func resultRowsAsSQLInserts(rowIndexes: IndexSet, skipAutoIncrement: Bool) -> String? {
        guard !rowIndexes.isEmpty, let connection else { return nil }

        let includedColumns = sqlInsertColumnIndexes(skipAutoIncrement: skipAutoIncrement)
        guard !includedColumns.isEmpty else { return nil }

        let tableName = sqlInsertTableName()
        let columnList = includedColumns.map { Self.backtickQuoted(columnName(for: $0, definition: columnDefinitions[$0])) }.joined(separator: ", ")
        var result = "INSERT INTO \(tableName) (\(columnList))\nVALUES\n"
        var valueBuffer = ""
        var copiedRows = 0

        rowIndexes.forEach { rowIndex in
            guard rowIndex < rows.count else { return }

            let row = rows[rowIndex]
            let values = includedColumns.map { columnIndex -> String in
                guard columnIndex < row.count else { return "NULL" }
                return sqlInsertValue(for: row[columnIndex], columnDefinition: columnDefinitions[columnIndex], connection: connection)
            }

            if copiedRows > 0 {
                if valueBuffer.count > 250_000 {
                    result += "\(valueBuffer));\n\nINSERT INTO \(tableName) (\(columnList))\nVALUES\n"
                    valueBuffer = ""
                } else {
                    valueBuffer += "),\n"
                }
            }

            valueBuffer += "\t(\(values.joined(separator: ", "))"
            copiedRows += 1
        }

        guard copiedRows > 0 else { return nil }

        result += valueBuffer + ");\n"
        return result
    }

    func sqlInsertColumnIndexes(skipAutoIncrement: Bool) -> [Int] {
        return tableView.tableColumns.compactMap { tableColumn -> Int? in
            guard let columnIndex = Int(tableColumn.identifier.rawValue),
                  columnIndex < columnDefinitions.count else { return nil }

            let columnDefinition = columnDefinitions[columnIndex]
            if columnDefinition["generatedalways"] != nil {
                return nil
            }

            if skipAutoIncrement, Self.dictionaryBool(columnDefinition, key: "autoincrement") || Self.dictionaryBool(columnDefinition, key: "AUTO_INCREMENT_FLAG") {
                return nil
            }

            return columnIndex
        }
    }

    func sqlInsertTableName() -> String {
        var tableNames = Set<String>()

        for columnDefinition in columnDefinitions {
            if let tableName = columnDefinition["org_table"] as? String, !tableName.isEmpty {
                tableNames.insert(tableName)
            }
        }

        if tableNames.count == 1, let tableName = tableNames.first {
            return Self.backtickQuoted(tableName)
        }

        return "<table>"
    }

    func sqlInsertValue(for value: Any, columnDefinition: NSDictionary, connection: SPMySQLConnection) -> String {
        if value is NSNull {
            return "NULL"
        }

        let type = ((columnDefinition["type"] as? String) ?? "").lowercased()
        let typeGrouping = ((columnDefinition["typegrouping"] as? String) ?? "").lowercased()

        if value is Data {
            return sqlValue(forStoredObject: value, columnDefinition: columnDefinition, connection: connection)
        }

        if typeGrouping == "integer" || typeGrouping == "float" || type == "year" {
            return displayString(for: value, truncate: false)
        }

        return sqlValue(forStoredObject: value, columnDefinition: columnDefinition, connection: connection)
    }

    func updateActionMenuState() {
        guard let menu = actionButton.menu else { return }

        for item in menu.items {
            switch item.action {
            case #selector(commentCurrentQuery(_:)):
                item.isEnabled = currentQueryRange.length > 0
            case #selector(commentLineOrSelection(_:)):
                item.title = queryTextView.selectedRange().length > 0
                    ? NSLocalizedString("Comment Selection", comment: "comment selection menu item")
                    : NSLocalizedString("Comment Line", comment: "comment line menu item")
            case #selector(toggleHistoryReplacesContent(_:)):
                item.state = UserDefaults.standard.bool(forKey: SPQueryHistoryReplacesContent) ? .on : .off
            case #selector(toggleFavoriteReplacesContent(_:)):
                item.state = UserDefaults.standard.bool(forKey: SPQueryFavoriteReplacesContent) ? .on : .off
            case #selector(toggleAutoindent(_:)):
                item.state = UserDefaults.standard.bool(forKey: SPCustomQueryAutoIndent) ? .on : .off
            case #selector(toggleAutopair(_:)):
                item.state = UserDefaults.standard.bool(forKey: SPCustomQueryAutoPairCharacters) ? .on : .off
            case #selector(toggleAutocomplete(_:)):
                item.state = UserDefaults.standard.bool(forKey: SPCustomQueryAutoComplete) ? .on : .off
            case #selector(toggleAutouppercaseKeywords(_:)):
                item.state = UserDefaults.standard.bool(forKey: SPCustomQueryAutoUppercaseKeywords) ? .on : .off
            case #selector(toggleAutohelp(_:)):
                item.state = UserDefaults.standard.bool(forKey: SPCustomQueryUpdateAutoHelp) ? .on : .off
            default:
                break
            }
        }

        updateRunMenuState()
    }

    func togglePreference(_ key: String, sender: NSMenuItem, apply: (Bool) -> Void) {
        let isEnabled = sender.state == .off
        UserDefaults.standard.set(isEnabled, forKey: key)
        sender.state = isEnabled ? .on : .off
        apply(isEnabled)
    }

    func commentOutCurrentQuery(takingSelection takeSelection: Bool) {
        if UserDefaults.standard.bool(forKey: UseDashStyleForBlockComment) {
            commentOutCurrentQueryWithDashes(takingSelection: takeSelection)
            return
        }

        let oldRange = queryTextView.selectedRange()
        var workingRange = takeSelection ? oldRange : currentQueryRange
        guard workingRange.length > 0 else { return }

        var text = (queryTextView.string as NSString).substring(with: workingRange)
        if text.range(of: #"\n\z"#, options: .regularExpression) != nil {
            workingRange.length -= 1
            text = String(text.dropLast())
        }

        text = text.replacingOccurrences(of: #"\*/(?=.)"#, with: #"*\/"#, options: .regularExpression)
        text = text.replacingOccurrences(of: #"\*/(?=\n)"#, with: #"*\/"#, options: .regularExpression)

        var replacement = "/* " + text + " */"
        if replacement.range(of: #"^/\* \s*/\*\s*(.|\n)*?\s*\*/ \*/\s*$"#, options: .regularExpression) != nil {
            replacement = replacement.replacingOccurrences(of: #"^/\* \s*/\*\s*"#, with: "", options: .regularExpression)
            replacement = replacement.replacingOccurrences(of: #"\s*\*/ \*/\s*\z"#, with: "", options: .regularExpression)
            replacement = replacement.replacingOccurrences(of: #"*\/"#, with: "*/")
        }

        queryTextView.insertText(replacement, replacementRange: workingRange)
        queryTextView.setSelectedRange(NSRange(location: workingRange.location, length: replacement.count))
        updateCurrentQueryRange()
    }

    func commentOutCurrentQueryWithDashes(takingSelection takeSelection: Bool) {
        let workingRange = takeSelection ? queryTextView.selectedRange() : currentQueryRange
        guard workingRange.length > 0 else { return }

        let fullText = queryTextView.string as NSString
        let lineRange = fullText.lineRange(for: workingRange)
        let selectedText = fullText.substring(with: lineRange)
        let lines = selectedText.components(separatedBy: "\n")
        let commentMarker = "-- "

        let shouldUncomment = lines.first { line in
            line.rangeOfCharacter(from: CharacterSet.whitespaces.inverted) != nil
        }.flatMap { line -> Bool? in
            guard let firstCharacter = line.rangeOfCharacter(from: CharacterSet.whitespaces.inverted) else { return nil }
            return line[firstCharacter.lowerBound...].hasPrefix(commentMarker)
        } ?? false

        let modifiedLines = lines.map { line -> String in
            guard let firstCharacter = line.rangeOfCharacter(from: CharacterSet.whitespaces.inverted) else { return line }
            let prefix = String(line[..<firstCharacter.lowerBound])
            let suffix = line[firstCharacter.lowerBound...]

            if shouldUncomment {
                return suffix.hasPrefix(commentMarker) ? prefix + String(suffix.dropFirst(commentMarker.count)) : line
            }

            return prefix + commentMarker + suffix
        }

        let replacement = modifiedLines.joined(separator: "\n")
        if queryTextView.shouldChangeText(in: lineRange, replacementString: replacement) {
            queryTextView.replaceCharacters(in: lineRange, with: replacement)
            queryTextView.didChangeText()
            queryTextView.setSelectedRange(NSRange(location: lineRange.location, length: replacement.count))
            updateCurrentQueryRange()
        }
    }

    func setQueryInfoPaneVisible(_ isVisible: Bool) {
        infoPaneView.isHidden = !isVisible
        if queryInfoPaneSplitView.bounds.height > 0 {
            let dividerPosition = isVisible
                ? max(120, queryInfoPaneSplitView.bounds.height - 120)
                : max(0, queryInfoPaneSplitView.bounds.height - queryInfoPaneSplitView.dividerThickness)
            queryInfoPaneSplitView.setPosition(dividerPosition, ofDividerAt: 0)
            queryInfoPaneSplitView.adjustSubviews()
        }
        queryInfoButton.state = isVisible ? .on : .off
    }

    func updateQueryInfo(title: String, message: String, isError: Bool) {
        infoTitleLabel.stringValue = title
        infoTextView.textColor = isError ? .systemRed : .labelColor
        infoTextView.string = message
        setQueryInfoPaneVisible(isError)
    }

    func setStatusText(_ status: String) {
        baseStatusText = status
        updateStatusSelectionSuffix()
    }

    func canRunExplainQueryAction() -> Bool {
        return !isRunning && connection != nil && !queryTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reportUnsupportedExplain() {
        let message = NSLocalizedString("EXPLAIN is only supported for a single SELECT or WITH statement.", comment: "EXPLAIN unsupported statement message")
        NSSound.beep()
        setStatusText(message)
        updateQueryInfo(title: NSLocalizedString("Query Status", comment: "Query Status"),
                        message: message,
                        isError: true)
    }

    func updateStatusSelectionSuffix() {
        let selectedRows = tableView.numberOfSelectedRows
        let selectionText: String

        if selectedRows == 1 {
            selectionText = NSLocalizedString("; 1 row selected", comment: "lightweight query one row selected")
        } else if selectedRows > 1 {
            selectionText = String(format: NSLocalizedString("; %ld rows selected", comment: "lightweight query rows selected"), selectedRows)
        } else {
            selectionText = ""
        }

        statusLabel.stringValue = baseStatusText + selectionText
    }

    func preserveResultColumnWidths() {
        for column in tableView.tableColumns {
            guard let columnIndex = Int(column.identifier.rawValue),
                  columnIndex < columnDefinitions.count else { continue }

            resultColumnWidths[resultColumnWidthKey(for: columnDefinitions[columnIndex], fallbackIndex: columnIndex)] = column.width
        }
    }

    func resultColumnWidthKey(for columnDefinition: NSDictionary, fallbackIndex: Int) -> String {
        if let origin = resultColumnOrigin(for: columnDefinition) {
            return "\(origin.database).\(origin.table).\(origin.column)"
        }

        return "column.\(fallbackIndex).\(columnName(for: fallbackIndex, definition: columnDefinition))"
    }

    func savedResultColumnWidth(for columnDefinition: NSDictionary) -> CGFloat? {
        guard let origin = resultColumnOrigin(for: columnDefinition),
              let host = connection?.host,
              !host.isEmpty,
              let savedWidths = UserDefaults.standard.dictionary(forKey: SPTableColumnWidths),
              let databaseWidths = savedWidths["\(origin.database)@\(host)"] as? [String: Any],
              let tableWidths = databaseWidths[origin.table] as? [String: Any],
              let width = tableWidths[origin.column] as? NSNumber else { return nil }

        return CGFloat(truncating: width)
    }

    func saveResultColumnWidth(_ tableColumn: NSTableColumn) {
        guard !isApplyingProgrammaticColumnWidths,
              let columnIndex = Int(tableColumn.identifier.rawValue),
              columnIndex < columnDefinitions.count else { return }

        let columnDefinition = columnDefinitions[columnIndex]
        resultColumnWidths[resultColumnWidthKey(for: columnDefinition, fallbackIndex: columnIndex)] = tableColumn.width

        guard let origin = resultColumnOrigin(for: columnDefinition),
              let host = connection?.host,
              !host.isEmpty else { return }

        let databaseKey = "\(origin.database)@\(host)"
        var savedWidths = UserDefaults.standard.dictionary(forKey: SPTableColumnWidths) ?? [:]
        var databaseWidths = savedWidths[databaseKey] as? [String: Any] ?? [:]
        var tableWidths = databaseWidths[origin.table] as? [String: Any] ?? [:]

        tableWidths[origin.column] = NSNumber(value: Double(tableColumn.width))
        databaseWidths[origin.table] = tableWidths
        savedWidths[databaseKey] = databaseWidths
        UserDefaults.standard.set(savedWidths, forKey: SPTableColumnWidths)
    }

    func clearSavedResultColumnWidth(for columnDefinition: NSDictionary, fallbackIndex: Int) {
        resultColumnWidths.removeValue(forKey: resultColumnWidthKey(for: columnDefinition, fallbackIndex: fallbackIndex))

        guard let origin = resultColumnOrigin(for: columnDefinition),
              let host = connection?.host,
              !host.isEmpty else { return }

        let databaseKey = "\(origin.database)@\(host)"
        var savedWidths = UserDefaults.standard.dictionary(forKey: SPTableColumnWidths) ?? [:]
        var databaseWidths = savedWidths[databaseKey] as? [String: Any] ?? [:]
        var tableWidths = databaseWidths[origin.table] as? [String: Any] ?? [:]

        tableWidths.removeValue(forKey: origin.column)

        if tableWidths.isEmpty {
            databaseWidths.removeValue(forKey: origin.table)
        } else {
            databaseWidths[origin.table] = tableWidths
        }

        if databaseWidths.isEmpty {
            savedWidths.removeValue(forKey: databaseKey)
        } else {
            savedWidths[databaseKey] = databaseWidths
        }

        UserDefaults.standard.set(savedWidths, forKey: SPTableColumnWidths)
    }

    func canEditResultCell(row: Int, column columnIndex: Int) -> Bool {
        guard canSaveResultCell(row: row, column: columnIndex),
              !shouldUseFieldEditor(row: row, column: columnIndex) else { return false }

        return true
    }

    func canSaveResultCell(row: Int, column columnIndex: Int) -> Bool {
        guard !isRunning,
              let connection,
              row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < columnDefinitions.count,
              columnIndex < rows[row].count,
              let origin = resultColumnOrigin(for: columnDefinitions[columnIndex]) else { return false }

        return whereClause(for: row, origin: origin, connection: connection) != nil
    }

    func shouldUseFieldEditor(row: Int, column columnIndex: Int) -> Bool {
        guard row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < columnDefinitions.count,
              columnIndex < rows[row].count else { return false }

        let columnDefinition = columnDefinitions[columnIndex]
        let typeGrouping = ((columnDefinition["typegrouping"] as? String) ?? "").lowercased()
        let value = rows[row][columnIndex]
        return SALightweightResultGrid.shouldUseFieldEditor(typeGrouping: typeGrouping, value: value, displayValue: displayString(for: value, columnDefinition: columnDefinition, truncate: false))
    }

    func openFieldEditor(row: Int, column columnIndex: Int) {
        guard !isFieldEditorPresented,
              row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < columnDefinitions.count,
              columnIndex < rows[row].count,
              let connection,
              let window = view.window else { return }

        isFieldEditorPresented = true
        let columnDefinition = columnDefinitions[columnIndex]
        let typeGrouping = ((columnDefinition["typegrouping"] as? String) ?? "").lowercased()
        let isBlob = typeGrouping == "textdata" || typeGrouping == "blobdata"
        let isEditable = canSaveResultCell(row: row, column: columnIndex)
        let editor = fieldEditor

        var editedFieldInfo: [String: Any] = [
            "usedQuery": usedQuery(),
            "tableSource": "query"
        ]
        if let columnName = columnDefinition["org_name"] as? String {
            editedFieldInfo["colName"] = columnName
        }
        if let tableName = columnDefinition["org_table"] as? String {
            editedFieldInfo["tableName"] = tableName
        }
        editor.editedFieldInfo = editedFieldInfo

        if let length = columnDefinition["char_length"] as? NSNumber {
            editor.textMaxLength = length.uint64Value
        }

        editor.fieldType = (columnDefinition["type"] as? String) ?? ""

        if let encoding = columnDefinition["charset_name"] as? String, encoding != "binary" {
            editor.fieldEncoding = encoding
        } else {
            editor.fieldEncoding = ""
        }

        if let allowsNull = columnDefinition["null"] as? NSNumber {
            editor.allowNULL = !allowsNull.boolValue
        } else if let allowsNull = columnDefinition["null"] as? String {
            editor.allowNULL = allowsNull == "0" || allowsNull.caseInsensitiveCompare("NO") == .orderedSame
        } else {
            editor.allowNULL = true
        }

        var originalData = rows[row][columnIndex]
        if originalData is NSNull {
            originalData = UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        editor.edit(with: originalData,
                    fieldName: (columnDefinition["name"] as? String) ?? "",
                    usingEncoding: connection.stringEncoding(),
                    isObjectBlob: isBlob,
                    isEditable: isEditable,
                    with: window,
                    sender: self,
                    contextInfo: [
                        "rowIndex": NSNumber(value: row),
                        "columnIndex": NSNumber(value: columnIndex),
                        "isFieldEditable": NSNumber(value: isEditable),
                        "disableSheetAnimation": NSNumber(value: true),
                        "deferTextLoading": NSNumber(value: true)
                    ])
    }

    func prepareResultContextMenu(for event: NSEvent) {
        SALightweightResultGrid.selectContextRow(in: tableView, event: event)
        updateStatusSelectionSuffix()
    }

    func showCellEditError(_ message: String) {
        NSSound.beep()
        setStatusText(message)
        tableView.reloadData(forRowIndexes: tableView.selectedRowIndexes, columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    func confirmDestructiveQueryIfNeeded(_ query: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: SPQueryWarningEnabled),
              queriesContainDestructiveSQL([query]) else { return true }

        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = NSLocalizedString("Execute SQL?", comment: "Execute SQL?")
        alert.informativeText = destructiveQueryWarning(for: [query])
        alert.addButton(withTitle: NSLocalizedString("Proceed", comment: "Proceed"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        return alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn
    }

    func handleNoAffectedRowsAfterCellEdit(row: Int) {
        let message = NSLocalizedString("The row was not written to the MySQL database. You probably haven't changed anything.\nReload the table to be sure that the row exists and use a primary key for your table.\n(This error can be turned off in the preferences.)", comment: "message of panel when no rows have been affected after writing to the db")

        if UserDefaults.standard.bool(forKey: SPShowNoAffectedRowsError) {
            let alert = NSAlert()
            alert.window.animationBehavior = .none
            alert.messageText = NSLocalizedString("Warning", comment: "warning")
            alert.informativeText = message
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModalCenteredInKeyWindow()
        } else {
            NSSound.beep()
        }

        setStatusText(NSLocalizedString("No rows were affected.", comment: "lightweight query no affected rows edit status"))
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    private func resultColumnOrigin(for columnDefinition: NSDictionary) -> ResultColumnOrigin? {
        guard let database = nonEmptyMetadata("db", in: columnDefinition),
              let table = nonEmptyMetadata("org_table", in: columnDefinition),
              let column = nonEmptyMetadata("org_name", in: columnDefinition) else { return nil }

        return ResultColumnOrigin(database: database, table: table, column: column)
    }

    func nonEmptyMetadata(_ key: String, in columnDefinition: NSDictionary) -> String? {
        guard let value = columnDefinition[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    private func cellUpdate(for object: Any?, row rowIndex: Int, column columnIndex: Int, connection: SPMySQLConnection) -> CellUpdate? {
        guard rowIndex >= 0,
              rowIndex < rows.count,
              columnIndex >= 0,
              columnIndex < columnDefinitions.count,
              columnIndex < rows[rowIndex].count,
              let origin = resultColumnOrigin(for: columnDefinitions[columnIndex]),
              let baseWhereClause = whereClause(for: rowIndex, origin: origin, connection: connection, includeBlobColumns: false) else { return nil }

        let newValue = sqlValue(forEditedObject: object, columnDefinition: columnDefinitions[columnIndex], connection: connection)
        let tableReference = "\(Self.backtickQuoted(origin.database)).\(Self.backtickQuoted(origin.table))"
        let countQuery = "SELECT COUNT(1) FROM \(tableReference) \(baseWhereClause)"
        let updateQuery = "UPDATE \(tableReference) SET \(Self.backtickQuoted(origin.column)) = \(newValue.sql) \(baseWhereClause)"
        let refreshQuery = newValue.requiresReload ? "SELECT \(Self.backtickQuoted(origin.column)) FROM \(tableReference) \(baseWhereClause) LIMIT 1" : nil
        var fallbackCountQuery: String?
        var fallbackUpdateQuery: String?
        var fallbackRefreshQuery: String?

        if let blobWhereClause = whereClause(for: rowIndex, origin: origin, connection: connection, includeBlobColumns: true),
           blobWhereClause != baseWhereClause {
            fallbackCountQuery = "SELECT COUNT(1) FROM \(tableReference) \(blobWhereClause)"
            fallbackUpdateQuery = "UPDATE \(tableReference) SET \(Self.backtickQuoted(origin.column)) = \(newValue.sql) \(blobWhereClause)"
            fallbackRefreshQuery = newValue.requiresReload ? "SELECT \(Self.backtickQuoted(origin.column)) FROM \(tableReference) \(blobWhereClause) LIMIT 1" : nil
        }

        return CellUpdate(countQuery: countQuery,
                          updateQuery: updateQuery,
                          refreshQuery: refreshQuery,
                          fallbackCountQuery: fallbackCountQuery,
                          fallbackUpdateQuery: fallbackUpdateQuery,
                          fallbackRefreshQuery: fallbackRefreshQuery,
                          localValue: newValue.localValue,
                          requiresReload: newValue.requiresReload)
    }

    private func whereClause(for rowIndex: Int, origin: ResultColumnOrigin, connection: SPMySQLConnection, includeBlobColumns: Bool = false) -> String? {
        guard rowIndex >= 0, rowIndex < rows.count else { return nil }

        var sameOriginColumns: [(index: Int, definition: NSDictionary)] = []

        for (columnIndex, columnDefinition) in columnDefinitions.enumerated() {
            guard columnIndex < rows[rowIndex].count,
                  let columnOrigin = resultColumnOrigin(for: columnDefinition),
                  columnOrigin.database == origin.database,
                  columnOrigin.table == origin.table else { continue }

            sameOriginColumns.append((columnIndex, columnDefinition))
        }

        let primaryColumnNames = primaryKeyColumnNames(database: origin.database, table: origin.table, connection: connection)
        let primaryColumns = sameOriginColumns.filter { _, definition in
            guard let columnOrigin = resultColumnOrigin(for: definition) else { return false }
            return primaryColumnNames.contains(columnOrigin.column)
        }
        let identityColumns = primaryColumns.isEmpty ? sameOriginColumns : primaryColumns

        let parts = identityColumns.compactMap { index, definition -> String? in
            guard let columnOrigin = resultColumnOrigin(for: definition),
                  index < rows[rowIndex].count else { return nil }

            let value = rows[rowIndex][index]
            if value is NSNull {
                return "\(Self.backtickQuoted(columnOrigin.column)) IS NULL"
            }

            if !includeBlobColumns, !canUseColumnForFallbackIdentity(definition) {
                return nil
            }

            return "\(Self.backtickQuoted(columnOrigin.column)) = \(sqlValue(forStoredObject: value, columnDefinition: definition, connection: connection))"
        }

        guard !parts.isEmpty else { return nil }

        return "WHERE (\(parts.joined(separator: " AND ")))"
    }

    func primaryKeyColumnNames(database: String, table: String, connection: SPMySQLConnection) -> Set<String> {
        let cacheKey = "\(database)\u{1f}\(table)"
        if let cached = primaryKeyColumnCache[cacheKey] {
            return cached
        }

        let query = "SHOW COLUMNS FROM \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table))"
        guard let result = connection.queryString(query) else {
            return []
        }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard !connection.queryErrored() else { return [] }
        let rows = result.getAllRows() as? [[String: Any]] ?? []
        let names = Set(rows.compactMap { row -> String? in
            let key = (row["Key"] as? String) ?? (row["key"] as? String) ?? ""
            guard key == "PRI" else { return nil }
            return (row["Field"] as? String) ?? (row["field"] as? String)
        })

        primaryKeyColumnCache[cacheKey] = names
        return names
    }

    func canUseColumnForFallbackIdentity(_ columnDefinition: NSDictionary) -> Bool {
        let typeGrouping = ((columnDefinition["typegrouping"] as? String) ?? "").lowercased()
        let type = ((columnDefinition["type"] as? String) ?? "").uppercased()

        if typeGrouping == "blobdata" || typeGrouping == "textdata" {
            return false
        }

        return type != "BINARY" && type != "VARBINARY"
    }

    func sqlValue(forStoredObject object: Any, columnDefinition: NSDictionary, connection: SPMySQLConnection) -> String {
        if let data = object as? Data {
            return connection.escapeAndQuoteData(data) ?? Self.singleQuoted(displayString(for: data, columnDefinition: columnDefinition, truncate: false))
        }

        if let geometry = object as? SPMySQLGeometryData,
           let data = geometry.data() {
            return connection.escapeAndQuoteData(data) ?? Self.singleQuoted(geometry.wktString() ?? String(describing: geometry))
        }

        let value = String(describing: object)
        if ((columnDefinition["typegrouping"] as? String) ?? "") == "bit" {
            return "b'\(value)'"
        }

        return connection.escapeAndQuoteString(value) ?? Self.singleQuoted(value)
    }

    func sqlValue(forEditedObject object: Any?, columnDefinition: NSDictionary, connection: SPMySQLConnection) -> (sql: String, localValue: Any, requiresReload: Bool) {
        if let number = object as? NSNumber {
            return (number.stringValue, number.stringValue, false)
        }

        if let data = object as? Data {
            return (connection.escapeAndQuoteData(data) ?? Self.singleQuoted(displayString(for: data, columnDefinition: columnDefinition, truncate: false)), data, false)
        }

        let value = String(describing: object ?? "")
        let typeGrouping = (columnDefinition["typegrouping"] as? String) ?? ""
        let nullValue = UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"

        if let expression = SALightweightResultGrid.editedSQLExpression(for: value,
                                                                        typeGrouping: typeGrouping,
                                                                        allowsStringUUIDFunction: true) {
            return (expression, value, true)
        }

        if value == nullValue || ((typeGrouping == "float" || typeGrouping == "integer" || typeGrouping == "date") && value.isEmpty) {
            return ("NULL", NSNull(), false)
        }

        if typeGrouping == "bit" {
            let bitValue = value.isEmpty || value == "0" ? "0" : value
            return ("b'\(bitValue)'", bitValue, false)
        }

        if typeGrouping == "geometry" {
            let geometryValue = geometrySQLValue(from: value)
            return (geometryValue, value, false)
        }

        return (connection.escapeAndQuoteString(value) ?? Self.singleQuoted(value), value, false)
    }

    func geometrySQLValue(from value: String) -> String {
        let geometry = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard geometry.count >= 5, geometry.contains(")") else { return "NULL" }

        if geometry.hasSuffix(")") {
            return "ST_GeomFromText(\(Self.singleQuoted(geometry)))"
        }

        guard let closingParenthesis = geometry.lastIndex(of: ")") else { return "NULL" }
        let textPart = String(geometry[...closingParenthesis])
        let sridPart = String(geometry[geometry.index(after: closingParenthesis)...])
        return "ST_GeomFromText(\(Self.singleQuoted(textPart))\(sridPart))"
    }

    static func backtickQuoted(_ value: String) -> String {
        SALightweightResultGrid.backtickQuoted(value)
    }

    static func singleQuoted(_ value: String) -> String {
        SALightweightResultGrid.singleQuoted(value)
    }

    static func dictionaryBool(_ dictionary: NSDictionary, key: String) -> Bool {
        if let value = dictionary[key] as? Bool {
            return value
        }

        if let value = dictionary[key] as? NSNumber {
            return value.boolValue
        }

        if let value = dictionary[key] as? String {
            return value == "1" || value.caseInsensitiveCompare("YES") == .orderedSame || value.caseInsensitiveCompare("true") == .orderedSame
        }

        return false
    }
}

extension SALightweightQueryViewController {
    func focusEditor() {
        queryTextView.window?.makeFirstResponder(queryTextView)
    }

    @objc func performFindPanelAction(_ sender: Any?) {
        focusEditor()
        queryTextView.performFindPanelAction(sender)
    }

    @objc func performLightweightTextFinderAction(_ sender: Any?) {
        focusEditor()
        queryTextView.performTextFinderAction(sender)
    }

    func canCopySelectedResultRows(_ sender: Any?) -> Bool {
        let skipAutoIncrement = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLNoAutoIncTag
        let copiesAsSQL = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLTag || skipAutoIncrement

        guard !isRunning, tableView.numberOfSelectedRows > 0 else { return false }
        guard copiesAsSQL else { return true }

        return !sqlInsertColumnIndexes(skipAutoIncrement: skipAutoIncrement).isEmpty
    }

    @objc func copySelectedResultRowsForMenu(_ sender: Any?) {
        let copiesAsSQL = (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLTag
            || (sender as? NSMenuItem)?.tag == SALightweightResultGridCopyAsSQLNoAutoIncTag

        if copiesAsSQL {
            copySelectedResultRowsAsSQL(sender)
        } else {
            copySelectedResultRows(sender)
        }
    }

    func exportResultRowCount() -> Int {
        return currentResultRowCount()
    }

    func exportDataResult(withNULLs includeNULLs: Bool, truncateDataFields truncate: Bool) -> [[Any]] {
        return currentDataResult(withNULLs: includeNULLs, truncateDataFields: truncate)
    }

    func exportUsedQuery() -> String {
        return usedQuery()
    }

    @objc(processFieldEditorResult:contextInfo:)
    func processFieldEditorResult(_ data: Any?, contextInfo: NSDictionary?) {
        defer {
            isFieldEditorPresented = false
        }

        guard let data,
              let contextInfo,
              (contextInfo["isFieldEditable"] as? NSNumber)?.boolValue == true,
              let rowNumber = contextInfo["rowIndex"] as? NSNumber,
              let columnNumber = contextInfo["columnIndex"] as? NSNumber else { return }

        let row = rowNumber.intValue
        let columnIndex = columnNumber.intValue
        guard row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < columnDefinitions.count else { return }

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(columnIndex)))
        tableView(tableView, setObjectValue: data, for: tableColumn, row: row)
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

extension SALightweightQueryViewController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSTextView.insertNewline(_:)),
           NSApp.currentEvent?.characters == "\u{3}" {
            runPrimaryQuery(nil)
            return true
        }

        return false
    }

    func textView(_ textView: NSTextView,
                  willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
                  toCharacterRange newSelectedCharRange: NSRange) -> NSRange {
        if newSelectedCharRange.length == 0, queryTextView.isSnippetMode() {
            _ = queryTextView.checkForCaretInsideSnippet()
        }
        return newSelectedCharRange
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard notification.object as AnyObject? === queryTextView else { return }
        updateCurrentQueryRange()
        updateContextualRunInterface()
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === queryTextView else { return }
        updateCurrentQueryRange()
        updateContextualRunInterface()
    }

    func textView(_ textView: NSTextView,
                  shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        textViewWasChanged = true
        didCacheCurrentQueryRanges = false
        if !isApplyingProgrammaticQueryText {
            shouldPersistCurrentQueryText = true
            sessionStateDidChange?()
        }
        return true
    }

    @objc func selectCurrentQuery() {
        if currentQueryRange.length > 0 {
            queryTextView.setSelectedRange(currentQueryRange)
        }
    }

    @objc(selectCurrentQuery:)
    func selectCurrentQuery(_ sender: Any?) {
        selectCurrentQuery()
    }

    @objc func showAutoHelpForCurrentWord(_ sender: Any?) {
        let textView = (sender as? SPTextView) ?? queryTextView
        let wordRange = rangeForCurrentWord(in: textView)
        let text = textView.string as NSString

        guard wordRange.location != NSNotFound,
              NSMaxRange(wordRange) <= text.length,
              wordRange.length > 0 else { return }

        let searchString = text.substring(with: wordRange)
        helpViewerClient.showHelp(for: searchString, addToHistory: true, calledByAutoHelp: true)
    }

    @objc func showMySQLHelpForCurrentWord(_ sender: Any?) {
        let textView = (sender as? SPTextView) ?? queryTextView
        let wordRange = rangeForCurrentWord(in: textView)
        let text = textView.string as NSString

        guard wordRange.location != NSNotFound,
              NSMaxRange(wordRange) <= text.length,
              wordRange.length > 0 else { return }

        let searchString = text.substring(with: wordRange)
        helpViewerClient.showHelp(for: searchString, addToHistory: true, calledByAutoHelp: false)
    }

    private func rangeForCurrentWord(in textView: NSTextView) -> NSRange {
        let selectedRange = textView.selectedRange()
        if selectedRange.length > 0 {
            return selectedRange
        }

        let text = textView.string as NSString
        let length = text.length
        var start = min(selectedRange.location, length)
        var end = start
        let wordCharacters = NSMutableCharacterSet.alphanumeric()
        wordCharacters.addCharacters(in: "_.")
        wordCharacters.removeCharacters(in: "`")

        if start > 0 {
            start -= 1
            while start > 0, wordCharacters.characterIsMember(text.character(at: start)) {
                start -= 1
            }
            if !wordCharacters.characterIsMember(text.character(at: start)) {
                start += 1
            }
        }

        while end < length, wordCharacters.characterIsMember(text.character(at: end)) {
            end += 1
        }

        var range = NSRange(location: start, length: max(0, end - start))
        if range.length > 0,
           text.character(at: NSMaxRange(range) - 1) == Character(".").utf16.first! {
            range.length -= 1
        }
        return range
    }
}

extension SALightweightQueryViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as AnyObject? === historySearchField {
            applyHistoryFilter()
        } else if obj.object as AnyObject? === favoriteSearchField {
            applyFavoritesFilter()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === historySearchField || control === favoriteSearchField else {
            return false
        }

        guard commandSelector == #selector(NSResponder.moveDown(_:))
            || commandSelector == #selector(NSResponder.moveUp(_:)) else {
            return false
        }

        historySearchField.abortEditing()
        favoriteSearchField.abortEditing()
        postSearchPopupArrowEvent(for: commandSelector)
        return true
    }

    private func postSearchPopupArrowEvent(for commandSelector: Selector) {
        let keyCode: UInt16 = commandSelector == #selector(NSResponder.moveDown(_:)) ? 0x7D : 0x7E
        guard let event = NSEvent.keyEvent(with: .keyDown,
                                           location: .zero,
                                           modifierFlags: [],
                                           timestamp: 0,
                                           windowNumber: view.window?.windowNumber ?? 0,
                                           context: NSGraphicsContext.current,
                                           characters: "",
                                           charactersIgnoringModifiers: "",
                                           isARepeat: false,
                                           keyCode: keyCode) else {
            return
        }

        NSApp.postEvent(event, atStart: false)
    }
}

extension SALightweightQueryViewController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if menu === favoritesMenu {
            favoritesSearchMenuItem?.view = favoriteSearchFieldView
            configureFavoritesMenuItems(menu)
            applyFavoritesFilter()
            focusMenuSearchField(favoriteSearchField)
        } else if menu === historyMenu {
            historySearchMenuItem?.view = historySearchFieldView
            configureHistoryMenuItems(menu)
            applyHistoryFilter()
            focusMenuSearchField(historySearchField)
        }
    }
}

extension SALightweightQueryViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }

        switch action {
        case #selector(copySelectedResultRows(_:)):
            return canCopySelectedResultRows(menuItem)

        case #selector(copySelectedResultRowsAsSQL(_:)):
            return canCopySelectedResultRows(menuItem)

        case #selector(exportQueryResultAsCSV(_:)), #selector(exportQueryResultAsXML(_:)):
            return !isRunning && !rows.isEmpty

        case #selector(runPrimaryQuery(_:)), #selector(runSecondaryQuery(_:)):
            return !isRunning && connection != nil

        case #selector(saveCurrentQueryToFavorites(_:)), #selector(saveAllQueriesToFavorites(_:)):
            if action == #selector(saveCurrentQueryToFavorites(_:)) {
                menuItem.title = titleForSaveCurrentFavoriteMenuItem()
            }
            return !isRunning && !queryTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case #selector(copyQueryHistory(_:)), #selector(saveQueryHistory(_:)), #selector(clearQueryHistory(_:)):
            if action == #selector(clearQueryHistory(_:)) {
                configureClearHistoryMenuItem(menuItem)
            }
            guard let documentURL else { return false }
            return !isRunning && !(SPQueryController.shared().history(forFileURL: documentURL) as? [String] ?? []).isEmpty

        case #selector(commentCurrentQuery(_:)):
            return !isRunning && currentQueryRange.length > 0

        case #selector(runExplainQueryAction(_:)):
            return canRunExplainQueryAction()

        case #selector(commentLineOrSelection(_:)):
            menuItem.title = queryTextView.selectedRange().length > 0
                ? NSLocalizedString("Comment Selection", comment: "comment selection menu item")
                : NSLocalizedString("Comment Line", comment: "comment line menu item")
            return !isRunning

        default:
            return !isRunning
        }
    }
}

extension SALightweightQueryViewController: SALightweightResultGridTableViewDelegate {
    func resultGridTableViewCopyRows(_ sender: Any?) {
        copySelectedResultRows(sender)
    }

    func resultGridTableViewCopyRowsAsSQL(_ sender: Any?) {
        copySelectedResultRowsAsSQL(sender)
    }

    func resultGridTableView(_ tableView: NSTableView, canCopyRowsFor item: NSValidatedUserInterfaceItem) -> Bool {
        return canCopySelectedResultRows(item as? NSMenuItem)
    }

    func resultGridTableViewPrepareContextMenu(_ tableView: NSTableView, for event: NSEvent) {
        prepareResultContextMenu(for: event)
    }

    func resultGridTableView(_ tableView: NSTableView, bundleInputFor inputSource: String, blobHandling: Int, onlySelectedRows: Bool, blobFileDirectory: String?) -> String? {
        let rowIndexes: IndexSet
        if onlySelectedRows {
            rowIndexes = self.tableView.selectedRowIndexes
        } else {
            rowIndexes = IndexSet(integersIn: 0..<rows.count)
        }

        switch inputSource {
        case SPBundleInputSourceSelectedTableRowsAsTab, SPBundleInputSourceTableRowsAsTab:
            return resultRowsAsTabStringForBundle(includeHeaders: true,
                                                  rowIndexes: rowIndexes,
                                                  requireRows: onlySelectedRows,
                                                  blobHandling: blobHandling,
                                                  blobFileDirectory: blobFileDirectory)
        case SPBundleInputSourceSelectedTableRowsAsCsv, SPBundleInputSourceTableRowsAsCsv:
            return resultRowsAsCSVStringForBundle(includeHeaders: true,
                                                  rowIndexes: rowIndexes,
                                                  requireRows: onlySelectedRows,
                                                  blobHandling: blobHandling,
                                                  blobFileDirectory: blobFileDirectory)
        case SPBundleInputSourceSelectedTableRowsAsSqlInsert, SPBundleInputSourceTableRowsAsSqlInsert:
            return resultRowsAsSQLInserts(rowIndexes: rowIndexes, skipAutoIncrement: false)
        default:
            return ""
        }
    }
}

extension SALightweightQueryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard !isRunning,
              let columnIndex = Int(tableColumn.identifier.rawValue),
              columnIndex < columnDefinitions.count else { return }

        guard !lastExecutedQuery.isEmpty else { return }

        let shiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        pendingSortFailureRestore = (querySortColumnIndex, querySortAscending)
        if querySortColumnIndex == columnIndex {
            querySortAscending.toggle()
        } else {
            querySortColumnIndex = columnIndex
            querySortAscending = !shiftPressed
        }
        applyQuerySortIndicator()

        isApplyingQuerySort = true
        runQueries([queryByApplyingSort(to: lastExecutedQuery, columnIndex: columnIndex, descending: !querySortAscending)],
                   preservingResultGridState: true,
                   recordsHistory: false)
    }

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
        guard let copyString = resultRowsAsTabString(includeHeaders: false, rowIndexes: rowIndexes) else { return false }

        return SALightweightResultGrid.writeRows(copyString, to: pasteboard)
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
                                                    columnCount: { self.rows[$0].count })
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return SALightweightResultGrid.objectValue(row: row,
                                                   rowCount: rows.count,
                                                   tableColumn: tableColumn,
                                                   columnCount: { self.rows[$0].count },
                                                   displayValue: { self.displayValue(row: $0, column: $1) })
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard tableView === self.tableView,
              !isRunning,
              row >= 0,
              row < rows.count,
              let connection,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].count,
              columnIndex < columnDefinitions.count,
              canSaveResultCell(row: row, column: columnIndex) else { return }

        let newValue = String(describing: object ?? "")
        guard newValue != displayString(for: rows[row][columnIndex], columnDefinition: columnDefinition(at: columnIndex), truncate: false) else { return }

        guard let update = cellUpdate(for: object, row: row, column: columnIndex, connection: connection) else {
            showCellEditError(NSLocalizedString("Couldn't identify field origin unambiguously.", comment: "lightweight query edit missing origin"))
            return
        }

        guard confirmDestructiveQueryIfNeeded(update.updateQuery) else {
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: columnIndex))
            return
        }

        let reloadAfterEdit = UserDefaults.standard.bool(forKey: SPReloadAfterEditingRow)
        let queryToReload = lastExecutedQuery

        setStatusText(NSLocalizedString("Saving cell...", comment: "lightweight query saving cell status"))
        isRunning = true
        updateDataTableBundleSupport()
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self, let connection else { return }

            if !self.database.isEmpty {
                _ = connection.selectDatabase(self.database)
            }

            var activeUpdateQuery = update.updateQuery
            var activeRefreshQuery = update.refreshQuery
            var matchingRows = SALightweightResultGrid.matchingRowCount(for: update.countQuery, connection: connection)
            var error = connection.queryErrored() ? connection.lastErrorMessage() : nil
            var affectedRows: UInt64 = 0

            if error == nil,
               let count = matchingRows,
               count > 1,
               let fallbackCountQuery = update.fallbackCountQuery,
               let fallbackUpdateQuery = update.fallbackUpdateQuery {
                matchingRows = SALightweightResultGrid.matchingRowCount(for: fallbackCountQuery, connection: connection)
                error = connection.queryErrored() ? connection.lastErrorMessage() : nil
                if error == nil {
                    activeUpdateQuery = fallbackUpdateQuery
                    activeRefreshQuery = update.fallbackRefreshQuery
                }
            }

            if error == nil, matchingRows == 1 {
                _ = connection.queryString(activeUpdateQuery)
                error = connection.queryErrored() ? connection.lastErrorMessage() : nil
                if error == nil {
                    affectedRows = connection.rowsAffectedByLastQuery()
                }
            }
            var refreshedValue: Any?
            if error == nil,
               matchingRows == 1,
               update.requiresReload,
               !reloadAfterEdit,
               let refreshQuery = activeRefreshQuery {
                let result = connection.queryString(refreshQuery)
                result?.defaultRowReturnType = SPMySQLResultRowAsArray
                if !connection.queryErrored(),
                   let row = result?.getRowAsArray(),
                   !row.isEmpty {
                    refreshedValue = row.first ?? NSNull()
                }
            }

            DispatchQueue.main.async {
                self.isRunning = false
                self.updateDataTableBundleSupport()
                self.updateControls()

                if let error, !error.isEmpty {
                    self.showCellEditError(error)
                    return
                }

                guard matchingRows == 1 else {
                    self.showCellEditError(NSLocalizedString("Couldn't identify a single row to update.", comment: "lightweight query edit no unique row"))
                    return
                }

                guard affectedRows > 0 else {
                    self.handleNoAffectedRowsAfterCellEdit(row: row)
                    return
                }

                if reloadAfterEdit, !queryToReload.isEmpty {
                    self.runQueries([queryToReload], preservingResultGridState: true, recordsHistory: false)
                    return
                }

                if update.requiresReload, !reloadAfterEdit, refreshedValue == nil, !queryToReload.isEmpty {
                    self.runQueries([queryToReload], preservingResultGridState: true, recordsHistory: false)
                    return
                }

                guard row < self.rows.count,
                      columnIndex < self.rows[row].count else {
                    self.tableView.reloadData()
                    return
                }

                self.rows[row][columnIndex] = refreshedValue ?? update.localValue
                self.displayCache.invalidate(row: row, column: columnIndex)
                self.setStatusText(NSLocalizedString("Cell updated.", comment: "lightweight query cell updated status"))
                self.reloadCell(row: row, columnIndex: columnIndex)
            }
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateStatusSelectionSuffix()
        updateControls()
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        guard let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        saveResultColumnWidth(tableColumn)
    }

    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        guard tableView === self.tableView,
              column >= 0,
              column < tableView.tableColumns.count,
              let columnIndex = Int(tableView.tableColumns[column].identifier.rawValue),
              columnIndex < columnDefinitions.count else { return 0 }

        clearSavedResultColumnWidth(for: columnDefinitions[columnIndex], fallbackIndex: columnIndex)
        return SALightweightResultGrid.sizeToFitWidthOfColumn(in: tableView,
                                                              displayColumn: column,
                                                              visibleRows: visibleDisplayRowsForResultAutosizing(maxRows: 128)) { [weak self] row, columnIndex in
            guard let self = self,
                  row < self.rows.count,
                  columnIndex < self.rows[row].count else { return "" }
            return self.displayValue(row: row, column: columnIndex)
        }
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard tableView === self.tableView,
              row >= 0,
              row < rows.count,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].count else { return }

        SALightweightResultGrid.configureDisplayCell(cell, isNullOrPlaceholder: rows[row][columnIndex] is NSNull)
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        guard !isFieldEditorPresented,
              !isRunning,
              tableView === self.tableView,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier) else { return false }

        if shouldUseFieldEditor(row: row, column: columnIndex) {
            openFieldEditor(row: row, column: columnIndex)
            return false
        }

        return canEditResultCell(row: row, column: columnIndex)
    }

    func displayValue(row: Int, column columnIndex: Int) -> String {
        guard row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < rows[row].count else { return "" }

        return displayCache.value(row: row, column: columnIndex) {
            displayString(for: rows[row][columnIndex], columnDefinition: columnDefinition(at: columnIndex), truncate: true)
        }
    }

    func compareResultValue(_ lhs: Any, _ rhs: Any, columnDefinition: NSDictionary) -> ComparisonResult {
        if lhs is NSNull, rhs is NSNull {
            return .orderedSame
        }

        if lhs is NSNull {
            return .orderedAscending
        }

        if rhs is NSNull {
            return .orderedDescending
        }

        if let typeGrouping = columnDefinition["typegrouping"] as? String,
           typeGrouping == "integer" || typeGrouping == "float",
           let leftNumber = Double(displayString(for: lhs, columnDefinition: columnDefinition)),
           let rightNumber = Double(displayString(for: rhs, columnDefinition: columnDefinition)) {
            if leftNumber < rightNumber {
                return .orderedAscending
            }

            if leftNumber > rightNumber {
                return .orderedDescending
            }

            return .orderedSame
        }

        return displayString(for: lhs, columnDefinition: columnDefinition)
            .localizedStandardCompare(displayString(for: rhs, columnDefinition: columnDefinition))
    }

    func columnDefinition(at index: Int) -> NSDictionary? {
        guard index >= 0, index < columnDefinitions.count else { return nil }
        return columnDefinitions[index]
    }

    func displayString(for value: Any, columnDefinition: NSDictionary? = nil, truncate: Bool = false) -> String {
        return SALightweightResultGrid.displayString(for: value,
                                                     descriptor: columnDefinition.map { Self.gridColumnDescriptor($0, fallbackName: "") },
                                                     truncate: truncate)
    }

    func rebuildDisplayRows() {
        displayCache.invalidateAll()
        columnWidthCache.invalidateAll()
    }

    func updateDataTableBundleSupport() {
        tableView.supportsDataTableBundleCommands = !isRunning
            && !lastExecutedQuery.isEmpty
            && !columnDefinitions.isEmpty
            && tableView.tableColumns.count == columnDefinitions.count
    }

}
