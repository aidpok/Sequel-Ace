//
//  SPWindowController+LightweightServices.swift
//  Sequel Ace
//

import Cocoa
import ObjectiveC
import UniformTypeIdentifiers

private enum SALightweightDBViewFallbackDiagnostics {
    static let reasonCountsDefaultsKey = "SALightweightDBViewFallbackReasonCounts"
    static let sourceCountsDefaultsKey = "SALightweightDBViewFallbackSourceCounts"
    static let totalCountDefaultsKey = "SALightweightDBViewFallbackTotalCount"
    static let lastReasonDefaultsKey = "SALightweightDBViewFallbackLastReason"
    static let lastSourceDefaultsKey = "SALightweightDBViewFallbackLastSource"
    static let lastCallSiteDefaultsKey = "SALightweightDBViewFallbackLastCallSite"
    static let lastRecordedAtDefaultsKey = "SALightweightDBViewFallbackLastRecordedAt"

    private static let lock = NSLock()

    static func record(reason: String,
                       source: String,
                       file: StaticString? = nil,
                       function: StaticString? = nil,
                       line: UInt? = nil) {
        let fallbackReason = normalizedReason(reason)
        let fallbackSource = normalizedSource(source)
        let fallbackCallSite = callSite(file: file, function: function, line: line)
        let defaults = UserDefaults.standard
        let shouldLog = diagnosticsLoggingEnabled
        let stackSignature = shouldLog ? currentStackSignature() : nil

        let (reasonCount, sourceCount, totalCount): (Int, Int, Int) = {
            lock.lock()
            defer { lock.unlock() }

            var reasonCounts = storedCounts(from: defaults, key: reasonCountsDefaultsKey)
            let reasonCount = (reasonCounts[fallbackReason] ?? 0) + 1
            reasonCounts[fallbackReason] = reasonCount

            var sourceCounts = storedCounts(from: defaults, key: sourceCountsDefaultsKey)
            let sourceCount = (sourceCounts[fallbackSource] ?? 0) + 1
            sourceCounts[fallbackSource] = sourceCount

            let totalCount = defaults.integer(forKey: totalCountDefaultsKey) + 1
            defaults.set(reasonCounts, forKey: reasonCountsDefaultsKey)
            defaults.set(sourceCounts, forKey: sourceCountsDefaultsKey)
            defaults.set(totalCount, forKey: totalCountDefaultsKey)
            defaults.set(fallbackReason, forKey: lastReasonDefaultsKey)
            defaults.set(fallbackSource, forKey: lastSourceDefaultsKey)
            if let fallbackCallSite {
                defaults.set(fallbackCallSite, forKey: lastCallSiteDefaultsKey)
            } else {
                defaults.removeObject(forKey: lastCallSiteDefaultsKey)
            }
            defaults.set(Date(), forKey: lastRecordedAtDefaultsKey)
            return (reasonCount, sourceCount, totalCount)
        }()

        guard shouldLog else { return }

        let callSiteDescription = fallbackCallSite ?? "unknown"
        let stackDescription = stackSignature ?? "unavailable"
        NSLog("[SA UI Diagnostics] Lightweight window DBView fallback reason=%@ source=%@ callSite=%@ reasonCount=%ld sourceCount=%ld totalCount=%ld stack=%@",
              fallbackReason,
              fallbackSource,
              callSiteDescription,
              reasonCount,
              sourceCount,
              totalCount,
              stackDescription)
    }

    private static var diagnosticsLoggingEnabled: Bool {
        let environmentEnabled = ProcessInfo.processInfo.environment["SA_ENABLE_UI_DIAGNOSTICS"]
            .map { ($0 as NSString).boolValue } ?? false
        return environmentEnabled || UserDefaults.standard.bool(forKey: "SAEnableUIDiagnostics")
    }

    private static func normalizedReason(_ reason: String) -> String {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedReason.isEmpty ? "Unspecified DBView fallback" : trimmedReason
    }

    private static func normalizedSource(_ source: String) -> String {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSource.isEmpty ? "Unspecified DBView fallback source" : trimmedSource
    }

    private static func callSite(file: StaticString?, function: StaticString?, line: UInt?) -> String? {
        guard let file, let function, let line else { return nil }
        return "\(file):\(line) \(function)"
    }

    private static func currentStackSignature() -> String {
        return Thread.callStackSymbols
            .dropFirst(2)
            .prefix(12)
            .joined(separator: " | ")
    }

    private static func storedCounts(from defaults: UserDefaults, key: String) -> [String: Int] {
        guard let storedCounts = defaults.dictionary(forKey: key) else { return [:] }

        var counts: [String: Int] = [:]
        for (name, count) in storedCounts {
            if let count = count as? Int {
                counts[name] = count
            } else if let count = count as? NSNumber {
                counts[name] = count.intValue
            }
        }
        return counts
    }
}

@objc(SALightweightAppleScriptDocument)
final class SALightweightAppleScriptDocument: NSObject {
    private weak var windowController: SPWindowController?

    @objc init(windowController: SPWindowController) {
        self.windowController = windowController
        super.init()
    }

    @objc var name: String {
        guard let windowController, windowController.hasActiveLightweightConnection else { return "" }
        return windowController.lightweightConnectionDisplayName()
    }

    @objc var displayName: String {
        guard let windowController, windowController.hasActiveLightweightConnection else { return "" }
        return windowController.window?.title ?? name
    }

    @objc var window: NSWindow? {
        guard let windowController, windowController.hasActiveLightweightConnection else { return nil }
        return windowController.window
    }

    @objc var isUntitled: Bool {
        return windowController?.lightweightConnectionFileURL == nil
    }

    @objc var isDocumentEdited: Bool {
        return false
    }

    @objc var fileURL: URL? {
        return windowController?.lightweightConnectionFileURL
    }

    @objc var host: String {
        guard let windowController, windowController.hasActiveLightweightConnection else { return "" }
        if windowController.activeConnectionInfo?.type == .socket { return "localhost" }
        return windowController.activeConnectionInfo?.host ?? windowController.activeConnection?.host ?? ""
    }

    @objc var database: String {
        guard let windowController, windowController.hasActiveLightweightConnection else { return "" }
        return windowController.selectedDatabase ?? windowController.activeConnectionInfo?.database ?? ""
    }

    @objc var port: String {
        guard let windowController, windowController.hasActiveLightweightConnection else { return "" }
        if let port = windowController.activeConnectionInfo?.port, !port.isEmpty { return port }
        if let port = windowController.activeConnection?.port, port > 0 { return String(port) }
        return ""
    }

    @objc var mySQLVersion: String {
        guard let windowController, windowController.hasActiveLightweightConnection else { return "" }
        return windowController.activeServerVersion ?? windowController.activeConnection?.serverVersionString() ?? ""
    }

    @objc var user: String {
        guard let windowController, windowController.hasActiveLightweightConnection else { return "" }
        return windowController.activeConnectionInfo?.user ?? ""
    }

    @objc var databaseEncoding: String {
        guard let windowController, windowController.hasActiveLightweightConnection else { return "" }
        return windowController.activeConnection?.encoding() ?? ""
    }

    @objc var table: String {
        guard let windowController, windowController.hasSelectedLightweightTable else { return "" }
        return windowController.selectedTable ?? ""
    }

    @objc func tableType() -> SPTableType {
        guard let windowController, windowController.hasSelectedLightweightTable else { return SPTableTypeNone }
        switch windowController.lightweightTableTypes[windowController.selectedTable ?? ""] ?? .table {
        case .view:
            return SPTableTypeView
        case .procedure:
            return SPTableTypeProc
        case .function:
            return SPTableTypeFunc
        case .table:
            return SPTableTypeTable
        case .none:
            return SPTableTypeNone
        }
    }

    @objc var allTableNames: [String] {
        guard let windowController, windowController.hasActiveLightweightConnection else { return [] }
        return windowController.lightweightTables.filter { (windowController.lightweightTableTypes[$0] ?? .table) == .table }
    }

    @objc var tabTitleForTooltip: String {
        return displayName
    }

    @objc func connectionID() -> String {
        guard let windowController, windowController.hasActiveLightweightConnection else { return "_" }
        return windowController.lightweightNavigatorConnectionID()
    }

    @objc func parentWindowControllerWindow() -> NSWindow? {
        return window
    }

    @objc func shellVariables() -> NSDictionary {
        guard let windowController, windowController.hasActiveLightweightConnection else { return [:] }
        return windowController.lightweightShellVariables()
    }

    @objc func runningActivities() -> [Any] {
        guard windowController?.hasActiveLightweightConnection == true else { return [] }
        return (NSApp.delegate as? SPAppController)?.runningActivities() ?? []
    }

    @objc func registerActivity(_ commandDict: NSDictionary) {
        windowController?.registerActivity(commandDict)
    }

    @objc func removeRegisteredActivity(_ pid: Int) {
        windowController?.removeRegisteredActivity(pid)
    }

    @objc func setActivityPaneHidden(_ hidden: NSNumber) {
        // Lightweight windows do not use the legacy DBView activity pane; activity state
        // is still registered globally for bundle/script parity.
    }

    @objc override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let appController = NSApp.delegate as? SPAppController,
              let documents = appController.orderedDocuments() as? [AnyObject],
              let index = documents.firstIndex(where: { ($0 as? SALightweightAppleScriptDocument) === self }),
              let containerDescription = NSScriptClassDescription(for: SPAppController.self) else {
            return nil
        }

