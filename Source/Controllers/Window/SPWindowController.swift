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

final class SALightweightConsoleLogger: NSObject, SPMySQLConnectionDelegate {
    weak var owner: SPWindowController?

    @objc func isWorking() -> Bool {
        return false
    }

    func willQueryString(_ query: String!, connection: Any!) {
        owner?.logLightweightConsoleQuery(query)
    }

    func queryGaveError(_ error: String!, connection: Any!) {
        owner?.logLightweightConsoleError(error)
    }
}

enum SALightweightWindowSessionSnapshotKey {
    static let state = "state"
    static let selectedDatabase = "selectedDatabase"
    static let selectedTable = "selectedTable"
    static let viewMode = "viewMode"
    static let tableFilter = "tableFilter"
    static let sidebarWidth = "sidebarWidth"
    static let tablesPaneHeight = "tablesPaneHeight"
    static let historyBackStack = "historyBackStack"
    static let historyForwardStack = "historyForwardStack"
}

enum SALightweightConnectionStateKey {
    static let connection = "connection"
    static let lightweightSession = "lightweightSession"
}

enum SALightweightConnectionDictionaryKey {
    static let rdbmsType = "rdbms_type"
    static let type = "type"
    static let name = "name"
    static let host = "host"
    static let user = "user"
    static let password = "password"
    static let database = "database"
    static let socket = "socket"
    static let port = "port"
    static let colorIndex = SPFavoriteColorIndexKey
    static let hasColorIndex = "hasColorIndex"
    static let kcid = "kcid"
    static let useSSL = "useSSL"
    static let allowDataLocalInfile = "allowDataLocalInfile"
    static let enableClearTextPlugin = "enableClearTextPlugin"
    static let useCompression = "useCompression"
    static let timeZoneMode = "timeZoneMode"
    static let timeZoneIdentifier = "timeZoneIdentifier"
    static let useAWSIAMAuth = "useAWSIAMAuth"
    static let awsProfile = "aws_profile"
    static let awsRegion = "aws_region"
    static let sslKeyFileLocationEnabled = "sslKeyFileLocationEnabled"
    static let sslKeyFileLocation = "sslKeyFileLocation"
    static let sslCertificateFileLocationEnabled = "sslCertificateFileLocationEnabled"
    static let sslCertificateFileLocation = "sslCertificateFileLocation"
    static let sslCACertFileLocationEnabled = "sslCACertFileLocationEnabled"
    static let sslCACertFileLocation = "sslCACertFileLocation"
    static let sshHost = "ssh_host"
    static let sshUser = "ssh_user"
    static let sshPassword = "ssh_password"
    static let sshKeyLocationEnabled = "ssh_keyLocationEnabled"
    static let sshKeyLocation = "ssh_keyLocation"
    static let sshPort = "ssh_port"
    static let connectionKeychainItemName = "connectionKeychainItemName"
    static let connectionKeychainItemAccount = "connectionKeychainItemAccount"
    static let connectionSSHKeychainItemName = "connectionSSHKeychainItemName"
    static let connectionSSHKeychainItemAccount = "connectionSSHKeychainItemAccount"
}

struct SALightweightSaveConnectionOptions {
    let encrypt: Bool
    let encryptionPassword: String
    let autoConnect: Bool
    let savePassword: Bool
    let includeSession: Bool
    let includeQuery: Bool
}

