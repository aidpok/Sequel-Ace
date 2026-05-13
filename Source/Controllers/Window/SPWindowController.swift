//
//  SPWindowController.swift
//  Sequel Ace
//
//  Created by Jakub Kašpar on 24.01.2021.
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

import Cocoa
import SnapKit

@objc final class SPWindowController: NSWindowController {

    private var loadedDatabaseDocument: SPDatabaseDocument?

    @objc var databaseDocument: SPDatabaseDocument {
        return installLegacyDatabaseDocumentIfNeeded()
    }

    @objc let uniqueID: UUID = UUID()

    private let connectionContentView = NSView(frame: .zero)
    private let connectionPlaceholderSplitView = SPSplitView(frame: .zero)
    private var connectionController: SPConnectionController?
    private var activeConnection: SPMySQLConnection?
    private var activeConnectionInfo: SAConnectionInfoObjC?

    private var selectedDatabase: String?
    private var databaseListNeedsLoad = true
    private var databaseListIsLoading = false
    private var lightweightTables: [String] = []
    private var filteredLightweightTables: [String] = []
    private var lightweightTableInfoRows: [String] = [NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane")]
    private var lightweightTableInfoLoadToken = UUID()
    private var selectedTable: String?
    private var activeConnectionName: String?
    private var activeServerVersion: String?
    private let databaseToolbarController = SADatabaseToolbarController()
    private let lightweightStructureController = SALightweightStructureViewController()
    private let lightweightContentController = SALightweightContentViewController()
    private let lightweightQueryController = SALightweightQueryViewController()
    private let lightweightTableInfoController = SALightweightTableInfoViewController()
    private let lightweightRelationsController = SALightweightRelationsViewController()
    private let lightweightTriggersController = SALightweightTriggersViewController()
    private var activeLightweightViewMode: SAViewMode = .structure
    private var lightweightHistoryBackStack: [String] = []
    private var lightweightHistoryForwardStack: [String] = []
    private var isRestoringLightweightHistory = false
    private let lightweightShellView = NSView(frame: .zero)
    private let lightweightContentSplitView = SPSplitView(frame: .zero)
    private let lightweightSidebarView = NSVisualEffectView(frame: .zero)
    private let lightweightSidebarSplitView = SPSplitView(frame: .zero)
    private let lightweightTablesPane = NSView(frame: .zero)
    private let lightweightTableInfoPane = NSVisualEffectView(frame: .zero)
    private let lightweightSidebarButtonBar = NSView(frame: .zero)
    private let lightweightDetailView = NSView(frame: .zero)
    private var didRegisterLightweightPreferenceObservers = false

    private lazy var tableFilterField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.focusRingType = .none
        field.placeholderString = NSLocalizedString("Filter", comment: "table list filter placeholder")
        field.target = self
        field.action = #selector(lightweightTableFilterChanged(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }()

    private lazy var tablesListView: NSTableView = {
        let tableView = SPTableView(frame: .zero)
        tableView.headerView = nil
        tableView.focusRingType = .none
        tableView.allowsExpansionToolTips = true
        tableView.allowsColumnReordering = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.selectionHighlightStyle = .sourceList
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        if #available(macOS 11.0, *) {
            tableView.style = .sourceList
        }
        tableView.rowHeight = 25
        let tableFont = UserDefaults.getFont()
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tables"))
        tableColumn.width = 182
        tableColumn.minWidth = 50
        tableColumn.maxWidth = 3000
        tableColumn.resizingMask = .autoresizingMask
        let tableCell = SPTableTextFieldCell(textCell: "")
        tableCell.lineBreakMode = .byTruncatingTail
        tableCell.isSelectable = true
        tableCell.isEditable = true
        tableCell.font = tableFont
        tableColumn.dataCell = tableCell
        tableView.addTableColumn(tableColumn)
        return tableView
    }()

    private lazy var lightweightTableInfoView: NSTableView = {
        let tableView = SPTableView(frame: .zero)
        tableView.identifier = NSUserInterfaceItemIdentifier("LightweightTableInfo")
        tableView.headerView = nil
        tableView.focusRingType = .none
        tableView.allowsExpansionToolTips = true
        tableView.allowsColumnReordering = false
        tableView.allowsTypeSelect = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.selectionHighlightStyle = .sourceList
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        if #available(macOS 11.0, *) {
            tableView.style = .sourceList
        }
        tableView.rowHeight = Self.lightweightInfoRowHeight(for: UserDefaults.getFont())
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tableInfo"))
        tableColumn.width = 182
        tableColumn.minWidth = 50
        tableColumn.maxWidth = 3000
        tableColumn.resizingMask = .autoresizingMask
        let tableCell = SPTableTextFieldCell(textCell: "")
        tableCell.lineBreakMode = .byTruncatingTail
        tableCell.isSelectable = false
        tableCell.isEditable = false
        tableCell.controlSize = .small
        tableCell.font = UserDefaults.getFont()
        tableColumn.dataCell = tableCell
        tableView.addTableColumn(tableColumn)
        return tableView
    }()

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == SPGlobalFontSettings {
            applyLightweightSidebarFontPreference()
            return
        }

        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }

    private lazy var lightweightStatusLabel: NSTextField = {
        let label = NSTextField(labelWithString: NSLocalizedString("Choose a database to load tables.", comment: "lightweight database shell empty state"))
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }()

    private var processing = false

    override func awakeFromNib() {
        super.awakeFromNib()

        if let window = window  {
            window.collectionBehavior = [window.collectionBehavior, .fullScreenPrimary]
        }

        setupAppearance()
    }

    // MARK: - Accessory
    private lazy var tabAccessoryView: SPWindowTabAccessory = SPWindowTabAccessory()

	deinit {
		if didRegisterLightweightPreferenceObservers {
			UserDefaults.standard.removeObserver(self, forKeyPath: SPGlobalFontSettings)
		}
	}
}

// MARK: - Private API

private extension SPWindowController {
    func setupAppearance() {
        installConnectionView()

        if #available(macOS 10.13, *) {
            window?.tab.accessoryView = tabAccessoryView
        }