        return NSIndexSpecifier(containerClassDescription: containerDescription,
                                containerSpecifier: nil,
                                key: "orderedDocuments",
                                index: index)
    }
}

private var lightweightAppleScriptDocumentAssociationKey: UInt8 = 0

@objc extension SPWindowController {
    func lightweightAppleScriptDocumentProxy() -> SALightweightAppleScriptDocument? {
        guard hasActiveLightweightConnection else { return nil }

        if let proxy = objc_getAssociatedObject(self, &lightweightAppleScriptDocumentAssociationKey) as? SALightweightAppleScriptDocument {
            return proxy
        }

        let proxy = SALightweightAppleScriptDocument(windowController: self)
        objc_setAssociatedObject(self,
                                 &lightweightAppleScriptDocumentAssociationKey,
                                 proxy,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return proxy
    }

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

    @objc(setLightweightConnectionFileURL:)
    func setLightweightConnectionFileURL(_ url: URL?) {
        lightweightConnectionFileURL = url
        if let url {
            synchronizeLightweightDocumentScope(for: url)
        }
        if hasActiveLightweightConnection {
            updateLightweightWindowTitle()
        }
    }

    @objc(setLightweightConnectionFileURL:savedInBundle:)
    func setLightweightConnectionFileURL(_ url: URL?, savedInBundle: Bool) {
        if let url {
            synchronizeLightweightDocumentScope(for: url)
        }
        lightweightConnectionFileURL = savedInBundle ? nil : url
        if hasActiveLightweightConnection {
            updateLightweightWindowTitle()
        }
    }

    @objc func loadedDatabaseDocumentIfAvailable() -> SPDatabaseDocument? {
        return loadedDatabaseDocument
    }

    @objc func legacyDatabaseDocumentForExplicitFallback() -> SPDatabaseDocument {
        return legacyDatabaseDocumentForExplicitFallback(reason: "Objective-C compatibility fallback")
    }

    @objc(legacyDatabaseDocumentForExplicitFallbackWithReason:)
    func legacyDatabaseDocumentForExplicitFallback(reason: String) -> SPDatabaseDocument {
        return performExplicitLegacyFallback(reason: reason,
                                             selectingDatabase: selectedDatabase,
                                             item: selectedTable,
                                             source: "Objective-C explicit legacy fallback")
    }

    @objc(recordLightweightDBViewFallbackWithReason:)
    func recordLightweightDBViewFallback(reason: String) {
        recordLightweightDBViewFallback(reason: reason, source: "Objective-C diagnostic bridge")
    }

    @nonobjc func recordLightweightDBViewFallback(reason: String,
                                                  source: String,
                                                  file: StaticString = #fileID,
                                                  function: StaticString = #function,
                                                  line: UInt = #line) {
        SALightweightDBViewFallbackDiagnostics.record(reason: reason,
                                                      source: source,
                                                      file: file,
                                                      function: function,
                                                      line: line)
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

        let selectedTables = selectedLightweightTableItems()
        if let selectedTable = selectedTables.first, !selectedTable.isEmpty {
            env[SPBundleShellVariableSelectedTable] = selectedTable
            env[SPBundleShellVariableSelectedTables] = selectedTables.joined(separator: "\t")
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

    @nonobjc func activeLightweightBundleDataTableResponder() -> SPCopyTable? {
        switch activeLightweightViewMode {
        case .content:
            return lightweightContentController.lightweightBundleDataTableResponder()
        case .query:
            return lightweightQueryController.lightweightBundleDataTableResponder()
        default:
            return nil
        }
    }

    @nonobjc func runLightweightBundleTrigger(_ trigger: String, preferredDataTable: SPCopyTable? = nil) {
        guard hasActiveLightweightConnection else { return }
        guard let bundleManager = SPBundleManager.shared() else { return }
        let commands = (bundleManager.bundleCommands(forTrigger: trigger) as? [String]) ?? []
        guard !commands.isEmpty else { return }

        for commandPath in commands {
            let data = commandPath.components(separatedBy: "|")
            guard data.count > 2 else { continue }

            if !data[2].isEmpty,
               !NSApp.windows.contains(where: { window in
                   guard let htmlDelegate = window.delegate as? SABundleHTMLOutputWindowController else { return false }
                   return htmlDelegate.windowUUID == data[2]
               }) {
                continue
            }

            let menuItem = NSMenuItem()
            menuItem.tag = 0
            menuItem.toolTip = data[0]

            let scope = data.count > 1 ? data[1] : ""
            if scope == SPBundleScopeGeneral {
                _ = bundleManager.perform(Selector(("executeBundleItemForApp:")), with: menuItem)
            }
            else if scope == SPBundleScopeDataTable {
                guard let tableView = preferredDataTable
                    ?? activeLightweightBundleDataTableResponder()
                    ?? (window?.firstResponder as? SPCopyTable)
                    ?? (NSApp.keyWindow?.firstResponder as? SPCopyTable) else { continue }
                _ = tableView.perform(Selector(("executeBundleItemForDataTable:")), with: menuItem)
            }
            else if scope == SPBundleScopeInputField {
                let inputSelector = Selector(("executeBundleItemForInputField:"))
                guard let responder = (window?.firstResponder ?? NSApp.keyWindow?.firstResponder),
                      responder.responds(to: inputSelector) else { continue }
                _ = responder.perform(inputSelector, with: menuItem)
            }
        }
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

        if command == "ReloadContentTable" {
            _ = refreshActiveLightweightDetail()
            return true
        }

        if command == "ReloadTablesList" {
            refreshLightweightTables()
            return true
        }

        if command == "ReloadContentTableWithWHEREClause" {
            if let whereClause = readAndRemoveLightweightSchemeInput(processID: callbackID), !whereClause.isEmpty {
                guard selectedLightweightTableSupportsContent() else {
                    NSSound.beep()
                    return true
                }
                viewContent()
                lightweightContentController.applyAdvancedFilter(whereClause: whereClause, distinct: false)
            }
            return true
        }

        if command == "RunQueryInQueryEditor" {
            if let query = readAndRemoveLightweightSchemeInput(processID: callbackID), !query.isEmpty {
                doPerformLightweightQueryService(query)
            }
            return true
        }

        if command == "CreateSyntaxForTables" {
            writeLightweightCreateSyntaxResult(params: params, processID: callbackID)
            return true
        }

        if command == "ExecuteQuery" {
            executeLightweightSchemeQuery(params: params, processID: callbackID)
            return true
        }

        NSAlert.createWarningAlert(title: NSLocalizedString("Remote Error", comment: "remote error"),
                                   message: String(format: NSLocalizedString("URL scheme command “%@” unsupported", comment: "URL scheme command “%@” unsupported"), command),
                                   callback: nil)
        return true
    }

    private func readAndRemoveLightweightSchemeInput(processID: String) -> String? {
        let path = lightweightSchemeFilePath(prefix: SPURLSchemeQueryInputPathHeader, processID: processID)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        defer { try? FileManager.default.removeItem(atPath: path) }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    private func lightweightSchemeFilePath(prefix: String, processID: String) -> String {
        return (prefix as NSString).expandingTildeInPath + processID
    }

    private func writeLightweightCreateSyntaxResult(params: [String], processID: String) {
        let fileManager = FileManager.default
        let resultPath = lightweightSchemeFilePath(prefix: SPURLSchemeQueryResultPathHeader, processID: processID)
        let metaPath = lightweightSchemeFilePath(prefix: SPURLSchemeQueryResultMetaPathHeader, processID: processID)
        let statusPath = lightweightSchemeFilePath(prefix: SPURLSchemeQueryResultStatusPathHeader, processID: processID)
        let inputPath = lightweightSchemeFilePath(prefix: SPURLSchemeQueryInputPathHeader, processID: processID)

        try? fileManager.removeItem(atPath: resultPath)
        try? fileManager.removeItem(atPath: metaPath)
        try? fileManager.removeItem(atPath: statusPath)
        try? fileManager.removeItem(atPath: inputPath)

        let tables = params.dropFirst().filter { !$0.hasPrefix("html") }
        guard !tables.isEmpty,
              let syntax = lightweightCreateTableSyntaxes(for: Array(tables), showErrors: false) else {
            try? "1".write(toFile: statusPath, atomically: true, encoding: .utf8)
            return
        }

        try? syntax.write(toFile: resultPath, atomically: true, encoding: .utf8)
        try? "".write(toFile: metaPath, atomically: true, encoding: .utf8)
        try? "0".write(toFile: statusPath, atomically: true, encoding: .utf8)
    }

    private func executeLightweightSchemeQuery(params: [String], processID: String) {
        let fileManager = FileManager.default
        let inputPath = lightweightSchemeFilePath(prefix: SPURLSchemeQueryInputPathHeader, processID: processID)
        let resultPath = lightweightSchemeFilePath(prefix: SPURLSchemeQueryResultPathHeader, processID: processID)
        let metaPath = lightweightSchemeFilePath(prefix: SPURLSchemeQueryResultMetaPathHeader, processID: processID)
        let statusPath = lightweightSchemeFilePath(prefix: SPURLSchemeQueryResultStatusPathHeader, processID: processID)
        var status = "0"

        defer {
            do {
                try status.write(toFile: statusPath, atomically: true, encoding: .utf8)
            } catch {
                NSSound.beep()
                NSAlert.createWarningAlert(title: NSLocalizedString("BASH Error", comment: "bash error"),
                                           message: NSLocalizedString("Status file for sequelace url scheme command couldn't be written!", comment: "status file for sequelace url scheme command couldn't be written error message"),
                                           callback: nil)
            }
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            status = "1"
            return
        }

        let query = (try? String(contentsOfFile: inputPath, encoding: .utf8)) ?? ""
        try? fileManager.removeItem(atPath: inputPath)
        try? fileManager.removeItem(atPath: resultPath)
        try? fileManager.removeItem(atPath: metaPath)
        try? fileManager.removeItem(atPath: statusPath)

        guard !query.isEmpty, let connection = activeConnection else {
            status = "1"
            return
        }

        fileManager.createFile(atPath: resultPath, contents: nil)
        guard let resultHandle = FileHandle(forWritingAtPath: resultPath) else {
            NSLog("Couldn't create file handle to %@", resultPath)
            status = "1"
            return
        }
        defer { try? resultHandle.close() }

        let writeAsCSV = params.count == 2 && params[1] == "csv"
        guard let result = connection.streamingQueryString(query) else {
            status = "1"
            return
        }
        result.defaultRowReturnType = SPMySQLResultRowAsArray
        result.returnDataAsStrings = true

        if connection.queryErrored() {
            writeLightweightSchemeString("MySQL said: \(connection.lastErrorMessage() ?? "")", to: resultHandle)
            status = "1"
            return
        }

        let fieldNames = result.fieldNames() as? [String] ?? []
        let header = writeAsCSV ? fieldNames.map { csvEscapedLightweightSchemeValue($0) }.joined(separator: ",") : fieldNames.joined(separator: "\t")
        writeLightweightSchemeString(header + "\n", to: resultHandle)
        writeLightweightSchemeMetaData(from: result, to: metaPath)

        while let row = result.getRowAsArray() {
            let values = row.map { value in
                writeAsCSV ? csvLightweightSchemeValue(value, connection: connection) : tabLightweightSchemeValue(value, connection: connection)
            }
            writeLightweightSchemeString(values.joined(separator: writeAsCSV ? "," : "\t") + "\n", to: resultHandle)
        }
    }

    private func writeLightweightSchemeMetaData(from result: SPMySQLResult, to path: String) {
        let definitions = result.fieldDefinitions() as? [NSDictionary] ?? []
        let lines = definitions.map { definition -> String in
            let type = stringForLightweightSchemeMetaValue(definition["type"])
            let typeGrouping = stringForLightweightSchemeMetaValue(definition["typegrouping"])
            let charLength = stringForLightweightSchemeMetaValue(definition["char_length"])
            let unsigned = stringForLightweightSchemeMetaValue(definition["UNSIGNED_FLAG"])
            let autoIncrement = stringForLightweightSchemeMetaValue(definition["AUTO_INCREMENT_FLAG"])
            let primary = stringForLightweightSchemeMetaValue(definition["PRI_KEY_FLAG"])
            return [type, typeGrouping, charLength, unsigned, autoIncrement, primary].joined(separator: "\t")
        }
        try? (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func stringForLightweightSchemeMetaValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return String(describing: value)
    }

    private func writeLightweightSchemeString(_ string: String, to handle: FileHandle) {
        if let data = string.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    private func csvLightweightSchemeValue(_ value: Any, connection: SPMySQLConnection) -> String {
        if value is NSNull {
            return "\"NULL\""
        }
        return csvEscapedLightweightSchemeValue(lightweightSchemeDisplayString(for: value, connection: connection))
    }

    private func csvEscapedLightweightSchemeValue(_ value: String) -> String {
        return SALightweightResultGrid.csvEscaped(value)
    }

    private func tabLightweightSchemeValue(_ value: Any, connection: SPMySQLConnection) -> String {
        if value is NSNull {
            return "NULL"
        }
        return lightweightSchemeDisplayString(for: value, connection: connection)
            .replacingOccurrences(of: "\n", with: "↵")
            .replacingOccurrences(of: "\t", with: "⇥")
    }

    private func lightweightSchemeDisplayString(for value: Any, connection: SPMySQLConnection) -> String {
        if let geometry = value as? SPMySQLGeometryData {
            return geometry.wktString() ?? ""
        }
        if let data = value as? Data {
            let encoding = String.Encoding(rawValue: UInt(connection.stringEncoding()))
            return String(data: data, encoding: encoding) ?? String(data: data, encoding: .ascii) ?? ""
        }
        return String(describing: value)
    }

    @objc func doPerformLightweightQueryService(_ query: String) {
        guard hasActiveLightweightConnection else { return }

        viewQuery()
        lightweightQueryController.doPerformQueryService(query)
    }

    @objc func doPerformLightweightLoadQueryService(_ query: String) {
        guard hasActiveLightweightConnection else { return }

        lightweightQueryController.setSQLFile(url: nil, encoding: nil)
        viewQuery()
        lightweightQueryController.doPerformLoadQueryService(query)
    }

    @objc(doPerformLightweightLoadQueryService:fileURL:encoding:)
    func doPerformLightweightLoadQueryService(_ query: String, fileURL: URL?, encoding: UInt) {
        guard hasActiveLightweightConnection else { return }

        lightweightQueryController.setSQLFile(url: fileURL, encoding: String.Encoding(rawValue: encoding))
        viewQuery()
        lightweightQueryController.doPerformLoadQueryService(query)
    }

    @objc(queueLightweightSQLFileOpenWithString:fileURL:encoding:)
    func queueLightweightSQLFileOpen(query: String, fileURL: URL, encoding: UInt) {
        guard loadedDatabaseDocument == nil else { return }

        pendingLightweightSQLFileOpen = SALightweightPendingSQLFileOpen(query: query,
                                                                        fileURL: fileURL,
                                                                        encoding: String.Encoding(rawValue: encoding))
        lightweightQueryController.setSQLFile(url: fileURL, encoding: String.Encoding(rawValue: encoding))
    }

    private func activeLightweightTextCopyResponder(for menuItem: NSMenuItem?) -> NSTextView? {
        guard menuItem?.tag ?? 0 == 0 else { return nil }
        guard let textView = window?.firstResponder as? NSTextView else { return nil }
        return textView
    }

    @objc func canCopyActiveLightweightSelection(_ menuItem: NSMenuItem?) -> Bool {
        guard hasActiveLightweightConnection else { return false }

        if let textView = activeLightweightTextCopyResponder(for: menuItem) {
            return textView.selectedRange().length > 0
        }

        switch activeLightweightViewMode {
        case .content:
            return lightweightContentController.canCopySelectedContentRows(menuItem)
        case .query:
            return lightweightQueryController.canCopySelectedResultRows(menuItem)
        default:
            return false
        }
    }

    @objc func validateLightweightContentRowMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard loadedDatabaseDocument == nil,
              activeLightweightDetailKey?.viewMode == .content else { return false }

        return lightweightContentController.validateMenuItem(menuItem)
    }

    @objc func addRow(_ sender: Any?) {
        guard loadedDatabaseDocument == nil,
              activeLightweightDetailKey?.viewMode == .content else { return }

        lightweightContentController.addRow(sender)
    }

    @objc func duplicateRow(_ sender: Any?) {
        guard loadedDatabaseDocument == nil,
              activeLightweightDetailKey?.viewMode == .content else { return }

        lightweightContentController.duplicateRow(sender)
    }

    @objc func removeRow(_ sender: Any?) {
        guard loadedDatabaseDocument == nil,
              activeLightweightDetailKey?.viewMode == .content else { return }

        lightweightContentController.removeRow(sender)
    }

    @objc func copyActiveLightweightSelection(_ sender: Any?) {
        guard hasActiveLightweightConnection else { return }

        if let textView = activeLightweightTextCopyResponder(for: sender as? NSMenuItem) {
            textView.copy(sender)
            return
        }

        switch activeLightweightViewMode {
        case .content:
            lightweightContentController.copySelectedContentRowsForMenu(sender)
        case .query:
            lightweightQueryController.copy(sender)
        default:
            NSSound.beep()
        }
    }

    @objc func canExportLightweightData() -> Bool {
        guard hasActiveLightweightConnection else { return false }

        if hasActiveLightweightResultExportData() {
            return true
        }

        return !lightweightTableExportItemsForMainMenu().isEmpty
    }

    @nonobjc private func hasActiveLightweightResultExportData() -> Bool {
        switch activeLightweightViewMode {
        case .content:
            return lightweightContentController.exportResultColumnCount() > 0
        case .query:
            return lightweightQueryController.exportResultColumnCount() > 0
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
              canExportLightweightData() else {
            NSSound.beep()
            return
        }

        if hasActiveLightweightResultExportData() {
            guard let controller = configuredActiveLightweightResultExportController() else {
                NSSound.beep()
                return
            }

            lightweightExportController = controller
            controller.exportData()
            return
        }

        if let controller = configuredLightweightTableExportControllerForMainMenu() {
            lightweightExportController = controller
            controller.exportData()
            return
        }

        NSSound.beep()
    }

    @nonobjc private func configuredActiveLightweightResultExportController() -> SPExportController? {
        let filteredSource = SALightweightExportSource.filteredResult
        let querySource = SALightweightExportSource.queryResult
        let source: SPExportSource = (activeLightweightViewMode == .content) ? filteredSource : querySource
        let isContentExport = source == filteredSource
        let isQueryExport = source == querySource
        let contentResult = isContentExport ? lightweightContentController.exportDataResult(withNULLs: true) : []
        let queryResult = isQueryExport ? lightweightQueryController.exportDataResult(withNULLs: true, truncateDataFields: false) : []
        guard let controller = configuredLightweightExportController(preferredSource: source,
                                                                     selectedTableItems: selectedTable.map { [$0] } ?? [],
                                                                     contentResult: contentResult,
                                                                     contentQuery: isContentExport ? lightweightContentController.exportUsedQuery() : "",
                                                                     queryResult: queryResult,
                                                                     queryString: isQueryExport ? lightweightQueryController.exportUsedQuery() : "") else {
            return nil
        }

        return controller
    }

    @nonobjc private func configuredLightweightTableExportControllerForMainMenu() -> SPExportController? {
        let selectedItems = lightweightTableExportItemsForMainMenu()
        guard !selectedItems.isEmpty else { return nil }

        let tableNames = selectedItems.filter { item in
            let type = lightweightTableTypes[item] ?? .table
            return type == .table || type == .view
        }
        let procedureNames = selectedItems.filter { lightweightTableTypes[$0] == .procedure }
        let functionNames = selectedItems.filter { lightweightTableTypes[$0] == .function }

        return configuredLightweightExportController(preferredSource: SALightweightExportSource.tableExport,
                                                     selectedTableItems: selectedItems,
                                                     tableNames: tableNames,
                                                     procedureNames: procedureNames,
                                                     functionNames: functionNames)
    }

    @nonobjc private func lightweightTableExportItemsForMainMenu() -> [String] {
        guard selectedDatabase?.isEmpty == false else { return [] }

        let selectedItems = selectedLightweightTableItems().filter { canExportLightweightTableItem($0) }
        if !selectedItems.isEmpty {
            return selectedItems
        }

        return lightweightTables.filter { canExportLightweightTableItem($0) }
    }

    @nonobjc private func canExportLightweightTableItem(_ item: String) -> Bool {
        switch lightweightTableTypes[item] ?? .table {
        case .table, .view, .procedure, .function:
            return true
        case .none:
            return false
        }
    }

    @nonobjc func configuredLightweightExportController(preferredSource source: SPExportSource,
                                                        selectedTableItems selectedTables: [String],
                                                        contentResult: [[Any]] = [],
                                                        contentQuery: String = "",
                                                        queryResult: [[Any]] = [],
                                                        queryString: String = "",
                                                        tableNames: [String]? = nil,
                                                        procedureNames: [String]? = nil,
                                                        functionNames: [String]? = nil) -> SPExportController? {
        guard hasActiveLightweightConnection,
              let activeConnection = activeConnection else {
            return nil
        }

        let tablesAndViews = lightweightTables.filter { table in
            let type = lightweightTableTypes[table] ?? .table
            return type == .table || type == .view
        }
        let procedures = lightweightTables.filter { lightweightTableTypes[$0] == .procedure }
        let functions = lightweightTables.filter { lightweightTableTypes[$0] == .function }
        let controller = SPExportController()

        let database = selectedDatabase ?? ""
        let host = activeConnection.host ?? activeConnectionInfo?.host ?? ""
        let serverVersion = activeServerVersion ?? ""
        let selectedTableName = selectedTable ?? ""
        let favoriteName = activeConnectionName ?? lightweightConnectionDisplayName()

        controller.configure(forLightweightWindowController: self,
                             connection: activeConnection,
                             serverSupport: nil,
                             database: database,
                             host: host,
                             serverVersion: serverVersion,
                             selectedTableName: selectedTableName,
                             favoriteName: favoriteName,
                             tablesAndViewNames: tableNames ?? tablesAndViews,
                             procedureNames: procedureNames ?? procedures,
                             functionNames: functionNames ?? functions,
                             selectedTableItems: selectedTables,
                             contentResult: contentResult,
                             contentQuery: contentQuery,
                             queryResult: queryResult,
                             queryString: queryString,
                             preferredSource: source)

        return controller
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

    @objc(importLightweightSQLFileAtURL:encoding:)
    func importLightweightSQLFile(at url: URL, encoding encodingNumber: NSNumber?) {
        guard canImportLightweightSQL() else {
            showLightweightImportUnavailableReason()
            return
        }

        let encoding: String.Encoding
        if let encodingNumber = encodingNumber {
            encoding = String.Encoding(rawValue: encodingNumber.uintValue)
            UserDefaults.standard.set(encodingNumber.uintValue, forKey: SPLastSQLFileEncoding)
        } else {
            let savedEncoding = UserDefaults.standard.integer(forKey: SPLastSQLFileEncoding)
            encoding = String.Encoding(rawValue: UInt(savedEncoding))
        }

        startLightweightImport(url: url, encoding: encoding)
    }

    @objc func importLightweightSQLFile(_ sender: Any?) {
        guard canImportLightweightSQL() else {
            showLightweightImportUnavailableReason()
            return
        }

        presentLightweightImportOpenPanel(initialURL: nil)
    }

    @nonobjc func presentLightweightImportOpenPanel(initialURL: URL?, csvSettings: SALightweightCSVImportSettings? = nil) {
        let prefs = UserDefaults.standard
        let selectedEncoding = String.Encoding(rawValue: UInt(prefs.integer(forKey: SPLastSQLFileEncoding)))
        let importAccessory = SALightweightImportOpenPanelAccessory(selectedEncoding: selectedEncoding, initialURL: initialURL)
        if let csvSettings {
            csvSettings.save(to: prefs)
            importAccessory.csvAccessory.updateUI(with: csvSettings)
        }

        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.allowedFileTypes = [
            SPFileExtensionSQL as String,
            "sql.gz",
            "sql.bz2",
            "csv",
            "csv.gz",
            "csv.bz2",
            "tsv",
            "tsv.gz",
            "tsv.bz2"
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.delegate = importAccessory
        panel.accessoryView = importAccessory.view
        panel.message = NSLocalizedString("Choose a SQL, CSV, or TSV file for lightweight import.", comment: "lightweight import panel message")

        if let initialURL {
            panel.directoryURL = initialURL.deletingLastPathComponent()
            panel.nameFieldStringValue = initialURL.lastPathComponent
        } else if let openPath = prefs.string(forKey: "exportPath"), !openPath.isEmpty {
            panel.directoryURL = URL(string: openPath) ?? URL(fileURLWithPath: openPath)
        }

        panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSWindow()) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }

            prefs.set(panel.directoryURL?.path, forKey: "exportPath")
            prefs.set(importAccessory.selectedEncoding.rawValue, forKey: SPLastSQLFileEncoding)

            switch importAccessory.importFileKind(for: url) {
            case .sql:
                self.startLightweightImport(url: url,
                                            encoding: importAccessory.selectedEncoding,
                                            importKind: .sql,
                                            sourceName: url.lastPathComponent)
            case .csv:
                do {
                    let csvURL = importAccessory.needsTemporaryCSVImportCopy(for: url)
                        ? try self.copyLightweightImportFileToTemporaryURL(url, fileExtension: importAccessory.temporaryCSVFileExtension(for: url))
                        : url
                    let csvSettings = importAccessory.saveCSVSettings(for: url)
                    self.startLightweightImport(url: csvURL,
                                                encoding: importAccessory.selectedEncoding,
                                                csvSettings: csvSettings,
                                                importKind: .csv,
                                                sourceName: url.lastPathComponent,
                                                sourceReturnURL: csvURL == url ? nil : url)
                } catch {
                    NSSound.beep()
                    self.showLightweightError(title: NSLocalizedString("Import Error", comment: "Import Error title"),
                                              message: String(format: NSLocalizedString("The selected file could not be prepared for lightweight CSV/TSV import. %@", comment: "lightweight import manual format temp copy error"), error.localizedDescription))
                }
            case .none:
                _ = self.validateLightweightImportFileURL(url)
            }
        }
    }

    @objc func importLightweightSQLFromClipboard(_ sender: Any?) {
        importLightweightSQLFromClipboard(sender, csvSettings: nil, preferredDelimitedKind: nil)
    }

    @nonobjc func importLightweightSQLFromClipboard(_ sender: Any?,
                                                    csvSettings: SALightweightCSVImportSettings?,
                                                    preferredDelimitedKind: LightweightClipboardImportKind?) {
        guard canImportLightweightSQL() else {
            showLightweightImportUnavailableReason()
            return
        }

        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            showLightweightError(title: NSLocalizedString("Import From Clipboard", comment: "import from clipboard title"),
                                 message: NSLocalizedString("The clipboard does not contain text to import.", comment: "lightweight import clipboard empty message"))
            return
        }

        let importKind = preferredDelimitedKind ?? lightweightClipboardImportKind(for: clipboardText)
        switch importKind {
        case .csv, .tsv:
            startLightweightCSVImportFromClipboard(clipboardText, kind: importKind, initialSettings: csvSettings)
            return
        case .cancel:
            return
        case .sql:
            break
        }

        let clipboardSourceName = NSLocalizedString("clipboard", comment: "clipboard import source name")
        guard confirmLightweightSQLImport(sourceName: clipboardSourceName) else { return }
        do {
            let temporaryURL = try writeLightweightSQLClipboardTemporaryFile(clipboardText)
            startLightweightSQLImport(url: temporaryURL,
                                      encoding: .utf8,
                                      sourceName: clipboardSourceName,
                                      removeTemporaryFileWhenFinished: true)
        } catch {
            NSSound.beep()
            showLightweightError(title: NSLocalizedString("Import From Clipboard", comment: "import from clipboard title"),
                                 message: String(format: NSLocalizedString("The clipboard text could not be written to a temporary SQL import file. %@", comment: "lightweight SQL clipboard temp write failure"), error.localizedDescription))
        }
    }

    @nonobjc func lightweightClipboardImportKind(for text: String) -> LightweightClipboardImportKind {
        if lightweightClipboardLooksLikeSQL(text) {
            return .sql
        }

        guard let delimitedKind = lightweightDelimitedClipboardImportKind(for: text) else {
            return .sql
        }

        return promptLightweightClipboardImportKind(suggestedKind: delimitedKind)
    }

    @nonobjc func lightweightDelimitedClipboardImportKind(for text: String) -> LightweightClipboardImportKind? {
        let rows = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(20)

        guard !rows.isEmpty else { return nil }

        let tabCounts = rows.map { row in row.filter { $0 == "\t" }.count }
        let commaCounts = rows.map { row in lightweightClipboardCommaCount(in: row) }
        let tabScore = lightweightDelimiterScore(tabCounts)
        let commaScore = lightweightDelimiterScore(commaCounts)

        guard tabScore > 0 || commaScore > 0 else { return nil }
        return tabScore >= commaScore ? .tsv : .csv
    }

    @nonobjc func lightweightDelimiterScore(_ counts: [Int]) -> Int {
        let positiveCounts = counts.filter { $0 > 0 }
        guard !positiveCounts.isEmpty else { return 0 }

        if positiveCounts.count >= 2 {
            let consistencyBonus = Set(positiveCounts).count == 1 ? positiveCounts.count : 0
            return positiveCounts.reduce(0, +) + consistencyBonus
        }

        return positiveCounts[0] >= 2 ? positiveCounts[0] : 0
    }

    @nonobjc func lightweightClipboardCommaCount(in row: String) -> Int {
        var count = 0
        var inQuotes = false

        for character in row {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == "," && !inQuotes {
                count += 1
            }
        }

        return count
    }

    @nonobjc func lightweightClipboardLooksLikeSQL(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }

        let lowercasedText = trimmedText.lowercased()
        if lowercasedText.hasPrefix("-- mysql dump")
            || lowercasedText.hasPrefix("/*")
            || lowercasedText.hasPrefix("/*!") {
            return true
        }

        let sqlKeywords: Set<String> = [
            "alter", "begin", "call", "commit", "create", "delete", "delimiter",
            "describe", "drop", "explain", "grant", "insert", "lock", "replace",
            "revoke", "select", "set", "show", "truncate", "unlock", "update", "use"
        ]

        let lines = trimmedText.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("--") || line.hasPrefix("#") {
                continue
            }

            let token = line
                .split { character in
                    character.isWhitespace || character == "(" || character == ";" || character == ","
                }
                .first?
                .lowercased() ?? ""

            return sqlKeywords.contains(token)
        }

        return false
    }

    @nonobjc func promptLightweightClipboardImportKind(suggestedKind: LightweightClipboardImportKind) -> LightweightClipboardImportKind {
        let suggestedTitle = suggestedKind == .tsv
            ? NSLocalizedString("Import as TSV", comment: "lightweight clipboard import as TSV button")
            : NSLocalizedString("Import as CSV", comment: "lightweight clipboard import as CSV button")
        let suggestedDescription = suggestedKind == .tsv
            ? NSLocalizedString("The clipboard text looks tab-separated. Import it with the lightweight CSV/TSV importer, or treat it as SQL?", comment: "lightweight clipboard TSV prompt")
            : NSLocalizedString("The clipboard text looks comma-separated. Import it with the lightweight CSV/TSV importer, or treat it as SQL?", comment: "lightweight clipboard CSV prompt")

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Import From Clipboard", comment: "import from clipboard title")
        alert.informativeText = suggestedDescription
        alert.addButton(withTitle: suggestedTitle)
        alert.addButton(withTitle: NSLocalizedString("Import as SQL", comment: "lightweight clipboard import as SQL button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        switch runLightweightModalAlert(alert) {
        case .alertFirstButtonReturn:
            return suggestedKind
        case .alertSecondButtonReturn:
            return .sql
        default:
            return .cancel
        }
    }

    @nonobjc func startLightweightCSVImportFromClipboard(_ text: String,
                                                         kind: LightweightClipboardImportKind,
                                                         initialSettings: SALightweightCSVImportSettings? = nil) {
        let fileExtension = kind == .tsv ? "tsv" : "csv"
        let clipboardSourceName = NSLocalizedString("clipboard", comment: "clipboard import source name")

        do {
            let temporaryURL = try writeLightweightClipboardImportTemporaryFile(text,
                                                                               fileExtension: fileExtension)
            let settings = initialSettings ?? SALightweightCSVImportSettings.load(inferringFrom: temporaryURL)
            guard let confirmedSettings = confirmLightweightClipboardCSVImportSettings(kind: kind,
                                                                                       settings: settings) else {
                try? FileManager.default.removeItem(at: temporaryURL)
                return
            }

            let didStart = startLightweightCSVImport(url: temporaryURL,
                                                     settings: confirmedSettings,
                                                     sourceName: clipboardSourceName)
            if !didStart {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        } catch {
            NSSound.beep()
            showLightweightError(title: NSLocalizedString("Import From Clipboard", comment: "import from clipboard title"),
                                 message: String(format: NSLocalizedString("The clipboard text could not be written to a temporary CSV/TSV import file. %@", comment: "lightweight clipboard temp write failure"), error.localizedDescription))
        }
    }

    @nonobjc func writeLightweightClipboardImportTemporaryFile(_ text: String, fileExtension: String) throws -> URL {
        let prefixPath = (SPImportClipboardTempFileNamePrefix as NSString).expandingTildeInPath
        let directoryPath = (prefixPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directoryPath,
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        let filePath = "\(prefixPath)\(UUID().uuidString).\(fileExtension)"
        let fileURL = URL(fileURLWithPath: filePath)
        let preferredEncoding = activeConnection.map { String.Encoding(rawValue: UInt($0.stringEncoding())) } ?? .utf8

        do {
            try text.write(to: fileURL, atomically: false, encoding: preferredEncoding)
        } catch {
            try text.write(to: fileURL, atomically: false, encoding: .utf8)
        }

        return fileURL
    }

    @nonobjc func writeLightweightSQLClipboardTemporaryFile(_ text: String) throws -> URL {
        let prefixPath = (SPImportClipboardTempFileNamePrefix as NSString).expandingTildeInPath
        let directoryPath = (prefixPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directoryPath,
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        let filePath = "\(prefixPath)\(UUID().uuidString).sql"
        let fileURL = URL(fileURLWithPath: filePath)
        try text.write(to: fileURL, atomically: false, encoding: .utf8)
        return fileURL
    }

    @nonobjc func copyLightweightImportFileToTemporaryURL(_ url: URL, fileExtension: String) throws -> URL {
        let prefixPath = (SPImportClipboardTempFileNamePrefix as NSString).expandingTildeInPath
        let directoryPath = (prefixPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directoryPath,
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        let filePath = "\(prefixPath)\(UUID().uuidString).\(fileExtension)"
        let temporaryURL = URL(fileURLWithPath: filePath)
        try FileManager.default.copyItem(at: url, to: temporaryURL)
        return temporaryURL
    }

    @nonobjc func confirmLightweightClipboardCSVImportSettings(kind: LightweightClipboardImportKind,
                                                               settings: SALightweightCSVImportSettings) -> SALightweightCSVImportSettings? {
        let csvAccessory = SALightweightCSVImportAccessory()
        csvAccessory.updateUI(with: settings)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("CSV/TSV Import Options", comment: "lightweight clipboard CSV settings title")
        alert.informativeText = kind == .tsv
            ? NSLocalizedString("Review the tab-separated clipboard import settings before field mapping.", comment: "lightweight clipboard TSV settings message")
            : NSLocalizedString("Review the comma-separated clipboard import settings before field mapping.", comment: "lightweight clipboard CSV settings message")
        alert.accessoryView = csvAccessory.rootView
        alert.addButton(withTitle: NSLocalizedString("Continue", comment: "continue button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard runLightweightModalAlert(alert) == .alertFirstButtonReturn else { return nil }
        return csvAccessory.saveSettings()
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
        let fileExtension = isSessionSave ? (SPBundleFileExtension as String) : (SPFileExtensionDefault as String)
        if let contentType = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [contentType]
        }

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
        case .vault:
            let vaultPort = info.vaultPort.isEmpty ? "443" : info.vaultPort
            return "\(user)@\(info.host)\(port)&Vault:\(info.vaultHost):\(vaultPort):\(info.vaultOIDCMount)/\(info.vaultCredentialsPath)"
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

    func refreshLightweightMetadataAfterQueryMutation(_ queries: [String]) {
        if let document = loadedDatabaseDocument {
            document.setDatabases()
            document.refreshTables()
            return
        }

        guard activeConnection != nil else { return }

        let usedDatabase = lightweightDatabaseNameFromUseQueries(queries)
        let droppedDatabases = lightweightDroppedDatabaseNames(from: queries)
        if let removedCurrentDatabase = [usedDatabase, selectedDatabase].compactMap({ $0 }).first(where: { lightweightDatabase($0, isIn: droppedDatabases) }) {
            clearLightweightDatabaseSelection(afterRemoving: removedCurrentDatabase)
            refreshLightweightQueryCompletionMetadataFromCurrentState()
            return
        }

        if !droppedDatabases.isEmpty {
            lightweightDatabases.removeAll { lightweightDatabase($0, isIn: droppedDatabases) }
            databaseToolbarController.reloadDatabases(lightweightDatabases, selectedDatabase: selectedDatabase)
            databaseListNeedsLoad = true
            requestLightweightDatabases(forceReload: true)
            refreshLightweightQueryCompletionMetadataFromCurrentState()
            return
        }

        lightweightStructureController.clearCachedTables()
        lightweightContentController.clearCachedTables()
        databaseListNeedsLoad = true
        requestLightweightDatabases(forceReload: true)

        let databaseToLoad = usedDatabase ?? selectedDatabase
        if let usedDatabase, !usedDatabase.isEmpty {
            selectLightweightDatabaseInToolbar(usedDatabase)
        }

        if let databaseToLoad, !databaseToLoad.isEmpty {
            loadTables(for: databaseToLoad, preservingSelection: usedDatabase == nil)
        } else {
            refreshLightweightQueryCompletionMetadataFromCurrentState()
        }
    }

    func refreshLightweightQueryCompletionMetadataFromCurrentState() {
        let fieldNames = selectedDatabase.flatMap { database in
            selectedTable.flatMap { table in
                lightweightStructureController.cachedColumnMetadata(for: table, database: database)
            }
        }?.compactMap { $0["name"] } ?? []

        lightweightQueryController.updateCompletionMetadata(database: selectedDatabase,
                                                          table: selectedTable,
                                                          databases: lightweightDatabases,
                                                          tables: lightweightTables,
                                                          tableTypes: lightweightTableTypes,
                                                          fieldNames: fieldNames)
    }

    func lightweightDatabaseNameFromUseQueries(_ queries: [String]) -> String? {
        for query in queries.reversed() {
            if let database = lightweightDatabaseNameFromUseQuery(query) {
                return database
            }
        }

        return nil
    }

    func lightweightDatabaseNameFromUseQuery(_ query: String) -> String? {
        let sql = lightweightSQLWithoutLeadingComments(query)

        guard let match = sql.range(of: #"(?i)^USE\s+(`(?:``|[^`])+`|[^\s;]+)"#, options: .regularExpression) else { return nil }

        var database = String(sql[match])
        guard let useRange = database.range(of: #"(?i)^USE\s+"#, options: .regularExpression) else { return nil }
        database.removeSubrange(useRange)

        return lightweightDatabaseName(fromIdentifier: database)
    }

    func lightweightDroppedDatabaseNames(from queries: [String]) -> [String] {
        return queries.compactMap { lightweightDroppedDatabaseName(from: $0) }
    }

    func lightweightDroppedDatabaseName(from query: String) -> String? {
        let sql = lightweightSQLWithoutLeadingComments(query)

        guard let match = sql.range(of: #"(?i)^DROP\s+(?:DATABASE|SCHEMA)\s+(?:IF\s+EXISTS\s+)?(`(?:``|[^`])+`|[^\s;]+)"#, options: .regularExpression) else { return nil }

        var database = String(sql[match])
        guard let dropRange = database.range(of: #"(?i)^DROP\s+(?:DATABASE|SCHEMA)\s+(?:IF\s+EXISTS\s+)?"#, options: .regularExpression) else { return nil }
        database.removeSubrange(dropRange)

        return lightweightDatabaseName(fromIdentifier: database)
    }

    func lightweightSQLWithoutLeadingComments(_ query: String) -> String {
        var sql = query.trimmingCharacters(in: .whitespacesAndNewlines)

        while !sql.isEmpty {
            if sql.hasPrefix("--") || sql.hasPrefix("#") {
                guard let newline = sql.firstIndex(of: "\n") else { return "" }
                sql = String(sql[sql.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if sql.hasPrefix("/*") {
                guard let end = sql.range(of: "*/") else { return "" }
                sql = String(sql[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            break
        }

        return sql
    }

    func lightweightDatabaseName(fromIdentifier identifier: String) -> String {
        var database = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if database.hasPrefix("`"), database.hasSuffix("`"), database.count >= 2 {
            database.removeFirst()
            database.removeLast()
            return database.replacingOccurrences(of: "``", with: "`")
        }

        return database.trimmingCharacters(in: CharacterSet(charactersIn: ";"))
    }

    func lightweightDatabase(_ database: String, isIn databases: [String]) -> Bool {
        return databases.contains { $0.caseInsensitiveCompare(database) == .orderedSame }
    }

    @objc func canRefreshActiveLightweightDetail() -> Bool {
        guard activeConnection != nil,
              loadedDatabaseDocument == nil,
              selectedDatabase != nil,
              selectedTable != nil else { return false }

        switch activeLightweightViewMode {
        case .structure, .content, .status, .relations, .triggers:
            return true
        case .query:
            return false
        }
    }

    @objc @discardableResult func refreshActiveLightweightDetail() -> Bool {
        guard canRefreshActiveLightweightDetail() else { return false }

        switch activeLightweightViewMode {
        case .structure:
            lightweightStructureController.refreshActiveStructureDetail()
        case .content:
            lightweightContentController.refreshActiveContentDetail()
        case .status:
            lightweightTableInfoController.refreshActiveTableInfoDetail()
        case .relations:
            lightweightRelationsController.refreshActiveRelationsDetail()
        case .triggers:
            lightweightTriggersController.refreshActiveTriggersDetail()
        case .query:
            return false
        }

        return true
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
        if let document = loadedDatabaseDocument {
            document.viewStructure()
            return
        }

        if activeConnection != nil, loadedDatabaseDocument == nil {
            guard let selectedTable = selectedTable else { return }

            showLightweightStructure(for: selectedTable)
            return
        }
    }

    @objc func viewContent() {
        if let document = loadedDatabaseDocument {
            document.viewContent()
            return
        }

        if activeConnection != nil, loadedDatabaseDocument == nil {
            guard let selectedTable = selectedTable else { return }

            guard selectedLightweightTableSupportsContent() else {
                showLightweightStatus(for: selectedTable)
                return
            }
            showLightweightContent(for: selectedTable)
            return
        }
    }

    @objc func viewQuery() {
        if let document = loadedDatabaseDocument {
            document.viewQuery()
            return
        }

        if activeConnection != nil, loadedDatabaseDocument == nil {
            showLightweightQuery()
            return
        }
    }

    @objc func viewStatus() {
        if let document = loadedDatabaseDocument {
            document.viewStatus()
            return
        }

        if activeConnection != nil, loadedDatabaseDocument == nil {
            guard let selectedTable = selectedTable else { return }

            showLightweightStatus(for: selectedTable)
            return
        }
    }

    @objc func viewRelations() {
        if let document = loadedDatabaseDocument {
            document.viewRelations()
            return
        }

        if activeConnection != nil, loadedDatabaseDocument == nil {
            guard let selectedTable = selectedTable else { return }

            showLightweightRelations(for: selectedTable)
            return
        }
    }

    @objc func viewTriggers() {
        if let document = loadedDatabaseDocument {
            document.viewTriggers()
            return
        }

        if activeConnection != nil, loadedDatabaseDocument == nil {
            guard let selectedTable = selectedTable else { return }

            showLightweightTriggers(for: selectedTable)
            return
        }
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

    @objc func performActiveLightweightFindPanelAction(_ sender: Any?) {
        guard activeConnection != nil, loadedDatabaseDocument == nil else { return }

        switch activeLightweightViewMode {
        case .content:
            lightweightContentController.focusRowFilter()
        case .query:
            lightweightQueryController.performFindPanelAction(sender)
        default:
            if let textView = window?.firstResponder as? NSTextView {
                textView.performFindPanelAction(sender)
            } else {
                NSSound.beep()
            }
        }
    }

    @objc func performActiveLightweightTextFinderAction(_ sender: Any?) {
        guard activeConnection != nil, loadedDatabaseDocument == nil else { return }

        switch activeLightweightViewMode {
        case .query:
            lightweightQueryController.performLightweightTextFinderAction(sender)
        default:
            if let textView = window?.firstResponder as? NSTextView {
                textView.performTextFinderAction(sender)
            } else {
                NSSound.beep()
            }
        }
    }

    @objc func focusLightweightContentFilter() {
        guard activeConnection != nil, loadedDatabaseDocument == nil, let selectedTable = selectedTable else { return }
        guard selectedLightweightTableSupportsContent() else {
            NSSound.beep()
            return
        }

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
        guard selectedLightweightTableSupportsContent() else {
            NSSound.beep()
            return
        }

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

    @nonobjc private func canHandleLightweightMenuSelector(requiresDatabase: Bool = false, requiresTable: Bool = false) -> Bool {
        guard hasActiveLightweightConnection else { return false }
        if requiresDatabase, !hasSelectedLightweightDatabase { return false }
        if requiresTable, !hasSelectedLightweightTable { return false }
        return true
    }

    @nonobjc func lightweightObjectTypeSupportsContent(_ objectType: SALightweightTableObjectType) -> Bool {
        return objectType == .table || objectType == .view
    }

    @nonobjc func selectedLightweightTableSupportsContent() -> Bool {
        guard let selectedTable = selectedTable else { return false }
        return lightweightObjectTypeSupportsContent(lightweightTableTypes[selectedTable] ?? .table)
    }

    @objc(import:) func importMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresDatabase: true) else { return }
        importLightweightSQLFile(sender)
    }

    @objc(importFromClipboard:) func importFromClipboardMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresDatabase: true) else { return }
        importLightweightSQLFromClipboard(sender)
    }

    @objc(export:) func exportMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        exportData()
    }

    @objc(printDocument:) func printDocumentMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        if activeLightweightViewMode == .query {
            lightweightQueryController.printDocument(sender)
            return
        }
        printLightweightDocument(sender)
    }

    @objc(copy:) func copyMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        copyActiveLightweightSelection(sender)
    }

    @objc(saveConnectionSheet:) func saveConnectionSheetMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        saveLightweightConnectionSheet(sender)
    }

    @objc(addConnectionToFavorites:) func addConnectionToFavoritesMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        addLightweightConnectionToFavorites()
    }

    @objc(showGotoDatabase:) func showGotoDatabaseMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        showLegacyGotoDatabase()
    }

    @objc(addDatabase:) func addDatabaseMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        addLightweightDatabase(sender)
    }

    @objc(removeDatabase:) func removeDatabaseMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresDatabase: true) else { return }
        removeLightweightDatabase(sender)
    }

    @objc(copyDatabase:) func copyDatabaseMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresDatabase: true) else { return }
        copyLightweightDatabase(sender)
    }

    @objc(renameDatabase:) func renameDatabaseMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresDatabase: true) else { return }
        renameLightweightDatabase(sender)
    }

    @objc(alterDatabase:) func alterDatabaseMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresDatabase: true) else { return }
        alterLightweightDatabase(sender)
    }

    @objc(refreshTables:) func refreshTablesMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresDatabase: true) else { return }
        refreshLightweightTables()
    }