final class SALightweightSaveConnectionAccessory: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 118))
    let encryptButton = NSButton(checkboxWithTitle: NSLocalizedString("Encrypt", comment: "encrypt checkbox"), target: nil, action: nil)
    let passwordField = NSSecureTextField(frame: .zero)
    let autoConnectButton = NSButton(checkboxWithTitle: NSLocalizedString("Automatically connect", comment: "automatically connect checkbox"), target: nil, action: nil)
    let savePasswordButton = NSButton(checkboxWithTitle: NSLocalizedString("Save password", comment: "save password checkbox"), target: nil, action: nil)
    let includeSessionButton = NSButton(checkboxWithTitle: NSLocalizedString("Save session", comment: "save session checkbox"), target: nil, action: nil)
    let includeQueryButton = NSButton(checkboxWithTitle: NSLocalizedString("Save query editor content", comment: "save query editor content checkbox"), target: nil, action: nil)

    init(includeQueryEnabled: Bool) {
        super.init()

        let sessionData = (NSApp.delegate as? SPAppController)?.spfSessionDocData() as? [AnyHashable: Any] ?? [:]
        encryptButton.state = Self.boolValue(sessionData["encrypted"]) ? .on : .off
        autoConnectButton.state = Self.boolValue(sessionData["auto_connect"]) ? .on : .off
        savePasswordButton.state = Self.boolValue(sessionData["save_password"]) ? .on : .off
        includeSessionButton.state = Self.boolValue(sessionData["include_session"], defaultValue: true) ? .on : .off
        includeQueryButton.state = Self.boolValue(sessionData["save_editor_content"]) ? .on : .off
        includeQueryButton.isEnabled = includeQueryEnabled
        if !includeQueryEnabled {
            includeQueryButton.state = .off
        }

        encryptButton.target = self
        encryptButton.action = #selector(updatePasswordFieldState)
        passwordField.placeholderString = NSLocalizedString("Encryption password", comment: "encryption password placeholder")

        let stack = NSStackView(views: [encryptButton, passwordField, autoConnectButton, savePasswordButton, includeSessionButton, includeQueryButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        passwordField.widthAnchor.constraint(equalToConstant: 230).isActive = true
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
        updatePasswordFieldState()
    }

    func options() -> SALightweightSaveConnectionOptions {
        return SALightweightSaveConnectionOptions(
            encrypt: encryptButton.state == .on,
            encryptionPassword: passwordField.stringValue,
            autoConnect: autoConnectButton.state == .on,
            savePassword: savePasswordButton.state == .on,
            includeSession: includeSessionButton.state == .on,
            includeQuery: includeQueryButton.isEnabled && includeQueryButton.state == .on
        )
    }

    @objc private func updatePasswordFieldState() {
        passwordField.isEnabled = encryptButton.state == .on
    }

    private static func boolValue(_ value: Any?, defaultValue: Bool = false) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return defaultValue
    }
}

let SALightweightSQLImportMaximumInMemoryFileSize: Int64 = 16 * 1024 * 1024

final class SALightweightSQLImportEncodingAccessory {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 34))
    let popup = NSPopUpButton(frame: NSRect(x: 74, y: 4, width: 246, height: 26), pullsDown: false)
    let encodings: [String.Encoding] = [
        .utf8,
        .isoLatin1,
        .ascii,
        .macOSRoman,
        .windowsCP1250,
        .windowsCP1251,
        .windowsCP1252,
        .windowsCP1253,
        .windowsCP1254,
        .shiftJIS,
        .japaneseEUC,
        .iso2022JP,
        .utf16,
        .utf16BigEndian,
        .utf16LittleEndian
    ]

    init(selectedEncoding: String.Encoding) {
        let label = NSTextField(labelWithString: NSLocalizedString("Encoding:", comment: "encoding popup label"))
        label.frame = NSRect(x: 0, y: 8, width: 68, height: 18)
        label.alignment = .right
        view.addSubview(label)

        for encoding in encodings {
            popup.addItem(withTitle: String.localizedName(of: encoding))
            popup.lastItem?.tag = Int(encoding.rawValue)
        }
        if popup.itemArray.first(where: { $0.tag == Int(selectedEncoding.rawValue) }) == nil {
            popup.addItem(withTitle: String.localizedName(of: selectedEncoding))
            popup.lastItem?.tag = Int(selectedEncoding.rawValue)
        }
        popup.selectItem(withTag: Int(selectedEncoding.rawValue))
        view.addSubview(popup)
    }

    var selectedEncoding: String.Encoding {
        return String.Encoding(rawValue: UInt(popup.selectedItem?.tag ?? Int(String.Encoding.utf8.rawValue)))
    }
}

struct SALightweightEncodingChoice {
    let title: String
    let name: String?
}

