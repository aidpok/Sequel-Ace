//
//  SPWindowController+LightweightSidebar.swift
//  Sequel Ace
//

import Cocoa

enum SALightweightSidebarRow {
    case group(String)
    case object(String)

    var tableName: String? {
        if case .object(let table) = self {
            return table
        }

        return nil
    }
}

extension SPWindowController {
    func preferredLightweightViewModeFromPreferences() -> SAViewMode {
        let preferredValue = UserDefaults.standard.integer(forKey: SPDefaultViewMode)
        if preferredValue > 0 {
            return SAViewMode.fromPreferences(preferredValue)
        }

        return SAViewMode.fromPreferences(UserDefaults.standard.integer(forKey: SPLastViewMode))
    }

    func setActiveLightweightViewMode(_ mode: SAViewMode, persist: Bool = true) {
        activeLightweightViewMode = mode
        if persist {
            UserDefaults.standard.set(mode.preferencesValue, forKey: SPLastViewMode)
        }
    }

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

    func ensureLightweightTableListAllowsMultipleSelection() {
        if !tablesListView.allowsMultipleSelection {
            tablesListView.allowsMultipleSelection = true
        }
    }

    @objc func selectedLightweightTableItems() -> [String] {
        guard hasActiveLightweightConnection else { return [] }

        let selectedRows = tablesListView.selectedRowIndexes
        var selectedTables: [String] = []
        for row in selectedRows {
            guard let table = lightweightTableName(atSidebarRow: row), !selectedTables.contains(table) else { continue }
            selectedTables.append(table)
        }

        return selectedTables
    }

    @objc var selectedLightweightTableCount: Int {
        return selectedLightweightTableItems().count
    }

    @objc var selectedLightweightTableSelectionObjectType: Int {
        let types = selectedLightweightTableTypes()
        guard let firstType = types.first, types.allSatisfy({ $0 == firstType }) else {
            return SALightweightTableObjectType.none.rawValue
        }

        return firstType.rawValue
    }

    @objc var selectedLightweightTableSelectionHasOnlyTables: Bool {
        let types = selectedLightweightTableTypes()
        return !types.isEmpty && types.allSatisfy { $0 == .table }
    }

    @objc var selectedLightweightTableSelectionHasOnlyTablesOrViews: Bool {
        let types = selectedLightweightTableTypes()
        return !types.isEmpty && types.allSatisfy { $0 == .table || $0 == .view }
    }

    func selectedLightweightTableTypes() -> [SALightweightTableObjectType] {
        return selectedLightweightTableItems().map { lightweightTableTypes[$0] ?? .table }
    }

    func primarySelectedLightweightTable() -> String? {
        let clickedRow = tablesListView.clickedRow
        if clickedRow >= 0,
           tablesListView.selectedRowIndexes.contains(clickedRow),
           let table = lightweightTableName(atSidebarRow: clickedRow) {
            return table
        }

        let selectedRow = tablesListView.selectedRow
        if selectedRow >= 0, let table = lightweightTableName(atSidebarRow: selectedRow) {
            return table
        }

        return selectedLightweightTableItems().first
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
        UserDefaults.standard.addObserver(self, forKeyPath: SPDisplayServerVersionInWindowTitle, options: .new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: SPDisplayCommentsInTablesList, options: .new, context: nil)
        didRegisterLightweightPreferenceObservers = true
    }