        databaseToolbarController.delegate = self
    }

    func installConnectionView() {
        guard let contentView = window?.contentView else { return }

        window?.toolbar = databaseToolbarController.toolbar
        updateWindow(title: NSLocalizedString("Sequel Ace", comment: "default connection tab title"),
                     tabTitle: NSLocalizedString("Sequel Ace", comment: "default connection tab title"))

        connectionContentView.frame = contentView.bounds
        connectionContentView.autoresizingMask = [.width, .height]
        contentView.addSubview(connectionContentView)

        connectionPlaceholderSplitView.frame = connectionContentView.bounds
        connectionPlaceholderSplitView.autoresizingMask = [.width, .height]
        connectionContentView.addSubview(connectionPlaceholderSplitView)

        let controller = SPConnectionController(document: self)
        controller?.connectionDelegate = self
        connectionController = controller
    }

    @discardableResult
    func installLegacyDatabaseDocumentIfNeeded(selectingDatabase database: String? = nil, item: String? = nil) -> SPDatabaseDocument {
        if let loadedDatabaseDocument = loadedDatabaseDocument {
            if let database = database ?? selectedDatabase {
                loadedDatabaseDocument.selectDatabase(database, item: item)
            }
            return loadedDatabaseDocument
        }

        if activeConnection == nil {
            connectionController?.cancelConnection(nil)
        }
        connectionContentView.removeFromSuperviewWithoutNeedingDisplay()
        lightweightShellView.removeFromSuperviewWithoutNeedingDisplay()

        let document = SPDatabaseDocument(windowController: self)!
        loadedDatabaseDocument = document

        if let activeConnectionInfo = activeConnectionInfo {
            document.connectionController()?.applyConnectionInfo(activeConnectionInfo)
        }
        if let database = database ?? selectedDatabase {
            document.connectionController()?.database = database
        }

        document.updateWindowTitle(self)

        window?.contentView?.addSubview(document.databaseView())
        document.databaseView()?.frame = window?.contentView?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 400)

        let connectedFallback = activeConnection != nil

        if let activeConnection = activeConnection {
            document.connectionController()?.restoreDatabaseView()
            document.setConnection(activeConnection)
            self.activeConnection = nil
        }

        if let database = database ?? selectedDatabase, !connectedFallback || item != nil {
            document.selectDatabase(database, item: item)
        }

        return document
    }

    private enum LightweightDBViewLayout {
        static let sidebarWidth: CGFloat = 214
        static let tableInfoHeight: CGFloat = 177
        static let sidebarButtonBarHeight: CGFloat = 25
        static let sidebarMinimumWidth: CGFloat = 40
        static let detailMinimumWidth: CGFloat = 505
        static let sidebarPaneMinimumHeight: CGFloat = 20
        static let dbViewAutosaveName = "DBViewSplitter"
        static let tableInfoAutosaveName = "DbViewInfoPanelSplit"
    }

    func installLightweightDatabaseShell() {
        guard let contentView = window?.contentView else { return }

        connectionContentView.removeFromSuperviewWithoutNeedingDisplay()
        window?.toolbar = databaseToolbarController.toolbar
        databaseToolbarController.setDatabasePickerEnabled(true)
        registerLightweightPreferenceObserversIfNeeded()

        let sidebarWidth = LightweightDBViewLayout.sidebarWidth
        let tableInfoHeight = LightweightDBViewLayout.tableInfoHeight
        let sidebarButtonBarHeight = LightweightDBViewLayout.sidebarButtonBarHeight
        let savedSidebarWidth = savedSplitViewFirstSubviewLength(forAutosaveName: LightweightDBViewLayout.dbViewAutosaveName, isVertical: true)

        lightweightShellView.removeFromSuperviewWithoutNeedingDisplay()
        lightweightShellView.frame = contentView.bounds
        lightweightShellView.autoresizingMask = [.width, .height]
        lightweightShellView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
        lightweightContentSplitView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
        lightweightSidebarView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
        lightweightSidebarSplitView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
        lightweightTablesPane.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
        lightweightTableInfoPane.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
        lightweightSidebarButtonBar.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        lightweightContentSplitView.frame = lightweightShellView.bounds
        lightweightContentSplitView.autoresizingMask = [.width, .height]
        lightweightContentSplitView.dividerStyle = .thin
        lightweightContentSplitView.isVertical = true
        lightweightContentSplitView.autosaveName = LightweightDBViewLayout.dbViewAutosaveName
        lightweightContentSplitView.delegate = self

        lightweightSidebarView.material = .sidebar
        lightweightSidebarView.blendingMode = .behindWindow
        lightweightSidebarView.state = .active
        lightweightSidebarView.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: lightweightShellView.bounds.height)
        lightweightSidebarView.autoresizingMask = [.height]
        lightweightSidebarView.wantsLayer = true

        lightweightSidebarSplitView.frame = NSRect(x: 0, y: sidebarButtonBarHeight, width: sidebarWidth, height: max(0, lightweightSidebarView.bounds.height - sidebarButtonBarHeight))
        lightweightSidebarSplitView.autoresizingMask = [.width, .height]
        lightweightSidebarSplitView.dividerStyle = .thin
        lightweightSidebarSplitView.isVertical = false
        lightweightSidebarSplitView.autosaveName = LightweightDBViewLayout.tableInfoAutosaveName
        lightweightSidebarSplitView.delegate = self

        lightweightTablesPane.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: max(20, lightweightShellView.bounds.height - tableInfoHeight))
        lightweightTablesPane.autoresizingMask = [.width, .height]
        lightweightTablesPane.wantsLayer = true

        tableFilterField.frame = NSRect(x: 5, y: lightweightTablesPane.bounds.height - 27, width: lightweightTablesPane.bounds.width - 10, height: 22)
        tableFilterField.autoresizingMask = [.width, .minYMargin]
        lightweightTablesPane.addSubview(tableFilterField)

        let tableScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: lightweightTablesPane.bounds.width, height: max(0, lightweightTablesPane.bounds.height - 30)))
        tableScrollView.autoresizingMask = [.width, .height]
        tableScrollView.focusRingType = .none
        tableScrollView.borderType = .noBorder
        tableScrollView.autohidesScrollers = true
        tableScrollView.hasHorizontalScroller = false
        tableScrollView.hasVerticalScroller = true
        tableScrollView.drawsBackground = false
        tableScrollView.contentView.drawsBackground = false
        tablesListView.frame = tableScrollView.bounds
        tablesListView.autoresizingMask = [.width, .height]
        tableScrollView.documentView = tablesListView
        lightweightTablesPane.addSubview(tableScrollView)

        lightweightTableInfoPane.material = .sidebar
        lightweightTableInfoPane.blendingMode = .behindWindow
        lightweightTableInfoPane.state = .active
        lightweightTableInfoPane.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: tableInfoHeight)
        lightweightTableInfoPane.autoresizingMask = [.width, .height]
        lightweightTableInfoPane.wantsLayer = true
        let tableInfoScrollView = NSScrollView(frame: lightweightTableInfoPane.bounds)
        tableInfoScrollView.autoresizingMask = [.width, .height]
        tableInfoScrollView.focusRingType = .none
        tableInfoScrollView.borderType = .noBorder
        tableInfoScrollView.autohidesScrollers = true
        tableInfoScrollView.hasHorizontalScroller = false
        tableInfoScrollView.hasVerticalScroller = false
        tableInfoScrollView.drawsBackground = false
        tableInfoScrollView.contentView.drawsBackground = false
        lightweightTableInfoView.frame = tableInfoScrollView.bounds
        lightweightTableInfoView.autoresizingMask = [.width, .height]
        tableInfoScrollView.documentView = lightweightTableInfoView
        lightweightTableInfoPane.addSubview(tableInfoScrollView)

        lightweightSidebarSplitView.addArrangedSubview(lightweightTablesPane)
        lightweightSidebarSplitView.addArrangedSubview(lightweightTableInfoPane)
        lightweightSidebarView.addSubview(lightweightSidebarSplitView)
        tablesListView.tableColumns.first?.width = tableScrollView.bounds.width
        lightweightTableInfoView.tableColumns.first?.width = tableInfoScrollView.bounds.width

        lightweightSidebarButtonBar.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: sidebarButtonBarHeight)
        lightweightSidebarButtonBar.autoresizingMask = [.width, .maxYMargin]
        lightweightSidebarButtonBar.wantsLayer = true
        installLightweightSidebarButtonBar()
        lightweightSidebarView.addSubview(lightweightSidebarButtonBar)

        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
        lightweightDetailView.frame = NSRect(x: sidebarWidth + lightweightContentSplitView.dividerThickness, y: 0, width: max(0, contentView.bounds.width - sidebarWidth - lightweightContentSplitView.dividerThickness), height: contentView.bounds.height)
        lightweightDetailView.autoresizingMask = [.width, .height]

        lightweightContentSplitView.addArrangedSubview(lightweightSidebarView)
        lightweightContentSplitView.addArrangedSubview(lightweightDetailView)
        lightweightContentSplitView.setCollapsibleSubviewIndex(0)
        lightweightContentSplitView.setMinSize(LightweightDBViewLayout.sidebarMinimumWidth, ofSubviewAt: 0)
        lightweightContentSplitView.setMinSize(LightweightDBViewLayout.detailMinimumWidth, ofSubviewAt: 1)
        lightweightSidebarSplitView.setCollapsibleSubviewIndex(1)
        lightweightSidebarSplitView.setMinSize(LightweightDBViewLayout.sidebarPaneMinimumHeight, ofSubviewAt: 0)
        lightweightSidebarSplitView.setMinSize(LightweightDBViewLayout.sidebarPaneMinimumHeight, ofSubviewAt: 1)
        lightweightShellView.addSubview(lightweightContentSplitView)
        contentView.addSubview(lightweightShellView)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.lightweightContentSplitView.superview != nil else { return }
            self.lightweightContentSplitView.setPosition(savedSidebarWidth ?? sidebarWidth, ofDividerAt: 0)
            let defaultTablesPaneHeight = max(LightweightDBViewLayout.sidebarPaneMinimumHeight, self.lightweightSidebarSplitView.bounds.height - tableInfoHeight)
            self.lightweightSidebarSplitView.setPosition(defaultTablesPaneHeight, ofDividerAt: 0)

            if UserDefaults.standard.bool(forKey: SPTableInformationPanelCollapsed) {
                self.lightweightSidebarSplitView.setCollapsibleSubviewCollapsed(true, animate: false)
            } else {
                self.lightweightSidebarSplitView.setCollapsibleSubviewCollapsed(false, animate: false)
            }
            self.applyLightweightSidebarFontPreference()
            self.resizeLightweightSidebarColumns()
        }

        showLightweightPlaceholder(NSLocalizedString("Choose a database to load tables.", comment: "lightweight database shell empty state"))
    }

    func installLightweightSidebarButtonBar() {
        let addTableButton = NSButton(frame: NSRect(x: 0, y: 0, width: 25, height: 25))
        addTableButton.bezelStyle = .smallSquare
        addTableButton.image = NSImage(named: NSImage.addTemplateName)
        addTableButton.imagePosition = .imageOnly
        addTableButton.toolTip = NSLocalizedString("Add new table", comment: "add new table tooltip")
        addTableButton.target = self
        addTableButton.action = #selector(addLightweightTable(_:))
        lightweightSidebarButtonBar.addSubview(addTableButton)

        let actionButton = NSPopUpButton(frame: NSRect(x: 25, y: 0, width: 35, height: 25), pullsDown: true)
        actionButton.bezelStyle = .regularSquare
        actionButton.image = NSImage(named: NSImage.actionTemplateName)
        actionButton.imagePosition = .imageOnly
        actionButton.menu = NSMenu(title: "OtherViews")
        actionButton.menu?.removeAllItems()
        let imageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        imageItem.image = NSImage(named: NSImage.actionTemplateName)
        imageItem.isHidden = true
        actionButton.menu?.addItem(imageItem)
        addLightweightSidebarAction(NSLocalizedString("Copy Table Name", comment: "copy table name menu item"), #selector(copyLightweightTableName(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Rename Table...", comment: "rename table menu title"), #selector(renameLightweightTable(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Duplicate Table...", comment: "duplicate table menu title"), #selector(duplicateLightweightTable(_:)), to: actionButton.menu)
        actionButton.menu?.addItem(.separator())
        addLightweightSidebarAction(NSLocalizedString("Truncate Table...", comment: "truncate table menu title"), #selector(truncateLightweightTable(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Remove Table...", comment: "remove table menu title"), #selector(removeLightweightTable(_:)), to: actionButton.menu)
        actionButton.menu?.addItem(.separator())
        addLightweightSidebarAction(NSLocalizedString("Toggle Pin Table", comment: "toggle pin table menu item"), #selector(togglePinLightweightTable(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Open Table in New Tab", comment: "open table in new tab title"), #selector(openLightweightTableInNewTab(_:)), to: actionButton.menu)
        actionButton.menu?.addItem(.separator())
        addLightweightSidebarAction(NSLocalizedString("Refresh Tables", comment: "refresh tables menu item"), #selector(refreshLightweightTables), to: actionButton.menu)
        lightweightSidebarButtonBar.addSubview(actionButton)

        let refreshButton = NSButton(frame: NSRect(x: 70, y: 0, width: 25, height: 25))
        refreshButton.bezelStyle = .smallSquare
        refreshButton.image = NSImage(named: NSImage.Name("NSRefreshTemplate"))
        refreshButton.imagePosition = .imageOnly
        refreshButton.toolTip = NSLocalizedString("Refresh table list", comment: "refresh table list tooltip")
        refreshButton.target = self
        refreshButton.action = #selector(refreshLightweightTables)
        lightweightSidebarButtonBar.addSubview(refreshButton)

        let quickLookButton = NSButton(frame: NSRect(x: 105, y: 0, width: 25, height: 25))
        quickLookButton.bezelStyle = .shadowlessSquare
        quickLookButton.image = NSImage(named: NSImage.quickLookTemplateName)
        quickLookButton.imagePosition = .imageOnly
        quickLookButton.toolTip = NSLocalizedString("Toggle the visibility of the Information panel", comment: "toggle table information panel tooltip")
        quickLookButton.target = self
        quickLookButton.action = #selector(toggleLightweightTableInfoPane(_:))
        lightweightSidebarSplitView.setToggleCollapse(quickLookButton)
        lightweightSidebarButtonBar.addSubview(quickLookButton)

        let handle = NSImageView(frame: NSRect(x: lightweightSidebarButtonBar.bounds.width - 25, y: 0, width: 25, height: 25))
        handle.autoresizingMask = [.minXMargin]
        handle.image = NSImage(named: "button_bar_handleTemplate")
        if #available(macOS 10.14, *) {
            handle.contentTintColor = .labelColor
        }
        lightweightContentSplitView.setAdditionalDragHandle(handle)
        lightweightSidebarButtonBar.addSubview(handle)
    }

    func addLightweightSidebarAction(_ title: String, _ action: Selector, to menu: NSMenu?) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu?.addItem(item)
    }

    @objc func addLightweightTable(_ sender: Any?) {
        performLegacyTableListAction(sender) { tableList, sender in
            tableList.addTable(sender)
        }
    }

    @objc func copyLightweightTableName(_ sender: Any?) {
        guard let selectedTable = selectedTable else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: self)
        pasteboard.setString(selectedTable, forType: .string)
    }

    @objc func renameLightweightTable(_ sender: Any?) {
        performLegacyTableListAction(sender) { tableList, sender in
            tableList.renameTable(sender)
        }
    }

    @objc func duplicateLightweightTable(_ sender: Any?) {
        performLegacyTableListAction(sender) { tableList, sender in
            tableList.copyTable(sender)
        }
    }

    @objc func truncateLightweightTable(_ sender: Any?) {
        performLegacyTableListAction(sender) { tableList, sender in
            tableList.truncateTable(sender)
        }
    }

    @objc func removeLightweightTable(_ sender: Any?) {
        performLegacyTableListAction(sender) { tableList, sender in
            tableList.removeTable(sender)
        }
    }

    @objc func togglePinLightweightTable(_ sender: Any?) {
        performLegacyTableListAction(sender) { tableList, sender in
            tableList.togglePinTable(sender)
        }
    }

    @objc func openLightweightTableInNewTab(_ sender: Any?) {
        performLegacyTableListAction(sender) { tableList, sender in
            tableList.openTableInNewTab(sender)
        }
    }

    func performLegacyTableListAction(_ sender: Any?, action: (SPTablesList, Any?) -> Void) {
        let document = installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable)
        action(document.tablesListInstance, sender)
    }

    @objc func toggleLightweightTableInfoPane(_ sender: Any?) {
        let shouldCollapse = !lightweightSidebarSplitView.isCollapsibleSubviewCollapsed()
        lightweightSidebarSplitView.setCollapsibleSubviewCollapsed(shouldCollapse, animate: true)
        UserDefaults.standard.set(shouldCollapse, forKey: SPTableInformationPanelCollapsed)
    }

    func resizeLightweightSidebarColumns() {
        if let tableColumn = tablesListView.tableColumns.first {
            tableColumn.width = max(tableColumn.minWidth, tablesListView.enclosingScrollView?.contentSize.width ?? tablesListView.bounds.width)
        }
        if let tableColumn = lightweightTableInfoView.tableColumns.first {
            tableColumn.width = max(tableColumn.minWidth, lightweightTableInfoView.enclosingScrollView?.contentSize.width ?? lightweightTableInfoView.bounds.width)
        }
    }

    func savedSplitViewFirstSubviewLength(forAutosaveName autosaveName: String, isVertical: Bool) -> CGFloat? {
        let key = "NSSplitView Subview Frames \(autosaveName)"
        guard let frames = UserDefaults.standard.array(forKey: key) as? [String],
              let firstFrame = frames.first else {
            return nil
        }

        let values = firstFrame.split(separator: ",").compactMap { part -> CGFloat? in
            let value = part.trimmingCharacters(in: .whitespaces)
            guard let doubleValue = Double(value) else { return nil }
            return CGFloat(doubleValue)
        }
        let lengthIndex = isVertical ? 2 : 3
        guard values.indices.contains(lengthIndex), values[lengthIndex] > 0 else {
            return nil
        }

        return values[lengthIndex]
    }

    func registerLightweightPreferenceObserversIfNeeded() {
        guard !didRegisterLightweightPreferenceObservers else { return }

        UserDefaults.standard.addObserver(self, forKeyPath: SPGlobalFontSettings, options: .new, context: nil)
        didRegisterLightweightPreferenceObservers = true
    }

    func applyLightweightSidebarFontPreference() {
        let tableFont = UserDefaults.getFont()
        tablesListView.rowHeight = 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: tableFont]).height
        lightweightTableInfoView.rowHeight = Self.lightweightInfoRowHeight(for: tableFont)

        for column in tablesListView.tableColumns {
            (column.dataCell as? NSCell)?.font = tableFont
        }

        for column in lightweightTableInfoView.tableColumns {
            (column.dataCell as? NSCell)?.font = tableFont
        }

        tablesListView.reloadData()
        lightweightTableInfoView.reloadData()
        tablesListView.setNeedsDisplay(tablesListView.bounds)
        lightweightTableInfoView.setNeedsDisplay(lightweightTableInfoView.bounds)
    }

    static func lightweightInfoRowHeight(for font: NSFont) -> CGFloat {
        return ceil("{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: font]).height) + 1.0
    }

    func requestLightweightDatabasesIfNeeded() {
        requestLightweightDatabases(forceReload: false)
    }

    private func requestLightweightDatabases(forceReload: Bool) {
        guard (forceReload || databaseListNeedsLoad), !databaseListIsLoading, let activeConnection = activeConnection else { return }

        databaseListIsLoading = true
        databaseToolbarController.showDatabaseLoadingState()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            let databases = activeConnection.databases() as? [String] ?? []

            DispatchQueue.main.async {
                self.databaseListNeedsLoad = false
                self.databaseListIsLoading = false
                let selectedDatabase = self.selectedDatabase.flatMap { databases.contains($0) ? $0 : nil }
                self.databaseToolbarController.reloadDatabases(databases, selectedDatabase: selectedDatabase)
            }
        }
    }

    func setLightweightFallbackToolbarItemsEnabled(_ enabled: Bool) {
        databaseToolbarController.setFallbackItemsEnabled(enabled)
        updateLightweightHistoryToolbarState()
    }

    func updateLightweightWindowTitle(table: String? = nil) {
        let name = activeConnectionName?.isEmpty == false
            ? activeConnectionName!
            : NSLocalizedString("Connected", comment: "lightweight connected tab title")
        let tabTitle = [name, selectedDatabase, table].compactMap { value -> String? in
            guard let value = value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: "/")

        var windowTitle = ""
        if UserDefaults.standard.bool(forKey: "DisplayServerVersionInWindowTitle"), let activeServerVersion = activeServerVersion, !activeServerVersion.isEmpty {
            windowTitle += "(MySQL \(activeServerVersion)) "
        }
        windowTitle += tabTitle

        updateWindow(title: windowTitle, tabTitle: tabTitle)
    }

    func applyLightweightTableFilter() {
        let filter = tableFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !filter.isEmpty else {
            filteredLightweightTables = lightweightTables
            return
        }

        filteredLightweightTables = lightweightTables.filter { table in
            table.range(of: filter, options: .caseInsensitive) != nil
        }
    }

    func loadTables(for database: String, preservingSelection: Bool = false) {
        guard let activeConnection = activeConnection else { return }

        let tableToRestore = preservingSelection ? selectedTable : nil
        if selectedDatabase != database {
            resetLightweightTableHistory()
        }
        selectedTable = nil
        resetLightweightTableInfo()
        showLightweightPlaceholder(NSLocalizedString("Loading tables...", comment: "lightweight database shell loading tables"))
        lightweightTables = []
        filteredLightweightTables = []
        tablesListView.reloadData()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }
            _ = activeConnection.selectDatabase(database)
            let tables = activeConnection.tables() as? [String] ?? []

            DispatchQueue.main.async {
                self.selectedDatabase = database
                self.updateLightweightWindowTitle()
                self.lightweightTables = tables
                self.applyLightweightTableFilter()
                self.tablesListView.reloadData()
                if let tableToRestore = tableToRestore, tables.contains(tableToRestore) {
                    self.selectLightweightTableInSidebar(tableToRestore)
                    self.selectLightweightTable(tableToRestore, recordsHistory: false)
                    return
                }
                self.showLightweightPlaceholder(tables.isEmpty
                    ? NSLocalizedString("No tables in this database.", comment: "lightweight database shell no tables")
                    : NSLocalizedString("Select a table or choose a toolbar section.", comment: "lightweight database shell table loaded empty state"))
            }
        }
    }

    func selectLightweightTable(_ table: String, recordsHistory: Bool = true) {
        selectedTable = table
        if recordsHistory {
            recordLightweightHistorySelection(table)
        }
        updateLightweightWindowTitle(table: table)
        loadLightweightTableInfo(for: table)

        switch activeLightweightViewMode {
        case .content:
            showLightweightContent(for: table)
        case .query:
            showLightweightQuery()
        case .status:
            showLightweightStatus(for: table)
        case .relations:
            showLightweightRelations(for: table)
        case .triggers:
            showLightweightTriggers(for: table)
        default:
            showLightweightStructure(for: table)
        }
    }

    func resetLightweightTableHistory() {
        lightweightHistoryBackStack.removeAll()
        lightweightHistoryForwardStack.removeAll()
        updateLightweightHistoryToolbarState()
    }

    func recordLightweightHistorySelection(_ table: String) {
        guard !isRestoringLightweightHistory else { return }
        guard lightweightHistoryBackStack.last != table else {
            updateLightweightHistoryToolbarState()
            return
        }

        lightweightHistoryBackStack.append(table)
        if lightweightHistoryBackStack.count > 50 {
            lightweightHistoryBackStack.removeFirst()
        }
        lightweightHistoryForwardStack.removeAll()
        updateLightweightHistoryToolbarState()
    }

    func updateLightweightHistoryToolbarState() {
        databaseToolbarController.setHistoryNavigationEnabled(canGoBack: lightweightHistoryBackStack.count > 1,
                                                              canGoForward: !lightweightHistoryForwardStack.isEmpty)
    }

    func navigateLightweightHistory(backwards: Bool) {
        guard activeConnection != nil, loadedDatabaseDocument == nil else { return }

        let table: String?
        if backwards {
            guard lightweightHistoryBackStack.count > 1 else {
                NSSound.beep()
                updateLightweightHistoryToolbarState()
                return
            }
            let previous = lightweightHistoryBackStack[lightweightHistoryBackStack.count - 2]
            guard lightweightTables.contains(previous) else {
                NSSound.beep()
                updateLightweightHistoryToolbarState()
                return
            }
            let current = lightweightHistoryBackStack.removeLast()
            lightweightHistoryForwardStack.append(current)
            table = previous
        } else {
            guard let next = lightweightHistoryForwardStack.popLast() else {
                NSSound.beep()
                updateLightweightHistoryToolbarState()
                return
            }
            guard lightweightTables.contains(next) else {
                lightweightHistoryForwardStack.append(next)
                NSSound.beep()
                updateLightweightHistoryToolbarState()
                return
            }
            lightweightHistoryBackStack.append(next)
            table = next
        }

        guard let table = table else {
            NSSound.beep()
            updateLightweightHistoryToolbarState()
            return
        }

        selectLightweightTableInSidebar(table)
        selectLightweightTable(table, recordsHistory: false)
        updateLightweightHistoryToolbarState()
    }

    func selectLightweightTableInSidebar(_ table: String) {
        if !filteredLightweightTables.contains(table) {
            tableFilterField.stringValue = ""
            applyLightweightTableFilter()
            tablesListView.reloadData()
        }

        guard let index = filteredLightweightTables.firstIndex(of: table) else { return }
        isRestoringLightweightHistory = true
        tablesListView.selectRowIndexes(IndexSet(integer: index + 1), byExtendingSelection: false)
        tablesListView.scrollRowToVisible(index + 1)
        isRestoringLightweightHistory = false
    }

    func resetLightweightTableInfo() {
        lightweightTableInfoLoadToken = UUID()
        lightweightTableInfoRows = [NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane")]
        lightweightTableInfoView.reloadData()
    }

    func loadLightweightTableInfo(for table: String) {
        guard let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else { return }

        lightweightTableInfoLoadToken = UUID()
        let token = lightweightTableInfoLoadToken
        lightweightTableInfoRows = [
            NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane"),
            NSLocalizedString("loading...", comment: "table info loading row")
        ]
        lightweightTableInfoView.reloadData()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            let rows = SALightweightTableInfoLoader.sidebarRows(for: table, database: selectedDatabase, connection: activeConnection)

            DispatchQueue.main.async {
                guard self.lightweightTableInfoLoadToken == token, self.selectedTable == table else { return }
                self.lightweightTableInfoRows = rows
                self.lightweightTableInfoView.reloadData()
            }
        }
    }

    func showLightweightPlaceholder(_ message: String) {
        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
        lightweightStatusLabel.stringValue = message
        lightweightStatusLabel.frame = NSRect(x: 20, y: max(0, (lightweightDetailView.bounds.height - 60) / 2), width: max(0, lightweightDetailView.bounds.width - 40), height: 60)
        lightweightStatusLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        lightweightDetailView.addSubview(lightweightStatusLabel)
    }

    func showLightweightStructure(for table: String) {
        guard let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else { return }

        activeLightweightViewMode = .structure
        databaseToolbarController.selectViewMode(.structure)
        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        let structureView = lightweightStructureController.view
        structureView.frame = lightweightDetailView.bounds
        structureView.autoresizingMask = [.width, .height]
        lightweightDetailView.addSubview(structureView)
        lightweightStructureController.tableStructureDidChange = { [weak self] in
            self?.lightweightContentController.clearCachedTables()
            self?.refreshLightweightTableInfoAfterMutation()
        }
        lightweightStructureController.loadStructure(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func showLightweightContent(for table: String) {
        guard let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else { return }

        activeLightweightViewMode = .content
        databaseToolbarController.selectViewMode(.content)
        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        let contentView = lightweightContentController.view
        contentView.frame = lightweightDetailView.bounds
        contentView.autoresizingMask = [.width, .height]
        lightweightDetailView.addSubview(contentView)
        lightweightContentController.requestLegacyContentFallback = { [weak self] in
            guard let self = self else { return }
            self.installLegacyDatabaseDocumentIfNeeded(selectingDatabase: self.selectedDatabase, item: self.selectedTable).viewContent()
        }
        lightweightContentController.tableContentDidChange = { [weak self] in
            self?.refreshLightweightTableInfoAfterMutation()
        }
        lightweightContentController.loadContent(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func refreshLightweightTableInfoAfterMutation() {
        guard let selectedTable = selectedTable else { return }

        loadLightweightTableInfo(for: selectedTable)
    }

    func showLightweightQuery() {
        guard let activeConnection = activeConnection else { return }

        activeLightweightViewMode = .query
        databaseToolbarController.selectViewMode(.query)
        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        let queryView = lightweightQueryController.view
        queryView.frame = lightweightDetailView.bounds
        queryView.autoresizingMask = [.width, .height]
        lightweightDetailView.addSubview(queryView)
        lightweightQueryController.requestLegacyQueryFallback = { [weak self] query in
            guard let self = self else { return }
            let document = self.installLegacyDatabaseDocumentIfNeeded(selectingDatabase: self.selectedDatabase, item: self.selectedTable)
            if let query = query, !query.isEmpty {
                document.doPerformLoadQueryService(query)
            } else {
                document.viewQuery()
            }
        }
        lightweightQueryController.loadQuery(database: selectedDatabase, table: selectedTable, connection: activeConnection)
    }

    func showLightweightStatus(for table: String?) {
        activeLightweightViewMode = .status
        databaseToolbarController.selectViewMode(.status)
        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        let tableInfoView = lightweightTableInfoController.view
        tableInfoView.frame = lightweightDetailView.bounds
        tableInfoView.autoresizingMask = [.width, .height]
        lightweightDetailView.addSubview(tableInfoView)

        guard let table = table, let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else {
            lightweightTableInfoController.showPlaceholder(NSLocalizedString("Select a table to view table information.", comment: "lightweight table info empty state"))
            return
        }

        lightweightTableInfoController.loadTableInfo(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func showLightweightRelations(for table: String?) {
        activeLightweightViewMode = .relations
        databaseToolbarController.selectViewMode(.relations)
        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        let relationsView = lightweightRelationsController.view
        relationsView.frame = lightweightDetailView.bounds
        relationsView.autoresizingMask = [.width, .height]
        lightweightDetailView.addSubview(relationsView)
        lightweightRelationsController.requestLegacyRelationsFallback = { [weak self] in
            guard let self = self else { return }
            self.installLegacyDatabaseDocumentIfNeeded(selectingDatabase: self.selectedDatabase, item: self.selectedTable).viewRelations()
        }

        guard let table = table, let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else {
            lightweightRelationsController.showPlaceholder(NSLocalizedString("Select a table to view relations.", comment: "lightweight relations empty state"))
            return
        }

        lightweightRelationsController.loadRelations(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func showLightweightTriggers(for table: String?) {
        activeLightweightViewMode = .triggers
        databaseToolbarController.selectViewMode(.triggers)
        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        let triggersView = lightweightTriggersController.view
        triggersView.frame = lightweightDetailView.bounds
        triggersView.autoresizingMask = [.width, .height]
        lightweightDetailView.addSubview(triggersView)
        lightweightTriggersController.requestLegacyTriggersFallback = { [weak self] in
            guard let self = self else { return }
            self.installLegacyDatabaseDocumentIfNeeded(selectingDatabase: self.selectedDatabase, item: self.selectedTable).viewTriggers()
        }

        guard let table = table, let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else {
            lightweightTriggersController.showPlaceholder(NSLocalizedString("Select a table to view triggers.", comment: "lightweight triggers empty state"))
            return
        }

        lightweightTriggersController.loadTriggers(for: table, database: selectedDatabase, connection: activeConnection)
    }
}

// MARK: - Public API

@objc extension SPWindowController {
    func updateWindow(title: String, tabTitle: String) {
        window?.title = title
        if #available(macOS 10.13, *) {
            window?.tab.title = tabTitle
        }
        
        tabAccessoryView.setTitle(title: tabTitle)
    }

    func updateWindowAccessory(color: NSColor?, isSSL: Bool) {
        tabAccessoryView.update(color: color, isSSL: isSSL)
    }

    @objc func loadedDatabaseDocumentIfAvailable() -> SPDatabaseDocument? {
        return loadedDatabaseDocument
    }

    @objc func refreshLightweightTables() {
        if let document = loadedDatabaseDocument {
            document.refreshTables()
            return
        }

        guard activeConnection != nil, let selectedDatabase = selectedDatabase else { return }
        lightweightStructureController.clearCachedTables()
        lightweightContentController.clearCachedTables()
        loadTables(for: selectedDatabase, preservingSelection: true)
    }

    @objc func refreshLightweightDatabases() {
        if let document = loadedDatabaseDocument {
            document.setDatabases()
            return
        }

        lightweightStructureController.clearCachedTables()
        lightweightContentController.clearCachedTables()
        requestLightweightDatabases(forceReload: true)
    }

    @objc func showLegacyGotoDatabase() {
        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).showGotoDatabase()
    }

    @objc func lightweightTableFilterChanged(_ sender: NSSearchField) {
        applyLightweightTableFilter()
        tablesListView.reloadData()
    }

    @objc func viewStructure() {
        if let selectedTable = selectedTable, loadedDatabaseDocument == nil {
            showLightweightStructure(for: selectedTable)
            return
        }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewStructure()
    }

    @objc func viewContent() {
        if let selectedTable = selectedTable, loadedDatabaseDocument == nil {
            showLightweightContent(for: selectedTable)
            return
        }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewContent()
    }

    @objc func viewQuery() {
        if activeConnection != nil, loadedDatabaseDocument == nil {
            showLightweightQuery()
            return
        }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewQuery()
    }

    @objc func viewStatus() {
        if activeConnection != nil, loadedDatabaseDocument == nil {
            showLightweightStatus(for: selectedTable)
            return
        }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewStatus()
    }

    @objc func viewRelations() {
        if activeConnection != nil, loadedDatabaseDocument == nil {
            showLightweightRelations(for: selectedTable)
            return
        }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewRelations()
    }

    @objc func viewTriggers() {
        if activeConnection != nil, loadedDatabaseDocument == nil {
            showLightweightTriggers(for: selectedTable)
            return
        }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewTriggers()
    }

    @objc func backForwardInHistory(_ sender: Any) {
        if activeConnection != nil, loadedDatabaseDocument == nil {
            let tag: Int
            if let menuItem = sender as? NSMenuItem {
                tag = menuItem.tag
            } else if let control = sender as? NSSegmentedControl {
                tag = control.selectedSegment
            } else {
                tag = 0
            }
            guard tag == 0 || tag == 1 else { return }
            navigateLightweightHistory(backwards: tag == 0)
            return
        }

        if let document = loadedDatabaseDocument {
            document.backForwardInHistory(sender)
        }
    }

    @objc func focusActiveLightweightContentFilter() {
        guard activeConnection != nil, loadedDatabaseDocument == nil, activeLightweightViewMode == .content else { return }

        lightweightContentController.focusRowFilter()
    }

    @objc func focusLightweightContentFilter() {
        guard activeConnection != nil, loadedDatabaseDocument == nil, let selectedTable = selectedTable else { return }

        if activeLightweightViewMode != .content {
            showLightweightContent(for: selectedTable)
        }
        lightweightContentController.focusRowFilter()
    }

    @objc func showLightweightFilterTable() {
        guard activeConnection != nil, loadedDatabaseDocument == nil else { return }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).showFilterTable()
    }

    @objc func focusLightweightTableFilter() {
        guard activeConnection != nil, loadedDatabaseDocument == nil else { return }

        window?.makeFirstResponder(tableFilterField)
    }

    @objc func copyLightweightCreateTableSyntax(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.copyCreateTableSyntax(nil)
            return
        }

        guard let table = selectedTable,
              let syntax = lightweightCreateTableSyntax(showErrors: true) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: self)
        pasteboard.setString(syntax, forType: .string)

        let notification = NSUserNotification()
        notification.title = NSLocalizedString("Syntax Copied", comment: "create table syntax copied notification title")
        notification.informativeText = String(format: NSLocalizedString("Syntax for %@ table copied", comment: "description for table syntax copied notification"), table)
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    @objc func showLightweightCreateTableSyntax(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.showCreateTableSyntax(nil)
            return
        }

        guard let table = selectedTable,
              let syntax = lightweightCreateTableSyntax(showErrors: true) else { return }

        let title = String(format: NSLocalizedString("Create syntax for TABLE '%@'", comment: "Create syntax label"), table)
        showLightweightCreateSyntaxSheet(title: title, syntax: syntax)
    }

    @objc func checkLightweightTable() {
        performLightweightTableMaintenance(.check)
    }

    @objc func repairLightweightTable() {
        performLightweightTableMaintenance(.repair)
    }

    @objc func analyzeLightweightTable() {
        performLightweightTableMaintenance(.analyze)
    }

    @objc func optimizeLightweightTable() {
        performLightweightTableMaintenance(.optimize)
    }

    @objc func flushLightweightTable() {
        performLightweightTableMaintenance(.flush)
    }

    @objc func checksumLightweightTable() {
        performLightweightTableMaintenance(.checksum)
    }

    @objc func showUserManager() {
        installLegacyDatabaseDocumentIfNeeded().showUserManager()
    }

    @objc func showConsole() {
        installLegacyDatabaseDocumentIfNeeded().toggleConsole()
    }

    private func lightweightCreateTableSyntax(showErrors: Bool) -> String? {
        guard let activeConnection = activeConnection,
              let selectedDatabase = selectedDatabase,
              let selectedTable = selectedTable else {
            if showErrors {
                showLightweightCreateSyntaxError(NSLocalizedString("Select a table to view create syntax.", comment: "create syntax no selected table error"))
            }
            return nil
        }

        guard let syntax = SALightweightTableInfoLoader.createSyntax(for: selectedTable, database: selectedDatabase, connection: activeConnection) else {
            if showErrors {
                let message: String
                if activeConnection.isConnected(), activeConnection.lastErrorMessage()?.isEmpty == false {
                    message = String(format: NSLocalizedString("An error occurred while creating table syntax.\n\n%@", comment: "Error shown when unable to show create table syntax"), activeConnection.lastErrorMessage() ?? "")
                } else {
                    message = NSLocalizedString("The creation syntax could not be retrieved due to a permissions error.\n\nPlease check your user permissions with an administrator.", comment: "Create syntax permission denied detail")
                }
                showLightweightCreateSyntaxError(message)
            }
            return nil
        }

        return syntax
    }

    private enum LightweightTableMaintenanceAction {
        case check
        case repair
        case analyze
        case optimize
        case flush
        case checksum

        var queryKeyword: String {
            switch self {
            case .check: return "CHECK TABLE"
            case .repair: return "REPAIR TABLE"
            case .analyze: return "ANALYZE TABLE"
            case .optimize: return "OPTIMIZE TABLE"
            case .flush: return "FLUSH TABLE"
            case .checksum: return "CHECKSUM TABLE"
            }
        }

        var errorTitle: String {
            switch self {
            case .check: return NSLocalizedString("Unable to check table", comment: "unable to check table message")
            case .repair: return NSLocalizedString("Unable to repair table", comment: "unable to repair table message")
            case .analyze: return NSLocalizedString("Unable to analyze table", comment: "unable to analyze table message")
            case .optimize: return NSLocalizedString("Unable to optimze table", comment: "unable to optimze table message")
            case .flush: return NSLocalizedString("Unable to flush table", comment: "unable to flush table message")
            case .checksum: return NSLocalizedString("Unable to perform the checksum", comment: "unable to perform the checksum")
            }
        }

        var resultTitlePrefix: String {
            switch self {
            case .check: return NSLocalizedString("Check", comment: "CHECK one or more tables - result title")
            case .repair: return NSLocalizedString("Repair", comment: "REPAIR one or more tables - result title")
            case .analyze: return NSLocalizedString("Analyze", comment: "ANALYZE one or more tables - result title")
            case .optimize: return NSLocalizedString("Optimize", comment: "OPTIMIZE one or more tables - result title")
            case .flush: return NSLocalizedString("Flush", comment: "FLUSH one or more tables - result title")
            case .checksum: return NSLocalizedString("Checksum", comment: "checksum %@ message")
            }
        }

        var successMessage: String {
            switch self {
            case .check: return NSLocalizedString("Check table successfully passed.", comment: "check table successfully passed message")
            case .repair: return NSLocalizedString("Successfully repaired table.", comment: "repair table successfully passed message")
            case .analyze: return NSLocalizedString("Successfully analyzed table.", comment: "analyze table successfully passed message")
            case .optimize: return NSLocalizedString("Successfully optimized table.", comment: "optimize table successfully passed message")
            case .flush: return NSLocalizedString("Successfully flushed table.", comment: "flush table successfully passed message")
            case .checksum: return ""
            }
        }

        var failureMessage: String {
            switch self {
            case .check: return NSLocalizedString("Check table failed.", comment: "check table failed message")
            case .repair: return NSLocalizedString("Repair table failed.", comment: "repair table failed message")
            case .analyze: return NSLocalizedString("Analyze table failed.", comment: "analyze table failed message")
            case .optimize: return NSLocalizedString("Optimize table failed.", comment: "optimize table failed message")
            case .flush: return NSLocalizedString("Flush table failed.", comment: "flush table failed message")
            case .checksum: return ""
            }
        }

        func errorMessage(what: String, mysqlError: String) -> String {
            switch self {
            case .check:
                return String(format: NSLocalizedString("An error occurred while trying to check the %@.\n\nMySQL said:%@", comment: "an error occurred while trying to check the %@.\n\nMySQL said:%@"), what, mysqlError)
            case .repair:
                return String(format: NSLocalizedString("An error occurred while repairing the %@.\n\nMySQL said:%@", comment: "an error occurred while trying to repair the %@.\n\nMySQL said:%@"), what, mysqlError)
            case .analyze:
                return String(format: NSLocalizedString("An error occurred while analyzing the %@.\n\nMySQL said:%@", comment: "an error occurred while analyzing the %@.\n\nMySQL said:%@"), what, mysqlError)
            case .optimize:
                return String(format: NSLocalizedString("An error occurred while optimzing the %@.\n\nMySQL said:%@", comment: "an error occurred while trying to optimze the %@.\n\nMySQL said:%@"), what, mysqlError)
            case .flush:
                return String(format: NSLocalizedString("An error occurred while flushing the %@.\n\nMySQL said:%@", comment: "an error occurred while trying to flush the %@.\n\nMySQL said:%@"), what, mysqlError)
            case .checksum:
                return String(format: NSLocalizedString("An error occurred while performing the checksum on %@.\n\nMySQL said:%@", comment: "an error occurred while performing the checksum on the %@.\n\nMySQL said:%@"), what, mysqlError)
            }
        }
    }

    @nonobjc private func performLightweightTableMaintenance(_ action: LightweightTableMaintenanceAction) {
        guard let activeConnection = activeConnection,
              let selectedDatabase = selectedDatabase,
              let selectedTable = selectedTable else { return }

        if let document = loadedDatabaseDocument {
            switch action {
            case .check: document.checkTable()
            case .repair: document.repairTable()
            case .analyze: document.analyzeTable()
            case .optimize: document.optimizeTable()
            case .flush: document.flushTable()
            case .checksum: document.checksumTable()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            let tableReference = "\(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(selectedTable))"
            guard let result = activeConnection.queryString("\(action.queryKeyword) \(tableReference)") else {
                DispatchQueue.main.async {
                    self.showLightweightTableMaintenanceQueryError(action, table: selectedTable, mysqlError: activeConnection.lastErrorMessage() ?? "")
                }
                return
            }

            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary

            if activeConnection.queryErrored() {
                DispatchQueue.main.async {
                    self.showLightweightTableMaintenanceQueryError(action, table: selectedTable, mysqlError: activeConnection.lastErrorMessage() ?? "")
                }
                return
            }

            let rows = result.getAllRows() as? [[String: Any]] ?? []
            DispatchQueue.main.async {
                self.showLightweightTableMaintenanceResult(action, table: selectedTable, rows: rows)
            }
        }
    }

    @nonobjc private func showLightweightTableMaintenanceQueryError(_ action: LightweightTableMaintenanceAction, table: String, mysqlError: String) {
        guard activeConnection?.isConnected() == true else { return }

        let what = String(format: "%@ '%@'", NSLocalizedString("table", comment: "table"), table)
        showLightweightTableMaintenanceAlert(title: action.errorTitle, message: action.errorMessage(what: what, mysqlError: mysqlError))
    }

    @nonobjc private func showLightweightTableMaintenanceResult(_ action: LightweightTableMaintenanceAction, table: String, rows: [[String: Any]]) {
        let what = String(format: "%@ '%@'", NSLocalizedString("table", comment: "table"), table)
        let title = "\(action.resultTitlePrefix) \(what)"
        let lastRow = rows.last ?? [:]

        if action == .checksum {
            let checksum = stringValue(lastRow["Checksum"])
            let message = String(format: NSLocalizedString("Table checksum: %@", comment: "table checksum: %@"), checksum)
            showLightweightTableMaintenanceAlert(title: title, message: message)
            return
        }

        let messageType = stringValue(lastRow["Msg_type"])
        let messageText = stringValue(lastRow["Msg_text"])
        let message = messageType == "status" ? action.successMessage : action.failureMessage
        showLightweightTableMaintenanceAlert(title: title, message: String(format: NSLocalizedString("%@\n\nMySQL said: %@", comment: "Error display text, showing original MySQL error"), message, messageText))
    }

    private static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    private func stringValue(_ value: Any?) -> String {
        guard let value = value else { return "" }
        if let string = value as? String { return string }
        return "\(value)"
    }

    private func showLightweightTableMaintenanceAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))

        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func showLightweightCreateSyntaxSheet(title: String, syntax: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 680, height: 360))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = UserDefaults.getFont()
        textView.string = syntax
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView
        alert.accessoryView = scrollView

        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func showLightweightCreateSyntaxError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Error", comment: "error message title")
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))

        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

}