struct SALightweightLegacySheetResult {
    let name: String
    let encoding: String?
    let collation: String?
    let tableType: String?
    let targetDatabase: String?
    let duplicateContent: Bool
}

final class SALightweightLegacySheetController: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    var response: NSApplication.ModalResponse = .cancel
    var encodingNamesByTitle: [String: String?] = [:]
    var collationsByEncoding: [String: [String]] = [:]
    var defaultCollationTitlesByEncoding: [String: String] = [:]
    var defaultCollationTitle = NSLocalizedString("Default", comment: "default collation title")
    let unknownDefaultCollationTitle = NSLocalizedString("Default", comment: "Collation Dropdown : Default (unknown)")
    weak var okButton: NSButton?
    weak var nameField: NSTextField?
    weak var encodingButton: NSPopUpButton?
    weak var collationButton: NSPopUpButton?
    weak var tableTypeButton: NSPopUpButton?
    weak var targetDatabaseButton: NSPopUpButton?
    weak var duplicateContentButton: NSButton?
    var requiresName = true
    var nameValidator: ((String) -> Bool)?

    init(window: NSWindow) {
        self.window = window
        super.init()
    }

    @objc func accept(_ sender: Any?) {
        updateOKButton()
        guard okButton?.isEnabled != false else {
            NSSound.beep()
            return
        }

        response = .OK
        NSApp.endSheet(window, returnCode: NSApplication.ModalResponse.OK.rawValue)
        window.orderOut(sender)
        NSApp.stopModal(withCode: .OK)
    }

    @objc func cancel(_ sender: Any?) {
        response = .cancel
        NSApp.endSheet(window, returnCode: NSApplication.ModalResponse.cancel.rawValue)
        window.orderOut(sender)
        NSApp.stopModal(withCode: .cancel)
    }

    @objc func encodingDidChange(_ sender: Any?) {
        guard let encodingButton = encodingButton, let collationButton = collationButton else { return }

        let selectedTitle = encodingButton.titleOfSelectedItem ?? ""
        let encodingName = encodingNamesByTitle[selectedTitle] ?? nil
        let defaultTitle: String
        if let encodingName = encodingName {
            defaultTitle = defaultCollationTitlesByEncoding[encodingName] ?? unknownDefaultCollationTitle
        } else {
            defaultTitle = defaultCollationTitle
        }

        collationButton.removeAllItems()
        collationButton.addItem(withTitle: defaultTitle)

        if let encodingName = encodingName, let collations = collationsByEncoding[encodingName], !collations.isEmpty {
            collationButton.menu?.addItem(.separator())
            collationButton.addItems(withTitles: collations)
            collationButton.isEnabled = true
        } else {
            collationButton.isEnabled = false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        updateOKButton()
    }

    func updateOKButton() {
        let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        okButton?.isEnabled = (!requiresName || !name.isEmpty) && (nameValidator?(name) ?? true)
    }

    var result: SALightweightLegacySheetResult? {
        guard response == .OK else { return nil }

        let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !requiresName || !name.isEmpty else { return nil }

        let selectedEncodingTitle = encodingButton?.titleOfSelectedItem ?? ""
        let selectedCollation = (collationButton?.indexOfSelectedItem ?? 0) > 0 ? collationButton?.titleOfSelectedItem : nil
        let selectedTableType = (tableTypeButton?.indexOfSelectedItem ?? 0) > 0 ? tableTypeButton?.titleOfSelectedItem : nil
        let selectedDatabase = targetDatabaseButton?.titleOfSelectedItem
        return SALightweightLegacySheetResult(name: name,
                                              encoding: encodingNamesByTitle[selectedEncodingTitle] ?? nil,
                                              collation: selectedCollation,
                                              tableType: selectedTableType,
                                              targetDatabase: selectedDatabase,
                                              duplicateContent: duplicateContentButton?.state == .on)
    }
}

extension Notification.Name {
    static let lightweightResumeStateDidChange = Notification.Name("SALightweightResumeStateDidChangeNotification")
}

