//
//  SPWindowController+LightweightSidebar.swift
//  Sequel Ace
//

import Cocoa

extension SPWindowController {
    func showLightweightError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        runLightweightModalAlert(alert)
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

    func currentLightweightSidebarWidth() -> CGFloat? {
        guard lightweightContentSplitView.superview != nil,
              let sidebarView = lightweightContentSplitView.subviews.first else {
            return nil
        }

        return sanitizedLightweightSidebarWidth(sidebarView.frame.width, in: lightweightContentSplitView.bounds.width)
    }

    func currentLightweightTablesPaneHeight() -> CGFloat? {
        guard lightweightSidebarSplitView.superview != nil,
              let tablesPane = lightweightSidebarSplitView.subviews.first else {
            return nil
        }

        return sanitizedLightweightTablesPaneHeight(tablesPane.frame.height, in: lightweightSidebarSplitView.bounds.height)
    }

    func restoredLightweightSidebarWidth(from snapshot: NSDictionary?) -> CGFloat? {
        return numericSnapshotValue(snapshot?[SALightweightWindowSessionSnapshotKey.sidebarWidth])
    }

    func restoredLightweightTablesPaneHeight(from snapshot: NSDictionary?) -> CGFloat? {
        return numericSnapshotValue(snapshot?[SALightweightWindowSessionSnapshotKey.tablesPaneHeight])
    }

    func sanitizedLightweightSidebarWidth(_ width: CGFloat?, in availableWidth: CGFloat) -> CGFloat? {
        guard let width = width, width.isFinite, availableWidth.isFinite else { return nil }

        let maximumWidth = min(CGFloat(420), availableWidth - LightweightDBViewLayout.detailMinimumWidth - lightweightContentSplitView.dividerThickness)
        guard maximumWidth >= LightweightDBViewLayout.sidebarMinimumWidth else { return nil }

        let roundedWidth = width.rounded()
        guard roundedWidth >= LightweightDBViewLayout.sidebarMinimumWidth, roundedWidth <= maximumWidth else {
            return nil
        }

        return roundedWidth
    }

    func sanitizedLightweightTablesPaneHeight(_ height: CGFloat?, in availableHeight: CGFloat) -> CGFloat? {
        guard let height = height, height.isFinite, availableHeight.isFinite else { return nil }

        let maximumHeight = availableHeight - LightweightDBViewLayout.sidebarPaneMinimumHeight - lightweightSidebarSplitView.dividerThickness
        guard maximumHeight >= LightweightDBViewLayout.sidebarPaneMinimumHeight else { return nil }

        let roundedHeight = height.rounded()
        guard roundedHeight >= LightweightDBViewLayout.sidebarPaneMinimumHeight, roundedHeight <= maximumHeight else {
            return nil
        }

        return roundedHeight
    }

    func numericSnapshotValue(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(number.doubleValue)
        }

        if let double = value as? Double {
            return CGFloat(double)
        }

        if let string = value as? String, let double = Double(string) {
            return CGFloat(double)
        }