extension SPWindowController: NSWindowDelegate {
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let loadedDatabaseDocument = loadedDatabaseDocument, !loadedDatabaseDocument.parentTabShouldClose() {
            return false
        }

        if let appDelegate = NSApp.delegate as? SPAppController{
            appDelegate.setSpfSessionDocData(nil)
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Tell listeners that this database document is being closed - fixes retain cycles and allows cleanup
        connectionController?.cancelConnection(nil)
        if let loadedDatabaseDocument = loadedDatabaseDocument {
            NotificationCenter.default.post(name: NSNotification.Name.SPDocumentWillClose, object: loadedDatabaseDocument)
        } else {
            activeConnection?.disconnect()
        }
    }
}

extension SPWindowController: SADatabaseDocumentProviding {
    @objc var contentViewSplitter: SPSplitView {
        return connectionPlaceholderSplitView
    }

    @objc func databaseView() -> NSView {
        return connectionContentView
    }

    @objc func parentWindowControllerWindow() -> NSWindow? {
        return window
    }

    @objc func setConnection(_ connection: SPMySQLConnection) {
        activeConnection = connection
    }

    @objc var isProcessing: Bool {
        get { processing }
        set { processing = newValue }
    }

    @objc func updateWindowTitle(_ sender: Any) {
        updateWindow(title: window?.title ?? NSLocalizedString("Sequel Ace", comment: "default connection tab title"),
                     tabTitle: window?.tab.title ?? NSLocalizedString("Sequel Ace", comment: "default connection tab title"))
    }
}