enum SALightweightExportSource {
    // Swift does not import the Objective-C SPExportSource cases by name here.
    // Keep the bridge to Source/Other/Data/SPConstants.h in one place instead of scattering raw values.
    static let filteredResult = SPExportSource(rawValue: 0)!
    static let queryResult = SPExportSource(rawValue: 1)!
}

enum SALightweightTableObjectType: Int {
    case none = -1
    case table = 0
    case view = 1
    case procedure = 2
    case function = 3

    var imageName: String? {
        switch self {
        case .none: return nil
        case .table: return "table-small"
        case .view: return "table-view-small"
        case .procedure: return "proc-small"
        case .function: return "func-small"
        }
    }

    var localizedName: String {
        switch self {
        case .none: return ""
        case .table: return NSLocalizedString("table", comment: "table")
        case .view: return NSLocalizedString("view", comment: "view")
        case .procedure: return NSLocalizedString("procedure", comment: "procedure")
        case .function: return NSLocalizedString("function", comment: "function")
        }
    }

    var sqlDropKeyword: String? {
        switch self {
        case .table: return "TABLE"
        case .view: return "VIEW"
        case .procedure: return "PROCEDURE"
        case .function: return "FUNCTION"
        case .none: return nil
        }
    }

    var sqlRenameKeyword: String? {
        switch self {
        case .procedure: return "PROCEDURE"
        case .function: return "FUNCTION"
        case .table, .view, .none: return nil
        }
    }
}

enum SALightweightEncodingMenu {
    static let autodetectTag = 0
    static let utf8ViaLatin1Tag = 30

    static let tagToMySQLEncoding: [Int: String] = [
        10: "ucs2",
        20: "utf8",
        30: "utf8-",
        40: "ascii",
        50: "latin1",
        60: "macroman",
        70: "cp1250",
        80: "latin2",
        90: "cp1256",
        100: "greek",
        110: "hebrew",
        120: "latin5",
        130: "cp1257",
        140: "cp1251",
        150: "big5",
        160: "sjis",
        170: "ujis",
        180: "euckr",
        190: "utf8mb4"
    ]

    static let mysqlEncodingToTag: [String: Int] = Dictionary(uniqueKeysWithValues: tagToMySQLEncoding.map { ($0.value, $0.key) })
}

enum SALightweightDatabaseRenameObjectType {
    case table
    case view
    case procedure
    case function
    case event
}

enum SALightweightDatabaseRenamePreflightResult {
    case ready([String])
    case sourceMissing
    case targetExists
    case unsupportedObjects
    case failed(String)
}

final class SALightweightSessionState {

    private enum SnapshotKey {
        static let version = "version"
        static let queries = "queries"
        static let content = "content"
        static let transport = "transport"
        static let host = "host"
        static let port = "port"
        static let username = "username"
        static let database = "database"
        static let table = "table"
        static let text = "text"
        static let serializedRuleFilter = "serializedRuleFilter"
        static let isRuleFilterActive = "isRuleFilterActive"
        static let sortColumn = "sortColumn"
        static let sortAscending = "sortAscending"
        static let pageIndex = "pageIndex"
        static let columnFilter = "columnFilter"
    }

    struct ConnectionKey: Hashable {
        let transport: String
        let host: String
        let port: String
        let username: String
    }

    struct TableKey: Hashable {
        let connection: ConnectionKey
        let database: String
        let table: String
    }

    struct QueryState {
        let text: String
    }

    struct ContentState {
        var serializedRuleFilter: NSDictionary?
        var isRuleFilterActive: Bool
        var sortColumn: String?
        var sortAscending: Bool
        var pageIndex: Int
        var columnFilter: String?
    }

    var queryStates: [TableKey: QueryState] = [:]
    var contentStates: [TableKey: ContentState] = [:]

    static func tableKey(database: String?, table: String?, connection: SPMySQLConnection) -> TableKey? {
        guard let database = database, !database.isEmpty, let table = table, !table.isEmpty else { return nil }

        return TableKey(connection: connectionKey(for: connection), database: database, table: table)
    }

