//
//  SPWindowController+LightweightDelegates.swift
//  Sequel Ace
//

import Cocoa

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
        connection.setDelegate(lightweightConsoleLogger)
        connection.delegateQueryLogging = true
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

extension SPWindowController: SPUserManagerDatabaseProviding {
    @objc func userManagerDatabaseNames() -> [Any] {
        if let document = loadedDatabaseDocument {
            return document.allDatabaseNames() as? [Any] ?? []
        }

        if !lightweightDatabases.isEmpty {
            return lightweightDatabases
        }

        return activeConnection?.databases() as? [Any] ?? []
    }
}

extension SPWindowController: SAConnectionDelegate {
    @objc func connectionDidEstablish(_ connection: SPMySQLConnection, info: SAConnectionInfoObjC) {
        activeConnection = connection
        connection.setDelegate(lightweightConsoleLogger)
        connection.delegateQueryLogging = true
        activeConnectionInfo = info
        activeConnectionName = info.name
        activeServerVersion = connection.serverVersionString()
        selectedDatabase = info.database.isEmpty ? nil : info.database
        selectedTable = nil
        databaseListNeedsLoad = true

        applyLightweightDefaultEncodingPreference()
        updateLightweightWindowTitle()
        updateWindowAccessory(color: SPFavoriteColorSupport.sharedInstance().color(for: info.colorIndex),
                              isSSL: connection.isConnectedViaSSL())
        installLightweightDatabaseShell()
        setLightweightFallbackToolbarItemsEnabled(true)
        requestLightweightDatabasesIfNeeded()
        markLightweightResumeStateChanged()

        if pendingLightweightSessionSnapshot != nil {
            applyPendingLightweightSessionSnapshot()
            return
        }

        if let selectedDatabase = selectedDatabase {
            selectLightweightDatabaseInToolbar(selectedDatabase)
            loadTables(for: selectedDatabase)
        }
    }

    @objc func connectionDidFail(withError error: String, detail: String?) {
        showLightweightPlaceholder(error)
    }
}

extension SPWindowController {
    enum LightweightSQLImportErrorChoice {
        case `continue`
        case ignoreAll
        case stop
    }

    enum LightweightImportRouteChoice {
        case lightweight
        case legacy
        case cancel
    }

    func isLightweightConnectionBusyForImport() -> Bool {
        return isLightweightImportRunning || processing || databaseListIsLoading
    }

    func showLightweightImportUnavailableReason() {
        NSSound.beep()
        if isLightweightConnectionBusyForImport() {
            showLightweightError(title: NSLocalizedString("Import Unavailable", comment: "lightweight import unavailable title"),
                                 message: NSLocalizedString("Wait for the current lightweight import, export, or connection task to finish before importing.", comment: "lightweight import busy message"))
            return
        }

        showLightweightError(title: NSLocalizedString("Import Unavailable", comment: "lightweight import unavailable title"),
                             message: NSLocalizedString("Select a database in the active lightweight connection before importing SQL.", comment: "lightweight import unavailable message"))
    }

    func lightweightImportRouteChoice() -> LightweightImportRouteChoice {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Import", comment: "import title")
        alert.informativeText = NSLocalizedString("Lightweight import supports small SQL files only. Choose the full database view for CSV, compressed files, large SQL dumps, or SQL that changes SQL_MODE while importing.", comment: "lightweight import route choice message")
        alert.addButton(withTitle: NSLocalizedString("Choose SQL File", comment: "lightweight import choose sql file button"))
        alert.addButton(withTitle: NSLocalizedString("Use Full Database View", comment: "lightweight import full database view button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        switch runLightweightModalAlert(alert) {
        case .alertFirstButtonReturn:
            return .lightweight
        case .alertSecondButtonReturn:
            return .legacy
        default:
            return .cancel
        }
    }

    func startLegacyFileImportFlow() {
        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).importFile()
    }