        return nil
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
    }

    static func lightweightInfoRowHeight(for font: NSFont) -> CGFloat {
        return ceil("{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: font]).height) + 1.0
    }

    func requestLightweightDatabasesIfNeeded() {
        requestLightweightDatabases(forceReload: false)
    }

    func requestLightweightDatabases(forceReload: Bool) {
        guard (forceReload || databaseListNeedsLoad), !databaseListIsLoading, let activeConnection = activeConnection else { return }

        databaseListIsLoading = true
        databaseToolbarController.showDatabaseLoadingState()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            let databases = activeConnection.databases() as? [String] ?? []

            DispatchQueue.main.async {
                self.databaseListNeedsLoad = false
                self.databaseListIsLoading = false
                self.lightweightDatabases = databases
                let selectedDatabase = self.selectedDatabase.flatMap { databases.contains($0) ? $0 : nil }
                self.databaseToolbarController.reloadDatabases(databases, selectedDatabase: selectedDatabase)
            }
        }
    }

    func selectLightweightDatabaseInToolbar(_ database: String) {
        var databases = lightweightDatabases
        if !databases.contains(where: { $0.caseInsensitiveCompare(database) == .orderedSame }) {
            databases.append(database)
            databases.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        if databases.isEmpty {
            databaseToolbarController.selectOnlyDatabase(database)
        } else {
            databaseToolbarController.reloadDatabases(databases, selectedDatabase: database)
        }
    }

    func clearLightweightDatabaseSelection(afterRemoving database: String) {
        saveCurrentLightweightViewState()
        lightweightSessionState.removeDatabase(database)
        activeLightweightDetailKey = nil
        selectedDatabase = nil
        selectedTable = nil
        lightweightDatabases.removeAll { $0.caseInsensitiveCompare(database) == .orderedSame }
        lightweightTables = []
        filteredLightweightTables = []
        lightweightTableTypes = [:]
        lightweightPinnedTables = []
        tableFilterField.stringValue = ""
        tablesListView.reloadData()
        resetLightweightTableHistory()
        resetLightweightTableInfo()
        lightweightStructureController.clearCachedTables()
        lightweightContentController.clearCachedTables()
        databaseToolbarController.reloadDatabases(lightweightDatabases, selectedDatabase: nil)
        setLightweightFallbackToolbarItemsEnabled(true)
        updateLightweightWindowTitle()
        markLightweightResumeStateChanged()
        showLightweightPlaceholder(NSLocalizedString("Choose a database to load tables.", comment: "lightweight database shell empty state"))
        databaseListNeedsLoad = true
        requestLightweightDatabases(forceReload: true)
    }

    func applyLightweightDatabaseRename(from oldDatabase: String, to newDatabase: String) {
        saveCurrentLightweightViewState()
        lightweightSessionState.renameDatabase(from: oldDatabase, to: newDatabase)
        activeLightweightDetailKey = nil
        selectedDatabase = newDatabase
        selectedTable = nil
        lightweightDatabases = lightweightDatabases.map { database in
            database.caseInsensitiveCompare(oldDatabase) == .orderedSame ? newDatabase : database
        }
        selectLightweightDatabaseInToolbar(newDatabase)
        markLightweightResumeStateChanged()
        databaseListNeedsLoad = true
        requestLightweightDatabases(forceReload: true)
        loadTables(for: newDatabase)
    }

    func postLightweightDatabaseCreatedRemovedRenamedNotification() {
        NotificationCenter.default.post(name: .SPDatabaseCreatedRemovedRenamed, object: nil)
    }

    func setLightweightFallbackToolbarItemsEnabled(_ enabled: Bool) {
        databaseToolbarController.setFallbackItemsEnabled(enabled,
                                                          databaseSelected: selectedDatabase?.isEmpty == false,
                                                          tableSelected: selectedTable != nil)
        updateLightweightHistoryToolbarState()
    }

    func markLightweightResumeStateChanged() {
        guard hasActiveLightweightConnection else { return }

        NotificationCenter.default.post(name: .lightweightResumeStateDidChange, object: self)
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

    func loadLightweightTableObjects(for database: String, connection: SPMySQLConnection) -> [(name: String, type: SALightweightTableObjectType)] {
        var objects: [(name: String, type: SALightweightTableObjectType)] = []

        if let result = connection.queryString("SHOW FULL TABLES FROM \(Self.backtickQuoted(database))") {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = row.first { key, _ in
                    let keyString = String(describing: key).lowercased()
                    return keyString != "table_type"
                }.map { stringValue($0.value) } ?? ""
                let tableType = row.first { key, _ in
                    String(describing: key).lowercased() == "table_type"
                }.map { stringValue($0.value).uppercased() } ?? ""

                guard !name.isEmpty else { continue }
                objects.append((name: name, type: tableType == "VIEW" ? .view : .table))
            }
        }

        if let quotedDatabase = connection.escapeAndQuoteString(database),
           let result = connection.queryString("SELECT ROUTINE_NAME, ROUTINE_TYPE FROM information_schema.routines WHERE routine_schema = \(quotedDatabase) ORDER BY routine_name") {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = stringValue(row["ROUTINE_NAME"] ?? row["routine_name"])
                let routineType = stringValue(row["ROUTINE_TYPE"] ?? row["routine_type"]).uppercased()
                guard !name.isEmpty else { continue }
                objects.append((name: name, type: routineType == "PROCEDURE" ? .procedure : .function))
            }
        }

        return objects
    }

    func orderLightweightTables(_ tables: [String], pinnedTables: Set<String>) -> [String] {
        guard !pinnedTables.isEmpty else { return tables }

        let pinned = tables.filter { pinnedTables.contains($0) }
        let unpinned = tables.filter { !pinnedTables.contains($0) }
        return pinned + unpinned
    }

    func loadLightweightPinnedTables(for database: String, connection: SPMySQLConnection) -> Set<String> {
        let connectionIdentifier = lightweightPinnedTableConnectionIdentifier(connection: connection)
        let legacyHost = connection.host ?? ""
        SQLitePinnedTableManager.sharedInstance.migratePinnedTablesFromLegacyHost(legacyHost,
                                                                                  toConnectionIdentifier: connectionIdentifier,
                                                                                  databaseName: database)
        return Set(SQLitePinnedTableManager.sharedInstance.getPinnedTables(hostName: connectionIdentifier, databaseName: database))
    }

    func lightweightPinnedTableConnectionIdentifier(connection: SPMySQLConnection) -> String {
        if let keychainID = activeConnectionInfo?.connectionKeychainID, !keychainID.isEmpty, keychainID != "_" {
            return keychainID
        }

        if connection.useSocket {
            return connection.socketPath ?? ""
        }

        return connection.host ?? ""
    }

    func pinLightweightTable(_ table: String, database: String) {
        guard let activeConnection = activeConnection else { return }

        SQLitePinnedTableManager.sharedInstance.pinTable(hostName: lightweightPinnedTableConnectionIdentifier(connection: activeConnection),
                                                         databaseName: database,
                                                         tableToPin: table)
    }

    func unpinLightweightTable(_ table: String, database: String) {
        guard let activeConnection = activeConnection else { return }

        SQLitePinnedTableManager.sharedInstance.unpinTable(hostName: lightweightPinnedTableConnectionIdentifier(connection: activeConnection),
                                                           databaseName: database,
                                                           tableToUnpin: table)
    }

    func handleLightweightPinnedTableRename(from oldName: String, to newName: String) {
        guard let selectedDatabase = selectedDatabase, lightweightPinnedTables.contains(oldName) else { return }

        unpinLightweightTable(oldName, database: selectedDatabase)
        pinLightweightTable(newName, database: selectedDatabase)
    }

    func applyPendingLightweightSessionSnapshot() {
        guard let snapshot = pendingLightweightSessionSnapshot else { return }

        pendingLightweightSessionSnapshot = nil
        lightweightSessionState.load(from: snapshot[SALightweightWindowSessionSnapshotKey.state] as? NSDictionary)

        tableFilterField.stringValue = snapshot[SALightweightWindowSessionSnapshotKey.tableFilter] as? String ?? ""
        lightweightHistoryBackStack = snapshot[SALightweightWindowSessionSnapshotKey.historyBackStack] as? [String] ?? []
        lightweightHistoryForwardStack = snapshot[SALightweightWindowSessionSnapshotKey.historyForwardStack] as? [String] ?? []
        updateLightweightHistoryToolbarState()

        let restoredDatabase = snapshot[SALightweightWindowSessionSnapshotKey.selectedDatabase] as? String
        let restoredTable = snapshot[SALightweightWindowSessionSnapshotKey.selectedTable] as? String
        let restoredViewMode = (snapshot[SALightweightWindowSessionSnapshotKey.viewMode] as? NSNumber)
            .flatMap { SAViewMode(rawValue: $0.intValue) }
            ?? (snapshot[SALightweightWindowSessionSnapshotKey.viewMode] as? Int).flatMap { SAViewMode(rawValue: $0) }
            ?? .structure

        activeLightweightViewMode = restoredViewMode

        guard let database = restoredDatabase ?? selectedDatabase else {
            showLightweightPlaceholder(NSLocalizedString("Choose a database to load tables.", comment: "lightweight database shell empty state"))
            return
        }

        selectedDatabase = database
        selectLightweightDatabaseInToolbar(database)
        loadTables(for: database, restoringTable: restoredTable, restoringViewMode: restoredViewMode)
    }

    func loadTables(for database: String, preservingSelection: Bool = false, restoringTable: String? = nil, restoringViewMode: SAViewMode? = nil) {
        guard let activeConnection = activeConnection else { return }

        saveCurrentLightweightViewState()

        let tableToRestore = restoringTable ?? (preservingSelection ? selectedTable : nil)
        if selectedDatabase != database {
            resetLightweightTableHistory()
        }
        selectedDatabase = database
        selectedTable = nil
        setLightweightFallbackToolbarItemsEnabled(true)
        resetLightweightTableInfo()
        showLightweightPlaceholder(NSLocalizedString("Loading tables...", comment: "lightweight database shell loading tables"))
        lightweightTables = []
        filteredLightweightTables = []
        lightweightTableTypes = [:]
        lightweightPinnedTables = []
        tablesListView.reloadData()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }
            _ = activeConnection.selectDatabase(database)
            let loadedObjects = self.loadLightweightTableObjects(for: database, connection: activeConnection)
            let pinnedTables = self.loadLightweightPinnedTables(for: database, connection: activeConnection)
            var uniqueTables: [String] = []
            var types: [String: SALightweightTableObjectType] = [:]
            for object in loadedObjects where types[object.name] == nil {
                uniqueTables.append(object.name)
                types[object.name] = object.type
            }
            let tables = self.orderLightweightTables(uniqueTables, pinnedTables: pinnedTables)

            DispatchQueue.main.async {
                self.selectedDatabase = database
                self.updateLightweightWindowTitle()
                self.lightweightTables = tables
                self.lightweightTableTypes = types
                self.lightweightPinnedTables = pinnedTables
                self.applyLightweightTableFilter()
                self.tablesListView.reloadData()
                if let tableToRestore = tableToRestore, tables.contains(tableToRestore) {
                    if let restoringViewMode = restoringViewMode {
                        self.activeLightweightViewMode = restoringViewMode
                    }
                    self.selectLightweightTableInSidebar(tableToRestore)
                    self.selectLightweightTable(tableToRestore, recordsHistory: false)
                    return
                }
                if let restoringViewMode = restoringViewMode, restoringViewMode == .query {
                    self.activeLightweightViewMode = restoringViewMode
                    self.showLightweightQuery()
                    return
                }
                self.showLightweightPlaceholder(tables.isEmpty
                    ? NSLocalizedString("No tables in this database.", comment: "lightweight database shell no tables")
                    : NSLocalizedString("Select a table or choose a toolbar section.", comment: "lightweight database shell table loaded empty state"))
            }
        }
    }

    func selectLightweightTable(_ table: String, recordsHistory: Bool = true) {
        let tableChanged = selectedTable != table
        if tableChanged {
            saveCurrentLightweightViewState()
        }
        selectedTable = table
        setLightweightFallbackToolbarItemsEnabled(true)
        markLightweightResumeStateChanged()
        if recordsHistory {
            recordLightweightHistorySelection(table)
        }
        updateLightweightWindowTitle(table: table)
        if tableChanged {
            loadLightweightTableInfo(for: table)
        }

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
        lightweightStatusLabel.stringValue = message
        lightweightStatusLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        let placeholderKey = LightweightDetailKey(viewMode: nil, database: selectedDatabase, table: selectedTable, placeholder: message)
        _ = installLightweightDetailSubview(lightweightStatusLabel, key: placeholderKey)
        lightweightStatusLabel.frame = NSRect(x: 20, y: max(0, (lightweightDetailView.bounds.height - 60) / 2), width: max(0, lightweightDetailView.bounds.width - 40), height: 60)
    }

    func showLightweightStructure(for table: String) {
        guard let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else { return }

        activeLightweightViewMode = .structure
        databaseToolbarController.selectViewMode(.structure)

        let structureView = lightweightStructureController.view
        let detailChanged = installLightweightDetailSubview(structureView, key: LightweightDetailKey(viewMode: .structure, database: selectedDatabase, table: table, placeholder: nil))
        lightweightStructureController.tableStructureDidChange = { [weak self] in
            self?.lightweightContentController.clearCachedTables()
            self?.refreshLightweightTableInfoAfterMutation()
        }
        lightweightStructureController.requestTableInfoView = { [weak self] in
            self?.viewStatus()
        }
        guard detailChanged else { return }
        lightweightStructureController.loadStructure(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func showLightweightContent(for table: String) {
        guard let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else { return }

        activeLightweightViewMode = .content
        databaseToolbarController.selectViewMode(.content)

        let contentView = lightweightContentController.view
        let detailChanged = installLightweightDetailSubview(contentView, key: LightweightDetailKey(viewMode: .content, database: selectedDatabase, table: table, placeholder: nil))
        lightweightContentController.tableContentDidChange = { [weak self] in
            self?.refreshLightweightTableInfoAfterMutation()
            self?.markLightweightResumeStateChanged()
        }
        if let columnMetadata = lightweightStructureController.cachedColumnMetadata(for: table, database: selectedDatabase) {
            lightweightContentController.cacheColumnInfo(fromStructureRows: columnMetadata, for: table, database: selectedDatabase, connection: activeConnection)
        }
        guard detailChanged else { return }
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

        let queryView = lightweightQueryController.view
        _ = installLightweightDetailSubview(queryView, key: LightweightDetailKey(viewMode: .query, database: selectedDatabase, table: selectedTable, placeholder: nil))
        lightweightQueryController.loadQuery(database: selectedDatabase, table: selectedTable, connection: activeConnection)
    }

    func showLightweightStatus(for table: String?) {
        activeLightweightViewMode = .status
        databaseToolbarController.selectViewMode(.status)

        let tableInfoView = lightweightTableInfoController.view
        let detailChanged = installLightweightDetailSubview(tableInfoView, key: LightweightDetailKey(viewMode: .status, database: selectedDatabase, table: table, placeholder: nil))

        guard let table = table, let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else {
            lightweightTableInfoController.showPlaceholder(NSLocalizedString("Select a table to view table information.", comment: "lightweight table info empty state"))
            return
        }

        guard detailChanged else { return }
        lightweightTableInfoController.loadTableInfo(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func showLightweightRelations(for table: String?) {
        activeLightweightViewMode = .relations
        databaseToolbarController.selectViewMode(.relations)

        let relationsView = lightweightRelationsController.view
        let detailChanged = installLightweightDetailSubview(relationsView, key: LightweightDetailKey(viewMode: .relations, database: selectedDatabase, table: table, placeholder: nil))
        lightweightRelationsController.requestLegacyRelationsFallback = { [weak self] in
            guard let self = self else { return }
            self.installLegacyDatabaseDocumentIfNeeded(selectingDatabase: self.selectedDatabase, item: self.selectedTable).viewRelations()
        }

        guard let table = table, let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else {
            lightweightRelationsController.showPlaceholder(NSLocalizedString("Select a table to view relations.", comment: "lightweight relations empty state"))
            return
        }

        guard detailChanged else { return }
        lightweightRelationsController.loadRelations(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func showLightweightTriggers(for table: String?) {
        activeLightweightViewMode = .triggers
        databaseToolbarController.selectViewMode(.triggers)

        let triggersView = lightweightTriggersController.view
        let detailChanged = installLightweightDetailSubview(triggersView, key: LightweightDetailKey(viewMode: .triggers, database: selectedDatabase, table: table, placeholder: nil))

        guard let table = table, let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else {
            lightweightTriggersController.showPlaceholder(NSLocalizedString("Select a table to view triggers.", comment: "lightweight triggers empty state"))
            return
        }

        guard detailChanged else { return }
        lightweightTriggersController.loadTriggers(for: table, database: selectedDatabase, connection: activeConnection)
    }
}