    static func queryKey(database: String?, table: String?, connection: SPMySQLConnection) -> TableKey? {
        guard let database = database, !database.isEmpty else { return nil }

        return TableKey(connection: connectionKey(for: connection), database: database, table: table ?? "")
    }

    static func connectionKey(for connection: SPMySQLConnection) -> ConnectionKey {
        let host = connection.useSocket ? connection.socketPath ?? "" : connection.host ?? ""
        return ConnectionKey(
            transport: connection.useSocket ? "socket" : "tcp",
            host: host,
            port: String(connection.port),
            username: connection.username ?? ""
        )
    }

    func queryState(for key: TableKey) -> QueryState? {
        return queryStates[key]
    }

    func setQueryText(_ text: String, for key: TableKey) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryStates.removeValue(forKey: key)
            return
        }

        queryStates[key] = QueryState(text: text)
    }

    func contentState(for key: TableKey) -> ContentState? {
        return contentStates[key]
    }

    func setContentState(_ state: ContentState, for key: TableKey) {
        contentStates[key] = state
    }

    func clearContentStates() {
        contentStates.removeAll()
    }

    func clearAll() {
        queryStates.removeAll()
        contentStates.removeAll()
    }

    func removeDatabase(_ database: String) {
        queryStates = queryStates.filter { $0.key.database.caseInsensitiveCompare(database) != .orderedSame }
        contentStates = contentStates.filter { $0.key.database.caseInsensitiveCompare(database) != .orderedSame }
    }

    func renameDatabase(from oldDatabase: String, to newDatabase: String) {
        queryStates = queryStates.reduce(into: [:]) { states, item in
            let key = item.key
            let newKey = key.database.caseInsensitiveCompare(oldDatabase) == .orderedSame
                ? TableKey(connection: key.connection, database: newDatabase, table: key.table)
                : key
            states[newKey] = item.value
        }
        contentStates = contentStates.reduce(into: [:]) { states, item in
            let key = item.key
            let newKey = key.database.caseInsensitiveCompare(oldDatabase) == .orderedSame
                ? TableKey(connection: key.connection, database: newDatabase, table: key.table)
                : key
            states[newKey] = item.value
        }
    }

    func exportDictionary(includeQueryStates: Bool = true, includeContentStates: Bool = true) -> NSDictionary {
        let snapshot = NSMutableDictionary()
        snapshot[SnapshotKey.version] = 1

        if includeQueryStates {
            snapshot[SnapshotKey.queries] = queryStates
                .sorted { lhs, rhs in Self.sortKey(for: lhs.key) < Self.sortKey(for: rhs.key) }
                .map { key, state -> NSDictionary in
                    let dictionary = NSMutableDictionary(dictionary: Self.dictionary(for: key))
                    dictionary[SnapshotKey.text] = state.text
                    return dictionary
                }
        }

        if includeContentStates {
            snapshot[SnapshotKey.content] = contentStates
                .sorted { lhs, rhs in Self.sortKey(for: lhs.key) < Self.sortKey(for: rhs.key) }
                .map { key, state -> NSDictionary in
                    let dictionary = NSMutableDictionary(dictionary: Self.dictionary(for: key))
                    if let serializedRuleFilter = state.serializedRuleFilter {
                        dictionary[SnapshotKey.serializedRuleFilter] = serializedRuleFilter
                    }
                    dictionary[SnapshotKey.isRuleFilterActive] = state.isRuleFilterActive
                    if let sortColumn = state.sortColumn {
                        dictionary[SnapshotKey.sortColumn] = sortColumn
                    }
                    dictionary[SnapshotKey.sortAscending] = state.sortAscending
                    dictionary[SnapshotKey.pageIndex] = state.pageIndex
                    if let columnFilter = state.columnFilter, !columnFilter.isEmpty {
                        dictionary[SnapshotKey.columnFilter] = columnFilter
                    }
                    return dictionary
                }
        }

        return snapshot
    }

    func load(from dictionary: NSDictionary?) {
        clearAll()
        guard let dictionary = dictionary else { return }

        if let queries = dictionary[SnapshotKey.queries] as? [NSDictionary] {
            for query in queries {
                guard let key = Self.queryKey(from: query),
                      let text = query[SnapshotKey.text] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                queryStates[key] = QueryState(text: text)
            }
        }

        if let content = dictionary[SnapshotKey.content] as? [NSDictionary] {
            for item in content {
                guard let key = Self.tableKey(from: item) else { continue }

                contentStates[key] = ContentState(
                    serializedRuleFilter: item[SnapshotKey.serializedRuleFilter] as? NSDictionary,
                    isRuleFilterActive: Self.boolValue(item[SnapshotKey.isRuleFilterActive]),
                    sortColumn: item[SnapshotKey.sortColumn] as? String,
                    sortAscending: Self.boolValue(item[SnapshotKey.sortAscending], defaultValue: true),
                    pageIndex: max(0, Self.intValue(item[SnapshotKey.pageIndex])),
                    columnFilter: item[SnapshotKey.columnFilter] as? String
                )
            }
        }
    }

    private static func dictionary(for key: TableKey) -> NSDictionary {
        return [
            SnapshotKey.transport: key.connection.transport,
            SnapshotKey.host: key.connection.host,
            SnapshotKey.port: key.connection.port,
            SnapshotKey.username: key.connection.username,
            SnapshotKey.database: key.database,
            SnapshotKey.table: key.table
        ]
    }

    private static func tableKey(from dictionary: NSDictionary) -> TableKey? {
        guard let transport = dictionary[SnapshotKey.transport] as? String,
              let host = dictionary[SnapshotKey.host] as? String,
              let port = dictionary[SnapshotKey.port] as? String,
              let username = dictionary[SnapshotKey.username] as? String,
              let database = dictionary[SnapshotKey.database] as? String,
              let table = dictionary[SnapshotKey.table] as? String,
              !database.isEmpty,
              !table.isEmpty else { return nil }

        return TableKey(
            connection: ConnectionKey(transport: transport, host: host, port: port, username: username),
            database: database,
            table: table
        )
    }

    private static func queryKey(from dictionary: NSDictionary) -> TableKey? {
        guard let transport = dictionary[SnapshotKey.transport] as? String,
              let host = dictionary[SnapshotKey.host] as? String,
              let port = dictionary[SnapshotKey.port] as? String,
              let username = dictionary[SnapshotKey.username] as? String,
              let database = dictionary[SnapshotKey.database] as? String,
              !database.isEmpty else { return nil }

        return TableKey(
            connection: ConnectionKey(transport: transport, host: host, port: port, username: username),
            database: database,
            table: dictionary[SnapshotKey.table] as? String ?? ""
        )
    }

    private static func sortKey(for key: TableKey) -> String {
        return [
            key.connection.transport,
            key.connection.host,
            key.connection.port,
            key.connection.username,
            key.database,
            key.table
        ].joined(separator: "\u{1F}")
    }

    private static func boolValue(_ value: Any?, defaultValue: Bool = false) -> Bool {
        return (value as? NSNumber)?.boolValue ?? (value as? Bool ?? defaultValue)
    }

    private static func intValue(_ value: Any?) -> Int {
        return (value as? NSNumber)?.intValue ?? (value as? Int ?? 0)
    }
}

