//
//  SPWindowController+LightweightServices.swift
//  Sequel Ace
//

import Cocoa

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

    @objc func assignLightweightBundleProcessID(_ processID: String) {
        guard hasActiveLightweightConnection else { return }

        lightweightBundleProcessID = processID
    }

    @objc func lightweightBundleProcessIDValue() -> String? {
        guard hasActiveLightweightConnection else { return nil }

        return lightweightBundleProcessID
    }

    @objc func registerActivity(_ commandDict: NSDictionary) {
        guard hasActiveLightweightConnection else { return }

        (NSApp.delegate as? SPAppController)?.registerActivity(commandDict as? [AnyHashable: Any])
    }

    @objc func removeRegisteredActivity(_ pid: Int) {
        guard hasActiveLightweightConnection else { return }

        (NSApp.delegate as? SPAppController)?.removeRegisteredActivity(pid)
    }

    @objc func lightweightShellVariables() -> NSDictionary {
        guard hasActiveLightweightConnection else { return [:] }

        let env = NSMutableDictionary()

        if let selectedDatabase = selectedDatabase, !selectedDatabase.isEmpty {
            env[SPBundleShellVariableSelectedDatabase] = selectedDatabase
        }

        if let selectedTable = selectedTable, !selectedTable.isEmpty {
            env[SPBundleShellVariableSelectedTable] = selectedTable
            env[SPBundleShellVariableSelectedTables] = selectedTable
        }

        if !lightweightDatabases.isEmpty {
            env[SPBundleShellVariableAllDatabases] = lightweightDatabases.joined(separator: "\t")
        }

        env[SPBundleShellVariableAllTables] = lightweightTables
            .filter { (lightweightTableTypes[$0] ?? .table) == .table }
            .joined(separator: "\t")
        env[SPBundleShellVariableAllViews] = lightweightTables
            .filter { lightweightTableTypes[$0] == .view }
            .joined(separator: "\t")
        env[SPBundleShellVariableAllFunctions] = lightweightTables
            .filter { lightweightTableTypes[$0] == .function }
            .joined(separator: "\t")
        env[SPBundleShellVariableAllProcedures] = lightweightTables
            .filter { lightweightTableTypes[$0] == .procedure }
            .joined(separator: "\t")

        if let user = activeConnectionInfo?.user, !user.isEmpty {
            env[SPBundleShellVariableCurrentUser] = user
        }

        if activeConnectionInfo?.type == .socket {
            env[SPBundleShellVariableCurrentHost] = "localhost"
        } else if let host = activeConnectionInfo?.host, !host.isEmpty {
            env[SPBundleShellVariableCurrentHost] = host
        } else if let host = activeConnection?.host, !host.isEmpty {
            env[SPBundleShellVariableCurrentHost] = host
        }

        if let port = activeConnectionInfo?.port, !port.isEmpty {
            env[SPBundleShellVariableCurrentPort] = port
        } else if let port = activeConnection?.port, port > 0 {
            env[SPBundleShellVariableCurrentPort] = String(port)
        }

        if let encoding = activeConnection?.encoding(), !encoding.isEmpty {
            env[SPBundleShellVariableDatabaseEncoding] = encoding
        }

        env[SPBundleShellVariableRDBMSType] = "mysql"

        if let serverVersion = activeServerVersion, !serverVersion.isEmpty {
            env[SPBundleShellVariableRDBMSVersion] = serverVersion
        } else if let serverVersion = activeConnection?.serverVersionString(), !serverVersion.isEmpty {
            env[SPBundleShellVariableRDBMSVersion] = serverVersion
        }

        return env
    }

    @objc func handleLightweightSchemeCommand(_ commandDict: NSDictionary) -> Bool {
        guard hasActiveLightweightConnection else { return false }
        guard let params = commandDict["parameter"] as? [String], !params.isEmpty else {
            NSLog("No URL scheme command passed")
            NSSound.beep()
            return true
        }

        let command = params[0]

        if command == "SelectDocumentView" {
            guard params.count == 2 else { return true }

            switch params[1].lowercased() {
            case let view where view.hasPrefix("str"):
                viewStructure()
            case let view where view.hasPrefix("con"):
                viewContent()
            case let view where view.hasPrefix("que"):
                viewQuery()
            case let view where view.hasPrefix("tab"):
                viewStatus()
            case let view where view.hasPrefix("rel"):
                viewRelations()
            case let view where view.hasPrefix("tri"):
                viewTriggers()
            default:
                break
            }

            return true
        }

        if command == "SelectTable" {
            guard params.count == 2, !params[1].isEmpty else { return true }

            selectLightweightTableInSidebar(params[1])
            selectLightweightTable(params[1])
            return true
        }

        if command == "SelectTables" {
            guard params.count > 1, let table = params.dropFirst().first, !table.isEmpty else { return true }

            selectLightweightTableInSidebar(table)
            selectLightweightTable(table)
            return true
        }

        if command == "SelectDatabase" {
            guard params.count > 1, !params[1].isEmpty else { return true }

            loadTables(for: params[1], restoringTable: params.count > 2 ? params[2] : nil)
            return true
        }

        if command == "SelectTableRows" {
            guard params.count > 1 else { return true }

            if let tableView = (window?.firstResponder ?? NSApp.keyWindow?.firstResponder) as? SPCopyTable {
                tableView.selectRows(Array(params.dropFirst()))
            } else {
                NSSound.beep()
            }
            return true
        }

        let callbackID = (commandDict["id"] as? String) ?? ""
        guard !callbackID.isEmpty, callbackID == (lightweightBundleProcessID ?? "") else {
            NSAlert.createWarningAlert(title: NSLocalizedString("Remote Error", comment: "remote error"),
                                       message: NSLocalizedString("URL scheme command couldn't authenticated", comment: "URL scheme command couldn't authenticated"),
                                       callback: nil)
            return true
        }

        if command == "SetSelectedTextRange" {
            guard params.count > 1,
                  let textView = window?.firstResponder as? NSTextView else {
                NSSound.beep()
                return true
            }

            let requestedRange = NSRangeFromString(params[1])
            let validRange = NSIntersectionRange(requestedRange, NSRange(location: 0, length: textView.string.count))
            if validRange.location != NSNotFound {
                textView.setSelectedRange(validRange)
            }
            return true
        }

        if command == "InsertText" {
            guard params.count > 1,
                  let textView = window?.firstResponder as? NSTextView else {
                NSSound.beep()
                return true
            }

            textView.insertText(params[1], replacementRange: textView.selectedRange())
            return true
        }

        if command == "SetText" {
            guard params.count > 1,
                  let textView = window?.firstResponder as? NSTextView else {
                NSSound.beep()
                return true
            }

            textView.string = params[1]
            return true
        }

        NSAlert.createWarningAlert(title: NSLocalizedString("Remote Error", comment: "remote error"),
                                   message: String(format: NSLocalizedString("URL scheme command “%@” unsupported", comment: "URL scheme command “%@” unsupported"), command),
                                   callback: nil)
        return true
    }

    @objc func doPerformLightweightQueryService(_ query: String) {
        guard hasActiveLightweightConnection else { return }

        viewQuery()
        lightweightQueryController.doPerformQueryService(query)
    }

    @objc func legacyDatabaseDocumentForMenuAction() -> SPDatabaseDocument {
        return installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable)
    }

    @objc func canCopyActiveLightweightSelection(_ menuItem: NSMenuItem?) -> Bool {
        guard hasActiveLightweightConnection else { return false }

        switch activeLightweightViewMode {
        case .content:
            return lightweightContentController.canCopySelectedContentRows(menuItem)
        case .query:
            return lightweightQueryController.canCopySelectedResultRows(menuItem)
        default:
            return false
        }
    }

    @objc func copyActiveLightweightSelection(_ sender: Any?) {
        guard hasActiveLightweightConnection else { return }

        switch activeLightweightViewMode {
        case .content:
            lightweightContentController.copySelectedContentRowsForMenu(sender)
        case .query:
            lightweightQueryController.copySelectedResultRowsForMenu(sender)
        default:
            NSSound.beep()
        }
    }

    @objc func canExportLightweightData() -> Bool {
        guard hasActiveLightweightConnection else { return false }

        switch activeLightweightViewMode {
        case .content:
            return lightweightContentController.exportResultRowCount() > 0
        case .query:
            return lightweightQueryController.exportResultRowCount() > 0
        default:
            return false
        }
    }

    @objc func exportData() {
        if let document = loadedDatabaseDocument {
            document.exportData()
            return
        }

        guard hasActiveLightweightConnection,
              let activeConnection = activeConnection,
              canExportLightweightData() else {
            NSSound.beep()
            return
        }

        let filteredSource = SALightweightExportSource.filteredResult
        let querySource = SALightweightExportSource.queryResult
        let source: SPExportSource = (activeLightweightViewMode == .content) ? filteredSource : querySource
        let isContentExport = source == filteredSource
        let isQueryExport = source == querySource
        let contentResult = isContentExport ? lightweightContentController.exportDataResult(withNULLs: true) : []
        let queryResult = isQueryExport ? lightweightQueryController.exportDataResult(withNULLs: true, truncateDataFields: false) : []
        let tablesAndViews = lightweightTables.filter { table in
            let type = lightweightTableTypes[table] ?? .table
            return type == .table || type == .view
        }
        let procedures = lightweightTables.filter { lightweightTableTypes[$0] == .procedure }
        let functions = lightweightTables.filter { lightweightTableTypes[$0] == .function }
        let selectedTables = selectedTable.map { [$0] } ?? []
        let controller = SPExportController()

        let database = selectedDatabase ?? ""
        let host = activeConnection.host ?? activeConnectionInfo?.host ?? ""
        let serverVersion = activeServerVersion ?? ""
        let selectedTableName = selectedTable ?? ""
        let favoriteName = activeConnectionName ?? lightweightConnectionDisplayName()
        let contentQuery = isContentExport ? lightweightContentController.exportUsedQuery() : ""
        let queryString = isQueryExport ? lightweightQueryController.exportUsedQuery() : ""

        controller.configure(forLightweightWindowController: self,
                             connection: activeConnection,
                             serverSupport: nil,
                             database: database,
                             host: host,
                             serverVersion: serverVersion,
                             selectedTableName: selectedTableName,
                             favoriteName: favoriteName,
                             tablesAndViewNames: tablesAndViews,
                             procedureNames: procedures,
                             functionNames: functions,
                             selectedTableItems: selectedTables,
                             contentResult: contentResult,
                             contentQuery: contentQuery,
                             queryResult: queryResult,
                             queryString: queryString,
                             preferredSource: source)
        lightweightExportController = controller
        controller.exportData()
    }

    @objc func canImportLightweightSQL() -> Bool {
        return activeConnection != nil
            && selectedDatabase?.isEmpty == false
            && loadedDatabaseDocument == nil
            && !isLightweightConnectionBusyForImport()
    }

    @objc func canImportLightweightSQLFromClipboard() -> Bool {
        guard canImportLightweightSQL() else { return false }
        return NSPasteboard.general.availableType(from: [.string]) != nil
    }

    @objc func importLightweightSQLFile(_ sender: Any?) {
        guard canImportLightweightSQL() else {
            showLightweightImportUnavailableReason()
            return
        }

        switch lightweightImportRouteChoice() {
        case .lightweight:
            break
        case .legacy:
            startLegacyFileImportFlow()
            return
        case .cancel:
            return
        }

        let prefs = UserDefaults.standard
        if prefs.integer(forKey: SPLastSQLFileEncoding) == 0 {
            prefs.set(String.Encoding.utf8.rawValue, forKey: SPLastSQLFileEncoding)
        }

        let selectedEncoding = String.Encoding(rawValue: UInt(prefs.integer(forKey: SPLastSQLFileEncoding)))
        let encodingAccessory = SALightweightSQLImportEncodingAccessory(selectedEncoding: selectedEncoding)
        let panel = NSOpenPanel()
        panel.allowedFileTypes = [SPFileExtensionSQL as String]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.accessoryView = encodingAccessory.view
        panel.message = NSLocalizedString("Lightweight windows can import SQL files. CSV import requires the full database view.", comment: "lightweight SQL import panel message")

        if let openPath = prefs.string(forKey: "exportPath"), !openPath.isEmpty {
            panel.directoryURL = URL(string: openPath) ?? URL(fileURLWithPath: openPath)
        }

        panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSWindow()) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }

            prefs.set(panel.directoryURL?.path, forKey: "exportPath")
            prefs.set(encodingAccessory.selectedEncoding.rawValue, forKey: SPLastSQLFileEncoding)

            guard self.validateLightweightSQLImportFileSize(url: url) else { return }
            guard self.confirmLightweightSQLImport(sourceName: url.lastPathComponent) else { return }
            self.startLightweightSQLImport(url: url, encoding: encodingAccessory.selectedEncoding)
        }
    }

    @objc func importLightweightSQLFromClipboard(_ sender: Any?) {
        guard canImportLightweightSQL() else {
            showLightweightImportUnavailableReason()
            return
        }

        guard let clipboardSQL = NSPasteboard.general.string(forType: .string),
              !clipboardSQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            showLightweightError(title: NSLocalizedString("Import From Clipboard", comment: "import from clipboard title"),
                                 message: NSLocalizedString("The clipboard does not contain SQL text to import.", comment: "lightweight import clipboard empty message"))
            return
        }

        let clipboardSourceName = NSLocalizedString("clipboard", comment: "clipboard import source name")
        guard confirmLightweightSQLImport(sourceName: clipboardSourceName) else { return }
        runLightweightSQLImport(sql: clipboardSQL, sourceName: clipboardSourceName, encoding: .utf8)
    }

    @objc func canPrintLightweightDocument() -> Bool {
        return lightweightPrintTarget() != nil
    }

    @objc func printLightweightDocument(_ sender: Any?) {
        guard hasActiveLightweightConnection else { return }

        guard let target = lightweightPrintTarget() else {
            showLightweightPrintUnsupportedAlert()
            return
        }

        if shouldWarnBeforePrintingLightweightContent(target) {
            warnBeforePrintingLightweightContent(target) { [weak self] in
                self?.runLightweightPrintOperation(for: target)
            }
            return
        }

        runLightweightPrintOperation(for: target)
    }

    @objc func canAddLightweightConnectionToFavorites() -> Bool {
        guard hasActiveLightweightConnection,
              let connectionController = connectionController else { return false }

        return connectionController.selectedFavorite() == nil || connectionController.isEditingConnection
    }

    @objc func addLightweightConnectionToFavorites() {
        guard canAddLightweightConnectionToFavorites(),
              let connectionController = connectionController,
              let activeConnectionInfo = activeConnectionInfo else { return }

        connectionController.applyLightweightConnectionInfo(activeConnectionInfo)
        connectionController.addFavoriteUsingCurrentDetails(self)
    }

    @objc func saveLightweightConnectionSheet(_ sender: Any?) {
        guard hasActiveLightweightConnection else { return }

        let tag = (sender as? NSMenuItem)?.tag ?? Int(SPMainMenuFileSaveConnection.rawValue)
        if tag == Int(SPMainMenuFileSaveQuery.rawValue) || tag == 0 {
            saveLightweightQuerySheet()
            return
        }

        let isSessionSave = tag == Int(SPMainMenuFileSaveSession.rawValue)
        let panel = NSSavePanel()
        panel.allowsOtherFileTypes = false
        panel.canSelectHiddenExtension = true
        panel.allowedFileTypes = [isSessionSave ? (SPBundleFileExtension as String) : (SPFileExtensionDefault as String)]

        let accessory = SALightweightSaveConnectionAccessory(includeQueryEnabled: !lightweightQueryText().isEmpty)
        panel.accessoryView = accessory.view
        panel.nameFieldStringValue = isSessionSave
            ? NSLocalizedString("Session", comment: "Initial filename for 'Save session' file")
            : lightweightConnectionDisplayName()

        panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let self = self, let url = panel.url else { return }
            let options = accessory.options()
            if isSessionSave {
                self.saveLightweightSession(to: url, options: options)
            } else {
                self.saveLightweightConnection(to: url, options: options)
            }
        }
    }

    @objc func validateLightweightSaveConnectionMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard hasActiveLightweightConnection else { return false }

        if menuItem.tag == Int(SPMainMenuFileSaveQuery.rawValue) || menuItem.tag == 0 {
            let count = lightweightQueryCount()
            menuItem.title = count == 1
                ? NSLocalizedString("Save Query…", comment: "Save Query…")
                : NSLocalizedString("Save Queries…", comment: "Save Queries…")
            return count > 0
        }

        return true
    }

    @objc func toggleLightweightNavigator() {
        guard hasActiveLightweightConnection else { return }

        let navigator = SPNavigatorController.shared()
        let isNavigatorVisible = navigator?.window?.isVisible ?? false
        navigator?.window?.setIsVisible(!isNavigatorVisible)
        if !isNavigatorVisible {
            navigator?.updateEntries(forLightweightWindowController: self)
        }
    }

    @objc func lightweightNavigatorConnectionID() -> String {
        guard hasActiveLightweightConnection,
              let info = activeConnectionInfo else { return "_" }

        let user = info.user.isEmpty ? "anonymous" : info.user
        let port = info.port.isEmpty ? "" : ":\(info.port)"
        switch info.type {
        case .socket:
            return "\(user)@localhost\(port)"
        case .sshTunnel:
            let sshUser = info.sshUser.isEmpty ? "anonymous" : info.sshUser
            let sshPort = info.sshPort.isEmpty ? "22" : info.sshPort
            return "\(user)@\(info.host)\(port)&SSH&\(sshUser)@\(info.sshHost):\(sshPort)"
        case .awsIAM:
            let profile = info.awsProfile.isEmpty ? "default" : info.awsProfile
            let region = info.awsRegion.isEmpty ? "auto" : info.awsRegion
            return "\(user)@\(info.host)\(port)&AWSIAM&\(profile)&\(region)"
        case .tcpIP:
            return "\(user)@\(info.host)\(port)"
        @unknown default:
            return "\(user)@\(info.host)\(port)"
        }
    }

    @objc func lightweightNavigatorSelectedPath() -> String {
        let connectionID = lightweightNavigatorConnectionID()
        guard connectionID != "_" else { return "" }

        var path = connectionID
        if let selectedDatabase = selectedDatabase, !selectedDatabase.isEmpty {
            path += SPUniqueSchemaDelimiter + selectedDatabase
        }
        if let selectedTable = selectedTable, !selectedTable.isEmpty {
            path += SPUniqueSchemaDelimiter + selectedTable
        }
        return path
    }

    @objc func lightweightNavigatorSchemaData() -> NSDictionary {
        let connectionID = lightweightNavigatorConnectionID()
        let structure = NSMutableDictionary()
        let databases = lightweightNavigatorDatabaseNames()
        for database in databases {
            let databaseKey = connectionID + SPUniqueSchemaDelimiter + database
            if selectedDatabase == database {
                let databaseDictionary = NSMutableDictionary()
                for table in lightweightTables {
                    let tableKey = databaseKey + SPUniqueSchemaDelimiter + table
                    let tableDictionary = NSMutableDictionary()
                    tableDictionary["  struct_type  "] = lightweightNavigatorTableTypeNumber(for: lightweightTableTypes[table])
                    databaseDictionary[tableKey] = tableDictionary
                }
                structure[databaseKey] = databaseDictionary
            } else {
                // Match SPDatabaseStructure's unloaded-database shape. Using an empty dictionary for
                // every database makes NSDictionary's allKeysForObject: treat each row as equal, so
                // the Navigator labels collapse to the first database name.
                structure[databaseKey] = database
            }
        }
        return structure
    }

    @objc func lightweightNavigatorAllSchemaKeys() -> [String] {
        let connectionID = lightweightNavigatorConnectionID()
        var keys: [String] = []
        for database in lightweightNavigatorDatabaseNames() {
            let databaseKey = connectionID + SPUniqueSchemaDelimiter + database
            keys.append(databaseKey)
            if selectedDatabase == database {
                for table in lightweightTables {
                    keys.append(databaseKey + SPUniqueSchemaDelimiter + table)
                }
            }
        }
        return keys
    }

    @objc func selectLightweightNavigatorDatabase(_ database: String, item: String?) {
        guard hasActiveLightweightConnection else { return }
        if let item = item, !item.isEmpty {
            loadTables(for: database, restoringTable: item)
        } else {
            loadTables(for: database)
        }
    }

    @objc func showLightweightMySQLHelp() {
        if let document = loadedDatabaseDocument {
            document.showMySQLHelp()
            return
        }

        guard let activeConnection = activeConnection else { return }
        lightweightHelpViewerClient.setConnection(activeConnection)
        lightweightHelpViewerClient.showHelp(for: "contents", addToHistory: true, calledByAutoHelp: false)
        lightweightHelpViewerClient.helpWebViewWindow().makeKey()
    }

    @objc func addLightweightDatabase(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.addDatabase(sender)
            return
        }

        guard let databaseDetails = promptForLightweightDatabase() else {
            if let selectedDatabase = selectedDatabase {
                selectLightweightDatabaseInToolbar(selectedDatabase)
            }
            return
        }
        let databaseName = databaseDetails.name
        guard validateLightweightDatabaseName(databaseName) else { return }

        if let activeConnection = activeConnection, activeConnection.encoding()?.hasPrefix("utf8") == false {
            _ = activeConnection.setEncoding("utf8mb4")
        }

        var options: [String] = []
        if let encoding = databaseDetails.encoding {
            options.append("DEFAULT CHARACTER SET = \(Self.backtickQuoted(encoding))")
        }
        if let collation = databaseDetails.collation {
            options.append("DEFAULT COLLATE = \(Self.backtickQuoted(collation))")
        }

        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Creating %@...", comment: "Creating database task string"), databaseName),
                                        statement: "CREATE DATABASE \(Self.backtickQuoted(databaseName)) \(options.joined(separator: " "))") { [weak self] success in
            guard let self = self else { return }
            guard success else {
                if let selectedDatabase = self.selectedDatabase {
                    self.loadTables(for: selectedDatabase, preservingSelection: true)
                } else {
                    self.showLightweightPlaceholder(NSLocalizedString("Choose a database to load tables.", comment: "lightweight database shell empty state"))
                }
                return
            }
            self.databaseListNeedsLoad = true
            self.requestLightweightDatabases(forceReload: true)
            self.selectLightweightDatabaseInToolbar(databaseName)
            self.loadTables(for: databaseName)
            self.postLightweightDatabaseCreatedRemovedRenamedNotification()
        }
    }

    @objc func removeLightweightDatabase(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.removeDatabase(sender)
            return
        }

        guard let selectedDatabase = selectedDatabase, !selectedDatabase.isEmpty else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Delete database '%@'?", comment: "delete database message"), selectedDatabase)
        alert.informativeText = String(format: NSLocalizedString("Are you sure you want to delete the database '%@'? This operation cannot be undone.", comment: "delete database informative message"), selectedDatabase)
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        alert.alertStyle = .critical

        guard runLightweightModalAlert(alert) == .alertFirstButtonReturn else { return }

        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Deleting %@...", comment: "Deleting database task string"), selectedDatabase),
                                        statement: "DROP DATABASE \(Self.backtickQuoted(selectedDatabase))") { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.loadTables(for: selectedDatabase, preservingSelection: true)
                return
            }
            self.clearLightweightDatabaseSelection(afterRemoving: selectedDatabase)
            self.postLightweightDatabaseCreatedRemovedRenamedNotification()
        }
    }

    @objc func copyLightweightDatabase(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.copyDatabase()
            return
        }

        guard let activeConnection = activeConnection,
              let selectedDatabase = selectedDatabase,
              !selectedDatabase.isEmpty else {
            NSSound.beep()
            return
        }

        if lightweightDatabaseHasNonTableObjects(selectedDatabase, connection: activeConnection) {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Only Partially Supported", comment: "partial copy database support message")
            alert.informativeText = String(format: NSLocalizedString("Duplicating the database '%@' is only partially supported as it contains objects other than tables (i.e. views, procedures, functions, etc.), which will not be copied.\n\nWould you like to continue?", comment: "partial copy database support informative message"), selectedDatabase)
            alert.addButton(withTitle: NSLocalizedString("Continue", comment: "continue button"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

            guard runLightweightModalAlert(alert) != .alertSecondButtonReturn else { return }
        }

        guard let copyDetails = promptForLightweightDatabaseCopy(sourceDatabase: selectedDatabase) else {
            selectLightweightDatabaseInToolbar(selectedDatabase)
            return
        }

        let targetDatabase = copyDetails.name
        guard validateLightweightDatabaseName(targetDatabase) else {
            selectLightweightDatabaseInToolbar(selectedDatabase)
            return
        }

        if activeConnection.encoding()?.hasPrefix("utf8") == false {
            _ = activeConnection.setEncoding("utf8mb4")
        }

        runLightweightDatabaseCopyMutation(from: selectedDatabase,
                                           to: targetDatabase,
                                           copyContent: copyDetails.duplicateContent,
                                           status: String(format: NSLocalizedString("Copying database '%@'...", comment: "Copying database task description"), selectedDatabase)) { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.loadTables(for: selectedDatabase, preservingSelection: true)
                return
            }

            self.databaseListNeedsLoad = true
            self.requestLightweightDatabases(forceReload: true)
            self.selectLightweightDatabaseInToolbar(targetDatabase)
            self.loadTables(for: targetDatabase)
            self.postLightweightDatabaseCreatedRemovedRenamedNotification()
        }
    }

    @objc func renameLightweightDatabase(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.renameDatabase()
            return
        }

        guard let selectedDatabase = selectedDatabase, !selectedDatabase.isEmpty else {
            NSSound.beep()
            return
        }

        guard let newDatabaseName = promptForLightweightName(title: NSLocalizedString("Rename Database", comment: "rename database sheet title"),
                                                             message: String(format: NSLocalizedString("Rename database '%@' to:", comment: "rename database message"), selectedDatabase),
                                                             defaultValue: selectedDatabase,
                                                             buttonTitle: NSLocalizedString("Rename", comment: "rename button"),
                                                             nameValidator: lightweightDatabaseNameLiveValidator()) else {
            selectLightweightDatabaseInToolbar(selectedDatabase)
            return
        }

        guard newDatabaseName != selectedDatabase else {
            selectLightweightDatabaseInToolbar(selectedDatabase)
            return
        }

        guard validateLightweightDatabaseName(newDatabaseName, ignoring: selectedDatabase) else {
            selectLightweightDatabaseInToolbar(selectedDatabase)
            return
        }

        runLightweightDatabaseRenameMutation(from: selectedDatabase,
                                              to: newDatabaseName,
                                              status: String(format: NSLocalizedString("Renaming %@...", comment: "Renaming database task string"), selectedDatabase)) { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.loadTables(for: selectedDatabase, preservingSelection: true)
                return
            }
            self.applyLightweightDatabaseRename(from: selectedDatabase, to: newDatabaseName)
            self.postLightweightDatabaseCreatedRemovedRenamedNotification()
        }
    }

    @objc func alterLightweightDatabase(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.alterDatabase()
            return
        }

        guard let selectedDatabase = selectedDatabase, !selectedDatabase.isEmpty else {
            NSSound.beep()
            return
        }

        guard let alterDetails = promptForLightweightDatabaseAlter(database: selectedDatabase),
              let encoding = alterDetails.encoding, !encoding.isEmpty else {
            selectLightweightDatabaseInToolbar(selectedDatabase)
            return
        }

        let tableToRestore = selectedTable
        let viewModeToRestore = activeLightweightViewMode
        runLightweightDatabaseAlterMutation(database: selectedDatabase,
                                            encoding: encoding,
                                            collation: alterDetails.collation) { [weak self] _ in
            guard let self = self else { return }
            self.loadTables(for: selectedDatabase,
                            preservingSelection: tableToRestore != nil,
                            restoringTable: tableToRestore,
                            restoringViewMode: viewModeToRestore)
        }
    }

    @objc func flushLightweightPrivileges(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.flushPrivileges()
            return
        }

        guard let activeConnection = activeConnection else {
            NSSound.beep()
            return
        }

        let databaseToRestore = selectedDatabase
        let tableToRestore = selectedTable
        let viewModeToRestore = activeLightweightViewMode
        showLightweightPlaceholder(NSLocalizedString("Flushing privileges...", comment: "flushing privileges task string"))

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            _ = activeConnection.queryString("FLUSH PRIVILEGES")
            let error = activeConnection.queryErrored() ? activeConnection.lastErrorMessage() : nil

            DispatchQueue.main.async {
                if databaseToRestore == nil, self.selectedDatabase == nil {
                    self.showLightweightPlaceholder(NSLocalizedString("Choose a database to load tables.", comment: "lightweight database shell empty state"))
                } else if let tableToRestore = tableToRestore, self.lightweightTables.contains(tableToRestore) {
                    self.activeLightweightViewMode = viewModeToRestore
                    self.selectLightweightTable(tableToRestore, recordsHistory: false)
                } else if viewModeToRestore == .query {
                    self.activeLightweightViewMode = viewModeToRestore
                    self.showLightweightQuery()
                } else {
                    self.showLightweightPlaceholder(self.lightweightTables.isEmpty
                        ? NSLocalizedString("No tables in this database.", comment: "lightweight database shell no tables")
                        : NSLocalizedString("Select a table or choose a toolbar section.", comment: "lightweight database shell table loaded empty state"))
                }

                if let error = error, !error.isEmpty {
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: String(format: NSLocalizedString("Couldn't flush privileges.\nMySQL said: %@", comment: "message of panel when flushing privs failed"), error))
                    return
                }

                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = NSLocalizedString("Flushed Privileges", comment: "title of panel when successfully flushed privs")
                alert.informativeText = NSLocalizedString("Successfully flushed privileges.", comment: "message of panel when successfully flushed privs")
                alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
                _ = self.runLightweightModalAlert(alert)
            }
        }
    }

    @objc func openLightweightDatabaseInNewTab(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.openDatabaseInNewTab()
            return
        }

        guard selectedDatabase != nil,
              let state = lightweightConnectionStateDictionary(includePasswords: true, includeSession: true, includeQuery: true)?.mutableCopy() as? NSMutableDictionary else {
            NSSound.beep()
            return
        }

        if let session = (state[SALightweightConnectionStateKey.lightweightSession] as? NSDictionary)?.mutableCopy() as? NSMutableDictionary {
            session.removeObject(forKey: SALightweightWindowSessionSnapshotKey.selectedTable)
            session[SALightweightWindowSessionSnapshotKey.viewMode] = SAViewMode.structure.rawValue
            state[SALightweightConnectionStateKey.lightweightSession] = session
        }

        NotificationCenter.default.post(name: .SPDocumentDuplicateTab, object: nil, userInfo: [
            "isLightweight": true,
            "lightweightState": state
        ])
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
        if let document = loadedDatabaseDocument {
            document.showGotoDatabase()
            return
        }

        guard activeConnection != nil else { return }

        requestLightweightDatabases(forceReload: false)
        var databaseList = lightweightDatabases
        if databaseList.isEmpty, let activeConnection = activeConnection {
            databaseList = activeConnection.databases() as? [String] ?? []
        }

        lightweightGotoDatabaseController.setDatabaseList(databaseList)
        if let gotoWindow = lightweightGotoDatabaseController.window {
            configureLightweightModalWindow(gotoWindow)
            centerLightweightModalWindow(gotoWindow)
        }
        if lightweightGotoDatabaseController.runModal() {
            guard let database = lightweightGotoDatabaseController.selectedDatabase(), !database.isEmpty else { return }
            if database.contains(".") {
                let components = database.components(separatedBy: ".")
                loadTables(for: components.first ?? database, restoringTable: components.last)
            } else {
                selectLightweightDatabaseInToolbar(database)
                loadTables(for: database)
            }
        }
    }

    @objc func lightweightTableFilterChanged(_ sender: NSSearchField) {
        applyLightweightTableFilter()
        tablesListView.reloadData()
        markLightweightResumeStateChanged()
    }

    @objc func viewStructure() {
        if activeConnection != nil, loadedDatabaseDocument == nil {
            guard let selectedTable = selectedTable else { return }

            showLightweightStructure(for: selectedTable)
            return
        }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewStructure()
    }

    @objc func viewContent() {
        if activeConnection != nil, loadedDatabaseDocument == nil {
            guard let selectedTable = selectedTable else { return }

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
            guard let selectedTable = selectedTable else { return }

            showLightweightStatus(for: selectedTable)
            return
        }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewStatus()
    }

    @objc func viewRelations() {
        if activeConnection != nil, loadedDatabaseDocument == nil {
            guard let selectedTable = selectedTable else { return }

            showLightweightRelations(for: selectedTable)
            return
        }

        installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable).viewRelations()
    }

    @objc func viewTriggers() {
        if activeConnection != nil, loadedDatabaseDocument == nil {
            guard let selectedTable = selectedTable else { return }

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
        if let document = loadedDatabaseDocument {
            document.showFilterTable()
            return
        }

        guard activeConnection != nil, let selectedTable = selectedTable else { return }

        if activeLightweightViewMode != .content {
            showLightweightContent(for: selectedTable)
        }

        var columns = lightweightContentController.legacyFilterColumns()
        if columns.count == 0, let selectedDatabase = selectedDatabase {
            columns = lightweightLegacyFilterColumns(for: selectedTable, database: selectedDatabase)
        }
        let filterColumns = (0..<columns.count).compactMap { columns.object(at: $0) }
        lightweightFilterTableController.setColumns(filterColumns)
        if let filterWindow = lightweightFilterTableController.window, !filterWindow.isVisible {
            configureLightweightModalWindow(filterWindow)
            centerLightweightModalWindow(filterWindow)
        }
        lightweightFilterTableController.showFilterTableWindow()
    }

    @objc func applyLightweightFilterTable(_ sender: Any?) {
        guard sender as AnyObject? === lightweightFilterTableController else { return }

        lightweightContentController.applyAdvancedFilter(whereClause: lightweightFilterTableController.tableFilterString(),
                                                         distinct: lightweightFilterTableController.isDistinct())
    }

    func lightweightLegacyFilterColumns(for table: String, database: String) -> NSArray {
        guard let activeConnection = activeConnection else { return [] }

        guard let result = activeConnection.queryString("SHOW FULL COLUMNS FROM \(Self.backtickQuoted(table)) FROM \(Self.backtickQuoted(database))") else { return [] }
        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary

        var columns: [NSDictionary] = []
        var index = 0
        while let row = result.getRowAsDictionary() as? [String: Any] {
            let name = stringValue(row["Field"])
            let type = stringValue(row["Type"])
            guard !name.isEmpty else { continue }

            columns.append([
                "name": name,
                "type": type,
                "typegrouping": Self.typeGrouping(forColumnType: type),
                "null": stringValue(row["Null"]).uppercased() == "YES" ? "1" : "0",
                "datacolumnindex": "\(index)"
            ])
            index += 1
        }

        return columns as NSArray
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
        if let document = loadedDatabaseDocument {
            document.showUserManager()
            return
        }

        guard let activeConnection = activeConnection, let window = window else {
            NSSound.beep()
            return
        }

        let userManager = SPUserManager()
        userManager.connection = activeConnection
        userManager.databaseProvider = self

        guard userManager.validateUserManagementAccessShowingAlert() else { return }

        lightweightUserManager = userManager
        userManager.beginSheetModal(for: window) { [weak self, weak userManager] in
            guard let self = self, self.lightweightUserManager === userManager else { return }
            self.lightweightUserManager = nil
        }
    }

    @objc func showLightweightServerVariables(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.showServerVariables()
            return
        }

        guard let activeConnection = activeConnection, let window = window else {
            NSSound.beep()
            return
        }

        lightweightServerVariablesController.connection = activeConnection
        lightweightServerVariablesController.perform(NSSelectorFromString("displayServerVariablesSheetAttachedToWindow:"), with: window)
    }

    @objc func showLightweightServerProcesses(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.showServerProcesses()
            return
        }

        guard let activeConnection = activeConnection else {
            NSSound.beep()
            return
        }

        lightweightProcessListController.connection = activeConnection
        lightweightProcessListController.displayProcessListWindow()
        lightweightProcessListController.window?.title = String(format: NSLocalizedString("Server Processes on %@", comment: "server processes window title (var = hostname)"), lightweightConnectionDisplayName())
    }

    @objc func shutdownLightweightServer(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.shutdownServer()
            return
        }

        guard let activeConnection = activeConnection else {
            NSSound.beep()
            return
        }

        NSAlert.createDefaultAlert(title: NSLocalizedString("Do you really want to shutdown the server?", comment: "shutdown server : confirmation dialog : title"),
                                   message: NSLocalizedString("This will wait for open transactions to complete and then quit the mysql daemon. Afterwards neither you nor anyone else can connect to this database!\n\nFull management access to the server's operating system is required to restart MySQL!", comment: "shutdown server : confirmation dialog : message"),
                                   primaryButtonTitle: NSLocalizedString("Shutdown", comment: "shutdown server : confirmation dialog : shutdown button"),
                                   primaryButtonHandler: {
            if !activeConnection.serverShutdown(), activeConnection.isConnected() {
                NSAlert.createWarningAlert(title: NSLocalizedString("Shutdown failed!", comment: "shutdown server : error dialog : title"),
                                           message: String(format: NSLocalizedString("MySQL said:\n%@", comment: "shutdown server : error dialog : message"), activeConnection.lastErrorMessage() ?? ""),
                                           callback: nil)
            }
        }, cancelButtonHandler: nil)
    }

    @objc func showConsole() {
        toggleLightweightConsole()
    }

    @objc func toggleConsole(_ sender: Any?) {
        toggleLightweightConsole()
    }

    @objc func clearConsole(_ sender: Any?) {
        SPQueryController.shared()?.clearConsole(sender)
    }

    func toggleLightweightConsole() {
        guard let queryController = SPQueryController.shared() else { return }
        guard let consoleWindow = queryController.window else { return }

        if consoleWindow.isVisible,
           NSApp.keyWindow?.windowController is SPQueryController {
            consoleWindow.orderOut(self)
            markLightweightResumeStateChanged()
            return
        }

        if !consoleWindow.isVisible {
            queryController.updateEntries()
        }

        consoleWindow.makeKeyAndOrderFront(self)
        markLightweightResumeStateChanged()
    }

    func setLightweightConsoleQueryMode(_ mode: Int) {
        lightweightConsoleLoggingLock.lock()
        lightweightConsoleQueryMode = mode
        lightweightConsoleLoggingLock.unlock()
    }

    func currentLightweightConsoleQueryMode() -> Int {
        lightweightConsoleLoggingLock.lock()
        defer { lightweightConsoleLoggingLock.unlock() }
        return lightweightConsoleQueryMode
    }

    func lightweightCreateTableSyntax(showErrors: Bool) -> String? {
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

    enum LightweightTableMaintenanceAction {
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

    @nonobjc func performLightweightTableMaintenance(_ action: LightweightTableMaintenanceAction) {
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

    @nonobjc func showLightweightTableMaintenanceQueryError(_ action: LightweightTableMaintenanceAction, table: String, mysqlError: String) {
        guard activeConnection?.isConnected() == true else { return }

        let what = String(format: "%@ '%@'", NSLocalizedString("table", comment: "table"), table)
        showLightweightTableMaintenanceAlert(title: action.errorTitle, message: action.errorMessage(what: what, mysqlError: mysqlError))
    }

    @nonobjc func showLightweightTableMaintenanceResult(_ action: LightweightTableMaintenanceAction, table: String, rows: [[String: Any]]) {
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

    static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    static func sqlString(_ value: String) -> String {
        return "'\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "''"))'"
    }

    static func displayString(for value: Any?) -> String {
        guard let value = value else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return "\(value)"
    }

    static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    static func typeGrouping(forColumnType type: String) -> String {
        let lowercasedType = type.lowercased()
        if lowercasedType.hasPrefix("tinyint") ||
            lowercasedType.hasPrefix("smallint") ||
            lowercasedType.hasPrefix("mediumint") ||
            lowercasedType.hasPrefix("int") ||
            lowercasedType.hasPrefix("bigint") {
            return "integer"
        }

        if lowercasedType.hasPrefix("float") ||
            lowercasedType.hasPrefix("double") ||
            lowercasedType.hasPrefix("decimal") {
            return "float"
        }

        if lowercasedType.hasPrefix("date") ||
            lowercasedType.hasPrefix("time") ||
            lowercasedType.hasPrefix("year") {
            return "date"
        }

        if lowercasedType.contains("blob") {
            return "blobdata"
        }

        if lowercasedType.contains("text") {
            return "textdata"
        }

        if lowercasedType.hasPrefix("bit") {
            return "bit"
        }

        if lowercasedType.hasPrefix("binary") || lowercasedType.hasPrefix("varbinary") {
            return "binary"
        }

        return "string"
    }

    func stringValue(_ value: Any?) -> String {
        guard let value = value else { return "" }
        if let string = value as? String { return string }
        return "\(value)"
    }

    func showLightweightTableMaintenanceAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        alert.window.animationBehavior = .none

        alert.runModalCentered(over: window)
    }

    func showLightweightCreateSyntaxSheet(title: String, syntax: String) {
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
        alert.window.animationBehavior = .none

        alert.runModalCentered(over: window)
    }

    func showLightweightCreateSyntaxError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Error", comment: "error message title")
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        alert.window.animationBehavior = .none

        alert.runModalCentered(over: window)
    }
}