extension SPWindowController: SAConnectionDelegate {
    @objc func connectionDidEstablish(_ connection: SPMySQLConnection, info: SAConnectionInfoObjC) {
        activeConnection = connection
        activeConnectionInfo = info
        activeConnectionName = info.name
        activeServerVersion = connection.serverVersionString()
        selectedDatabase = info.database.isEmpty ? nil : info.database
        databaseListNeedsLoad = true

        updateLightweightWindowTitle()
        installLightweightDatabaseShell()
        setLightweightFallbackToolbarItemsEnabled(true)
        requestLightweightDatabasesIfNeeded()

        if let selectedDatabase = selectedDatabase {
            databaseToolbarController.selectOnlyDatabase(selectedDatabase)
            loadTables(for: selectedDatabase)
        }
    }

    @objc func connectionDidFail(withError error: String, detail: String?) {
        showLightweightPlaceholder(error)
    }
}

extension SPWindowController: SADatabaseToolbarControllerDelegate {
    func databaseToolbarDidRequestDatabaseLoad(_ controller: SADatabaseToolbarController) {
        requestLightweightDatabasesIfNeeded()
    }

    func databaseToolbar(_ controller: SADatabaseToolbarController, didSelectDatabase database: String) {
        loadTables(for: database)
    }

    func databaseToolbar(_ controller: SADatabaseToolbarController, didSelectViewMode mode: SAViewMode) {
        switch mode {
        case .structure:
            viewStructure()
        case .content:
            viewContent()
        case .query:
            viewQuery()
        case .status:
            viewStatus()
        case .relations:
            viewRelations()
        case .triggers:
            viewTriggers()
        }
    }