@objc final class SPWindowController: NSWindowController {

    var loadedDatabaseDocument: SPDatabaseDocument?

    @objc var databaseDocument: SPDatabaseDocument {
        return installLegacyDatabaseDocumentIfNeeded()
    }

    @objc let uniqueID: UUID = UUID()

    let connectionContentView = NSView(frame: .zero)
    let connectionPlaceholderSplitView = SPSplitView(frame: .zero)
    var connectionController: SPConnectionController?
    var activeConnection: SPMySQLConnection?
    var activeConnectionInfo: SAConnectionInfoObjC?
    var lightweightBundleProcessID: String?
    let lightweightConsoleLoggingLock = NSLock()
    var lightweightConsoleQueryMode = 0
    let lightweightConsoleLogger = SALightweightConsoleLogger()
    var isLightweightImportRunning = false

    var selectedDatabase: String?
    var databaseListNeedsLoad = true
    var databaseListIsLoading = false
    var lightweightDatabases: [String] = []
    var lightweightTables: [String] = []
    var filteredLightweightTables: [String] = []
    var lightweightTableTypes: [String: SALightweightTableObjectType] = [:]
    var lightweightPinnedTables: Set<String> = []
    var lightweightTableInfoRows: [String] = [NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane")]
    var lightweightTableInfoLoadToken = UUID()
    var selectedTable: String?
    var activeConnectionName: String?
    var activeServerVersion: String?
    let databaseToolbarController = SADatabaseToolbarController()
    let lightweightSessionState = SALightweightSessionState()
    let lightweightStructureController = SALightweightStructureViewController()
    let lightweightContentController = SALightweightContentViewController()
    let lightweightQueryController = SALightweightQueryViewController()
    let lightweightTableInfoController = SALightweightTableInfoViewController()
    let lightweightRelationsController = SALightweightRelationsViewController()
    let lightweightTriggersController = SALightweightTriggersViewController()
    let lightweightHelpViewerClient = SPHelpViewerClient()
    lazy var lightweightServerVariablesController = SPServerVariablesController()
    lazy var lightweightProcessListController = SPProcessListController()
    var lightweightUserManager: SPUserManager?
    lazy var lightweightGotoDatabaseController = SPGotoDatabaseController()
    var lightweightExportController: SPExportController?
    lazy var lightweightFilterTableController: SPFilterTableController = {
        let controller = SPFilterTableController()
        controller.target = self
        controller.action = #selector(applyLightweightFilterTable(_:))
        return controller
    }()
    var activeLightweightViewMode: SAViewMode = .structure
    struct LightweightDetailKey: Equatable {
        let viewMode: SAViewMode?
        let database: String?
        let table: String?
        let placeholder: String?
    }
    var activeLightweightDetailKey: LightweightDetailKey?
    var lightweightHistoryBackStack: [String] = []
    var lightweightHistoryForwardStack: [String] = []
    var isRestoringLightweightHistory = false
    var pendingLightweightSessionSnapshot: NSDictionary?
    var activeLightweightLegacySheetController: SALightweightLegacySheetController?
    let lightweightShellView = NSView(frame: .zero)
    let lightweightContentSplitView = SPSplitView(frame: .zero)
    let lightweightSidebarView = NSVisualEffectView(frame: .zero)
    let lightweightSidebarSplitView = SPSplitView(frame: .zero)
    let lightweightTablesPane = NSView(frame: .zero)
    let lightweightTableInfoPane = NSVisualEffectView(frame: .zero)
    let lightweightSidebarButtonBar = NSView(frame: .zero)
    let lightweightDetailView = NSView(frame: .zero)
    var didRegisterLightweightPreferenceObservers = false

    lazy var tableFilterField: NSSearchField = {
        let field = NSSearchField(frame: .zero)
        field.focusRingType = .none
        field.placeholderString = NSLocalizedString("Filter", comment: "table list filter placeholder")
        field.target = self
        field.action = #selector(lightweightTableFilterChanged(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }()

    lazy var tablesListView: NSTableView = {
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

    lazy var lightweightTableInfoView: NSTableView = {
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

    lazy var lightweightStatusLabel: NSTextField = {
        let label = NSTextField(labelWithString: NSLocalizedString("Choose a database to load tables.", comment: "lightweight database shell empty state"))
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }()

    var processing = false

    override func awakeFromNib() {
        super.awakeFromNib()

        if let window = window  {
            window.collectionBehavior = [window.collectionBehavior, .fullScreenPrimary]
        }

        setupAppearance()
    }

    // MARK: - Accessory
    lazy var tabAccessoryView: SPWindowTabAccessory = SPWindowTabAccessory()

	deinit {
		if didRegisterLightweightPreferenceObservers {
			UserDefaults.standard.removeObserver(self, forKeyPath: SPGlobalFontSettings)
		}
	}
}
