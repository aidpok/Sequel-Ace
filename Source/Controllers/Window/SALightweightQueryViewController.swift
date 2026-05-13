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

private let SALightweightCopyWithColumnsTag = 2002
private let SALightweightCopyAsSQLTag = 2003
private let SALightweightCopyAsSQLNoAutoIncTag = 2004

private final class SALightweightQueryTableView: NSTableView {
    weak var queryController: SALightweightQueryViewController?

    @objc(copy:)
    func copy(_ sender: Any?) {
        if let menuItem = sender as? NSMenuItem,
           menuItem.tag == SALightweightCopyAsSQLTag || menuItem.tag == SALightweightCopyAsSQLNoAutoIncTag {
            queryController?.copySelectedResultRowsAsSQL(sender)
            return
        }

        queryController?.copySelectedResultRows(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return numberOfSelectedRows > 0
        }

        return super.validateUserInterfaceItem(item)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        queryController?.prepareResultContextMenu(for: event)
        return super.menu(for: event)
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
        let localValue: Any
    }

    private weak var connection: SPMySQLConnection?
    private var documentURL: URL?
    private var database = ""
    private var table: String?
    private var columnDefinitions: [NSDictionary] = []
    private var rows: [[Any]] = []
    private var lastExecutedQuery = ""
    private var lastResultQuery = ""
    private var queryToken = UUID()
    private var isRunning = false
    private var isCancellationRequested = false
    private var editorWasConfigured = false
    private var didInstallObservers = false
    private var isApplyingProgrammaticColumnWidths = false
    private var isApplyingQuerySort = false
    private var bracketHighlighter: SPBracketHighlighter?
    private let maxDisplayedRows = 10_000
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
    private var currentQueryBeforeCaret = false
    var currentQueryRange = NSRange(location: 0, length: 0)
    private var currentQueryRanges: [NSRange] = []
    private var didCacheCurrentQueryRanges = false
    var requestLegacyQueryFallback: ((String?) -> Void)?

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
    private var didSetInitialQueryEditorSplitPosition = false
    private var didSetInitialQueryInfoSplitPosition = false
    private static let tabularPasteboardType = NSPasteboard.PasteboardType("public.utf8-tab-separated-values-text")

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
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 180, height: 22))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.placeholderString = NSLocalizedString("Filter", comment: "query history filter placeholder")
        field.delegate = self
        return field
    }()

    private lazy var favoriteSearchField: NSSearchField = {
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 180, height: 22))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.placeholderString = NSLocalizedString("Filter", comment: "query favorite filter placeholder")
        field.delegate = self
        return field
    }()

    private lazy var queryTextView: SPTextView = {
        let textView = SPTextView(frame: .zero)
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        return textView
    }()

    private lazy var tableView: SALightweightQueryTableView = {
        let tableView = SALightweightQueryTableView(frame: .zero)
        tableView.identifier = NSUserInterfaceItemIdentifier("LightweightQueryTable")
        tableView.queryController = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: UserDefaults.getFont()]).height
        tableView.registerForDraggedTypes([Self.tabularPasteboardType, .string])
        return tableView
    }()

    private lazy var favoritesButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.target = self
        button.action = #selector(chooseQueryFavorite(_:))
        button.toolTip = NSLocalizedString("Choose a favorite from the menu or save queries to the favorites (⌥⌘F)", comment: "query favorites tooltip")
        button.keyEquivalent = "f"
        button.keyEquivalentModifierMask = [.option, .command]
        button.bezelStyle = .recessed
        button.cell?.controlSize = .small
        return button
    }()

    private lazy var historyButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.target = self
        button.action = #selector(chooseQueryHistory(_:))
        button.toolTip = NSLocalizedString("Choose a query from your recent queries (⌥⌘Y)", comment: "query history tooltip")
        button.keyEquivalent = "y"
        button.keyEquivalentModifierMask = [.option, .command]
        button.bezelStyle = .recessed
        button.cell?.controlSize = .small
        return button
    }()

    private lazy var runButton: SPComboPopupButton = {
        let button = SPComboPopupButton(frame: NSRect(x: 0, y: 0, width: 180, height: 22), pullsDown: true)
        button.target = self
        button.action = #selector(runPrimaryQuery(_:))
        button.keyEquivalent = "r"
        button.keyEquivalentModifierMask = [.command]
        button.cell?.controlSize = .small
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

        resultScrollView.borderType = .noBorder
        resultScrollView.focusRingType = .none
        resultScrollView.hasVerticalScroller = true
        resultScrollView.hasHorizontalScroller = true
        resultScrollView.autohidesScrollers = true
        resultScrollView.documentView = tableView

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
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        guard editorWasConfigured else { return }

        if !didSetInitialQueryEditorSplitPosition && queryEditorSplitView.bounds.height > 0 {
            let initialDividerPosition = min(143, max(0, queryEditorSplitView.bounds.height - queryEditorSplitView.dividerThickness))
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
        NotificationCenter.default.removeObserver(self)
        if didInstallObservers {
            for key in Self.observedPreferenceKeys {
                UserDefaults.standard.removeObserver(self, forKeyPath: key)
            }
        }
        if let documentURL = documentURL {
            SPQueryController.shared().removeRegisteredDocument(withFileURL: documentURL)
        }
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        switch keyPath {
        case SPDisplayTableViewVerticalGridlines:
            tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
            tableView.reloadData()
        case SPGlobalFontSettings:
            updateAppearanceFromPreferences()
        case SPDisplayTableViewColumnTypes:
            rebuildColumns()
        case SPDisplayBinaryDataAsHex,
             SPNullValue:
            tableView.reloadData()
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
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func loadQuery(database: String?, table: String?, connection: SPMySQLConnection) {
        self.connection = connection
        self.database = database ?? ""
        self.table = table

        if documentURL == nil {
            documentURL = SPQueryController.shared().registerDocument(withFileURL: nil, andContextInfo: nil)
        }

        configureEditorIfNeeded()
        queryTextView.setConnection(connection, withVersion: Int(connection.serverMajorVersion()))

        if queryTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let table,
           let database {
            replaceEditorText("SELECT * FROM \(Self.backtickQuoted(database)).\(Self.backtickQuoted(table)) LIMIT 100;")
        }

        updateCurrentQueryRange()
        rebuildMenus()
        updateControls()
    }
}

private extension SALightweightQueryViewController {
    func configureEditorIfNeeded() {
        guard !editorWasConfigured else { return }

        queryTextView.delegate = self
        queryTextView.setValue(queryScrollView, forKey: "scrollView")
        queryTextView.setValue(self, forKey: "customQueryInstance")
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
        for key in Self.observedPreferenceKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: .new, context: nil)
        }
        didInstallObservers = true
    }

    @objc func queryFavoritesHaveBeenUpdated(_ notification: Notification?) {
        rebuildFavoritesMenu()
    }

    @objc func historyItemsHaveBeenUpdated(_ notification: Notification?) {
        rebuildHistoryMenu()
    }

    func updateAppearanceFromPreferences() {
        let tableFont = UserDefaults.getFont()
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: tableFont]).height
        for column in tableView.tableColumns {
            if let cell = column.dataCell as? NSTextFieldCell {
                cell.font = tableFont
            }
        }
        updateQueryInteractionInterface()
        rebuildColumns()
        tableView.reloadData()
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
        let menu = NSMenu()
        menu.autoenablesItems = true

        let copyItem = NSMenuItem(title: NSLocalizedString("Copy", comment: "copy result rows menu item"),
                                  action: #selector(copySelectedResultRows(_:)),
                                  keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let copyWithColumnsItem = NSMenuItem(title: NSLocalizedString("Copy With Column Names", comment: "copy result rows with column names menu item"),
                                             action: #selector(copySelectedResultRows(_:)),
                                             keyEquivalent: "")
        copyWithColumnsItem.target = self
        copyWithColumnsItem.tag = SALightweightCopyWithColumnsTag
        menu.addItem(copyWithColumnsItem)

        let copyAsSQLItem = NSMenuItem(title: NSLocalizedString("Copy as SQL INSERT", comment: "copy result rows as SQL INSERT menu item"),
                                       action: #selector(copySelectedResultRowsAsSQL(_:)),
                                       keyEquivalent: "")
        copyAsSQLItem.target = self
        copyAsSQLItem.tag = SALightweightCopyAsSQLTag
        menu.addItem(copyAsSQLItem)

        let copyAsSQLNoAutoIncItem = NSMenuItem(title: NSLocalizedString("Copy as SQL INSERT (no auto_inc)", comment: "copy result rows as SQL INSERT without auto increment menu item"),
                                                action: #selector(copySelectedResultRowsAsSQL(_:)),
                                                keyEquivalent: "")
        copyAsSQLNoAutoIncItem.target = self
        copyAsSQLNoAutoIncItem.tag = SALightweightCopyAsSQLNoAutoIncTag
        menu.addItem(copyAsSQLNoAutoIncItem)

        menu.addItem(.separator())

        let exportCSVItem = NSMenuItem(title: NSLocalizedString("Export Result as CSV...", comment: "export result as csv context menu item"),
                                       action: #selector(exportQueryResultAsCSV(_:)),
                                       keyEquivalent: "")
        exportCSVItem.target = self
        menu.addItem(exportCSVItem)

        let exportXMLItem = NSMenuItem(title: NSLocalizedString("Export Result as XML...", comment: "export result as xml context menu item"),
                                       action: #selector(exportQueryResultAsXML(_:)),
                                       keyEquivalent: "")
        exportXMLItem.target = self
        menu.addItem(exportXMLItem)

        tableView.menu = menu
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
    }

    @objc func runPrimaryQuery(_ sender: Any?) {
        if isRunning {
            cancelRunningQuery()
            return
        }

        if UserDefaults.standard.bool(forKey: SPQueryPrimaryControlRunsAll) {
            runQueries(splitQueries(in: queryTextView.string))
        } else {
            runQueries(queriesForCurrentAction())
        }
    }

    @objc func runSecondaryQuery(_ sender: Any?) {
        if isRunning {
            cancelRunningQuery()
            return
        }

        if UserDefaults.standard.bool(forKey: SPQueryPrimaryControlRunsAll) {
            runQueries(queriesForCurrentAction())
        } else {
            runQueries(splitQueries(in: queryTextView.string))
        }
    }

    func cancelRunningQuery() {
        isCancellationRequested = true
        connection?.cancelCurrentQuery()
        setStatusText(NSLocalizedString("Cancelling query...", comment: "lightweight query cancelling status"))
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
        queryTextView.showCompletionList(for: "$SP_ASLIST_ALL_FIELDS", at: NSRange(location: queryTextView.selectedRange().location, length: 0), fuzzySearch: false)
    }

    func performTextViewCompletion(fuzzySearch: Bool) {
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

    func runQueries(_ queries: [String]) {
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
            alert.messageText = NSLocalizedString("Execute SQL?", comment: "execute sql alert title")
            alert.informativeText = destructiveQueryWarning(for: runnableQueries)
            alert.addButton(withTitle: NSLocalizedString("Proceed", comment: "execute sql proceed button"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        queryToken = UUID()
        let token = queryToken
        isCancellationRequested = false

        isRunning = true
        columnDefinitions = []
        rows = []
        lastExecutedQuery = ""
        lastResultQuery = ""
        rebuildColumns()
        setStatusText(runnableQueries.count > 1
            ? String(format: NSLocalizedString("Running query 1 of %ld...", comment: "lightweight query running multiple status"), runnableQueries.count)
            : NSLocalizedString("Running query...", comment: "lightweight query running status"))
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self, let connection else { return }

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
            var finalResult = QueryResult(columnDefinitions: [], rows: [], affectedRows: 0, executionTime: 0, fatalError: nil, errorText: nil, firstErrorQueryNumber: nil, executedQuery: "", resultQuery: "", lastErrorID: 0, queriesRun: 0, truncated: false)

            for (index, query) in runnableQueries.enumerated() {
                if token != self.queryToken || self.isCancellationRequested {
                    finalResult = QueryResult(columnDefinitions: finalResult.columnDefinitions, rows: finalResult.rows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: NSLocalizedString("Query cancelled.", comment: "lightweight query cancelled status"), errorText: NSLocalizedString("Query cancelled.", comment: "lightweight query cancelled status"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: resultQuery, lastErrorID: 0, queriesRun: queriesRun, truncated: finalResult.truncated)
                    break
                }

                if runnableQueries.count > 1 {
                    DispatchQueue.main.async {
                        guard self.queryToken == token else { return }
                        self.setStatusText(String(format: NSLocalizedString("Running query %ld of %ld...", comment: "lightweight query running multiple status"), index + 1, runnableQueries.count))
                    }
                }

                executedQueries.append(query)
                guard let result = connection.queryString(query) else {
                    queriesRun += 1
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

                queriesRun += 1

                result.returnDataAsStrings = true
                result.defaultRowReturnType = SPMySQLResultRowAsArray

                totalExecutionTime += result.queryExecutionTime()

                let affectedRows = connection.rowsAffectedByLastQuery()
                if affectedRows != UInt64.max {
                    totalAffectedRows += affectedRows
                }

                if connection.queryErrored() {
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
                var truncated = false
                resultQuery = definitions.isEmpty ? resultQuery : query

                while let row = result.getRowAsArray() {
                    if loadedRows.count < self.maxDisplayedRows {
                        loadedRows.append(row)
                    } else {
                        truncated = true
                    }
                }

                finalResult = QueryResult(columnDefinitions: definitions, rows: loadedRows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: nil, errorText: errors.isEmpty ? nil : errors.joined(separator: "\n"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: resultQuery, lastErrorID: 0, queriesRun: queriesRun, truncated: truncated)
            }

            if finalResult.executedQuery.isEmpty, !executedQueries.isEmpty {
                finalResult = QueryResult(columnDefinitions: finalResult.columnDefinitions, rows: finalResult.rows, affectedRows: totalAffectedRows, executionTime: totalExecutionTime, fatalError: finalResult.fatalError, errorText: errors.isEmpty ? finalResult.errorText : errors.joined(separator: "\n"), firstErrorQueryNumber: firstErrorQueryNumber, executedQuery: executedQueries.joined(separator: ";\n"), resultQuery: resultQuery, lastErrorID: finalResult.lastErrorID, queriesRun: queriesRun, truncated: finalResult.truncated)
            }

            DispatchQueue.main.async {
                guard self.queryToken == token else { return }

                self.isRunning = false
                self.isCancellationRequested = false
                self.lastExecutedQuery = finalResult.executedQuery
                self.lastResultQuery = finalResult.resultQuery

                if !self.lastExecutedQuery.isEmpty {
                    self.addHistoryEntry(self.lastExecutedQuery)
                }

                if let error = finalResult.fatalError, !error.isEmpty {
                    self.columnDefinitions = []
                    self.rows = []
                    self.rebuildColumns()
                    self.selectQueryForError(number: finalResult.firstErrorQueryNumber, errorText: finalResult.errorText ?? error, errorID: finalResult.lastErrorID)
                    self.updateQueryInfo(title: NSLocalizedString("Last Error Message", comment: "lightweight query error info title"), message: finalResult.errorText ?? error, isError: true)
                    self.setStatusText(error)
                    self.rebuildMenus()
                    self.updateControls()
                    return
                }

                self.columnDefinitions = finalResult.columnDefinitions
                self.rows = finalResult.rows
                self.rebuildColumns()
                self.updateStatus(for: finalResult, queryCount: max(finalResult.queriesRun, runnableQueries.count))
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
        alert.messageText = NSLocalizedString("MySQL Error", comment: "mysql error message")
        alert.informativeText = error
        alert.addButton(withTitle: NSLocalizedString("Run All", comment: "run all button"))
        alert.addButton(withTitle: NSLocalizedString("Continue", comment: "continue button"))
        alert.addButton(withTitle: NSLocalizedString("Stop", comment: "stop button"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .runAll
        case .alertSecondButtonReturn:
            return .continueQueries
        default:
            return .stopQueries
        }
    }

    func queriesForCurrentAction() -> [String] {
        let selection = queryTextView.selectedRange()
        if selection.length > 0 {
            return splitQueries(in: (queryTextView.string as NSString).substring(with: selection))
        }

        if currentQueryRange.length > 0 {
            let query = (queryTextView.string as NSString).substring(with: currentQueryRange)
            return [SPSQLParser.normaliseQuery(forExecution: query)]
        }

        return splitQueries(in: queryTextView.string)
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
        currentQueryBeforeCaret = true
        currentQueryRange = queryRange(at: caretPosition, lookBehind: &currentQueryBeforeCaret)
        queryTextView.queryRange = currentQueryRange
        queryTextView.setNeedsDisplay(queryTextView.bounds)
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

        var previousNonEmptyRange = NSRange(location: 0, length: 0)

        for range in cachedCurrentQueryRanges() {
            let trimmed = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            if position < range.location {
                break
            }

            previousNonEmptyRange = range

            if NSLocationInRange(position, range) || position == NSMaxRange(range) {
                if position == NSMaxRange(range) && position > range.location {
                    let lastCharacter = text.substring(with: NSRange(location: max(range.location, position - 1), length: 1))
                    if lastCharacter == ";" {
                        break
                    }
                }
                lookBehind = false
                return range
            }
        }

        return previousNonEmptyRange
    }

    func queryTextRange(forQueryNumber queryNumber: Int) -> NSRange {
        let text = queryTextView.string as NSString
        guard queryNumber > 0 else { return NSRange(location: 0, length: 0) }

        var currentQueryNumber = 0
        for range in cachedCurrentQueryRanges() {
            let trimmed = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            currentQueryNumber += 1
            if currentQueryNumber == queryNumber {
                return NSIntersectionRange(NSRange(location: 0, length: text.length), range)
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
        let safeCommands = ["SHOW", "SELECT"]

        for query in queries {
            var cleanedQuery = query.replacingOccurrences(of: #"--.*?\n"#, with: "", options: .regularExpression)
            cleanedQuery = cleanedQuery.replacingOccurrences(of: #"--.*?$"#, with: "", options: .regularExpression)
            cleanedQuery = cleanedQuery.replacingOccurrences(of: #"/\*(.|\n)*?\*/"#, with: "", options: .regularExpression)
            cleanedQuery = cleanedQuery.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleanedQuery.isEmpty {
                continue
            }

            if safeCommands.contains(where: { cleanedQuery.range(of: $0, options: [.anchored, .caseInsensitive]) != nil }) {
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

    func rebuildFavoritesMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let titleItem = NSMenuItem(title: NSLocalizedString("Query Favorites", comment: "query favorites menu title"), action: nil, keyEquivalent: "")
        titleItem.isHidden = true
        menu.addItem(titleItem)

        let saveQueryItem = NSMenuItem(title: titleForSaveCurrentFavoriteMenuItem(),
                                       action: #selector(saveCurrentQueryToFavorites(_:)),
                                       keyEquivalent: "")
        saveQueryItem.target = self
        saveQueryItem.toolTip = NSLocalizedString("Save current query, selection, or - if no selection or current query could be found - the entire content to Favorite.", comment: "save query to favorites tooltip")
        saveQueryItem.isEnabled = !queryTextView.string.isEmpty
        menu.addItem(saveQueryItem)

        let saveAllItem = NSMenuItem(title: NSLocalizedString("Save All to Favorites", comment: "save all to favorites menu item"),
                                     action: #selector(saveAllQueriesToFavorites(_:)),
                                     keyEquivalent: "")
        saveAllItem.target = self
        saveAllItem.toolTip = NSLocalizedString("Save editor content to Favorite. Press ⌥ to restrict for current query or selection.", comment: "save all to favorites tooltip")
        saveAllItem.isEnabled = !queryTextView.string.isEmpty
        menu.addItem(saveAllItem)

        let editItem = NSMenuItem(title: NSLocalizedString("Edit Favorites...", comment: "edit favorites menu item"),
                                  action: #selector(editQueryFavorites(_:)),
                                  keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem()
        searchItem.view = favoriteSearchField
        menu.addItem(searchItem)
        menu.addItem(.separator())

        let filterText = favoriteSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let documentURL {
            let documentHeader = NSMenuItem(title: documentURL.lastPathComponent, action: nil, keyEquivalent: "")
            documentHeader.isEnabled = false
            menu.addItem(documentHeader)

            for favorite in SPQueryController.shared().favorites(forFileURL: documentURL) as? [[String: Any]] ?? [] {
                if !favoriteMatchesFilter(favorite, filterText: filterText) {
                    continue
                }
                addFavorite(favorite, to: menu)
            }
        }

        let globalHeader = NSMenuItem(title: NSLocalizedString("Global", comment: "query favorites global header"), action: nil, keyEquivalent: "")
        globalHeader.isEnabled = false
        menu.addItem(globalHeader)

        for favorite in UserDefaults.standard.array(forKey: SPQueryFavorites) as? [[String: Any]] ?? [] {
            if !favoriteMatchesFilter(favorite, filterText: filterText) {
                continue
            }
            addFavorite(favorite, to: menu)
        }

        favoritesButton.menu = menu
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
        item.representedObject = favorite["query"] as? String
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

    func rebuildHistoryMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let titleItem = NSMenuItem(title: NSLocalizedString("Query History", comment: "query history menu title"), action: nil, keyEquivalent: "")
        titleItem.isHidden = true
        menu.addItem(titleItem)

        let copyItem = NSMenuItem(title: NSLocalizedString("Copy History", comment: "copy query history menu item"), action: #selector(copyQueryHistory(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let saveItem = NSMenuItem(title: NSLocalizedString("Save History...", comment: "save query history menu item"), action: #selector(saveQueryHistory(_:)), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        let clearItem = NSMenuItem(title: NSLocalizedString("Clear History", comment: "clear query history menu item"), action: #selector(clearQueryHistory(_:)), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem()
        searchItem.view = historySearchField
        menu.addItem(searchItem)
        menu.addItem(.separator())

        let filterText = historySearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let documentURL {
            for history in SPQueryController.shared().history(forFileURL: documentURL) as? [String] ?? [] {
                if !filterText.isEmpty, !history.localizedCaseInsensitiveContains(filterText) {
                    continue
                }

                let title = history.count > 64 ? "\(history.prefix(63))..." : history
                let item = NSMenuItem(title: title, action: #selector(chooseQueryHistory(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = history
                item.toolTip = history.count > 256 ? "\(history.prefix(255))..." : history
                menu.addItem(item)
            }
        }

        historyButton.menu = menu
    }

    @objc func chooseQueryFavorite(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let query = item.representedObject as? String else { return }
        insertQuery(query, replacingContentByDefault: UserDefaults.standard.bool(forKey: SPQueryFavoriteReplacesContent))
        favoritesButton.selectItem(at: 0)
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
        requestLegacyQueryFallback?(queryTextView.string)
        favoritesButton.selectItem(at: 0)
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
        historyButton.selectItem(at: 0)
    }

    @objc func copyQueryHistory(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(buildHistoryString(), forType: .string)
    }

    @objc func saveQueryHistory(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedFileTypes = [SPFileExtensionSQL]
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "history"
        if panel.runModal() == .OK, let url = panel.url {
            try? buildHistoryString().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc func clearQueryHistory(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Clear History?", comment: "clear history message")
        alert.informativeText = NSLocalizedString("Are you sure you want to clear the lightweight query history? This action cannot be undone.", comment: "clear history confirmation message")
        alert.addButton(withTitle: NSLocalizedString("Clear", comment: "clear button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard alert.runModal() == .alertFirstButtonReturn, let documentURL else { return }
        SPQueryController.shared().replaceHistory(by: [], forFileURL: documentURL)
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
            alert.messageText = NSLocalizedString("Empty query", comment: "empty query message")
            alert.informativeText = NSLocalizedString("Cannot save an empty query.", comment: "empty query informative message")
            alert.runModal()
            return
        }

        let nameField = NSTextField(frame: NSRect(x: 0, y: 24, width: 260, height: 22))
        nameField.placeholderString = NSLocalizedString("Favorite Name", comment: "query favorite name placeholder")

        let globalCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Save Globally", comment: "save query favorite globally checkbox"),
                                      target: nil,
                                      action: nil)
        globalCheckbox.frame = NSRect(x: 0, y: 0, width: 260, height: 18)
        globalCheckbox.state = .on

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 50))
        accessoryView.addSubview(nameField)
        accessoryView.addSubview(globalCheckbox)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Save Query to Favorites", comment: "save query favorite alert title")
        alert.informativeText = NSLocalizedString("Enter a name for the query favorite.", comment: "save query favorite alert message")
        alert.accessoryView = accessoryView
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "save button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NSSound.beep()
            return
        }

        let favorite: [String: Any] = ["name": name, "query": query]
        if globalCheckbox.state == .on || documentURL == nil {
            var favorites = UserDefaults.standard.array(forKey: SPQueryFavorites) as? [[String: Any]] ?? []
            favorites.append(favorite)
            UserDefaults.standard.set(favorites, forKey: SPQueryFavorites)
        } else if let documentURL {
            SPQueryController.shared().addFavorite(favorite, forFileURL: documentURL)
        }

        NotificationCenter.default.post(name: .SPQueryFavoritesHaveBeenUpdated, object: self)
        favoritesButton.selectItem(at: 0)
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

    func replaceEditorText(_ query: String) {
        queryTextView.shouldChangeText(in: NSRange(location: 0, length: queryTextView.string.count), replacementString: query)
        queryTextView.string = query
        textViewWasChanged = true
        didCacheCurrentQueryRanges = false
        queryTextView.didChangeText()
        queryTextView.scrollRangeToVisible(NSRange(location: query.count, length: 0))
        if query.count < SP_TEXT_SIZE_MAX_PASTE_LENGTH {
            queryTextView.doSyntaxHighlighting(withForce: true)
        }
        updateCurrentQueryRange()
    }

    func rebuildColumns() {
        let showColumnTypes = UserDefaults.standard.bool(forKey: SPDisplayTableViewColumnTypes)
        let tableFont = UserDefaults.getFont()
        preserveResultColumnWidths()

        tableView.tableColumns.forEach {
            $0.headerToolTip = nil
            tableView.removeTableColumn($0)
        }

        for (index, columnDefinition) in columnDefinitions.enumerated() {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(index)"))
            tableColumn.resizingMask = .userResizingMask
            tableColumn.isEditable = canEditResultColumn(columnDefinition)
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: "\(index)", ascending: true)

            let dataCell = NSTextFieldCell(textCell: "")
            dataCell.isEditable = tableColumn.isEditable
            dataCell.isSelectable = true
            dataCell.font = tableFont
            dataCell.lineBreakMode = .byTruncatingTail

            if let typeGrouping = columnDefinition["typegrouping"] as? String,
               typeGrouping == "integer" || typeGrouping == "float" {
                dataCell.alignment = .right
            }

            let formatter = SPDataCellFormatter()
            formatter.fieldType = (columnDefinition["type"] as? String) ?? ""
            if let typeGrouping = columnDefinition["typegrouping"] as? String,
               typeGrouping == "string" || typeGrouping == "bit",
               let charLength = columnDefinition["char_length"] as? NSNumber {
                formatter.textLimit = charLength.intValue
            }
            dataCell.formatter = formatter

            tableColumn.dataCell = dataCell
            tableColumn.headerCell.font = NSFontManager.shared.convert(tableFont, toSize: max(tableFont.pointSize * 0.75, 11))
            tableColumn.headerCell.attributedStringValue = columnDefinition.tableContentColumnHeaderAttributedString(columnTypesVisible: showColumnTypes)
            if let name = columnDefinition["name"] as? String, let type = columnDefinition["type"] as? String {
                let lengthSuffix: String
                if let charLength = columnDefinition["char_length"] {
                    lengthSuffix = "(\(charLength))"
                } else {
                    lengthSuffix = ""
                }
                tableColumn.headerToolTip = "\(name) - \(type)\(lengthSuffix)"
            }

            let columnName = (columnDefinition["name"] as? String) ?? ""
            tableColumn.width = savedResultColumnWidth(for: columnDefinition)
                ?? resultColumnWidths[resultColumnWidthKey(for: columnDefinition, fallbackIndex: index)]
                ?? max(90, min(260, CGFloat(columnName.count * 9 + 32)))
            tableColumn.minWidth = 40
            tableView.addTableColumn(tableColumn)
        }

        tableView.reloadData()
        autosizeResultColumns()
    }

    func autosizeResultColumns() {
        isApplyingProgrammaticColumnWidths = true
        defer { isApplyingProgrammaticColumnWidths = false }

        var widthsByIdentifier: [String: CGFloat] = [:]

        for tableColumn in tableView.tableColumns {
            guard let columnIndex = Int(tableColumn.identifier.rawValue),
                  columnIndex < columnDefinitions.count else { continue }

            if savedResultColumnWidth(for: columnDefinitions[columnIndex]) != nil {
                continue
            }

            widthsByIdentifier[tableColumn.identifier.rawValue] = autodetectedResultWidth(for: tableColumn, columnIndex: columnIndex, maxRows: 160)
        }

        for tableColumn in tableView.tableColumns {
            guard let targetWidth = widthsByIdentifier[tableColumn.identifier.rawValue] else { continue }
            tableColumn.maxWidth = max(tableColumn.maxWidth, targetWidth)
            tableColumn.width = ceil(max(targetWidth, tableColumn.minWidth))
        }
    }

    func autodetectedResultWidth(for tableColumn: NSTableColumn, columnIndex: Int, maxRows: Int) -> CGFloat {
        var maxCellWidth: CGFloat = 0
        for row in visibleRowsForResultAutosizing(maxRows: maxRows) {
            guard columnIndex < row.count else { continue }
            let cellWidth = measuredResultCellWidth(displayString(for: row[columnIndex], columnDefinition: columnDefinition(at: columnIndex)), in: tableColumn)
            maxCellWidth = max(maxCellWidth, cellWidth)
        }

        let headerWidth = measuredResultHeaderWidth(for: tableColumn) + 10
        return ceil(max(maxCellWidth + 24, headerWidth, tableColumn.minWidth))
    }

    func visibleRowsForResultAutosizing(maxRows: Int) -> [[Any]] {
        guard maxRows > 0, !rows.isEmpty else { return [] }
        if maxRows > 160 {
            return Array(rows.prefix(maxRows))
        }

        let visibleRange = tableView.rows(in: tableView.visibleRect)
        let start = visibleRange.length > 0 ? visibleRange.location : 0
        let end = visibleRange.length > 0 ? min(rows.count, visibleRange.location + visibleRange.length) : min(rows.count, maxRows)
        guard start < end else { return Array(rows.prefix(maxRows)) }

        return Array(rows[start..<min(end, start + maxRows)])
    }

    func measuredResultHeaderWidth(for tableColumn: NSTableColumn) -> CGFloat {
        let headerCell = tableColumn.headerCell

        if headerCell.attributedStringValue.length > 0 {
            return max(headerCell.cellSize.width, headerCell.attributedStringValue.size().width)
        }

        let title = headerCell.stringValue as NSString
        let font = headerCell.font ?? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        return max(headerCell.cellSize.width, title.size(withAttributes: [.font: font]).width)
    }

    func measuredResultCellWidth(_ value: String, in tableColumn: NSTableColumn) -> CGFloat {
        guard let cell = (tableColumn.dataCell as? NSCell)?.copy() as? NSCell else {
            return (value as NSString).size(withAttributes: [.font: UserDefaults.getFont()]).width
        }

        cell.stringValue = value
        let font = cell.font ?? UserDefaults.getFont()
        return max(cell.cellSize.width, (value as NSString).size(withAttributes: [.font: font]).width)
    }

    func updateStatus(for result: QueryResult, queryCount: Int) {
        let time = String(format: "%.3fs", result.executionTime)
        let statusTitle = result.errorText?.isEmpty == false
            ? NSLocalizedString("Errors", comment: "Errors title")
            : NSLocalizedString("No errors", comment: "No errors title")

        if result.columnDefinitions.isEmpty {
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

    func queryByApplyingSort(to query: String, columnIndex: Int, descending: Bool) -> String {
        let orderClause = " ORDER BY \(columnIndex + 1) \(descending ? "DESC" : "ASC") "
        let maskedQuery = queryMaskedForClauseSearch(query)
        var mutableQuery = NSMutableString(string: query)

        if let existingOrderRange = firstRegexRange(in: maskedQuery, pattern: #"(?is)\s+ORDER\s+BY\s+[\s\S]+?(?:\s+(?:DESC|ASC))?(?=\s+(?:LIMIT|PROCEDURE|INTO|FOR|LOCK)\b)"#) {
            mutableQuery.replaceCharacters(in: existingOrderRange, with: orderClause)
            return mutableQuery as String
        }

        if let trailingOrderRange = firstRegexRange(in: maskedQuery, pattern: #"(?is)\s+ORDER\s+BY\s+[\s\S]*$"#) {
            mutableQuery.replaceCharacters(in: trailingOrderRange, with: orderClause)
            return mutableQuery as String
        }

        if let suffixRange = firstRegexRange(in: maskedQuery, pattern: #"(?is)\s+(?:LIMIT|PROCEDURE|INTO|FOR|LOCK)\b"#),
           firstRegexRange(in: maskedQuery, pattern: #"(?is)^\s*\(?\s*SELECT\b"#) != nil {
            mutableQuery.insert(orderClause, at: suffixRange.location)
            return mutableQuery as String
        }

        mutableQuery.append(" \(orderClause)")
        return mutableQuery as String
    }

    func queryMaskedForClauseSearch(_ query: String) -> String {
        let maskedQuery = NSMutableString(string: query)
        let patterns = [
            #"(?s)"(?:[^"\\]|\\.)*""#,
            #"(?s)'(?:[^'\\]|\\.)*'"#,
            #"(?s)`(?:[^`\\]|\\.)*`"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            while true {
                let range = regex.rangeOfFirstMatch(in: maskedQuery as String, range: NSRange(location: 0, length: maskedQuery.length))
                if range.location == NSNotFound { break }
                maskedQuery.replaceCharacters(in: range, with: String(repeating: "_", count: range.length))
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
            runButton.menu?.items.first?.title = NSLocalizedString("Stop query", comment: "Stop query string")
        } else {
            updateContextualRunInterface()
        }
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

    @objc func copySelectedResultRows(_ sender: Any?) {
        let includeHeaders = (sender as? NSMenuItem)?.tag == SALightweightCopyWithColumnsTag
        guard let copyString = resultRowsAsTabString(includeHeaders: includeHeaders, rowIndexes: tableView.selectedRowIndexes) else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([Self.tabularPasteboardType, .string], owner: nil)
        pasteboard.setString(copyString, forType: Self.tabularPasteboardType)
        pasteboard.setString(copyString, forType: .string)
    }

    @objc func copySelectedResultRowsAsSQL(_ sender: Any?) {
        let skipAutoIncrement = (sender as? NSMenuItem)?.tag == SALightweightCopyAsSQLNoAutoIncTag
        guard let copyString = resultRowsAsSQLInserts(rowIndexes: tableView.selectedRowIndexes, skipAutoIncrement: skipAutoIncrement) else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(copyString, forType: .string)
    }

    func exportQueryResult(fileExtension: String, content: String) {
        guard !rows.isEmpty else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.allowedFileTypes = [fileExtension]
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "query_result.\(fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    func csvStringForCurrentResult() -> String {
        var lines = [tableView.tableColumns.enumerated().map { csvEscaped(columnName(forVisibleColumn: $0.offset, tableColumn: $0.element)) }.joined(separator: ",")]
        lines.append(contentsOf: rows.map { row in
            tableView.tableColumns.map { tableColumn in
                guard let columnIndex = Int(tableColumn.identifier.rawValue), columnIndex < row.count else { return csvEscaped("") }
                return csvEscaped(displayString(for: row[columnIndex], columnDefinition: columnDefinition(at: columnIndex)))
            }.joined(separator: ",")
        })
        return lines.joined(separator: "\n")
    }

    func xmlStringForCurrentResult() -> String {
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<resultset>"]
        for row in rows {
            lines.append("\t<row>")
            for (visibleColumn, tableColumn) in tableView.tableColumns.enumerated() {
                guard let columnIndex = Int(tableColumn.identifier.rawValue) else { continue }
                let name = xmlEscaped(columnName(forVisibleColumn: visibleColumn, tableColumn: tableColumn))
                let value = columnIndex < row.count ? xmlEscaped(displayString(for: row[columnIndex], columnDefinition: columnDefinition(at: columnIndex))) : ""
                lines.append("\t\t<field name=\"\(name)\">\(value)</field>")
            }
            lines.append("\t</row>")
        }
        lines.append("</resultset>")
        return lines.joined(separator: "\n")
    }

    func csvEscaped(_ value: String) -> String {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    func xmlEscaped(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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

    func resultRowsAsTabString(includeHeaders: Bool, rowIndexes: IndexSet) -> String? {
        guard !rowIndexes.isEmpty else { return nil }

        var lines: [String] = []
        if includeHeaders {
            lines.append(tableView.tableColumns.enumerated().map { copyEscaped(columnName(forVisibleColumn: $0.offset, tableColumn: $0.element)) }.joined(separator: "\t"))
        }

        rowIndexes.forEach { rowIndex in
            guard rowIndex < rows.count else { return }
            let row = rows[rowIndex]
            lines.append(tableView.tableColumns.map { tableColumn in
                guard let columnIndex = Int(tableColumn.identifier.rawValue), columnIndex < row.count else { return "" }
                return copyEscaped(displayString(for: row[columnIndex], columnDefinition: columnDefinition(at: columnIndex)))
            }.joined(separator: "\t"))
        }

        return lines.joined(separator: "\n")
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

    func copyEscaped(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\n", with: "\u{21B5}")
            .replacingOccurrences(of: "\t", with: "\u{21E5}")
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

    func canEditResultColumn(_ columnDefinition: NSDictionary) -> Bool {
        guard resultColumnOrigin(for: columnDefinition) != nil else { return false }

        let typeGrouping = ((columnDefinition["typegrouping"] as? String) ?? "").lowercased()
        return typeGrouping != "blobdata" && typeGrouping != "textdata"
    }

    func canEditResultCell(row: Int, column columnIndex: Int) -> Bool {
        guard !isRunning,
              let connection,
              row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < columnDefinitions.count,
              canEditResultColumn(columnDefinitions[columnIndex]),
              let origin = resultColumnOrigin(for: columnDefinitions[columnIndex]) else { return false }

        return whereClause(for: row, origin: origin, connection: connection) != nil
    }

    func prepareResultContextMenu(for event: NSEvent) {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let clickedRow = tableView.row(at: point)

        if clickedRow >= 0 && !tableView.selectedRowIndexes.contains(clickedRow) {
            tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }

        updateStatusSelectionSuffix()
    }

    func showCellEditError(_ message: String) {
        NSSound.beep()
        setStatusText(message)
        tableView.reloadData()
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
              let whereClause = whereClause(for: rowIndex, origin: origin, connection: connection) else { return nil }

        let newValue = sqlValue(forEditedObject: object, columnDefinition: columnDefinitions[columnIndex], connection: connection)
        let tableReference = "\(Self.backtickQuoted(origin.database)).\(Self.backtickQuoted(origin.table))"
        let countQuery = "SELECT COUNT(1) FROM \(tableReference) \(whereClause)"
        let updateQuery = "UPDATE \(tableReference) SET \(Self.backtickQuoted(origin.column)) = \(newValue.sql) \(whereClause)"

        return CellUpdate(countQuery: countQuery, updateQuery: updateQuery, localValue: newValue.localValue)
    }

    private func whereClause(for rowIndex: Int, origin: ResultColumnOrigin, connection: SPMySQLConnection) -> String? {
        var sameOriginColumns: [(index: Int, definition: NSDictionary)] = []

        for tableColumn in tableView.tableColumns {
            guard let columnIndex = Int(tableColumn.identifier.rawValue),
                  columnIndex < columnDefinitions.count,
                  columnIndex < rows[rowIndex].count,
                  let columnOrigin = resultColumnOrigin(for: columnDefinitions[columnIndex]),
                  columnOrigin.database == origin.database,
                  columnOrigin.table == origin.table else { continue }

            sameOriginColumns.append((columnIndex, columnDefinitions[columnIndex]))
        }

        let primaryColumns = sameOriginColumns.filter { isPrimaryKeyColumn($0.definition) }
        let identityColumns = primaryColumns.isEmpty
            ? sameOriginColumns.filter { canUseColumnForFallbackIdentity($0.definition) }
            : primaryColumns

        let parts = identityColumns.compactMap { index, definition -> String? in
            guard let columnOrigin = resultColumnOrigin(for: definition) else { return nil }
            let value = rows[rowIndex][index]

            if value is NSNull {
                return "\(Self.backtickQuoted(columnOrigin.column)) IS NULL"
            }

            return "\(Self.backtickQuoted(columnOrigin.column)) = \(sqlValue(forStoredObject: value, columnDefinition: definition, connection: connection))"
        }

        guard !parts.isEmpty else { return nil }

        return "WHERE (\(parts.joined(separator: " AND ")))"
    }

    func isPrimaryKeyColumn(_ columnDefinition: NSDictionary) -> Bool {
        if let value = columnDefinition["PRI_KEY_FLAG"] as? Bool {
            return value
        }

        if let value = columnDefinition["PRI_KEY_FLAG"] as? NSNumber {
            return value.boolValue
        }

        if let value = columnDefinition["PRI_KEY_FLAG"] as? String {
            return value == "1" || value.uppercased() == "PRI" || value.uppercased() == "YES"
        }

        return false
    }

    func canUseColumnForFallbackIdentity(_ columnDefinition: NSDictionary) -> Bool {
        let typeGrouping = ((columnDefinition["typegrouping"] as? String) ?? "").lowercased()
        let type = ((columnDefinition["type"] as? String) ?? "").uppercased()

        if typeGrouping == "blobdata" || typeGrouping == "textdata" || typeGrouping == "binary" {
            return false
        }

        return !type.hasSuffix("BLOB")
            && !type.hasSuffix("TEXT")
            && type != "BINARY"
            && type != "VARBINARY"
    }

    func sqlValue(forStoredObject object: Any, columnDefinition: NSDictionary, connection: SPMySQLConnection) -> String {
        if let data = object as? Data {
            return connection.escapeAndQuoteData(data) ?? Self.singleQuoted(displayString(for: data, columnDefinition: columnDefinition, truncate: false))
        }

        let value = String(describing: object)
        if ((columnDefinition["typegrouping"] as? String) ?? "") == "bit" {
            return "b'\(value)'"
        }

        return connection.escapeAndQuoteString(value) ?? Self.singleQuoted(value)
    }

    func sqlValue(forEditedObject object: Any?, columnDefinition: NSDictionary, connection: SPMySQLConnection) -> (sql: String, localValue: Any) {
        if let number = object as? NSNumber {
            return (number.stringValue, number.stringValue)
        }

        let value = String(describing: object ?? "")
        let typeGrouping = (columnDefinition["typegrouping"] as? String) ?? ""
        let nullValue = UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"

        if value == nullValue || ((typeGrouping == "float" || typeGrouping == "integer" || typeGrouping == "date") && value.isEmpty) {
            return ("NULL", NSNull())
        }

        if typeGrouping == "bit" {
            let bitValue = value.isEmpty || value == "0" ? "0" : value
            return ("b'\(bitValue)'", bitValue)
        }

        if typeGrouping == "date" && value == "NOW()" {
            return ("NOW()", value)
        }

        return (connection.escapeAndQuoteString(value) ?? Self.singleQuoted(value), value)
    }

    func matchingRowCount(for query: String, connection: SPMySQLConnection) -> Int? {
        guard let result = connection.queryString(query) else { return nil }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsArray

        guard let row = result.getRowAsArray(),
              let value = row.first else { return nil }

        return Int(String(describing: value))
    }

    static func backtickQuoted(_ value: String) -> String {
        "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    static func singleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
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

    func textView(_ textView: NSTextView,
                  shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        textViewWasChanged = true
        didCacheCurrentQueryRanges = false
        return true
    }

    @objc func selectCurrentQuery() {
        if currentQueryRange.length > 0 {
            queryTextView.setSelectedRange(currentQueryRange)
        }
    }

    @objc func showAutoHelpForCurrentWord(_ sender: Any?) {
    }
}

extension SALightweightQueryViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as AnyObject? === historySearchField {
            rebuildHistoryMenu()
        } else if obj.object as AnyObject? === favoriteSearchField {
            rebuildFavoritesMenu()
        }
    }
}

extension SALightweightQueryViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }

        switch action {
        case #selector(copySelectedResultRows(_:)):
            return !isRunning && tableView.numberOfSelectedRows > 0

        case #selector(copySelectedResultRowsAsSQL(_:)):
            return !isRunning && tableView.numberOfSelectedRows > 0 && !sqlInsertColumnIndexes(skipAutoIncrement: menuItem.tag == SALightweightCopyAsSQLNoAutoIncTag).isEmpty

        case #selector(exportQueryResultAsCSV(_:)), #selector(exportQueryResultAsXML(_:)):
            return !isRunning && !rows.isEmpty

        case #selector(runPrimaryQuery(_:)), #selector(runSecondaryQuery(_:)):
            return !isRunning && connection != nil

        case #selector(saveCurrentQueryToFavorites(_:)), #selector(saveAllQueriesToFavorites(_:)):
            return !isRunning && !queryTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case #selector(copyQueryHistory(_:)), #selector(saveQueryHistory(_:)), #selector(clearQueryHistory(_:)):
            guard let documentURL else { return false }
            return !isRunning && !(SPQueryController.shared().history(forFileURL: documentURL) as? [String] ?? []).isEmpty

        case #selector(commentCurrentQuery(_:)):
            return !isRunning && currentQueryRange.length > 0

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

extension SALightweightQueryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isRunning,
              !isApplyingQuerySort,
              let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let columnIndex = Int(key),
              columnIndex < columnDefinitions.count else { return }

        let queryToSort = lastResultQuery.isEmpty ? lastExecutedQuery : lastResultQuery
        guard !queryToSort.isEmpty else { return }

        isApplyingQuerySort = true
        runQueries([queryByApplyingSort(to: queryToSort, columnIndex: columnIndex, descending: !descriptor.ascending)])
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingQuerySort = false
        }
    }

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
        guard let copyString = resultRowsAsTabString(includeHeaders: false, rowIndexes: rowIndexes) else { return false }

        pasteboard.declareTypes([Self.tabularPasteboardType, .string], owner: nil)
        pasteboard.setString(copyString, forType: Self.tabularPasteboardType)
        pasteboard.setString(copyString, forType: .string)
        return true
    }

    func tableView(_ tableView: NSTableView,
                   toolTipFor cell: NSCell,
                   rect: UnsafeMutablePointer<NSRect>,
                   tableColumn: NSTableColumn?,
                   row: Int,
                   mouseLocation: NSPoint) -> String {
        guard row >= 0,
              row < rows.count,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].count else { return "" }

        let value = displayString(for: rows[row][columnIndex], columnDefinition: columnDefinition(at: columnIndex), truncate: false)
        return value.count > 1 ? value : ""
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0,
              row < rows.count,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].count else { return nil }

        return displayValue(row: row, column: columnIndex)
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
              canEditResultCell(row: row, column: columnIndex) else { return }

        let newValue = String(describing: object ?? "")
        guard newValue != displayString(for: rows[row][columnIndex], columnDefinition: columnDefinition(at: columnIndex), truncate: false) else { return }

        guard let update = cellUpdate(for: object, row: row, column: columnIndex, connection: connection) else {
            showCellEditError(NSLocalizedString("Couldn't identify field origin unambiguously.", comment: "lightweight query edit missing origin"))
            return
        }

        let reloadAfterEdit = UserDefaults.standard.bool(forKey: SPReloadAfterEditingRow)
        let queryToReload = lastExecutedQuery

        setStatusText(NSLocalizedString("Saving cell...", comment: "lightweight query saving cell status"))
        isRunning = true
        updateControls()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak connection] in
            guard let self, let connection else { return }

            if !self.database.isEmpty {
                _ = connection.selectDatabase(self.database)
            }

            let matchingRows = self.matchingRowCount(for: update.countQuery, connection: connection)
            var error = connection.queryErrored() ? connection.lastErrorMessage() : nil

            if error == nil, matchingRows == 1 {
                _ = connection.queryString(update.updateQuery)
                error = connection.queryErrored() ? connection.lastErrorMessage() : nil
            }

            DispatchQueue.main.async {
                self.isRunning = false
                self.updateControls()

                if let error, !error.isEmpty {
                    self.showCellEditError(error)
                    return
                }

                guard matchingRows == 1 else {
                    self.showCellEditError(NSLocalizedString("Couldn't identify a single row to update.", comment: "lightweight query edit no unique row"))
                    return
                }

                if reloadAfterEdit, !queryToReload.isEmpty {
                    self.runQueries([queryToReload])
                    return
                }

                guard row < self.rows.count,
                      columnIndex < self.rows[row].count else {
                    self.tableView.reloadData()
                    return
                }

                self.rows[row][columnIndex] = update.localValue
                self.setStatusText(NSLocalizedString("Cell updated.", comment: "lightweight query cell updated status"))
                self.tableView.reloadData()
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
        return autodetectedResultWidth(for: tableView.tableColumns[column], columnIndex: columnIndex, maxRows: 500)
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard tableView === self.tableView,
              row >= 0,
              row < rows.count,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier),
              columnIndex < rows[row].count,
              let textCell = cell as? NSTextFieldCell else { return }

        textCell.textColor = rows[row][columnIndex] is NSNull ? .secondaryLabelColor : .labelColor
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        guard tableView === self.tableView,
              let columnIdentifier = tableColumn?.identifier.rawValue,
              let columnIndex = Int(columnIdentifier) else { return false }

        return canEditResultCell(row: row, column: columnIndex)
    }

    func displayValue(row: Int, column columnIndex: Int) -> String {
        guard row >= 0,
              row < rows.count,
              columnIndex >= 0,
              columnIndex < rows[row].count else { return "" }

        return displayString(for: rows[row][columnIndex], columnDefinition: columnDefinition(at: columnIndex))
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
        if value is NSNull {
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        if let data = value as? Data {
            if UserDefaults.standard.bool(forKey: SPDisplayBinaryDataAsHex),
               shouldDisplayDataAsHex(columnDefinition: columnDefinition) {
                if truncate && data.count > 255 {
                    return "0x" + data.prefix(255).map { String(format: "%02X", $0) }.joined() + "..."
                }
                return "0x" + data.map { String(format: "%02X", $0) }.joined()
            }

            return String(data: data, encoding: .utf8) ?? ""
        }

        let string = String(describing: value)
        if truncate, string.count > 256 {
            return "\(string.prefix(256))..."
        }

        return string
    }

    func shouldDisplayDataAsHex(columnDefinition: NSDictionary?) -> Bool {
        let typeGrouping = ((columnDefinition?["typegrouping"] as? String) ?? "").lowercased()
        let type = ((columnDefinition?["type"] as? String) ?? "").lowercased()

        return typeGrouping == "binary"
            || typeGrouping == "blobdata"
            || type.contains("binary")
            || type.hasSuffix("blob")
    }
}