    func databaseToolbarDidSelectUserManager(_ controller: SADatabaseToolbarController) {
        showUserManager()
    }

    func databaseToolbarDidSelectConsole(_ controller: SADatabaseToolbarController) {
        showConsole()
    }

    func databaseToolbar(_ controller: SADatabaseToolbarController, didSelectHistorySegment segment: Int) {
        guard segment == 0 || segment == 1 else { return }

        if activeConnection != nil, loadedDatabaseDocument == nil {
            navigateLightweightHistory(backwards: segment == 0)
            return
        }

        if let document = loadedDatabaseDocument {
            let item = NSMenuItem()
            item.tag = segment
            document.backForwardInHistory(item)
        }
    }
}

extension SPWindowController: NSSplitViewDelegate, AllowSplitViewResizing {
    @objc func allowSplitViewResizing() -> Bool {
        return true
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard dividerIndex == 0 else { return proposedMinimumPosition }

        if splitView == lightweightContentSplitView {
            return max(proposedMinimumPosition, 40)
        }

        if splitView == lightweightSidebarSplitView {
            return max(proposedMinimumPosition, 20)
        }

        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard dividerIndex == 0 else { return proposedMaximumPosition }

        if splitView == lightweightContentSplitView {
            return min(proposedMaximumPosition, splitView.bounds.width - 505)
        }

        if splitView == lightweightSidebarSplitView {
            return min(proposedMaximumPosition, splitView.bounds.height - 20)
        }

        return proposedMaximumPosition
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard notification.object as? NSSplitView == lightweightContentSplitView || notification.object as? NSSplitView == lightweightSidebarSplitView else {
            return
        }

        resizeLightweightSidebarColumns()
    }
}