    @objc(flushPrivileges:) func flushPrivilegesMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        flushLightweightPrivileges(sender)
    }

    @objc(setDatabases:) func setDatabasesMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        refreshLightweightDatabases()
    }

    @objc(showUserManager:) func showUserManagerMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        showUserManager()
    }

    @objc(chooseEncoding:) func chooseEncodingMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresDatabase: true) else { return }
        chooseLightweightEncoding(sender ?? self)
    }

    @objc(openDatabaseInNewTab:) func openDatabaseInNewTabMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresDatabase: true) else { return }
        openLightweightDatabaseInNewTab(sender)
    }

    @objc(showServerVariables:) func showServerVariablesMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        showLightweightServerVariables(sender)
    }

    @objc(showServerProcesses:) func showServerProcessesMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        showLightweightServerProcesses(sender)
    }

    @objc(shutdownServer:) func shutdownServerMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        shutdownLightweightServer(sender)
    }

    @objc(toggleNavigator:) func toggleNavigatorMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        toggleLightweightNavigator()
    }

    @objc(viewStructure:) func viewStructureMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresTable: true) else { return }
        viewStructure()
    }

    @objc(viewContent:) func viewContentMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresTable: true) else { return }
        viewContent()
    }

    @objc(viewQuery:) func viewQueryMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        viewQuery()
    }

    @objc(viewStatus:) func viewStatusMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresTable: true) else { return }
        viewStatus()
    }

    @objc(viewRelations:) func viewRelationsMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresTable: true) else { return }
        viewRelations()
    }

    @objc(viewTriggers:) func viewTriggersMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresTable: true) else { return }
        viewTriggers()
    }

    @objc(showMySQLHelp:) func showMySQLHelpMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        showLightweightMySQLHelp()
    }

    @objc(focusOnTableContentFilter:) func focusOnTableContentFilterMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresTable: true) else { return }
        focusLightweightContentFilter()
    }

    @objc(showFilterTable:) func showFilterTableMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector(requiresTable: true) else { return }
        showLightweightFilterTable()
    }

    @objc(makeTableListFilterHaveFocus:) func makeTableListFilterHaveFocusMenuBridge(_ sender: Any?) {
        guard canHandleLightweightMenuSelector() else { return }
        focusLightweightTableFilter()
    }

    @objc func copyLightweightCreateTableSyntax(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.copyCreateTableSyntax(nil)
            return
        }

        let tables = selectedLightweightTableItems()
        guard !tables.isEmpty,
              let syntax = lightweightCreateTableSyntaxes(for: tables, showErrors: true) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: self)
        pasteboard.setString(syntax, forType: .string)

        let notification = NSUserNotification()
        notification.title = NSLocalizedString("Syntax Copied", comment: "create table syntax copied notification title")
        notification.informativeText = tables.count == 1
            ? String(format: NSLocalizedString("Syntax for %@ copied", comment: "description for create syntax copied notification"), tables[0])
            : NSLocalizedString("Syntaxes for selected items copied", comment: "description for selected create syntaxes copied notification")
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    @objc func showLightweightCreateTableSyntax(_ sender: Any?) {
        if let document = loadedDatabaseDocument {
            document.showCreateTableSyntax(nil)
            return
        }

        let tables = selectedLightweightTableItems()
        guard !tables.isEmpty,
              let syntax = lightweightCreateTableSyntaxes(for: tables, showErrors: true) else { return }

        let title = tables.count == 1
            ? String(format: NSLocalizedString("Create syntax for %@ '%@'", comment: "Create syntax label"), lightweightCreateSyntaxTypeTitle(for: tables[0]), tables[0])
            : NSLocalizedString("Create syntaxes for selected items", comment: "Create syntaxes for selected items label")
        showLightweightCreateSyntaxSheet(title: title, syntax: syntax)
    }

    @objc(copyCreateTableSyntax:) func copyCreateTableSyntaxMenuBridge(_ sender: Any?) {
        copyLightweightCreateTableSyntax(sender)
    }

    @objc(showCreateTableSyntax:) func showCreateTableSyntaxMenuBridge(_ sender: Any?) {
        showLightweightCreateTableSyntax(sender)
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

    @objc(checkTable:) func checkTableMenuBridge(_ sender: Any?) {
        checkLightweightTable()
    }

    @objc(repairTable:) func repairTableMenuBridge(_ sender: Any?) {
        repairLightweightTable()
    }

    @objc(analyzeTable:) func analyzeTableMenuBridge(_ sender: Any?) {
        analyzeLightweightTable()
    }

    @objc(optimizeTable:) func optimizeTableMenuBridge(_ sender: Any?) {
        optimizeLightweightTable()
    }

    @objc(flushTable:) func flushTableMenuBridge(_ sender: Any?) {
        flushLightweightTable()
    }

    @objc(checksumTable:) func checksumTableMenuBridge(_ sender: Any?) {
        checksumLightweightTable()
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
        guard let selectedTable = selectedLightweightTableItems().first else {
            if showErrors {
                showLightweightCreateSyntaxError(NSLocalizedString("Select a table to view create syntax.", comment: "create syntax no selected table error"))
            }
            return nil
        }

        return lightweightCreateSyntax(for: selectedTable, showErrors: showErrors)
    }

    @nonobjc func lightweightCreateTableSyntaxes(for tables: [String], showErrors: Bool) -> String? {
        guard !tables.isEmpty else {
            if showErrors {
                showLightweightCreateSyntaxError(NSLocalizedString("Select a table to view create syntax.", comment: "create syntax no selected table error"))
            }
            return nil
        }

        var syntaxes: [String] = []
        for table in tables {
            guard let syntax = lightweightCreateSyntax(for: table, showErrors: showErrors) else { return nil }
            if tables.count > 1 {
                let typeTitle = lightweightCreateSyntaxTypeTitle(for: table)
                syntaxes.append("-- Create syntax for \(typeTitle) '\(table)'\n\(syntax)")
            } else {
                syntaxes.append(syntax)
            }
        }

        return syntaxes.joined(separator: "\n\n")
    }

    @nonobjc func lightweightCreateSyntax(for table: String, showErrors: Bool) -> String? {
        guard let activeConnection = activeConnection,
              let selectedDatabase = selectedDatabase else {
            if showErrors {
                showLightweightCreateSyntaxError(NSLocalizedString("Select a table to view create syntax.", comment: "create syntax no selected table error"))
            }
            return nil
        }

        let objectType = lightweightTableTypes[table] ?? .table
        let keyword = lightweightCreateSyntaxKeyword(for: objectType)
        let query = "SHOW CREATE \(keyword) \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(table))"
        guard let result = activeConnection.queryString(query) else {
            if showErrors {
                showLightweightCreateSyntaxError(NSLocalizedString("Couldn't get create syntax.", comment: "message of panel when table information cannot be retrieved"))
            }
            return nil
        }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary

        guard let row = result.getRowAsDictionary() as? [String: Any],
              let syntax = lightweightCreateSyntax(from: row, objectType: objectType) else {
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

    @nonobjc func lightweightCreateSyntaxKeyword(for objectType: SALightweightTableObjectType) -> String {
        switch objectType {
        case .view:
            return "VIEW"
        case .procedure:
            return "PROCEDURE"
        case .function:
            return "FUNCTION"
        case .none, .table:
            return "TABLE"
        }
    }

    @nonobjc func lightweightCreateSyntaxTypeTitle() -> String {
        guard let selectedTable = selectedLightweightTableItems().first else {
            return NSLocalizedString("TABLE", comment: "Create syntax table type")
        }

        return lightweightCreateSyntaxTypeTitle(for: selectedTable)
    }

    @nonobjc func lightweightCreateSyntaxTypeTitle(for table: String) -> String {
        switch lightweightTableTypes[table] ?? .table {
        case .view:
            return NSLocalizedString("VIEW", comment: "Create syntax view type")
        case .procedure:
            return NSLocalizedString("PROCEDURE", comment: "Create syntax procedure type")
        case .function:
            return NSLocalizedString("FUNCTION", comment: "Create syntax function type")
        case .none, .table:
            return NSLocalizedString("TABLE", comment: "Create syntax table type")
        }
    }

    @nonobjc func lightweightCreateSyntax(from row: [String: Any], objectType: SALightweightTableObjectType) -> String? {
        for key in ["Create Table", "Create View", "Create Procedure", "Create Function"] {
            if let syntax = row[key] as? String, !syntax.isEmpty {
                return lightweightCreateSyntaxString(syntax, objectType: objectType)
            }
        }

        for (key, value) in row where key.lowercased().contains("create") {
            if let syntax = value as? String, !syntax.isEmpty {
                return lightweightCreateSyntaxString(syntax, objectType: objectType)
            }
        }

        return nil
    }

    @nonobjc func lightweightCreateSyntaxString(_ syntax: String, objectType: SALightweightTableObjectType) -> String {
        switch objectType {
        case .procedure, .function:
            return lightweightRoutineCreateSyntaxString(syntax)
        case .none, .table, .view:
            return syntax.hasSuffix(";") ? syntax : "\(syntax);"
        }
    }

    @nonobjc func lightweightRoutineCreateSyntaxString(_ syntax: String) -> String {
        let trimmedSyntax = syntax.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSyntax.range(of: #"(?im)^\s*DELIMITER\b"#, options: .regularExpression) == nil else { return trimmedSyntax }

        var statement = trimmedSyntax
        while statement.hasSuffix(";") {
            statement.removeLast()
            statement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard statement.contains(";") else { return "\(statement);" }

        return "DELIMITER ;;\n\(statement);;\nDELIMITER ;"
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

        var menuSelector: Selector {
            switch self {
            case .check: return #selector(SPWindowController.checkTableMenuBridge(_:))
            case .repair: return #selector(SPWindowController.repairTableMenuBridge(_:))
            case .analyze: return #selector(SPWindowController.analyzeTableMenuBridge(_:))
            case .optimize: return #selector(SPWindowController.optimizeTableMenuBridge(_:))
            case .flush: return #selector(SPWindowController.flushTableMenuBridge(_:))
            case .checksum: return #selector(SPWindowController.checksumTableMenuBridge(_:))
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

        var selectedItemsErrorTitle: String {
            switch self {
            case .check: return NSLocalizedString("Unable to check selected items", comment: "unable to check selected items message")
            case .repair: return NSLocalizedString("Unable to repair selected items", comment: "unable to repair selected items message")
            case .analyze: return NSLocalizedString("Unable to analyze selected items", comment: "unable to analyze selected items message")
            case .optimize: return NSLocalizedString("Unable to optimze selected items", comment: "unable to optimze selected items message")
            case .flush: return NSLocalizedString("Unable to flush selected items", comment: "unable to flush selected items message")
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

        var selectedItemsSuccessMessage: String {
            switch self {
            case .check: return NSLocalizedString("Check of all selected items successfully passed.", comment: "check of all selected items successfully passed message")
            case .repair: return NSLocalizedString("Successfully repaired all selected items.", comment: "successfully repaired all selected items message")
            case .analyze: return NSLocalizedString("Successfully analyzed all selected items.", comment: "successfully analyzed all selected items message")
            case .optimize: return NSLocalizedString("Successfully optimized all selected items.", comment: "successfully optimized all selected items message")
            case .flush: return NSLocalizedString("Successfully flushed all selected items.", comment: "successfully flushed all selected items message")
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

    @objc func canPerformLightweightTableMaintenanceAction(_ selector: Selector) -> Bool {
        guard loadedDatabaseDocument == nil else { return hasSelectedLightweightTable }

        switch NSStringFromSelector(selector) {
        case "checkTable:", "flushTable:":
            return selectedLightweightTableSelectionHasOnlyTablesOrViews
        case "repairTable:", "analyzeTable:", "optimizeTable:", "checksumTable:":
            return selectedLightweightTableSelectionHasOnlyTables
        default:
            return false
        }
    }

    @nonobjc func performLightweightTableMaintenance(_ action: LightweightTableMaintenanceAction) {
        guard let activeConnection = activeConnection,
              let selectedDatabase = selectedDatabase else { return }

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

        let selectedTables = selectedLightweightTableItems()
        guard !selectedTables.isEmpty,
              canPerformLightweightTableMaintenanceAction(action.menuSelector) else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            let tableReference = selectedTables
                .map { "\(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted($0))" }
                .joined(separator: ", ")
            guard let result = activeConnection.queryString("\(action.queryKeyword) \(tableReference)") else {
                DispatchQueue.main.async {
                    self.showLightweightTableMaintenanceQueryError(action, tables: selectedTables, mysqlError: activeConnection.lastErrorMessage() ?? "")
                }
                return
            }

            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary

            if activeConnection.queryErrored() {
                DispatchQueue.main.async {
                    self.showLightweightTableMaintenanceQueryError(action, tables: selectedTables, mysqlError: activeConnection.lastErrorMessage() ?? "")
                }
                return
            }

            let rows = result.getAllRows() as? [[String: Any]] ?? []
            DispatchQueue.main.async {
                self.showLightweightTableMaintenanceResult(action, tables: selectedTables, rows: rows)
            }
        }
    }

    @nonobjc func showLightweightTableMaintenanceQueryError(_ action: LightweightTableMaintenanceAction, tables: [String], mysqlError: String) {
        guard activeConnection?.isConnected() == true else { return }

        let title = tables.count > 1 ? action.selectedItemsErrorTitle : action.errorTitle
        showLightweightTableMaintenanceAlert(title: title, message: action.errorMessage(what: lightweightTableMaintenanceObjectDescription(tables), mysqlError: mysqlError))
    }

    @nonobjc func showLightweightTableMaintenanceResult(_ action: LightweightTableMaintenanceAction, tables: [String], rows: [[String: Any]]) {
        let what = lightweightTableMaintenanceObjectDescription(tables)
        let title = "\(action.resultTitlePrefix) \(what)"
        let lastRow = rows.last ?? [:]

        if action == .checksum {
            if tables.count > 1 {
                showLightweightTableMaintenanceAlert(title: String(format: NSLocalizedString("Checksums of %@", comment: "Checksums of %@ message"), what),
                                                     message: lightweightTableMaintenanceRowsSummary(rows))
                return
            }

            let checksum = stringValue(lastRow["Checksum"])
            let message = String(format: NSLocalizedString("Table checksum: %@", comment: "table checksum: %@"), checksum)
            showLightweightTableMaintenanceAlert(title: title, message: message)
            return
        }

        let messageType = stringValue(lastRow["Msg_type"])
        let messageText = stringValue(lastRow["Msg_text"])
        if tables.count > 1 {
            let allStatus = rows.allSatisfy { stringValue($0["Msg_type"]) == "status" }
            let message = allStatus ? action.selectedItemsSuccessMessage : action.failureMessage
            showLightweightTableMaintenanceAlert(title: title, message: String(format: NSLocalizedString("%@\n\nMySQL said: %@", comment: "Error display text, showing original MySQL error"), message, lightweightTableMaintenanceRowsSummary(rows)))
            return
        }

        let message = messageType == "status" ? action.successMessage : action.failureMessage
        showLightweightTableMaintenanceAlert(title: title, message: String(format: NSLocalizedString("%@\n\nMySQL said: %@", comment: "Error display text, showing original MySQL error"), message, messageText))
    }

    @nonobjc func lightweightTableMaintenanceObjectDescription(_ tables: [String]) -> String {
        return tables.count > 1
            ? NSLocalizedString("selected items", comment: "selected items")
            : String(format: "%@ '%@'", NSLocalizedString("table", comment: "table"), tables.first ?? "")
    }

    @nonobjc func lightweightTableMaintenanceRowsSummary(_ rows: [[String: Any]]) -> String {
        let lines = rows.compactMap { row -> String? in
            let table = stringValue(row["Table"])
            let messageType = stringValue(row["Msg_type"])
            let messageText = stringValue(row["Msg_text"])
            let checksum = stringValue(row["Checksum"])
            guard !table.isEmpty || !messageType.isEmpty || !messageText.isEmpty || !checksum.isEmpty else { return nil }
            if !checksum.isEmpty {
                return "\(table): \(checksum)"
            }
            return "\(table): \(messageType) \(messageText)".trimmingCharacters(in: .whitespaces)
        }

        return lines.isEmpty ? NSLocalizedString("MySQL returned no rows.", comment: "no mysql result rows message") : lines.joined(separator: "\n")
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
