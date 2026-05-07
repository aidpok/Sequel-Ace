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
    private var selectedTable: String?
    private var activeConnectionName: String?
    private var activeServerVersion: String?
    private let databaseToolbarController = SADatabaseToolbarController()
    private let lightweightStructureController = SALightweightStructureViewController()
    private let lightweightContentController = SALightweightContentViewController()
    private let lightweightShellView = NSView(frame: .zero)
    private let lightweightDetailView = NSView(frame: .zero)

    private lazy var tableFilterField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = NSLocalizedString("Filter", comment: "table list filter placeholder")
        field.target = self
        field.action = #selector(lightweightTableFilterChanged(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }()

    private lazy var tablesListView: NSTableView = {
        let tableView = NSTableView(frame: .zero)
        tableView.headerView = nil
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
        let tableFont = UserDefaults.getFont()
        tableView.rowHeight = 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: tableFont]).height
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tables"))
        tableColumn.width = 182
        tableColumn.minWidth = 50
        tableColumn.maxWidth = 3000
        tableColumn.resizingMask = .autoresizingMask
        let tableCell = SPTableTextFieldCell(textCell: "")
        tableCell.lineBreakMode = .byClipping
        tableCell.isSelectable = true
        tableCell.isEditable = true
        tableCell.font = tableFont
        tableColumn.dataCell = tableCell
        tableView.addTableColumn(tableColumn)
        return tableView
    }()

    private lazy var lightweightActivitiesLabel: NSTextField = {
        let label = NSTextField(labelWithString: NSLocalizedString("ACTIVITIES", comment: "activities sidebar heading"))
        label.font = NSFont.boldSystemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }()

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
        print("Deinit called")
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

    func installLightweightDatabaseShell() {
        guard let contentView = window?.contentView else { return }

        connectionContentView.removeFromSuperviewWithoutNeedingDisplay()
        window?.toolbar = databaseToolbarController.toolbar
        databaseToolbarController.setDatabasePickerEnabled(true)

        let sidebarWidth: CGFloat = 214

        lightweightShellView.removeFromSuperviewWithoutNeedingDisplay()
        lightweightShellView.frame = contentView.bounds
        lightweightShellView.autoresizingMask = [.width, .height]
        lightweightShellView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        let sidebar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: contentView.bounds.height))
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.autoresizingMask = [.height]
        sidebar.wantsLayer = true
        sidebar.layer?.masksToBounds = true

        tableFilterField.frame = NSRect(x: 5, y: sidebar.bounds.height - 27, width: sidebar.bounds.width - 10, height: 22)
        tableFilterField.autoresizingMask = [.width, .minYMargin]
        sidebar.addSubview(tableFilterField)

        let activitiesHeight: CGFloat = 205
        let tablesPane = NSView(frame: NSRect(x: 0, y: activitiesHeight, width: sidebar.bounds.width, height: sidebar.bounds.height - activitiesHeight - 30))
        tablesPane.autoresizingMask = [.width, .height]
        tablesPane.wantsLayer = true
        tablesPane.layer?.masksToBounds = true
        let tableScrollView = NSScrollView(frame: tablesPane.bounds)
        tableScrollView.autoresizingMask = [.width, .height]
        tableScrollView.hasVerticalScroller = true
        tableScrollView.drawsBackground = false
        tableScrollView.wantsLayer = true
        tableScrollView.layer?.masksToBounds = true
        tablesListView.frame = tableScrollView.bounds
        tablesListView.autoresizingMask = [.width, .height]
        tableScrollView.documentView = tablesListView
        tablesPane.addSubview(tableScrollView)

        let activitiesPane = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sidebar.bounds.width, height: activitiesHeight))
        activitiesPane.material = .sidebar
        activitiesPane.blendingMode = .behindWindow
        activitiesPane.state = .active
        activitiesPane.autoresizingMask = [.width, .maxYMargin]
        activitiesPane.wantsLayer = true
        activitiesPane.layer?.masksToBounds = true
        lightweightActivitiesLabel.frame = NSRect(x: 12, y: activitiesPane.bounds.height - 37, width: activitiesPane.bounds.width - 24, height: 17)
        lightweightActivitiesLabel.autoresizingMask = [.width, .minYMargin]
        activitiesPane.addSubview(lightweightActivitiesLabel)

        sidebar.addSubview(tablesPane)
        sidebar.addSubview(activitiesPane)
        tablesListView.tableColumns.first?.width = tableScrollView.bounds.width

        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }
        lightweightDetailView.frame = NSRect(x: sidebarWidth, y: 0, width: max(0, contentView.bounds.width - sidebarWidth), height: contentView.bounds.height)
        lightweightDetailView.autoresizingMask = [.width, .height]

        lightweightShellView.addSubview(sidebar)
        lightweightShellView.addSubview(lightweightDetailView)
        contentView.addSubview(lightweightShellView)
        showLightweightPlaceholder(NSLocalizedString("Choose a database to load tables.", comment: "lightweight database shell empty state"))
    }

    func requestLightweightDatabasesIfNeeded() {
        guard databaseListNeedsLoad, !databaseListIsLoading, let activeConnection = activeConnection else { return }

        databaseListIsLoading = true
        databaseToolbarController.showDatabaseLoadingState()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            let databases = activeConnection.databases() as? [String] ?? []

            DispatchQueue.main.async {
                self.databaseListNeedsLoad = false
                self.databaseListIsLoading = false
                self.databaseToolbarController.reloadDatabases(databases, selectedDatabase: self.selectedDatabase)
            }
        }
    }

    func setLightweightFallbackToolbarItemsEnabled(_ enabled: Bool) {
        databaseToolbarController.setFallbackItemsEnabled(enabled)
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

    func loadTables(for database: String) {
        guard let activeConnection = activeConnection else { return }

        selectedTable = nil
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
                self.showLightweightPlaceholder(tables.isEmpty
                    ? NSLocalizedString("No tables in this database.", comment: "lightweight database shell no tables")
                    : NSLocalizedString("Select a table or choose a toolbar section.", comment: "lightweight database shell table loaded empty state"))
            }
        }
    }

    func selectLightweightTable(_ table: String) {
        selectedTable = table
        updateLightweightWindowTitle(table: table)
        showLightweightStructure(for: table)
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

        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        let structureView = lightweightStructureController.view
        structureView.frame = lightweightDetailView.bounds
        structureView.autoresizingMask = [.width, .height]
        lightweightDetailView.addSubview(structureView)
        lightweightStructureController.loadStructure(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func showLightweightContent(for table: String) {
        guard let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else { return }

        lightweightDetailView.subviews.forEach { $0.removeFromSuperviewWithoutNeedingDisplay() }

        let contentView = lightweightContentController.view
        contentView.frame = lightweightDetailView.bounds
        contentView.autoresizingMask = [.width, .height]
        lightweightDetailView.addSubview(contentView)
        lightweightContentController.loadContent(for: table, database: selectedDatabase, connection: activeConnection)
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
        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewQuery()
    }

    @objc func viewStatus() {
        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewStatus()
    }

    @objc func viewRelations() {
        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewRelations()
    }

    @objc func viewTriggers() {
        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewTriggers()
    }

    @objc func backForwardInHistory(_ sender: Any) {
        installLegacyDatabaseDocumentIfNeeded().backForwardInHistory(sender)
    }

    @objc func showUserManager() {
        installLegacyDatabaseDocumentIfNeeded().showUserManager()
    }

    @objc func showConsole() {
        installLegacyDatabaseDocumentIfNeeded().toggleConsole()
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
        let item = NSMenuItem()
        item.tag = segment
        installLegacyDatabaseDocumentIfNeeded().backForwardInHistory(item)
    }
}

extension SPWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return lightweightTables.isEmpty ? 1 : filteredLightweightTables.count + 1
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if row == 0 {
            return NSLocalizedString("TABLES", comment: "header for table list")
        }

        return filteredLightweightTables[row - 1]
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard let cell = cell as? SPTableTextFieldCell else { return }

        cell.font = UserDefaults.getFont()
        cell.setIndentationLevel(0)
        cell.setNote("")
        cell.image = row == 0 ? nil : NSImage(named: "table-small")
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        return row == 0
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return row > 0
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if row == 0 {
            return 25
        }

        return tableView.rowHeight
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !filteredLightweightTables.isEmpty else { return }
        let selectedRow = tablesListView.selectedRow
        guard selectedRow > 0, selectedRow - 1 < filteredLightweightTables.count else { return }

        let table = filteredLightweightTables[selectedRow - 1]
        selectLightweightTable(table)
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