extension SPWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if isLightweightTableInfoView(tableView) {
            return lightweightTableInfoRows.count
        }

        return lightweightTables.isEmpty ? 1 : filteredLightweightTables.count + 1
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if isLightweightTableInfoView(tableView) {
            guard row >= 0, row < lightweightTableInfoRows.count else { return nil }
            return lightweightTableInfoRows[row]
        }

        if row == 0 {
            return NSLocalizedString("TABLES", comment: "header for table list")
        }

        return filteredLightweightTables[row - 1]
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard let cell = cell as? SPTableTextFieldCell else { return }

        cell.font = isLightweightTableInfoView(tableView) && row == 0
            ? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            : UserDefaults.getFont()
        cell.setIndentationLevel(0)
        cell.setNote("")
        if isLightweightTableInfoView(tableView) {
            cell.image = row == 0 ? nil : NSImage(named: "table-property")
            return
        }

        cell.image = row == 0 ? nil : NSImage(named: "table-small")
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        return row == 0
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if isLightweightTableInfoView(tableView) {
            return false
        }

        return row > 0
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if row == 0 {
            return 25
        }

        return tableView.rowHeight
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView == tablesListView else { return }
        guard !isRestoringLightweightHistory else { return }
        guard !filteredLightweightTables.isEmpty else { return }
        let selectedRow = tablesListView.selectedRow
        guard selectedRow > 0, selectedRow - 1 < filteredLightweightTables.count else { return }

        let table = filteredLightweightTables[selectedRow - 1]
        selectLightweightTable(table)
    }

    private func isLightweightTableInfoView(_ tableView: NSTableView) -> Bool {
        return tableView.identifier == NSUserInterfaceItemIdentifier("LightweightTableInfo")
    }
}