    func confirmLightweightSQLImport(sourceName: String) -> Bool {
        guard let selectedDatabase = selectedDatabase else { return false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Import SQL", comment: "lightweight SQL import confirmation title")
        let limitation = NSLocalizedString("Lightweight import pre-splits SQL before execution, so dumps that change SQL_MODE/NO_BACKSLASH_ESCAPES during import should use the full database view.", comment: "lightweight SQL import limitation warning")
        if lightweightTables.isEmpty {
            alert.informativeText = String(format: NSLocalizedString("Import %@ into database “%@”?", comment: "lightweight SQL import confirmation message"), sourceName, selectedDatabase) + "\n\n" + limitation
        } else {
            alert.informativeText = String(format: NSLocalizedString("Import %@ into database “%@”? The current database already has tables, so the import may overwrite data.", comment: "lightweight SQL import overwrite warning"), sourceName, selectedDatabase) + "\n\n" + limitation
        }
        alert.addButton(withTitle: NSLocalizedString("Import", comment: "import button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        return runLightweightModalAlert(alert) == .alertFirstButtonReturn
    }

    func validateLightweightSQLImportFileSize(url: URL) -> Bool {
        let fileSize: Int64
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            fileSize = Int64(values.fileSize ?? 0)
        } catch {
            NSSound.beep()
            showLightweightError(title: NSLocalizedString("Import Error", comment: "Import Error title"),
                                 message: NSLocalizedString("The SQL file you selected could not be inspected.", comment: "lightweight SQL import file inspection error"))
            return false
        }

        guard fileSize <= SALightweightSQLImportMaximumInMemoryFileSize else {
            NSSound.beep()
            let maximumSize = ByteCountFormatter.string(fromByteCount: SALightweightSQLImportMaximumInMemoryFileSize, countStyle: .file)
            let selectedSize = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = NSLocalizedString("Import Requires Full Database View", comment: "lightweight SQL import size gate title")
            alert.informativeText = String(format: NSLocalizedString("This lightweight import path currently supports SQL files up to %@. The selected file is %@. Large SQL files require the full database view, which uses the legacy streaming importer.", comment: "lightweight SQL import size gate message"), maximumSize, selectedSize)
            alert.addButton(withTitle: NSLocalizedString("Use Full Database View", comment: "lightweight import full database view button"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
            if runLightweightModalAlert(alert) == .alertFirstButtonReturn {
                startLegacyFileImportFlow()
            }
            return false
        }

        return true
    }

    func startLightweightSQLImport(url: URL, encoding: String.Encoding) {
        showLightweightPlaceholder(String(format: NSLocalizedString("Reading %@...", comment: "lightweight SQL import reading status"), url.lastPathComponent))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let sql = try String(contentsOf: url, encoding: encoding)
                DispatchQueue.main.async {
                    self?.runLightweightSQLImport(sql: sql, sourceName: url.lastPathComponent, encoding: encoding)
                }
            } catch {
                DispatchQueue.main.async {
                    NSSound.beep()
                    self?.showLightweightError(title: NSLocalizedString("File read error", comment: "File read error title (Import Dialog)"),
                                               message: String(format: NSLocalizedString("The SQL file could not be read using %@.", comment: "lightweight SQL import encoding read error"), String.localizedName(of: encoding)))
                }
            }
        }
    }

    func runLightweightSQLImport(sql: String, sourceName: String, encoding: String.Encoding) {
        guard !isLightweightConnectionBusyForImport() else {
            showLightweightImportUnavailableReason()
            return
        }

        guard let connection = activeConnection, let database = selectedDatabase else {
            showLightweightImportUnavailableReason()
            return
        }

        let queries = lightweightSQLQueries(in: sql)
        guard !queries.isEmpty else {
            NSSound.beep()
            showLightweightError(title: NSLocalizedString("Import SQL", comment: "lightweight SQL import confirmation title"),
                                 message: NSLocalizedString("No SQL statements were found to import.", comment: "lightweight SQL import no statements message"))
            return
        }

        isLightweightImportRunning = true
        processing = true
        showLightweightPlaceholder(String(format: NSLocalizedString("Importing %@...", comment: "lightweight SQL import status"), sourceName))
        setLightweightConsoleQueryMode(2)

        DispatchQueue.global(qos: .userInitiated).async { [weak self, connection] in
            guard let self = self else { return }
            let oldRetryQueries = connection.retryQueriesOnConnectionFailure
            connection.retryQueriesOnConnectionFailure = false

            var errors: [String] = []
            var queriesPerformed = 0
            var progressCancelled = false
            var ignoreSQLErrors = false
            var ignoreCharsetError = false
            var connectionEncodingToRestore: String?
            var sqlModeToRestore: String?

            defer {
                if let connectionEncodingToRestore = connectionEncodingToRestore {
                    _ = connection.queryString("SET NAMES '\(connectionEncodingToRestore)'")
                }
                if let sqlModeToRestore = sqlModeToRestore {
                    _ = connection.queryString("SET SQL_MODE=\(Self.sqlSingleQuoted(sqlModeToRestore))")
                }
                connection.retryQueriesOnConnectionFailure = oldRetryQueries

                DispatchQueue.main.async {
                    self.isLightweightImportRunning = false
                    self.processing = false
                    self.setLightweightConsoleQueryMode(0)
                    self.requestLightweightDatabases(forceReload: true)
                    self.loadTables(for: database, preservingSelection: true)

                    if errors.isEmpty {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("Import Complete", comment: "lightweight SQL import complete title")
                        alert.informativeText = String(format: NSLocalizedString("Imported %ld SQL statements from %@.", comment: "lightweight SQL import complete message"), queriesPerformed, sourceName)
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
                        _ = self.runLightweightModalAlert(alert)
                    } else {
                        self.showLightweightSQLImportErrors(errors.joined(separator: "\n"))
                    }
                }
            }

            _ = connection.selectDatabase(database)

            if let mysqlCharset = Self.mysqlCharset(for: encoding), let currentEncoding = connection.encoding(), !currentEncoding.isEmpty {
                connectionEncodingToRestore = currentEncoding
                _ = connection.queryString("SET NAMES '\(mysqlCharset)'")
            }

            if let result = connection.queryString("SELECT @@sql_mode") {
                result.returnDataAsStrings = true
                result.defaultRowReturnType = SPMySQLResultRowAsArray
                if let row = result.getRowAsArray() as? [Any], let sqlMode = row.first as? String {
                    sqlModeToRestore = sqlMode
                }
            }

            for (index, query) in queries.enumerated() {
                if progressCancelled { break }

                if !connection.isConnected() && (connection.userTriggeredDisconnect() || !connection.check()) {
                    errors.append(NSLocalizedString("The connection to the server was lost during the import. The import is only partially complete.", comment: "Connection lost during import error message"))
                    break
                }

                _ = connection.queryString(query, usingEncoding: encoding.rawValue, with: SPMySQLResultAsResult)

                if connection.queryErrored(), connection.lastErrorMessage() != "Query was empty" {
                    let error = connection.lastErrorMessage() ?? NSLocalizedString("Unknown MySQL error.", comment: "unknown mysql error")
                    errors.append(String(format: NSLocalizedString("[ERROR in query %ld] %@", comment: "error text when multiple custom query failed"), index + 1, error))

                    if connection.lastErrorID() == 1115,
                       error.range(of: "utf8mb4", options: .caseInsensitive) != nil,
                       query.range(of: "SET NAMES", options: .caseInsensitive) != nil,
                       !ignoreCharsetError {
                        let shouldContinue = DispatchQueue.main.sync {
                            self.confirmLightweightCharsetImportError()
                        }
                        if shouldContinue {
                            ignoreCharsetError = true
                        } else {
                            errors.append(NSLocalizedString("Import cancelled!", comment: "import cancelled message"))
                            progressCancelled = true
                        }
                    } else if !ignoreSQLErrors {
                        let choice = DispatchQueue.main.sync {
                            self.lightweightSQLImportErrorChoice(error)
                        }
                        switch choice {
                        case .continue:
                            break
                        case .ignoreAll:
                            ignoreSQLErrors = true
                        case .stop:
                            errors.append(NSLocalizedString("Import cancelled!", comment: "import cancelled message"))
                            progressCancelled = true
                        }
                    }
                }

                queriesPerformed += 1
            }
        }
    }

    func lightweightSQLQueries(in text: String) -> [String] {
        // Bounded lightweight imports intentionally pre-split SQL. Unlike the legacy
        // streaming importer, this cannot adjust parser noBackslashEscapes after
        // mid-file SQL_MODE changes; the confirmation alert routes those dumps to
        // the full database view.
        let parser = SPSQLParser(string: text)
        parser.setDelimiterSupport(true)
        guard let rawQueries = parser.splitString(byCharacter: Character(";").utf16.first!) as? [String] else { return [] }

        return rawQueries.compactMap { query in
            let normalised = parser.containsCarriageReturns() ? (SPSQLParser.normaliseQuery(forExecution: query) ?? query) : query
            let trimmed = normalised.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    func lightweightSQLImportErrorChoice(_ error: String) -> LightweightSQLImportErrorChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("An error occurred while importing SQL", comment: "sql import error message")
        alert.informativeText = error
        alert.addButton(withTitle: NSLocalizedString("Continue", comment: "continue button"))
        alert.addButton(withTitle: NSLocalizedString("Ignore All Errors", comment: "ignore errors button"))
        alert.addButton(withTitle: NSLocalizedString("Stop", comment: "stop button"))

        switch runLightweightModalAlert(alert) {
        case .alertFirstButtonReturn:
            return .continue
        case .alertSecondButtonReturn:
            return .ignoreAll
        default:
            return .stop
        }
    }

    func confirmLightweightCharsetImportError() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Incompatible encoding in SQL file", comment: "sql import error message")
        alert.informativeText = NSLocalizedString("The SQL file uses utf8mb4 encoding, but your MySQL version only supports the limited utf8 subset. You can continue the import, but any non-BMP characters in the SQL file will be unrecoverably lost.", comment: "sql import charset error detail message")
        alert.addButton(withTitle: NSLocalizedString("Import Anyway", comment: "sql import : charset error alert : continue button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        return runLightweightModalAlert(alert) == .alertFirstButtonReturn
    }

    func showLightweightSQLImportErrors(_ errors: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Import Errors", comment: "lightweight SQL import errors title")
        alert.informativeText = errors
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        _ = runLightweightModalAlert(alert)
    }

    static func mysqlCharset(for encoding: String.Encoding) -> String? {
        switch encoding {
        case .utf8:
            return "utf8mb4"
        case .isoLatin1:
            return "latin1"
        case .ascii:
            return "ascii"
        case .windowsCP1250:
            return "cp1250"
        case .windowsCP1251:
            return "cp1251"
        case .shiftJIS:
            return "sjis"
        case .japaneseEUC:
            return "ujis"
        case .utf16, .utf16BigEndian, .utf16LittleEndian:
            return "utf16"
        default:
            return nil
        }
    }

    static func sqlSingleQuoted(_ value: String) -> String {
        return "'\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'"))'"
    }
}

extension SPWindowController {
    func logLightweightConsoleQuery(_ query: String?) {
        guard let query = query, !query.isEmpty else { return }

        let prefs = UserDefaults.standard
        guard prefs.bool(forKey: SPConsoleEnableLogging) else { return }

        let queryMode = currentLightweightConsoleQueryMode()
        let shouldLog: Bool
        switch queryMode {
        case 1:
            shouldLog = prefs.bool(forKey: SPConsoleEnableCustomQueryLogging)
        case 2:
            shouldLog = prefs.bool(forKey: SPConsoleEnableImportExportLogging)
        default:
            shouldLog = prefs.bool(forKey: SPConsoleEnableInterfaceLogging)
        }
        guard shouldLog else { return }

        SPQueryController.shared()?.showMessage(inConsole: query,
                                                connection: lightweightConsoleConnectionName(),
                                                database: lightweightConsoleDatabaseName())
    }

    func logLightweightConsoleError(_ error: String?) {
        guard let error = error, !error.isEmpty else { return }

        let prefs = UserDefaults.standard
        guard prefs.bool(forKey: SPConsoleEnableLogging),
              prefs.bool(forKey: SPConsoleEnableErrorLogging) else { return }

        SPQueryController.shared()?.showError(inConsole: error,
                                              connection: lightweightConsoleConnectionName(),
                                              database: lightweightConsoleDatabaseName())
    }

    func lightweightConnectionDisplayName() -> String {
        if let activeConnectionName, !activeConnectionName.isEmpty {
            return activeConnectionName
        }

        let user = activeConnectionInfo?.user.isEmpty == false ? activeConnectionInfo!.user : "anonymous"
        let host: String
        if activeConnectionInfo?.type == .socket {
            host = "localhost"
        } else if let infoHost = activeConnectionInfo?.host, !infoHost.isEmpty {
            host = infoHost
        } else if let connectionHost = activeConnection?.host, !connectionHost.isEmpty {
            host = connectionHost
        } else {
            host = ""
        }

        return "\(user)@\(host)"
    }

    func lightweightConsoleConnectionName() -> String {
        if let activeConnectionName, !activeConnectionName.isEmpty {
            return activeConnectionName
        }
        if let name = activeConnectionInfo?.name, !name.isEmpty {
            return name
        }
        if let host = activeConnection?.host, !host.isEmpty {
            return host
        }
        return ""
    }

    func lightweightConsoleDatabaseName() -> String {
        if let selectedDatabase, !selectedDatabase.isEmpty {
            return selectedDatabase
        }
        if let database = activeConnection?.database, !database.isEmpty {
            return database
        }
        return activeConnectionInfo?.database ?? ""
    }
}

extension SPWindowController: SADatabaseToolbarControllerDelegate {
    func databaseToolbarDidRequestDatabaseLoad(_ controller: SADatabaseToolbarController) {
        requestLightweightDatabasesIfNeeded()
    }

    func databaseToolbarDidRequestDatabaseRefresh(_ controller: SADatabaseToolbarController) {
        refreshLightweightDatabases()
    }

    func databaseToolbarDidRequestAddDatabase(_ controller: SADatabaseToolbarController) {
        addLightweightDatabase(nil)
    }

    func databaseToolbar(_ controller: SADatabaseToolbarController, didSelectDatabase database: String) {
        markLightweightResumeStateChanged()
        loadTables(for: database)
    }

    func databaseToolbar(_ controller: SADatabaseToolbarController, didSelectViewMode mode: SAViewMode) {
        if activeConnection != nil,
           loadedDatabaseDocument == nil,
           selectedDatabase?.isEmpty != false {
            return
        }

        if activeConnection != nil, loadedDatabaseDocument == nil, mode != .query, selectedTable == nil {
            return
        }

        markLightweightResumeStateChanged()
        saveCurrentLightweightViewState()

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
        markLightweightResumeStateChanged()
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
            return lightweightTableTypes.values.contains(.view)
                ? NSLocalizedString("TABLES & VIEWS", comment: "header for table & views list")
                : NSLocalizedString("TABLES", comment: "header for table list")
        }

        return filteredLightweightTables[row - 1]
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard tableView == tablesListView,
              row > 0,
              row - 1 < filteredLightweightTables.count,
              let selectedDatabase = selectedDatabase else { return }

        let oldName = filteredLightweightTables[row - 1]
        let newName = String(describing: object ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, oldName != newName else {
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            return
        }

        let tableType = lightweightTableTypes[oldName] ?? .table
        guard validateLightweightObjectName(newName, type: tableType, ignoring: oldName) else {
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            return
        }

        if tableType == .procedure || tableType == .function {
            duplicateLightweightRoutine(oldName, to: newName, type: tableType, database: selectedDatabase, dropSource: true)
            return
        }

        let statement = "RENAME TABLE \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(oldName)) TO \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(newName))"
        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Renaming %@...", comment: "Renaming table task string"), oldName), statement: statement) { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.tablesListView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<self.tablesListView.numberOfColumns))
                return
            }

            self.handleLightweightPinnedTableRename(from: oldName, to: newName)
            self.loadTables(for: selectedDatabase, restoringTable: newName)
        }
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return tableView == tablesListView && row > 0
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

        guard row > 0, row - 1 < filteredLightweightTables.count else {
            cell.image = nil
            return
        }

        let table = filteredLightweightTables[row - 1]
        cell.image = (lightweightTableTypes[table] ?? .table).imageName.flatMap { NSImage(named: NSImage.Name($0)) }
        if lightweightPinnedTables.contains(table) {
            cell.setNote(NSLocalizedString("Pinned", comment: "pinned table list note"))
        }
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

    func isLightweightTableInfoView(_ tableView: NSTableView) -> Bool {
        return tableView.identifier == NSUserInterfaceItemIdentifier("LightweightTableInfo")
    }
}