    func applyLightweightSidebarFontPreference() {
        let tableFont = UserDefaults.getFont()
        tablesListView.rowHeight = 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: tableFont]).height
        lightweightTableInfoView.font = tableFont
        lightweightTableInfoView.rowHeight = Self.lightweightInfoRowHeight(for: tableFont)

        for column in tablesListView.tableColumns {
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
        updateLightweightSidebarActionMenuState()
        lightweightDatabases.removeAll { $0.caseInsensitiveCompare(database) == .orderedSame }
        lightweightTables = []
        filteredLightweightTables = []
        lightweightTableTypes = [:]
        lightweightTableComments = [:]
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
        updateLightweightSidebarActionMenuState()
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
        let connectionName = activeConnectionName?.isEmpty == false
            ? activeConnectionName!
            : NSLocalizedString("Connected", comment: "lightweight connected tab title")
        let result = SAWindowTitleBuilder.buildTitle(
            connectionState: .connected,
            filePath: lightweightConnectionFileURL?.path,
            isUntitled: lightweightConnectionFileURL == nil,
            bundleName: Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ?? NSLocalizedString("Sequel Ace", comment: "default connection tab title"),
            connectionName: connectionName,
            database: selectedDatabase,
            table: table ?? selectedTable,
            mySQLVersion: activeServerVersion,
            showServerVersionInTitle: UserDefaults.standard.bool(forKey: SPDisplayServerVersionInWindowTitle)
        )

        updateWindow(title: result.windowTitle, tabTitle: result.tabTitle)
    }

    func applyLightweightTableFilter() {
        let filter = tableFilterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !filter.isEmpty else {
            filteredLightweightTables = lightweightTables
            restoreLightweightSidebarSelectionIfPossible()
            return
        }

        filteredLightweightTables = lightweightTables.filter { table in
            table.range(of: filter, options: .caseInsensitive) != nil
        }
        restoreLightweightSidebarSelectionIfPossible()
    }

    func restoreLightweightSidebarSelectionIfPossible() {
        guard let selectedTable = selectedTable,
              let row = lightweightSidebarRowIndex(for: selectedTable) else { return }

        isRestoringLightweightHistory = true
        tablesListView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isRestoringLightweightHistory = false
    }

    func lightweightSidebarRows() -> [SALightweightSidebarRow] {
        let tableHeader = lightweightTableTypes.values.contains(.view)
            ? NSLocalizedString("TABLES & VIEWS", comment: "header for table & views list")
            : NSLocalizedString("TABLES", comment: "header for table list")
        var rows: [SALightweightSidebarRow] = []

        let pinnedTables = lightweightTables.filter { lightweightPinnedTables.contains($0) }
        if !pinnedTables.isEmpty {
            rows.append(.group(NSLocalizedString("PINNED", comment: "header for pinned tables")))
            rows.append(contentsOf: pinnedTables.map { .object($0) })
        }

        let tableRows = filteredLightweightTables.filter { table in
            let type = lightweightTableTypes[table] ?? .table
            return type == .table || type == .view
        }
        if !tableRows.isEmpty || lightweightTables.isEmpty {
            rows.append(.group(tableHeader))
            rows.append(contentsOf: tableRows.map { .object($0) })
        }

        let routineRows = filteredLightweightTables.filter { table in
            let type = lightweightTableTypes[table] ?? .table
            return type == .procedure || type == .function
        }
        if !routineRows.isEmpty {
            rows.append(.group(NSLocalizedString("PROCS & FUNCS", comment: "header for procs & funcs list")))
            rows.append(contentsOf: routineRows.map { .object($0) })
        }

        if rows.isEmpty {
            rows.append(.group(NSLocalizedString("NO MATCHES", comment: "header for no matches in filtered list")))
        }

        if let selectedTable = selectedTable,
           lightweightTables.contains(selectedTable),
           !rows.contains(where: { $0.tableName == selectedTable }) {
            rows.append(.group(NSLocalizedString("CURRENT SELECTION", comment: "header for current selection in filtered list")))
            rows.append(.object(selectedTable))
        }

        return rows
    }

    func lightweightSidebarRow(at row: Int) -> SALightweightSidebarRow? {
        let rows = lightweightSidebarRows()
        guard rows.indices.contains(row) else { return nil }
        return rows[row]
    }

    func lightweightTableName(atSidebarRow row: Int) -> String? {
        return lightweightSidebarRow(at: row)?.tableName
    }

    func lightweightSidebarRowIndex(for table: String) -> Int? {
        return lightweightSidebarRows().firstIndex { $0.tableName == table }
    }

    func loadLightweightTableObjects(for database: String, connection: SPMySQLConnection) -> [(name: String, type: SALightweightTableObjectType, comment: String?)] {
        var objects: [(name: String, type: SALightweightTableObjectType, comment: String?)] = []
        let shouldLoadComments = UserDefaults.standard.bool(forKey: SPDisplayCommentsInTablesList)
        let tableQuery = shouldLoadComments
            ? "SHOW TABLE STATUS FROM \(Self.backtickQuoted(database))"
            : "SHOW FULL TABLES FROM \(Self.backtickQuoted(database))"

        if let result = connection.queryString(tableQuery) {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = lightweightTableName(from: row)
                let tableType = row.first { key, _ in
                    String(describing: key).lowercased() == "table_type"
                }.map { stringValue($0.value).uppercased() } ?? ""
                let tableComment = shouldLoadComments ? lightweightRowString(row["Comment"] ?? row["COMMENT"] ?? row["comment"]) : nil

                guard !name.isEmpty else { continue }
                objects.append((name: name, type: tableType == "VIEW" || tableComment?.uppercased() == "VIEW" ? .view : .table, comment: tableComment))
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
                objects.append((name: name, type: routineType == "PROCEDURE" ? .procedure : .function, comment: nil))
            }
        }

        return objects
    }

    func updateLightweightTableCommentsForPreferenceChange() {
        lightweightTableComments = [:]

        guard UserDefaults.standard.bool(forKey: SPDisplayCommentsInTablesList),
              hasActiveLightweightConnection,
              let selectedDatabase = selectedDatabase,
              let activeConnection = activeConnection else {
            tablesListView.reloadData()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }
            let comments = self.loadLightweightTableComments(for: selectedDatabase, connection: activeConnection)

            DispatchQueue.main.async {
                guard self.selectedDatabase == selectedDatabase else { return }
                self.lightweightTableComments = comments
                self.tablesListView.reloadData()
            }
        }
    }

    func loadLightweightTableComments(for database: String, connection: SPMySQLConnection) -> [String: String] {
        var comments: [String: String] = [:]

        guard let result = connection.queryString("SHOW TABLE STATUS FROM \(Self.backtickQuoted(database))") else { return comments }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        while let row = result.getRowAsDictionary() as? [String: Any] {
            let name = lightweightTableName(from: row)
            guard !name.isEmpty else { continue }
            comments[name] = lightweightRowString(row["Comment"] ?? row["COMMENT"] ?? row["comment"])
        }

        return comments
    }

    private func lightweightTableName(from row: [String: Any]) -> String {
        let explicitName = lightweightRowString(row["Name"] ?? row["NAME"] ?? row["name"])
        if !explicitName.isEmpty {
            return explicitName
        }

        return row.first { key, _ in
            let keyString = String(describing: key).lowercased()
            return keyString != "table_type"
        }.map { lightweightRowString($0.value) } ?? ""
    }

    private func lightweightRowString(_ value: Any?) -> String {
        guard let value = value, !(value is NSNull) else { return "" }
        return stringValue(value)
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

        setActiveLightweightViewMode(restoredViewMode, persist: false)

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

        ensureLightweightTableListAllowsMultipleSelection()
        saveCurrentLightweightViewState()

        let tableToRestore = restoringTable ?? (preservingSelection ? selectedTable : nil)
        if selectedDatabase != database {
            resetLightweightTableHistory()
        }
        selectedDatabase = database
        selectedTable = nil
        updateLightweightSidebarActionMenuState()
        setLightweightFallbackToolbarItemsEnabled(true)
        resetLightweightTableInfo()
        showLightweightPlaceholder(NSLocalizedString("Loading tables...", comment: "lightweight database shell loading tables"))
        lightweightTables = []
        filteredLightweightTables = []
        lightweightTableTypes = [:]
        lightweightTableComments = [:]
        lightweightPinnedTables = []
        tablesListView.reloadData()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }
            _ = activeConnection.selectDatabase(database)
            let loadedObjects = self.loadLightweightTableObjects(for: database, connection: activeConnection)
            let pinnedTables = self.loadLightweightPinnedTables(for: database, connection: activeConnection)
            var uniqueTables: [String] = []
            var types: [String: SALightweightTableObjectType] = [:]
            var comments: [String: String] = [:]
            for object in loadedObjects where types[object.name] == nil {
                uniqueTables.append(object.name)
                types[object.name] = object.type
                if let comment = object.comment {
                    comments[object.name] = comment
                }
            }
            let tables = self.orderLightweightTables(uniqueTables, pinnedTables: pinnedTables)

            DispatchQueue.main.async {
                self.selectedDatabase = database
                self.updateLightweightWindowTitle()
                self.lightweightTables = tables
                self.lightweightTableTypes = types
                self.lightweightTableComments = comments
                self.lightweightPinnedTables = pinnedTables
                self.applyLightweightTableFilter()
                self.tablesListView.reloadData()
                if let tableToRestore = tableToRestore, tables.contains(tableToRestore) {
                    if let restoringViewMode = restoringViewMode {
                        self.setActiveLightweightViewMode(restoringViewMode, persist: false)
                    }
                    self.selectLightweightTableInSidebar(tableToRestore)
                    self.selectLightweightTable(tableToRestore, recordsHistory: false)
                    return
                }
                if let restoringViewMode = restoringViewMode, restoringViewMode == .query {
                    self.setActiveLightweightViewMode(restoringViewMode, persist: false)
                    self.showLightweightQuery()
                    return
                }
                if self.activeLightweightViewMode == .query {
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
        updateLightweightSidebarActionMenuState()
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

    @objc func canNavigateLightweightHistoryBack() -> Bool {
        guard hasActiveLightweightConnection else { return false }
        return lightweightHistoryBackStack.count > 1
    }

    @objc func canNavigateLightweightHistoryForward() -> Bool {
        guard hasActiveLightweightConnection else { return false }
        return !lightweightHistoryForwardStack.isEmpty
    }

    @objc func canNavigateLightweightHistory(_ sender: Any?) -> Bool {
        let tag: Int
        if let menuItem = sender as? NSMenuItem {
            tag = menuItem.tag
        } else if let control = sender as? NSSegmentedControl {
            tag = control.selectedSegment
        } else {
            tag = 0
        }

        switch tag {
        case 0:
            return canNavigateLightweightHistoryBack()
        case 1:
            return canNavigateLightweightHistoryForward()
        default:
            return false
        }
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
        ensureLightweightTableListAllowsMultipleSelection()
        if !filteredLightweightTables.contains(table) {
            tableFilterField.stringValue = ""
            applyLightweightTableFilter()
            tablesListView.reloadData()
        }

        guard let index = lightweightSidebarRowIndex(for: table) else { return }
        isRestoringLightweightHistory = true
        tablesListView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tablesListView.scrollRowToVisible(index)
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
        lightweightPlaceholderView.message = message
        let placeholderKey = LightweightDetailKey(viewMode: nil, database: selectedDatabase, table: selectedTable, placeholder: message)
        _ = installLightweightDetailSubview(lightweightPlaceholderView, key: placeholderKey)
    }

    func showLightweightStructure(for table: String) {
        guard let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else { return }

        setActiveLightweightViewMode(.structure)
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

        setActiveLightweightViewMode(.content)
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
        lightweightContentController.setContentFilterDocumentURL(lightweightQueryController.ensureDocumentURLForLegacyQueryConsumers())
        guard detailChanged else { return }
        lightweightContentController.loadContent(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func refreshLightweightTableInfoAfterMutation() {
        guard let selectedTable = selectedTable else { return }

        loadLightweightTableInfo(for: selectedTable)
    }

    func showLightweightQuery() {
        guard let activeConnection = activeConnection else { return }

        setActiveLightweightViewMode(.query)
        databaseToolbarController.selectViewMode(.query)

        let queryView = lightweightQueryController.view
        _ = installLightweightDetailSubview(queryView, key: LightweightDetailKey(viewMode: .query, database: selectedDatabase, table: selectedTable, placeholder: nil))
        let fieldNames = selectedDatabase.flatMap { database in
            selectedTable.flatMap { table in
                lightweightStructureController.cachedColumnMetadata(for: table, database: database)
            }
        }?.compactMap { $0["name"] } ?? []
        lightweightQueryController.loadQuery(database: selectedDatabase,
                                             table: selectedTable,
                                             connection: activeConnection,
                                             databases: lightweightDatabases,
                                             tables: lightweightTables,
                                             tableTypes: lightweightTableTypes,
                                             fieldNames: fieldNames)
        lightweightQueryController.focusEditor()
    }

    func showLightweightStatus(for table: String?) {
        setActiveLightweightViewMode(.status)
        databaseToolbarController.selectViewMode(.status)

        let tableInfoView = lightweightTableInfoController.view
        let detailChanged = installLightweightDetailSubview(tableInfoView, key: LightweightDetailKey(viewMode: .status, database: selectedDatabase, table: table, placeholder: nil))
        lightweightTableInfoController.tableInfoDidChange = { [weak self] in
            self?.refreshLightweightTableInfoAfterMutation()
            self?.updateLightweightTableCommentsForPreferenceChange()
            self?.markLightweightResumeStateChanged()
        }

        guard let table = table, let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else {
            lightweightTableInfoController.showPlaceholder(NSLocalizedString("Select a table to view table information.", comment: "lightweight table info empty state"))
            return
        }

        guard detailChanged else { return }
        lightweightTableInfoController.loadTableInfo(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func showLightweightRelations(for table: String?) {
        setActiveLightweightViewMode(.relations)
        databaseToolbarController.selectViewMode(.relations)

        let relationsView = lightweightRelationsController.view
        let detailChanged = installLightweightDetailSubview(relationsView, key: LightweightDetailKey(viewMode: .relations, database: selectedDatabase, table: table, placeholder: nil))

        guard let table = table, let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else {
            lightweightRelationsController.showPlaceholder(NSLocalizedString("Select a table to view relations.", comment: "lightweight relations empty state"))
            return
        }

        guard detailChanged else { return }
        lightweightRelationsController.loadRelations(for: table, database: selectedDatabase, connection: activeConnection)
    }

    func showLightweightTriggers(for table: String?) {
        setActiveLightweightViewMode(.triggers)
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