private extension SPConnectionController {
    func applyConnectionInfo(_ info: SAConnectionInfoObjC) {
        type = info.type.rawValue
        name = info.name
        host = info.host
        user = info.user
        password = info.password
        database = info.database
        socket = info.socket
        port = info.port
        colorIndex = info.colorIndex
        useCompression = info.useCompression
        timeZoneMode = SPConnectionTimeZoneMode(rawValue: info.timeZoneMode.rawValue)!
        timeZoneIdentifier = info.timeZoneIdentifier
        allowDataLocalInfile = info.allowDataLocalInfile
        enableClearTextPlugin = info.enableClearTextPlugin
        useAWSIAMAuth = info.useAWSIAMAuth
        awsRegion = info.awsRegion
        awsProfile = info.awsProfile
        useSSL = info.useSSL
        sslKeyFileLocationEnabled = info.sslKeyFileLocationEnabled
        sslKeyFileLocation = info.sslKeyFileLocation
        sslCertificateFileLocationEnabled = info.sslCertificateFileLocationEnabled
        sslCertificateFileLocation = info.sslCertificateFileLocation
        sslCACertFileLocationEnabled = info.sslCACertFileLocationEnabled
        sslCACertFileLocation = info.sslCACertFileLocation
        sshHost = info.sshHost
        sshUser = info.sshUser
        sshPassword = info.sshPassword
        sshKeyLocationEnabled = info.sshKeyLocationEnabled
        sshKeyLocation = info.sshKeyLocation
        sshPort = info.sshPort
    }
}
