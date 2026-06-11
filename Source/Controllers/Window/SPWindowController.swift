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

private final class SALightweightConsoleLogger: NSObject, SPMySQLConnectionDelegate {
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

private enum SALightweightWindowSessionSnapshotKey {
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

private enum SALightweightConnectionStateKey {
    static let connection = "connection"
    static let lightweightSession = "lightweightSession"
}

private enum SALightweightConnectionDictionaryKey {
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

private struct SALightweightEncodingChoice {
    let title: String
    let name: String?
}

private struct SALightweightLegacySheetResult {
    let name: String
    let encoding: String?
    let collation: String?
    let tableType: String?
    let targetDatabase: String?
    let duplicateContent: Bool
}

private final class SALightweightLegacySheetController: NSObject, NSTextFieldDelegate {
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

private extension Notification.Name {
    static let lightweightResumeStateDidChange = Notification.Name("SALightweightResumeStateDidChangeNotification")
}

private enum SALightweightTableObjectType: Int {
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

private enum SALightweightEncodingMenu {
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

private enum SALightweightDatabaseRenameObjectType {
    case table
    case view
    case procedure
    case function
    case event
}

private enum SALightweightDatabaseRenamePreflightResult {
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

    private var queryStates: [TableKey: QueryState] = [:]
    private var contentStates: [TableKey: ContentState] = [:]

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
    private let lightweightConsoleLoggingLock = NSLock()
    private var lightweightConsoleQueryMode = 0
    private let lightweightConsoleLogger = SALightweightConsoleLogger()

    private var selectedDatabase: String?
    private var databaseListNeedsLoad = true
    private var databaseListIsLoading = false
    private var lightweightDatabases: [String] = []
    private var lightweightTables: [String] = []
    private var filteredLightweightTables: [String] = []
    private var lightweightTableTypes: [String: SALightweightTableObjectType] = [:]
    private var lightweightPinnedTables: Set<String> = []
    private var lightweightTableInfoRows: [String] = [NSLocalizedString("TABLE INFORMATION", comment: "header for table info pane")]
    private var lightweightTableInfoLoadToken = UUID()
    private var selectedTable: String?
    private var activeConnectionName: String?
    private var activeServerVersion: String?
    private let databaseToolbarController = SADatabaseToolbarController()
    private let lightweightSessionState = SALightweightSessionState()
    private let lightweightStructureController = SALightweightStructureViewController()
    private let lightweightContentController = SALightweightContentViewController()
    private let lightweightQueryController = SALightweightQueryViewController()
    private let lightweightTableInfoController = SALightweightTableInfoViewController()
    private let lightweightRelationsController = SALightweightRelationsViewController()
    private let lightweightTriggersController = SALightweightTriggersViewController()
    private let lightweightHelpViewerClient = SPHelpViewerClient()
    private lazy var lightweightServerVariablesController = SPServerVariablesController()
    private lazy var lightweightProcessListController = SPProcessListController()
    private var lightweightUserManager: SPUserManager?
    private lazy var lightweightGotoDatabaseController = SPGotoDatabaseController()
    private lazy var lightweightFilterTableController: SPFilterTableController = {
        let controller = SPFilterTableController()
        controller.target = self
        controller.action = #selector(applyLightweightFilterTable(_:))
        return controller
    }()
    private var activeLightweightViewMode: SAViewMode = .structure
    private struct LightweightDetailKey: Equatable {
        let viewMode: SAViewMode?
        let database: String?
        let table: String?
        let placeholder: String?
    }
    private var activeLightweightDetailKey: LightweightDetailKey?
    private var lightweightHistoryBackStack: [String] = []
    private var lightweightHistoryForwardStack: [String] = []
    private var isRestoringLightweightHistory = false
    private var pendingLightweightSessionSnapshot: NSDictionary?
    private var activeLightweightLegacySheetController: SALightweightLegacySheetController?
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

extension SPWindowController {
    @objc func lightweightSessionSnapshotDictionary() -> NSDictionary {
        return lightweightSessionSnapshotDictionary(includeQueryText: true, includeContentState: true)
    }

    func lightweightSessionSnapshotDictionary(includeQueryText: Bool, includeContentState: Bool) -> NSDictionary {
        lightweightContentController.saveCurrentSessionState()
        lightweightQueryController.saveCurrentSessionState()

        let snapshot = NSMutableDictionary()
        snapshot[SALightweightWindowSessionSnapshotKey.state] = lightweightSessionState.exportDictionary(includeQueryStates: includeQueryText, includeContentStates: includeContentState)
        if let selectedDatabase = selectedDatabase {
            snapshot[SALightweightWindowSessionSnapshotKey.selectedDatabase] = selectedDatabase
        }
        if let selectedTable = selectedTable {
            snapshot[SALightweightWindowSessionSnapshotKey.selectedTable] = selectedTable
        }
        snapshot[SALightweightWindowSessionSnapshotKey.viewMode] = activeLightweightViewMode.rawValue
        if !tableFilterField.stringValue.isEmpty {
            snapshot[SALightweightWindowSessionSnapshotKey.tableFilter] = tableFilterField.stringValue
        }
        if let sidebarWidth = currentLightweightSidebarWidth() {
            snapshot[SALightweightWindowSessionSnapshotKey.sidebarWidth] = sidebarWidth
        }
        if let tablesPaneHeight = currentLightweightTablesPaneHeight() {
            snapshot[SALightweightWindowSessionSnapshotKey.tablesPaneHeight] = tablesPaneHeight
        }
        if !lightweightHistoryBackStack.isEmpty {
            snapshot[SALightweightWindowSessionSnapshotKey.historyBackStack] = lightweightHistoryBackStack
        }
        if !lightweightHistoryForwardStack.isEmpty {
            snapshot[SALightweightWindowSessionSnapshotKey.historyForwardStack] = lightweightHistoryForwardStack
        }

        return snapshot
    }

    @objc func restoreLightweightSessionSnapshotDictionary(_ snapshot: NSDictionary?) {
        guard let snapshot = snapshot else { return }

        pendingLightweightSessionSnapshot = snapshot
        if activeConnection != nil {
            applyPendingLightweightSessionSnapshot()
        }
    }

    @objc var hasActiveLightweightConnection: Bool {
        return activeConnection != nil && activeConnectionInfo != nil && loadedDatabaseDocument == nil
    }

    @objc var hasSelectedLightweightDatabase: Bool {
        return activeConnection != nil && selectedDatabase?.isEmpty == false && loadedDatabaseDocument == nil
    }

    @objc func chooseLightweightEncoding(_ sender: Any) {
        if let document = loadedDatabaseDocument {
            document.chooseEncoding(sender)
            return
        }

        guard hasActiveLightweightConnection, hasSelectedLightweightDatabase else { return }

        let tag = (sender as? NSMenuItem)?.tag ?? SALightweightEncodingMenu.autodetectTag
        let mysqlEncoding = Self.lightweightMySQLEncoding(fromEncodingTag: tag)
        setLightweightConnectionEncoding(mysqlEncoding, reloadingViews: true)
    }

    @objc func validateLightweightEncodingMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard hasActiveLightweightConnection, hasSelectedLightweightDatabase else {
            menuItem.state = .off
            return false
        }

        menuItem.state = (menuItem.tag == currentLightweightEncodingMenuTag()) ? .on : .off
        return true
    }

    @objc(lightweightConnectionStateDictionaryWithIncludePasswords:includeSession:includeQuery:)
    func lightweightConnectionStateDictionary(includePasswords: Bool, includeSession: Bool, includeQuery: Bool) -> NSDictionary? {
        guard hasActiveLightweightConnection, let activeConnectionInfo = activeConnectionInfo else { return nil }

        let state = NSMutableDictionary()
        state[SALightweightConnectionStateKey.connection] = lightweightConnectionDictionary(for: activeConnectionInfo, includePasswords: includePasswords)
        if includeSession || includeQuery {
            state[SALightweightConnectionStateKey.lightweightSession] = lightweightSessionSnapshotDictionary(includeQueryText: includeQuery, includeContentState: includeSession)
        }
        return state
    }

    @objc func restoreLightweightConnectionStateDictionary(_ state: NSDictionary?) -> Bool {
        guard loadedDatabaseDocument == nil,
              let state = state,
              let connectionDictionary = state[SALightweightConnectionStateKey.connection] as? NSDictionary,
              let info = lightweightConnectionInfo(from: connectionDictionary),
              let connectionController = connectionController else { return false }

        if let lightweightSession = state[SALightweightConnectionStateKey.lightweightSession] as? NSDictionary {
            restoreLightweightSessionSnapshotDictionary(lightweightSession)
        }

        activeConnectionInfo = info
        selectedDatabase = info.database.isEmpty ? nil : info.database
        connectionController.applyConnectionInfo(info)
        connectionController.initiateConnection(nil)
        return true
    }

    func lightweightConnectionDictionary(for info: SAConnectionInfoObjC, includePasswords: Bool) -> NSDictionary {
        let connection = NSMutableDictionary()
        connection[SALightweightConnectionDictionaryKey.rdbmsType] = "mysql"
        connection[SALightweightConnectionDictionaryKey.type] = Self.connectionTypeString(for: info.type)
        connection[SALightweightConnectionDictionaryKey.name] = info.name
        connection[SALightweightConnectionDictionaryKey.host] = info.host
        connection[SALightweightConnectionDictionaryKey.user] = info.user
        if let selectedDatabase = selectedDatabase, !selectedDatabase.isEmpty {
            connection[SALightweightConnectionDictionaryKey.database] = selectedDatabase
        } else if !info.database.isEmpty {
            connection[SALightweightConnectionDictionaryKey.database] = info.database
        }
        if !info.socket.isEmpty {
            connection[SALightweightConnectionDictionaryKey.socket] = info.socket
        }
        if let port = Int(info.port), port > 0 {
            connection[SALightweightConnectionDictionaryKey.port] = port
        }
        if info.colorIndex >= 0 {
            connection[SALightweightConnectionDictionaryKey.colorIndex] = info.colorIndex
            connection[SALightweightConnectionDictionaryKey.hasColorIndex] = true
        }
        if !info.connectionKeychainID.isEmpty {
            connection[SALightweightConnectionDictionaryKey.kcid] = info.connectionKeychainID
        }
        if includePasswords, !info.password.isEmpty {
            connection[SALightweightConnectionDictionaryKey.password] = info.password
        }

        connection[SALightweightConnectionDictionaryKey.useSSL] = info.useSSL
        connection[SALightweightConnectionDictionaryKey.allowDataLocalInfile] = info.allowDataLocalInfile
        connection[SALightweightConnectionDictionaryKey.enableClearTextPlugin] = info.enableClearTextPlugin
        connection[SALightweightConnectionDictionaryKey.useCompression] = info.useCompression
        connection[SALightweightConnectionDictionaryKey.timeZoneMode] = info.timeZoneMode.rawValue
        if !info.timeZoneIdentifier.isEmpty {
            connection[SALightweightConnectionDictionaryKey.timeZoneIdentifier] = info.timeZoneIdentifier
        }

        connection[SALightweightConnectionDictionaryKey.useAWSIAMAuth] = info.useAWSIAMAuth
        if !info.awsProfile.isEmpty {
            connection[SALightweightConnectionDictionaryKey.awsProfile] = info.awsProfile
        }
        if !info.awsRegion.isEmpty {
            connection[SALightweightConnectionDictionaryKey.awsRegion] = info.awsRegion
        }

        connection[SALightweightConnectionDictionaryKey.sslKeyFileLocationEnabled] = info.sslKeyFileLocationEnabled
        if !info.sslKeyFileLocation.isEmpty {
            connection[SALightweightConnectionDictionaryKey.sslKeyFileLocation] = info.sslKeyFileLocation
        }
        connection[SALightweightConnectionDictionaryKey.sslCertificateFileLocationEnabled] = info.sslCertificateFileLocationEnabled
        if !info.sslCertificateFileLocation.isEmpty {
            connection[SALightweightConnectionDictionaryKey.sslCertificateFileLocation] = info.sslCertificateFileLocation
        }
        connection[SALightweightConnectionDictionaryKey.sslCACertFileLocationEnabled] = info.sslCACertFileLocationEnabled
        if !info.sslCACertFileLocation.isEmpty {
            connection[SALightweightConnectionDictionaryKey.sslCACertFileLocation] = info.sslCACertFileLocation
        }

        if info.type == .sshTunnel {
            connection[SALightweightConnectionDictionaryKey.sshHost] = info.sshHost
            connection[SALightweightConnectionDictionaryKey.sshUser] = info.sshUser
            connection[SALightweightConnectionDictionaryKey.sshKeyLocationEnabled] = info.sshKeyLocationEnabled
            if !info.sshKeyLocation.isEmpty {
                connection[SALightweightConnectionDictionaryKey.sshKeyLocation] = info.sshKeyLocation
            }
            if let sshPort = Int(info.sshPort), sshPort > 0 {
                connection[SALightweightConnectionDictionaryKey.sshPort] = sshPort
            }
            if includePasswords {
                connection[SALightweightConnectionDictionaryKey.sshPassword] = info.sshPassword
            }
        }

        if !info.connectionKeychainItemName.isEmpty {
            connection[SALightweightConnectionDictionaryKey.connectionKeychainItemName] = info.connectionKeychainItemName
        }
        if !info.connectionKeychainItemAccount.isEmpty {
            connection[SALightweightConnectionDictionaryKey.connectionKeychainItemAccount] = info.connectionKeychainItemAccount
        }
        if !info.connectionSSHKeychainItemName.isEmpty {
            connection[SALightweightConnectionDictionaryKey.connectionSSHKeychainItemName] = info.connectionSSHKeychainItemName
        }
        if !info.connectionSSHKeychainItemAccount.isEmpty {
            connection[SALightweightConnectionDictionaryKey.connectionSSHKeychainItemAccount] = info.connectionSSHKeychainItemAccount
        }

        return connection
    }

    func lightweightConnectionInfo(from connection: NSDictionary) -> SAConnectionInfoObjC? {
        guard let typeString = connection[SALightweightConnectionDictionaryKey.type] as? String else { return nil }

        let info = SAConnectionInfoObjC()
        info.type = Self.connectionType(for: typeString)
        info.name = Self.stringValue(connection[SALightweightConnectionDictionaryKey.name])
        info.host = Self.stringValue(connection[SALightweightConnectionDictionaryKey.host])
        info.user = Self.stringValue(connection[SALightweightConnectionDictionaryKey.user])
        info.password = Self.stringValue(connection[SALightweightConnectionDictionaryKey.password])
        info.database = Self.stringValue(connection[SALightweightConnectionDictionaryKey.database])
        info.socket = Self.stringValue(connection[SALightweightConnectionDictionaryKey.socket])
        info.port = Self.stringValue(connection[SALightweightConnectionDictionaryKey.port])
        if Self.boolValue(connection[SALightweightConnectionDictionaryKey.hasColorIndex]) {
            info.colorIndex = Self.intValue(connection[SALightweightConnectionDictionaryKey.colorIndex], defaultValue: -1)
        } else {
            info.colorIndex = -1
        }
        info.connectionKeychainID = Self.stringValue(connection[SALightweightConnectionDictionaryKey.kcid])
        info.useSSL = Self.intValue(connection[SALightweightConnectionDictionaryKey.useSSL])
        info.allowDataLocalInfile = Self.intValue(connection[SALightweightConnectionDictionaryKey.allowDataLocalInfile])
        info.enableClearTextPlugin = Self.intValue(connection[SALightweightConnectionDictionaryKey.enableClearTextPlugin])
        info.useCompression = Self.boolValue(connection[SALightweightConnectionDictionaryKey.useCompression])
        info.timeZoneMode = SAConnectionTimeZoneMode(rawValue: Self.intValue(connection[SALightweightConnectionDictionaryKey.timeZoneMode])) ?? .useServerTZ
        info.timeZoneIdentifier = Self.stringValue(connection[SALightweightConnectionDictionaryKey.timeZoneIdentifier])
        info.useAWSIAMAuth = Self.intValue(connection[SALightweightConnectionDictionaryKey.useAWSIAMAuth])
        info.awsProfile = Self.stringValue(connection[SALightweightConnectionDictionaryKey.awsProfile])
        info.awsRegion = Self.stringValue(connection[SALightweightConnectionDictionaryKey.awsRegion])
        info.sslKeyFileLocationEnabled = Self.intValue(connection[SALightweightConnectionDictionaryKey.sslKeyFileLocationEnabled])
        info.sslKeyFileLocation = Self.stringValue(connection[SALightweightConnectionDictionaryKey.sslKeyFileLocation])
        info.sslCertificateFileLocationEnabled = Self.intValue(connection[SALightweightConnectionDictionaryKey.sslCertificateFileLocationEnabled])
        info.sslCertificateFileLocation = Self.stringValue(connection[SALightweightConnectionDictionaryKey.sslCertificateFileLocation])
        info.sslCACertFileLocationEnabled = Self.intValue(connection[SALightweightConnectionDictionaryKey.sslCACertFileLocationEnabled])
        info.sslCACertFileLocation = Self.stringValue(connection[SALightweightConnectionDictionaryKey.sslCACertFileLocation])
        info.sshHost = Self.stringValue(connection[SALightweightConnectionDictionaryKey.sshHost])
        info.sshUser = Self.stringValue(connection[SALightweightConnectionDictionaryKey.sshUser])
        info.sshPassword = Self.stringValue(connection[SALightweightConnectionDictionaryKey.sshPassword])
        info.sshKeyLocationEnabled = Self.intValue(connection[SALightweightConnectionDictionaryKey.sshKeyLocationEnabled])
        info.sshKeyLocation = Self.stringValue(connection[SALightweightConnectionDictionaryKey.sshKeyLocation])
        info.sshPort = Self.stringValue(connection[SALightweightConnectionDictionaryKey.sshPort])
        info.connectionKeychainItemName = Self.stringValue(connection[SALightweightConnectionDictionaryKey.connectionKeychainItemName])
        info.connectionKeychainItemAccount = Self.stringValue(connection[SALightweightConnectionDictionaryKey.connectionKeychainItemAccount])
        info.connectionSSHKeychainItemName = Self.stringValue(connection[SALightweightConnectionDictionaryKey.connectionSSHKeychainItemName])
        info.connectionSSHKeychainItemAccount = Self.stringValue(connection[SALightweightConnectionDictionaryKey.connectionSSHKeychainItemAccount])
        return info
    }

    static func connectionTypeString(for type: SAConnectionType) -> String {
        switch type {
        case .socket:
            return "SPSocketConnection"
        case .sshTunnel:
            return "SPSSHTunnelConnection"
        case .awsIAM:
            return "SPAWSIAMConnection"
        case .tcpIP:
            return "SPTCPIPConnection"
        @unknown default:
            return "SPTCPIPConnection"
        }
    }

    static func connectionType(for typeString: String) -> SAConnectionType {
        switch typeString {
        case "SPSocketConnection":
            return .socket
        case "SPSSHTunnelConnection":
            return .sshTunnel
        case "SPAWSIAMConnection":
            return .awsIAM
        default:
            return .tcpIP
        }
    }

    static func stringValue(_ value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    static func intValue(_ value: Any?, defaultValue: Int = 0) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let int = value as? Int {
            return int
        }
        if let string = value as? String {
            return Int(string) ?? defaultValue
        }
        return defaultValue
    }

    static func boolValue(_ value: Any?, defaultValue: Bool = false) -> Bool {
        return (value as? NSNumber)?.boolValue ?? (value as? Bool ?? defaultValue)
    }
}

// MARK: - Private API

private extension SPWindowController {
    func setupAppearance() {
        installConnectionView()
        lightweightConsoleLogger.owner = self

        if #available(macOS 10.13, *) {
            window?.tab.accessoryView = tabAccessoryView
        }

        lightweightContentController.sessionState = lightweightSessionState
        lightweightContentController.sessionStateDidChange = { [weak self] in
            self?.markLightweightResumeStateChanged()
        }
        lightweightQueryController.sessionState = lightweightSessionState
        lightweightQueryController.sessionStateDidChange = { [weak self] in
            self?.markLightweightResumeStateChanged()
        }
        lightweightQueryController.queryExecutionWillBegin = { [weak self] in
            self?.setLightweightConsoleQueryMode(1)
        }
        lightweightQueryController.queryExecutionDidEnd = { [weak self] in
            self?.setLightweightConsoleQueryMode(0)
        }
        databaseToolbarController.delegate = self
    }

    func saveCurrentLightweightViewState() {
        switch activeLightweightDetailKey?.viewMode {
        case .content:
            lightweightContentController.saveCurrentSessionState()
        case .query:
            lightweightQueryController.saveCurrentSessionState()
        default:
            break
        }
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

        let defaultSidebarWidth = LightweightDBViewLayout.sidebarWidth
        let tableInfoHeight = LightweightDBViewLayout.tableInfoHeight
        let sidebarButtonBarHeight = LightweightDBViewLayout.sidebarButtonBarHeight
        let restoredSidebarWidth = restoredLightweightSidebarWidth(from: pendingLightweightSessionSnapshot)
        let savedSidebarWidth = sanitizedLightweightSidebarWidth(restoredSidebarWidth ?? savedSplitViewFirstSubviewLength(forAutosaveName: LightweightDBViewLayout.dbViewAutosaveName, isVertical: true),
                                                                 in: contentView.bounds.width)
        let sidebarWidth = savedSidebarWidth ?? defaultSidebarWidth
        let restoredTablesPaneHeight = restoredLightweightTablesPaneHeight(from: pendingLightweightSessionSnapshot)
        let savedTablesPaneHeight = sanitizedLightweightTablesPaneHeight(restoredTablesPaneHeight ?? savedSplitViewFirstSubviewLength(forAutosaveName: LightweightDBViewLayout.tableInfoAutosaveName, isVertical: false),
                                                                         in: max(0, contentView.bounds.height - sidebarButtonBarHeight))

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

        activeLightweightDetailKey = nil
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
            self.lightweightContentSplitView.setPosition(sidebarWidth, ofDividerAt: 0)
            let defaultTablesPaneHeight = max(LightweightDBViewLayout.sidebarPaneMinimumHeight, self.lightweightSidebarSplitView.bounds.height - tableInfoHeight)
            self.lightweightSidebarSplitView.setPosition(savedTablesPaneHeight ?? defaultTablesPaneHeight, ofDividerAt: 0)

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

    @discardableResult
    private func installLightweightDetailSubview(_ detailSubview: NSView, key: LightweightDetailKey) -> Bool {
        detailSubview.frame = lightweightDetailView.bounds
        detailSubview.autoresizingMask = [.width, .height]

        if activeLightweightDetailKey == key, detailSubview.superview === lightweightDetailView {
            return false
        }

        lightweightDetailView.subviews.forEach { subview in
            guard subview !== detailSubview else { return }
            subview.removeFromSuperviewWithoutNeedingDisplay()
        }

        if detailSubview.superview !== lightweightDetailView {
            detailSubview.removeFromSuperviewWithoutNeedingDisplay()
            lightweightDetailView.addSubview(detailSubview)
        }

        activeLightweightDetailKey = key
        return true
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
        guard let selectedDatabase = selectedDatabase else { return }
        guard let tableDetails = promptForLightweightTable() else { return }
        let tableName = tableDetails.name

        guard validateLightweightObjectName(tableName, type: .table) else { return }

        var options: [String] = []
        if let encoding = tableDetails.encoding {
            options.append("DEFAULT CHARACTER SET \(Self.backtickQuoted(encoding))")
        }
        if let collation = tableDetails.collation {
            options.append("DEFAULT COLLATE \(Self.backtickQuoted(collation))")
        }
        if let tableType = tableDetails.tableType {
            options.append("ENGINE = \(Self.backtickQuoted(tableType))")
        }

        let primaryKey = tableDetails.tableType == "CSV" ? "" : " PRIMARY KEY AUTO_INCREMENT"
        let statement = "CREATE TABLE \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(tableName)) (id INT(11) UNSIGNED NOT NULL\(primaryKey)) \(options.joined(separator: " "))"
        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Creating %@...", comment: "Creating table task string"), tableName), statement: statement) { [weak self] success in
            guard let self = self, success else { return }
            self.loadTables(for: selectedDatabase, restoringTable: tableName)
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
        guard let selectedDatabase = selectedDatabase,
              let selectedTable = selectedTable else { return }

        guard let row = filteredLightweightTables.firstIndex(of: selectedTable).map({ $0 + 1 }) else {
            return
        }

        tablesListView.editColumn(0, row: row, with: nil, select: true)
    }

    @objc func duplicateLightweightTable(_ sender: Any?) {
        guard let selectedDatabase = selectedDatabase,
              let selectedTable = selectedTable else { return }

        let tableType = lightweightTableTypes[selectedTable] ?? .table
        guard let duplicateDetails = promptForLightweightDuplicateTable(sourceName: selectedTable,
                                                                        tableType: tableType,
                                                                        defaultValue: "\(selectedTable)_copy") else { return }
        let newName = duplicateDetails.name
        let targetDatabase = duplicateDetails.targetDatabase?.isEmpty == false ? duplicateDetails.targetDatabase! : selectedDatabase
        guard validateLightweightObjectName(newName, type: tableType) else { return }

        if tableType == .procedure || tableType == .function {
            duplicateLightweightRoutine(selectedTable, to: newName, type: tableType, database: selectedDatabase, dropSource: false)
        } else {
            duplicateLightweightObject(selectedTable,
                                       to: newName,
                                       type: tableType,
                                       sourceDatabase: selectedDatabase,
                                       targetDatabase: targetDatabase,
                                       copyContent: duplicateDetails.duplicateContent)
        }
    }

    @objc func truncateLightweightTable(_ sender: Any?) {
        guard let selectedDatabase = selectedDatabase,
              let selectedTable = selectedTable else { return }

        guard (lightweightTableTypes[selectedTable] ?? .table) == .table else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Truncate table '%@'?", comment: "truncate table message"), selectedTable)
        alert.informativeText = String(format: NSLocalizedString("Are you sure you want to delete ALL records in the table '%@'? This operation cannot be undone.", comment: "truncate table informative message"), selectedTable)
        alert.addButton(withTitle: NSLocalizedString("Truncate", comment: "truncate button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        guard runLightweightModalAlert(alert) == .alertFirstButtonReturn else { return }

        let statement = "TRUNCATE TABLE \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(selectedTable))"
        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Truncating %@...", comment: "Truncating table task string"), selectedTable), statement: statement) { [weak self] success in
            guard let self = self, success else { return }
            self.loadTables(for: selectedDatabase, restoringTable: selectedTable, restoringViewMode: self.activeLightweightViewMode)
        }
    }

    @objc func removeLightweightTable(_ sender: Any?) {
        guard let selectedDatabase = selectedDatabase,
              let selectedTable = selectedTable else { return }

        let tableType = lightweightTableTypes[selectedTable] ?? .table
        guard let dropKeyword = tableType.sqlDropKeyword else { return }

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Delete %@ '%@'?", comment: "delete table/view message"), tableType.localizedName, selectedTable)
        alert.informativeText = String(format: NSLocalizedString("Are you sure you want to delete the %@ '%@'? This operation cannot be undone.", comment: "delete table/view informative message"), tableType.localizedName, selectedTable)
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: "delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        alert.alertStyle = .critical
        alert.suppressionButton?.title = NSLocalizedString("Force delete (disables integrity checks)", comment: "force table deletion button text")
        alert.suppressionButton?.toolTip = NSLocalizedString("Disables foreign key checks (FOREIGN_KEY_CHECKS) before deletion and re-enables them afterwards.", comment: "force table deltion button text tooltip")
        alert.showsSuppressionButton = true

        guard runLightweightModalAlert(alert) == .alertFirstButtonReturn else { return }

        let force = alert.suppressionButton?.state == .on
        let statement = "DROP \(dropKeyword) \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(selectedTable))"
        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Deleting %@...", comment: "Deleting table task string"), selectedTable), statements: [
            force ? "/*!32352 SET FOREIGN_KEY_CHECKS=0 */" : nil,
            statement,
            force ? "/*!32352 SET FOREIGN_KEY_CHECKS=1 */" : nil
        ].compactMap { $0 }) { [weak self] success in
            guard let self = self, success else { return }
            self.unpinLightweightTable(selectedTable, database: selectedDatabase)
            self.selectedTable = nil
            self.loadTables(for: selectedDatabase)
        }
    }

    @objc func togglePinLightweightTable(_ sender: Any?) {
        guard let selectedDatabase = selectedDatabase,
              let selectedTable = selectedTable else { return }

        if lightweightPinnedTables.contains(selectedTable) {
            unpinLightweightTable(selectedTable, database: selectedDatabase)
        } else {
            pinLightweightTable(selectedTable, database: selectedDatabase)
        }

        loadTables(for: selectedDatabase, preservingSelection: true)
    }

    @objc func openLightweightTableInNewTab(_ sender: Any?) {
        guard selectedTable != nil,
              let state = lightweightConnectionStateDictionary(includePasswords: true, includeSession: true, includeQuery: true) else { return }

        NotificationCenter.default.post(name: .SPDocumentDuplicateTab, object: nil, userInfo: [
            "isLightweight": true,
            "lightweightState": state
        ])
    }

    func promptForLightweightName(title: String,
                                  message: String,
                                  defaultValue: String = "",
                                  buttonTitle: String,
                                  nameValidator: ((String) -> Bool)? = nil) -> String? {
        let result = promptForLightweightSimpleName(title: title,
                                                    message: message,
                                                    defaultValue: defaultValue,
                                                    buttonTitle: buttonTitle,
                                                    nameValidator: nameValidator)
        return result?.name
    }

    func promptForLightweightSimpleName(title: String,
                                        message: String,
                                        defaultValue: String = "",
                                        buttonTitle: String,
                                        nameValidator: ((String) -> Bool)? = nil) -> SALightweightLegacySheetResult? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 314, height: 102),
                              styleMask: .titled,
                              backing: .buffered,
                              defer: false)
        window.title = title
        let controller = SALightweightLegacySheetController(window: window)
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView

        let messageField = legacyLabel(message, frame: NSRect(x: 20, y: 64, width: 274, height: 18), alignment: .left)
        let nameField = legacyTextField(frame: NSRect(x: 20, y: 42, width: 274, height: 19), value: defaultValue)
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: 122, y: 12, width: 86, height: 28), keyEquivalent: "\u{1b}")
        let okButton = legacyButton(title: buttonTitle, frame: NSRect(x: 207, y: 12, width: 92, height: 28), keyEquivalent: "\r")

        contentView.addSubview(messageField)
        contentView.addSubview(nameField)
        contentView.addSubview(cancelButton)
        contentView.addSubview(okButton)

        controller.nameField = nameField
        controller.okButton = okButton
        controller.nameValidator = nameValidator
        nameField.delegate = controller
        nameField.target = controller
        nameField.action = #selector(SALightweightLegacySheetController.accept(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        okButton.target = controller
        okButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: nameField) == .OK else { return nil }
        return controller.result
    }

    func promptForLightweightDatabase() -> SALightweightLegacySheetResult? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 384, height: 133),
                              styleMask: .titled,
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("New Database", comment: "new database sheet title")
        window.minSize = NSSize(width: 384, height: 133)
        window.maxSize = NSSize(width: 600, height: 133)
        return runLightweightNamedObjectSheet(window: window,
                                              nameLabel: NSLocalizedString("Database Name:", comment: "database name label"),
                                              encodingLabel: NSLocalizedString("Database Encoding:", comment: "database encoding label"),
                                              collationLabel: NSLocalizedString("Database Collation:", comment: "database collation label"),
                                              defaultEncodingTitle: lightweightDefaultEncodingTitle(database: nil, format: NSLocalizedString("Server Default (%@)", comment: "Add Database : Charset dropdown : default item ($1 = charset name)")),
                                              defaultCollationTitle: lightweightDefaultCollationTitle(database: nil, format: NSLocalizedString("Server Default (%@)", comment: "Add Database : Collation dropdown : default item ($1 = collation name)")),
                                               buttonTitle: NSLocalizedString("Add", comment: "add database button"),
                                               nameValidator: lightweightDatabaseNameLiveValidator())
    }

    func promptForLightweightDatabaseCopy(sourceDatabase: String) -> SALightweightLegacySheetResult? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 314, height: 127),
                              styleMask: .titled,
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("Duplicate Database", comment: "copy database sheet title")

        let controller = SALightweightLegacySheetController(window: window)
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView

        let messageField = legacyLabel(sourceDatabase, frame: NSRect(x: 20, y: 89, width: 274, height: 18), alignment: .center)
        let nameField = legacyTextField(frame: NSRect(x: 20, y: 67, width: 274, height: 19), value: sourceDatabase)
        let duplicateContent = NSButton(checkboxWithTitle: NSLocalizedString("Duplicate database content", comment: "duplicate database content checkbox"), target: nil, action: nil)
        duplicateContent.frame = NSRect(x: 20, y: 42, width: 274, height: 18)
        duplicateContent.controlSize = .small
        duplicateContent.font = .messageFont(ofSize: 11)
        duplicateContent.state = .on
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: 122, y: 12, width: 86, height: 28), keyEquivalent: "\u{1b}")
        let duplicateButton = legacyButton(title: NSLocalizedString("Duplicate", comment: "duplicate database button"), frame: NSRect(x: 207, y: 12, width: 92, height: 28), keyEquivalent: "\r")

        [messageField, nameField, duplicateContent, cancelButton, duplicateButton].forEach(contentView.addSubview)

        controller.nameField = nameField
        controller.okButton = duplicateButton
        controller.duplicateContentButton = duplicateContent
        controller.nameValidator = lightweightDatabaseNameLiveValidator()
        nameField.delegate = controller
        nameField.target = controller
        nameField.action = #selector(SALightweightLegacySheetController.accept(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        duplicateButton.target = controller
        duplicateButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: nameField) == .OK else { return nil }
        return controller.result
    }

    func promptForLightweightDatabaseAlter(database: String) -> SALightweightLegacySheetResult? {
        guard let activeConnection = activeConnection else { return nil }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 384, height: 104),
                              styleMask: .titled,
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("Alter Database", comment: "alter database sheet title")

        let controller = SALightweightLegacySheetController(window: window)
        controller.requiresName = false
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView

        let currentDefaults = lightweightDatabaseDefaults(for: database, connection: activeConnection)
        let currentEncoding = currentDefaults?.encoding ?? ""
        let currentCollation = currentDefaults?.collation ?? ""
        let encodingChoices = lightweightEncodingChoices(defaultTitle: NSLocalizedString("Default", comment: "default encoding title")).filter { $0.name != nil }
        let selectedEncodingTitle = encodingChoices.first { $0.name?.caseInsensitiveCompare(currentEncoding) == .orderedSame }?.title ?? encodingChoices.first?.title ?? currentEncoding

        let encodingButton = legacyPopup(frame: NSRect(x: 143, y: 66, width: 224, height: 22),
                                         choices: encodingChoices,
                                         defaultTitle: selectedEncodingTitle)
        let collationButton = legacyPopup(frame: NSRect(x: 143, y: 41, width: 224, height: 22),
                                          choices: [SALightweightEncodingChoice(title: currentCollation.isEmpty ? NSLocalizedString("Default", comment: "default collation title") : currentCollation, name: currentCollation.isEmpty ? nil : currentCollation)],
                                          defaultTitle: currentCollation.isEmpty ? NSLocalizedString("Default", comment: "default collation title") : currentCollation)
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: 205, y: 13, width: 86, height: 28), keyEquivalent: "\u{1b}")
        let alterButton = legacyButton(title: NSLocalizedString("Alter", comment: "alter database button"), frame: NSRect(x: 289, y: 13, width: 80, height: 28), keyEquivalent: "\r")

        contentView.addSubview(legacyLabel(NSLocalizedString("Database Encoding:", comment: "database encoding label"), frame: NSRect(x: 5, y: 71, width: 134, height: 14), alignment: .right))
        contentView.addSubview(encodingButton)
        contentView.addSubview(legacyLabel(NSLocalizedString("Database Collation:", comment: "database collation label"), frame: NSRect(x: 5, y: 46, width: 134, height: 14), alignment: .right))
        contentView.addSubview(collationButton)
        contentView.addSubview(cancelButton)
        contentView.addSubview(alterButton)

        controller.okButton = alterButton
        controller.encodingButton = encodingButton
        controller.collationButton = collationButton
        controller.encodingNamesByTitle = Dictionary(uniqueKeysWithValues: encodingChoices.map { ($0.title, $0.name) })
        let collationChoices = lightweightCollationChoices()
        controller.collationsByEncoding = collationChoices.collationsByEncoding
        controller.defaultCollationTitlesByEncoding = collationChoices.defaultCollationTitlesByEncoding
        controller.defaultCollationTitle = currentCollation.isEmpty ? NSLocalizedString("Default", comment: "default collation title") : currentCollation
        encodingButton.target = controller
        encodingButton.action = #selector(SALightweightLegacySheetController.encodingDidChange(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        alterButton.target = controller
        alterButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.encodingDidChange(encodingButton)
        if !currentCollation.isEmpty {
            collationButton.selectItem(withTitle: currentCollation)
        }
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: encodingButton) == .OK else { return nil }
        return controller.result
    }

    func promptForLightweightTable() -> SALightweightLegacySheetResult? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 425, height: 162),
                              styleMask: [.titled, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("New Table", comment: "new table sheet title")
        window.minSize = NSSize(width: 425, height: 162)
        window.maxSize = NSSize(width: 600, height: 162)
        let result = runLightweightNamedObjectSheet(window: window,
                                                    nameLabel: NSLocalizedString("Table Name:", comment: "table name label"),
                                                    encodingLabel: NSLocalizedString("Table Encoding:", comment: "table encoding label"),
                                                    collationLabel: NSLocalizedString("Table Collation:", comment: "table collation label"),
                                                    defaultEncodingTitle: lightweightDefaultEncodingTitle(database: selectedDatabase, format: NSLocalizedString("Inherit from database (%@)", comment: "New Table Sheet : Table Encoding Dropdown : Default inherited from database")),
                                                    defaultCollationTitle: lightweightDefaultCollationTitle(database: selectedDatabase, format: NSLocalizedString("Inherit from database (%@)", comment: "New Table Sheet : Table Collation Dropdown : Default inherited from database")),
                                                    buttonTitle: NSLocalizedString("Add", comment: "add table button"),
                                                    typeLabel: NSLocalizedString("Table Type:", comment: "table type label"),
                                                    typeChoices: lightweightTableTypeChoices())
        return result
    }

    func promptForLightweightDuplicateTable(sourceName: String, tableType: SALightweightTableObjectType, defaultValue: String) -> SALightweightLegacySheetResult? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 192),
                              styleMask: [.titled, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = NSLocalizedString("Duplicate Table", comment: "duplicate table sheet title")
        window.minSize = NSSize(width: 260, height: 127)
        window.maxSize = NSSize(width: 260, height: 192)

        let controller = SALightweightLegacySheetController(window: window)
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView

        let titleField = legacyLabel(NSLocalizedString("Duplicate Table", comment: "duplicate table sheet title"), frame: NSRect(x: 18, y: 167, width: 224, height: 19), alignment: .center)
        let databaseLabel = legacyLabel(NSLocalizedString("Database:", comment: "database label"), frame: NSRect(x: 16, y: 145, width: 226, height: 14), alignment: .left)
        let databaseButton = legacyPopup(frame: NSRect(x: 16, y: 113, width: 228, height: 25),
                                         choices: lightweightDatabases.map { SALightweightEncodingChoice(title: $0, name: $0) },
                                         defaultTitle: selectedDatabase ?? NSLocalizedString("Choose Database...", comment: "menu item for choose db"))
        let message = String(format: NSLocalizedString("Duplicate %@ '%@' to:", comment: "duplicate object message"), tableType.localizedName, sourceName)
        let messageField = legacyLabel(message, frame: NSRect(x: 17, y: 95, width: 226, height: 14), alignment: .left)
        let nameField = legacyTextField(frame: NSRect(x: 19, y: 68, width: 222, height: 19), value: defaultValue)
        let duplicateContent = NSButton(checkboxWithTitle: NSLocalizedString("Duplicate table content", comment: "duplicate table content checkbox"), target: nil, action: nil)
        duplicateContent.frame = NSRect(x: 17, y: 43, width: 227, height: 18)
        duplicateContent.controlSize = .small
        duplicateContent.font = .messageFont(ofSize: 11)
        duplicateContent.state = tableType == .table ? .on : .off
        duplicateContent.isEnabled = tableType == .table
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: 61, y: 13, width: 91, height: 28), keyEquivalent: "\u{1b}")
        let duplicateButton = legacyButton(title: NSLocalizedString("Duplicate", comment: "duplicate table button"), frame: NSRect(x: 150, y: 13, width: 97, height: 28), keyEquivalent: "\r")

        [titleField, databaseLabel, databaseButton, messageField, nameField, duplicateContent, cancelButton, duplicateButton].forEach(contentView.addSubview)

        controller.nameField = nameField
        controller.okButton = duplicateButton
        controller.targetDatabaseButton = databaseButton
        controller.duplicateContentButton = duplicateContent
        nameField.delegate = controller
        nameField.target = controller
        nameField.action = #selector(SALightweightLegacySheetController.accept(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        duplicateButton.target = controller
        duplicateButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: nameField) == .OK else { return nil }
        return controller.result
    }

    func runLightweightNamedObjectSheet(window: NSWindow,
                                        nameLabel: String,
                                        encodingLabel: String,
                                        collationLabel: String,
                                        defaultEncodingTitle: String,
                                        defaultCollationTitle: String,
                                        buttonTitle: String,
                                        typeLabel: String? = nil,
                                        typeChoices: [SALightweightEncodingChoice] = [],
                                        nameValidator: ((String) -> Bool)? = nil) -> SALightweightLegacySheetResult? {
        let controller = SALightweightLegacySheetController(window: window)
        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = contentView
        let hasType = typeLabel != nil
        let choices = lightweightEncodingChoices(defaultTitle: defaultEncodingTitle)

        let labelWidth = hasType ? 128.0 : 134.0
        let fieldX = hasType ? 135.0 : 143.0
        let textFieldX = hasType ? 138.0 : 146.0
        let fieldWidth = hasType ? 273.0 : 224.0
        let textFieldWidth = hasType ? 267.0 : 218.0
        let topY = hasType ? 125.0 : 96.0
        let nameFieldY = hasType ? 124.0 : 94.0
        let encodingY = hasType ? 100.0 : 71.0
        let encodingPopupY = hasType ? 95.0 : 66.0
        let collationY = hasType ? 75.0 : 46.0
        let collationPopupY = hasType ? 70.0 : 41.0

        let nameField = legacyTextField(frame: NSRect(x: textFieldX, y: nameFieldY, width: textFieldWidth, height: 19), value: "")
        let encodingButton = legacyPopup(frame: NSRect(x: fieldX, y: encodingPopupY, width: fieldWidth, height: 22),
                                         choices: choices,
                                         defaultTitle: defaultEncodingTitle)
        let collationButton = legacyPopup(frame: NSRect(x: fieldX, y: collationPopupY, width: fieldWidth, height: 22),
                                          choices: [SALightweightEncodingChoice(title: defaultCollationTitle, name: nil)],
                                          defaultTitle: defaultCollationTitle)
        let cancelX = hasType ? 250.0 : 205.0
        let okX = hasType ? 332.0 : 289.0
        let cancelButton = legacyButton(title: NSLocalizedString("Cancel", comment: "cancel button"), frame: NSRect(x: cancelX, y: 13, width: hasType ? 84 : 86, height: 28), keyEquivalent: "\u{1b}")
        let okButton = legacyButton(title: buttonTitle, frame: NSRect(x: okX, y: 13, width: hasType ? 78 : 80, height: 28), keyEquivalent: "\r")

        contentView.addSubview(legacyLabel(nameLabel, frame: NSRect(x: 5, y: topY, width: labelWidth, height: 14), alignment: .right))
        contentView.addSubview(nameField)
        contentView.addSubview(legacyLabel(encodingLabel, frame: NSRect(x: 5, y: encodingY, width: labelWidth, height: 14), alignment: .right))
        contentView.addSubview(encodingButton)
        contentView.addSubview(legacyLabel(collationLabel, frame: NSRect(x: 5, y: collationY, width: labelWidth, height: 14), alignment: .right))
        contentView.addSubview(collationButton)

        if let typeLabel = typeLabel {
            let typeButton = legacyPopup(frame: NSRect(x: 135, y: 45, width: 273, height: 22),
                                         choices: typeChoices,
                                         defaultTitle: typeChoices.first?.title ?? NSLocalizedString("Default", comment: "default table type"))
            contentView.addSubview(legacyLabel(typeLabel, frame: NSRect(x: 5, y: 49, width: 128, height: 14), alignment: .right))
            contentView.addSubview(typeButton)
            controller.tableTypeButton = typeButton
        }

        contentView.addSubview(cancelButton)
        contentView.addSubview(okButton)

        controller.nameField = nameField
        controller.okButton = okButton
        controller.nameValidator = nameValidator
        controller.encodingButton = encodingButton
        controller.collationButton = collationButton
        controller.encodingNamesByTitle = Dictionary(uniqueKeysWithValues: choices.map { ($0.title, $0.name) })
        let collationChoices = lightweightCollationChoices()
        controller.collationsByEncoding = collationChoices.collationsByEncoding
        controller.defaultCollationTitlesByEncoding = collationChoices.defaultCollationTitlesByEncoding
        controller.defaultCollationTitle = defaultCollationTitle
        nameField.delegate = controller
        nameField.target = controller
        nameField.action = #selector(SALightweightLegacySheetController.accept(_:))
        encodingButton.target = controller
        encodingButton.action = #selector(SALightweightLegacySheetController.encodingDidChange(_:))
        cancelButton.target = controller
        cancelButton.action = #selector(SALightweightLegacySheetController.cancel(_:))
        okButton.target = controller
        okButton.action = #selector(SALightweightLegacySheetController.accept(_:))
        controller.updateOKButton()

        guard runLightweightLegacySheet(controller, firstResponder: nameField) == .OK else { return nil }
        return controller.result
    }

    func runLightweightLegacySheet(_ controller: SALightweightLegacySheetController, firstResponder: NSResponder?) -> NSApplication.ModalResponse {
        configureLightweightModalWindow(controller.window)

        guard let parentWindow = window else {
            controller.window.center()
            controller.window.makeKeyAndOrderFront(nil)
            if let firstResponder = firstResponder {
                controller.window.makeFirstResponder(firstResponder)
            }
            return NSApp.runModal(for: controller.window)
        }

        centerLightweightModalWindow(controller.window)
        if let firstResponder = firstResponder {
            controller.window.makeFirstResponder(firstResponder)
        }

        var response: NSApplication.ModalResponse = .cancel
        activeLightweightLegacySheetController = controller
        parentWindow.beginSheet(controller.window) { modalResponse in
            response = modalResponse
            controller.window.orderOut(nil)
            self.activeLightweightLegacySheetController = nil
            NSApp.stopModal(withCode: modalResponse)
        }

        let modalResponse = NSApp.runModal(for: controller.window)
        return response == .cancel ? modalResponse : response
    }

    func applyLightweightDefaultEncodingPreference() {
        let preferredTag = UserDefaults.standard.integer(forKey: SPDefaultEncoding)
        let mysqlEncoding = preferredTag == SALightweightEncodingMenu.autodetectTag
            ? "utf8mb4"
            : Self.lightweightMySQLEncoding(fromEncodingTag: preferredTag)
        setLightweightConnectionEncoding(mysqlEncoding, reloadingViews: false)
    }

    @discardableResult
    func setLightweightConnectionEncoding(_ mysqlEncoding: String, reloadingViews reloadViews: Bool) -> Bool {
        guard let activeConnection = activeConnection else { return false }

        var mysqlEncoding = mysqlEncoding
        var useLatin1Transport = false
        if mysqlEncoding == "utf8-" {
            useLatin1Transport = true
            mysqlEncoding = "utf8mb4"
        }

        guard activeConnection.setEncoding(mysqlEncoding) else {
            NSLog("Error: could not set encoding to %@ nor fall back to database encoding on MySQL %@", mysqlEncoding, activeServerVersion ?? "")
            return false
        }

        activeConnection.setEncodingUsesLatin1Transport(useLatin1Transport)
        activeConnection.storeEncodingForRestoration()

        if reloadViews {
            reloadLightweightViewsAfterEncodingChange()
        }

        return true
    }

    func reloadLightweightViewsAfterEncodingChange() {
        lightweightStructureController.clearCachedTables()
        lightweightContentController.clearCachedTables()

        guard let activeConnection = activeConnection, let selectedDatabase = selectedDatabase else { return }

        if let selectedTable = selectedTable {
            loadLightweightTableInfo(for: selectedTable)

            switch activeLightweightViewMode {
            case .content:
                lightweightContentController.loadContent(for: selectedTable, database: selectedDatabase, connection: activeConnection)
            case .query:
                lightweightQueryController.loadQuery(database: selectedDatabase, table: selectedTable, connection: activeConnection)
            case .status:
                lightweightTableInfoController.loadTableInfo(for: selectedTable, database: selectedDatabase, connection: activeConnection)
            case .relations:
                showLightweightRelations(for: selectedTable)
            case .triggers:
                showLightweightTriggers(for: selectedTable)
            default:
                lightweightStructureController.loadStructure(for: selectedTable, database: selectedDatabase, connection: activeConnection, useCache: false)
            }
        } else {
            loadTables(for: selectedDatabase, preservingSelection: true)
        }
    }

    func currentLightweightEncodingMenuTag() -> Int {
        guard let activeConnection = activeConnection else { return SALightweightEncodingMenu.autodetectTag }

        if activeConnection.encodingUsesLatin1Transport() {
            return SALightweightEncodingMenu.utf8ViaLatin1Tag
        }

        let mysqlEncoding = activeConnection.encoding() ?? ""
        return SALightweightEncodingMenu.mysqlEncodingToTag[mysqlEncoding] ?? SALightweightEncodingMenu.autodetectTag
    }

    static func lightweightMySQLEncoding(fromEncodingTag tag: Int) -> String {
        return SALightweightEncodingMenu.tagToMySQLEncoding[tag] ?? "utf8mb4"
    }

    func legacyLabel(_ title: String, frame: NSRect, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.font = .messageFont(ofSize: 11)
        label.alignment = alignment
        label.lineBreakMode = .byClipping
        return label
    }

    func legacyTextField(frame: NSRect, value: String) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.controlSize = .small
        field.font = .messageFont(ofSize: 11)
        field.cell?.controlSize = .small
        field.cell?.usesSingleLineMode = true
        field.stringValue = value
        return field
    }

    func legacyButton(title: String, frame: NSRect, keyEquivalent: String) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .messageFont(ofSize: 11)
        button.keyEquivalent = keyEquivalent
        return button
    }

    func legacyPopup(frame: NSRect, choices: [SALightweightEncodingChoice], defaultTitle: String) -> NSPopUpButton {
        let button = NSPopUpButton(frame: frame, pullsDown: false)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .messageFont(ofSize: 11)
        button.addItem(withTitle: defaultTitle)
        if choices.contains(where: { $0.title != defaultTitle }) {
            button.menu?.addItem(.separator())
        }
        choices.filter { $0.title != defaultTitle }.forEach { button.addItem(withTitle: $0.title) }
        return button
    }

    func lightweightDefaultEncodingTitle(database: String?, format: String) -> String {
        guard let activeConnection = activeConnection else { return NSLocalizedString("Default", comment: "default encoding title") }

        let query: String
        if let database = database {
            query = "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = \(Self.sqlString(database))"
        } else {
            query = "SHOW VARIABLES LIKE 'character_set_server'"
        }

        guard let result = activeConnection.queryString(query) else { return NSLocalizedString("Default", comment: "default encoding title") }
        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return NSLocalizedString("Default", comment: "default encoding title") }
        let value = Self.displayString(for: row["DEFAULT_CHARACTER_SET_NAME"] ?? row["Value"])
        return value.isEmpty ? NSLocalizedString("Default", comment: "default encoding title") : String(format: format, value)
    }

    func lightweightDefaultCollationTitle(database: String?, format: String) -> String {
        guard let activeConnection = activeConnection else { return NSLocalizedString("Default", comment: "default collation title") }

        let query: String
        if let database = database {
            query = "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = \(Self.sqlString(database))"
        } else {
            query = "SHOW VARIABLES LIKE 'collation_server'"
        }

        guard let result = activeConnection.queryString(query) else { return NSLocalizedString("Default", comment: "default collation title") }
        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return NSLocalizedString("Default", comment: "default collation title") }
        let value = Self.displayString(for: row["DEFAULT_COLLATION_NAME"] ?? row["Value"])
        return value.isEmpty ? NSLocalizedString("Default", comment: "default collation title") : String(format: format, value)
    }

    func lightweightEncodingChoices(defaultTitle: String) -> [SALightweightEncodingChoice] {
        guard let activeConnection = activeConnection else { return [SALightweightEncodingChoice(title: defaultTitle, name: nil)] }

        let queries = [
            "SELECT CHARACTER_SET_NAME, DESCRIPTION FROM information_schema.character_sets ORDER BY character_set_name ASC",
            "SHOW CHARACTER SET"
        ]

        for query in queries {
            guard let result = activeConnection.queryString(query) else { continue }

            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            var utf8Choices: [SALightweightEncodingChoice] = []
            var otherChoices: [SALightweightEncodingChoice] = []

            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = Self.displayString(for: row["CHARACTER_SET_NAME"] ?? row["Charset"])
                guard !name.isEmpty else { continue }
                let description = Self.displayString(for: row["DESCRIPTION"] ?? row["Description"])
                let title = description.isEmpty ? name : "\(description) (\(name))"
                let choice = SALightweightEncodingChoice(title: title, name: name)
                if name.hasPrefix("utf8") {
                    utf8Choices.append(choice)
                } else {
                    otherChoices.append(choice)
                }
            }

            let choices = [SALightweightEncodingChoice(title: defaultTitle, name: nil)] + utf8Choices + otherChoices
            if choices.count > 1 {
                return choices
            }
        }

        return [SALightweightEncodingChoice(title: defaultTitle, name: nil)]
    }

    func lightweightCollationChoices() -> (collationsByEncoding: [String: [String]], defaultCollationTitlesByEncoding: [String: String]) {
        guard let activeConnection = activeConnection else { return ([:], [:]) }

        let queries = [
            "SELECT COLLATION_NAME, CHARACTER_SET_NAME, IS_DEFAULT FROM information_schema.collations ORDER BY collation_name ASC",
            "SHOW COLLATION"
        ]

        for query in queries {
            guard let result = activeConnection.queryString(query) else { continue }

            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            var collationsByEncoding: [String: [String]] = [:]
            var defaultCollationsByEncoding: [String: String] = [:]

            while let row = result.getRowAsDictionary() as? [String: Any] {
                let collation = Self.displayString(for: row["COLLATION_NAME"] ?? row["Collation"])
                let encoding = Self.displayString(for: row["CHARACTER_SET_NAME"] ?? row["Charset"])
                guard !collation.isEmpty, !encoding.isEmpty else { continue }
                collationsByEncoding[encoding, default: []].append(collation)
                let isDefault = Self.displayString(for: row["IS_DEFAULT"] ?? row["Default"])
                if isDefault.caseInsensitiveCompare("Yes") == .orderedSame {
                    defaultCollationsByEncoding[encoding] = collation
                }
            }

            if !collationsByEncoding.isEmpty {
                if collationsByEncoding["utf8mb3"] == nil, let utf8Collations = collationsByEncoding["utf8"] {
                    collationsByEncoding["utf8mb3"] = utf8Collations
                    defaultCollationsByEncoding["utf8mb3"] = defaultCollationsByEncoding["utf8"]
                } else if collationsByEncoding["utf8"] == nil, let utf8mb3Collations = collationsByEncoding["utf8mb3"] {
                    collationsByEncoding["utf8"] = utf8mb3Collations
                    defaultCollationsByEncoding["utf8"] = defaultCollationsByEncoding["utf8mb3"]
                }

                let defaultTitlesByEncoding = defaultCollationsByEncoding.mapValues {
                    String(format: NSLocalizedString("Default (%@)", comment: "Collation Dropdown : Default ($1 = collation name)"), $0)
                }
                return (collationsByEncoding.mapValues { Self.uniqueStrings($0).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } },
                        defaultTitlesByEncoding)
            }
        }

        return ([:], [:])
    }

    func lightweightTableTypeChoices() -> [SALightweightEncodingChoice] {
        let defaultEngine = lightweightDefaultStorageEngine()
        var choices = [SALightweightEncodingChoice(title: String(format: NSLocalizedString("Default (%@)", comment: "New Table Sheet : Table Engine Dropdown : Default"), defaultEngine), name: nil)]
        guard let activeConnection = activeConnection,
              let result = activeConnection.queryString("SHOW ENGINES") else { return choices }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        while let row = result.getRowAsDictionary() as? [String: Any] {
            let support = Self.displayString(for: row["Support"])
            guard support != "NO" else { continue }
            let engine = Self.displayString(for: row["Engine"])
            guard !engine.isEmpty else { continue }
            choices.append(SALightweightEncodingChoice(title: engine, name: engine))
        }

        return choices
    }

    func lightweightDefaultStorageEngine() -> String {
        guard let activeConnection = activeConnection,
              let result = activeConnection.queryString("SHOW VARIABLES LIKE 'default_storage_engine'") else { return "InnoDB" }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return "InnoDB" }
        let value = Self.displayString(for: row["Value"])
        return value.isEmpty ? "InnoDB" : value
    }

    func runLightweightModalAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alert.window.isRestorable = false
        alert.window.animationBehavior = .none

        return alert.runModalCentered(over: window)
    }

    func centerLightweightModalWindow(_ modalWindow: NSWindow) {
        guard let parentWindow = window else {
            modalWindow.center()
            return
        }

        let parentFrame = parentWindow.frame
        let modalFrame = modalWindow.frame
        modalWindow.setFrameOrigin(NSPoint(x: parentFrame.midX - modalFrame.width / 2,
                                           y: parentFrame.midY - modalFrame.height / 2))
    }

    func configureLightweightModalWindow(_ modalWindow: NSWindow) {
        modalWindow.isRestorable = false
        modalWindow.animationBehavior = .none
    }

    func validateLightweightObjectName(_ name: String, type: SALightweightTableObjectType, ignoring ignoredName: String? = nil) -> Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) != name || name.isEmpty {
            NSSound.beep()
            return false
        }

        let matchesExisting = lightweightTables.contains { table in
            guard table.caseInsensitiveCompare(ignoredName ?? "") != .orderedSame else { return false }
            guard (lightweightTableTypes[table] ?? .table) == type || type == .table || type == .view else { return false }
            return table.caseInsensitiveCompare(name) == .orderedSame
        }

        guard !matchesExisting else {
            showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                 message: String(format: NSLocalizedString("The name '%@' is already used.", comment: "message when trying to rename a table/view/proc/etc to an already used name"), name))
            return false
        }

        return true
    }

    func validateLightweightDatabaseName(_ name: String, ignoring ignoredName: String? = nil) -> Bool {
        guard !name.isEmpty else {
            showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                 message: NSLocalizedString("Database must have a name.", comment: "message of panel when no db name is given"))
            return false
        }

        let databases = activeConnection?.databases() as? [String] ?? lightweightDatabases
        let matchesExisting = databases.contains { database in
            guard database.caseInsensitiveCompare(ignoredName ?? "") != .orderedSame else { return false }
            return database.caseInsensitiveCompare(name) == .orderedSame
        }

        guard !matchesExisting else {
            showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                 message: String(format: NSLocalizedString("The name '%@' is already used.", comment: "message when trying to rename a table/view/proc/etc to an already used name"), name))
            return false
        }

        return true
    }

    func lightweightDatabaseNameLiveValidator() -> (String) -> Bool {
        let databases = activeConnection?.databases() as? [String] ?? lightweightDatabases
        return { candidate in
            !databases.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
    }

    func showLightweightDatabaseRenameUnsupportedAlert(database: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Database Rename Unsupported", comment: "databsse rename unsupported message")
        alert.informativeText = String(format: NSLocalizedString("Renaming the database '%@' is currently unsupported as it contains objects other than tables (i.e. views, procedures, functions, events, etc.).\n\nIf you would like to rename a database please use the 'Duplicate Database', move any non-table objects manually then drop the old database.", comment: "databsse rename unsupported informative message"), database)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        _ = runLightweightModalAlert(alert)
    }

    func lightweightDatabaseRenamePreflight(from sourceDatabase: String, to targetDatabase: String, connection: SPMySQLConnection) -> SALightweightDatabaseRenamePreflightResult {
        let databases = connection.databases() as? [String] ?? []
        guard databases.contains(sourceDatabase) else { return .sourceMissing }
        guard !databases.contains(targetDatabase) else { return .targetExists }

        let objects = loadLightweightDatabaseRenameObjects(for: sourceDatabase, connection: connection)
        if connection.queryErrored() {
            let error = connection.lastErrorMessage()
            return .failed(error?.isEmpty == false ? error! : NSLocalizedString("Unable to inspect database objects before rename.", comment: "database rename preflight failed"))
        }

        guard objects.allSatisfy({ $0.type == .table }) else { return .unsupportedObjects }

        var options: [String] = []
        if let defaults = lightweightDatabaseDefaults(for: sourceDatabase, connection: connection) {
            if let encoding = defaults.encoding, !encoding.isEmpty {
                options.append("DEFAULT CHARACTER SET = \(Self.backtickQuoted(encoding))")
            }
            if let collation = defaults.collation, !collation.isEmpty {
                options.append("DEFAULT COLLATE = \(Self.backtickQuoted(collation))")
            }
        }

        var statements = [
            "CREATE DATABASE \(Self.backtickQuoted(targetDatabase)) \(options.joined(separator: " "))"
        ]

        let tableRenames = objects
            .filter { $0.type == .table }
            .map { table in
                "\(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(table.name)) TO \(Self.backtickQuoted(targetDatabase)).\(Self.backtickQuoted(table.name))"
            }
        if !tableRenames.isEmpty {
            statements.append("RENAME TABLE \(tableRenames.joined(separator: ", "))")
        }

        statements.append("DROP DATABASE \(Self.backtickQuoted(sourceDatabase))")
        return .ready(statements)
    }

    func loadLightweightDatabaseRenameObjects(for database: String, connection: SPMySQLConnection) -> [(name: String, type: SALightweightDatabaseRenameObjectType)] {
        var objects: [(name: String, type: SALightweightDatabaseRenameObjectType)] = []

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

        if connection.queryErrored() {
            return objects
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

        if connection.queryErrored() {
            return objects
        }

        if let quotedDatabase = connection.escapeAndQuoteString(database),
           let result = connection.queryString("SELECT EVENT_NAME FROM information_schema.events WHERE event_schema = \(quotedDatabase) ORDER BY event_name") {
            result.returnDataAsStrings = true
            result.defaultRowReturnType = SPMySQLResultRowAsDictionary
            while let row = result.getRowAsDictionary() as? [String: Any] {
                let name = stringValue(row["EVENT_NAME"] ?? row["event_name"])
                guard !name.isEmpty else { continue }
                objects.append((name: name, type: .event))
            }
        }

        return objects
    }

    func lightweightDatabaseDefaults(for database: String, connection: SPMySQLConnection) -> (encoding: String?, collation: String?)? {
        guard let result = connection.queryString("SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = \(Self.sqlString(database))") else {
            return nil
        }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsDictionary
        guard let row = result.getRowAsDictionary() as? [String: Any] else { return nil }
        return (Self.displayString(for: row["DEFAULT_CHARACTER_SET_NAME"]),
                Self.displayString(for: row["DEFAULT_COLLATION_NAME"]))
    }

    func runLightweightDatabaseMutation(status: String, statement: String, completion: @escaping (Bool) -> Void) {
        runLightweightDatabaseMutation(status: status, statements: [statement], completion: completion)
    }

    func runLightweightDatabaseMutation(status: String, statements: [String], completion: @escaping (Bool) -> Void) {
        guard let activeConnection = activeConnection else { return }

        showLightweightPlaceholder(status)
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            for statement in statements {
                _ = activeConnection.queryString(statement)
                if activeConnection.queryErrored() { break }
            }

            let error = activeConnection.queryErrored() ? activeConnection.lastErrorMessage() : nil
            DispatchQueue.main.async {
                if let error = error, !error.isEmpty {
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"), message: error)
                    completion(false)
                    return
                }

                self.lightweightStructureController.clearCachedTables()
                self.lightweightContentController.clearCachedTables()
                completion(true)
            }
        }
    }

    func runLightweightDatabaseRenameMutation(from sourceDatabase: String, to targetDatabase: String, status: String, completion: @escaping (Bool) -> Void) {
        guard let activeConnection = activeConnection else { return }

        showLightweightPlaceholder(status)
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            switch self.lightweightDatabaseRenamePreflight(from: sourceDatabase, to: targetDatabase, connection: activeConnection) {
            case .ready(let statements):
                for statement in statements {
                    _ = activeConnection.queryString(statement)
                    if activeConnection.queryErrored() { break }
                }

                let error = activeConnection.queryErrored() ? activeConnection.lastErrorMessage() : nil
                DispatchQueue.main.async {
                    if let error = error, !error.isEmpty {
                        self.showLightweightError(title: NSLocalizedString("Error", comment: "error"), message: error)
                        completion(false)
                        return
                    }

                    self.lightweightStructureController.clearCachedTables()
                    self.lightweightContentController.clearCachedTables()
                    completion(true)
                }
            case .sourceMissing:
                DispatchQueue.main.async {
                    self.showLightweightError(title: NSLocalizedString("Unable to rename database", comment: "unable to rename database message"),
                                             message: String(format: NSLocalizedString("The database '%@' no longer exists.", comment: "database rename source missing message"), sourceDatabase))
                    completion(false)
                }
            case .targetExists:
                DispatchQueue.main.async {
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                             message: String(format: NSLocalizedString("The name '%@' is already used.", comment: "message when trying to rename a table/view/proc/etc to an already used name"), targetDatabase))
                    completion(false)
                }
            case .unsupportedObjects:
                DispatchQueue.main.async {
                    self.showLightweightDatabaseRenameUnsupportedAlert(database: sourceDatabase)
                    completion(false)
                }
            case .failed(let message):
                DispatchQueue.main.async {
                    self.showLightweightError(title: NSLocalizedString("Unable to rename database", comment: "unable to rename database message"), message: message)
                    completion(false)
                }
            }
        }
    }

    func lightweightDatabaseHasNonTableObjects(_ database: String, connection: SPMySQLConnection) -> Bool {
        return loadLightweightDatabaseRenameObjects(for: database, connection: connection).contains { $0.type != .table }
    }

    func runLightweightDatabaseCopyMutation(from sourceDatabase: String,
                                            to targetDatabase: String,
                                            copyContent: Bool,
                                            status: String,
                                            completion: @escaping (Bool) -> Void) {
        guard let activeConnection = activeConnection else { return }

        showLightweightPlaceholder(status)
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            let databases = activeConnection.databases() as? [String] ?? []
            guard databases.contains(sourceDatabase), !databases.contains(targetDatabase) else {
                DispatchQueue.main.async {
                    self.showLightweightError(title: NSLocalizedString("Unable to copy database", comment: "unable to copy database message"),
                                              message: String(format: NSLocalizedString("An error occurred while trying to copy the database '%@' to '%@'.", comment: "unable to copy database message informative message"), sourceDatabase, targetDatabase))
                    completion(false)
                }
                return
            }

            let objects = self.loadLightweightDatabaseRenameObjects(for: sourceDatabase, connection: activeConnection)
            if activeConnection.queryErrored() {
                let error = activeConnection.lastErrorMessage() ?? ""
                DispatchQueue.main.async {
                    self.showLightweightError(title: NSLocalizedString("Unable to copy database", comment: "unable to copy database message"),
                                              message: error.isEmpty ? String(format: NSLocalizedString("An error occurred while trying to copy the database '%@' to '%@'.", comment: "unable to copy database message informative message"), sourceDatabase, targetDatabase) : error)
                    completion(false)
                }
                return
            }

            let tables = objects.filter { $0.type == .table }.map(\.name)
            var options: [String] = []
            if let defaults = self.lightweightDatabaseDefaults(for: sourceDatabase, connection: activeConnection) {
                if let encoding = defaults.encoding, !encoding.isEmpty {
                    options.append("DEFAULT CHARACTER SET = \(Self.backtickQuoted(encoding))")
                }
                if let collation = defaults.collation, !collation.isEmpty {
                    options.append("DEFAULT COLLATE = \(Self.backtickQuoted(collation))")
                }
            }

            _ = activeConnection.queryString("CREATE DATABASE \(Self.backtickQuoted(targetDatabase)) \(options.joined(separator: " "))")
            var success = !activeConnection.queryErrored()
            var error = success ? nil : activeConnection.lastErrorMessage()
            var didDisableForeignKeyChecks = false
            var didStoreSQLMode = false

            if success {
                _ = activeConnection.queryString("/*!32352 SET foreign_key_checks=0 */")
                success = success && !activeConnection.queryErrored()
                didDisableForeignKeyChecks = success
                if !success { error = activeConnection.lastErrorMessage() }
            }
            if success {
                _ = activeConnection.queryString("/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */")
                success = success && !activeConnection.queryErrored()
                didStoreSQLMode = success
                if !success { error = activeConnection.lastErrorMessage() }
            }

            if success {
                for table in tables {
                    guard let createStatement = self.lightweightCreateTableCopyStatement(table: table,
                                                                                        sourceDatabase: sourceDatabase,
                                                                                        targetDatabase: targetDatabase,
                                                                                        connection: activeConnection) else {
                        success = false
                        break
                    }

                    _ = activeConnection.queryString(createStatement)
                    if activeConnection.queryErrored() {
                        success = false
                        error = activeConnection.lastErrorMessage()
                        break
                    }

                    if copyContent {
                        _ = activeConnection.queryString("INSERT INTO \(Self.backtickQuoted(targetDatabase)).\(Self.backtickQuoted(table)) SELECT * FROM \(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(table))")
                        if activeConnection.queryErrored() {
                            success = false
                            error = activeConnection.lastErrorMessage()
                            break
                        }
                    }
                }
            }

            if didDisableForeignKeyChecks {
                _ = activeConnection.queryString("/*!32352 SET foreign_key_checks=1 */")
                if activeConnection.queryErrored(), error == nil {
                    success = false
                    error = activeConnection.lastErrorMessage()
                }
            }
            if didStoreSQLMode {
                _ = activeConnection.queryString("/*!40101 SET SQL_MODE=@OLD_SQL_MODE */")
                if activeConnection.queryErrored(), error == nil {
                    success = false
                    error = activeConnection.lastErrorMessage()
                }
            }

            DispatchQueue.main.async {
                if success {
                    self.lightweightStructureController.clearCachedTables()
                    self.lightweightContentController.clearCachedTables()
                    completion(true)
                    return
                }

                self.showLightweightError(title: NSLocalizedString("Unable to copy database", comment: "unable to copy database message"),
                                          message: error?.isEmpty == false ? error! : String(format: NSLocalizedString("An error occurred while trying to copy the database '%@' to '%@'.", comment: "unable to copy database message informative message"), sourceDatabase, targetDatabase))
                completion(false)
            }
        }
    }

    func lightweightCreateTableCopyStatement(table: String, sourceDatabase: String, targetDatabase: String, connection: SPMySQLConnection) -> String? {
        guard let result = connection.queryString("SHOW CREATE TABLE \(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(table))") else {
            return nil
        }

        result.returnDataAsStrings = true
        guard let row = result.getRowAsArray(), row.count > 1 else { return nil }
        var createStatement = Self.displayString(for: row[1])
        let unqualifiedTable = Self.backtickQuoted(table)
        let qualifiedTable = "\(Self.backtickQuoted(targetDatabase)).\(unqualifiedTable)"
        for prefix in ["CREATE TABLE ", "CREATE TEMPORARY TABLE "] {
            let needle = "\(prefix)\(unqualifiedTable)"
            if let range = createStatement.range(of: needle, options: [.caseInsensitive]) {
                createStatement.replaceSubrange(range, with: "\(prefix)\(qualifiedTable)")
                return createStatement
            }
        }

        return nil
    }

    func runLightweightDatabaseAlterMutation(database: String,
                                             encoding: String,
                                             collation: String?,
                                             completion: @escaping (Bool) -> Void) {
        var statement = "ALTER DATABASE \(Self.backtickQuoted(database)) DEFAULT CHARACTER SET \(Self.backtickQuoted(encoding))"
        if let collation = collation, !collation.isEmpty {
            statement += " DEFAULT COLLATE \(Self.backtickQuoted(collation))"
        }

        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Altering %@...", comment: "Altering database task string"), database),
                                       statement: statement) { [weak self] success in
            guard let self = self else { return }
            guard success else {
                completion(false)
                return
            }

            completion(true)
        }
    }

    func duplicateLightweightObject(_ sourceName: String,
                                    to targetName: String,
                                    type: SALightweightTableObjectType,
                                    sourceDatabase: String,
                                    targetDatabase: String,
                                    copyContent: Bool) {
        guard let activeConnection = activeConnection else { return }

        showLightweightPlaceholder(String(format: NSLocalizedString("Duplicating %@...", comment: "Duplicating table task string"), sourceName))
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            _ = activeConnection.selectDatabase(sourceDatabase)
            var statements: [String] = []
            if type == .view {
                if let result = activeConnection.queryString("SHOW CREATE VIEW \(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(sourceName))"),
                   let row = result.getRowAsArray(),
                   row.count > 1,
                   let createView = row[1] as? String {
                    statements = [createView.replacingOccurrences(of: Self.backtickQuoted(sourceName), with: Self.backtickQuoted(targetName), options: [], range: createView.range(of: Self.backtickQuoted(sourceName)))]
                }
            } else {
                statements = ["CREATE TABLE \(Self.backtickQuoted(targetDatabase)).\(Self.backtickQuoted(targetName)) LIKE \(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(sourceName))"]
                if copyContent {
                    statements.append("INSERT INTO \(Self.backtickQuoted(targetDatabase)).\(Self.backtickQuoted(targetName)) SELECT * FROM \(Self.backtickQuoted(sourceDatabase)).\(Self.backtickQuoted(sourceName))")
                }
            }

            if statements.isEmpty {
                DispatchQueue.main.async {
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: NSLocalizedString("The object could not be duplicated.", comment: "lightweight duplicate failed message"))
                }
                return
            }

            for statement in statements {
                _ = activeConnection.queryString(statement)
                if activeConnection.queryErrored() { break }
            }

            let error = activeConnection.queryErrored() ? activeConnection.lastErrorMessage() : nil
            DispatchQueue.main.async {
                if let error = error, !error.isEmpty {
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"), message: error)
                    return
                }

                self.lightweightStructureController.clearCachedTables()
                self.lightweightContentController.clearCachedTables()
                self.loadTables(for: targetDatabase, restoringTable: targetName)
            }
        }
    }

    func duplicateLightweightRoutine(_ sourceName: String, to targetName: String, type: SALightweightTableObjectType, database: String, dropSource: Bool) {
        guard let activeConnection = activeConnection else { return }

        let keyword = type == .procedure ? "PROCEDURE" : "FUNCTION"
        showLightweightPlaceholder(String(format: NSLocalizedString("Duplicating %@...", comment: "Duplicating table task string"), sourceName))
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak activeConnection] in
            guard let self = self, let activeConnection = activeConnection else { return }

            _ = activeConnection.selectDatabase(database)
            guard let result = activeConnection.queryString("SHOW CREATE \(keyword) \(Self.backtickQuoted(database)).\(Self.backtickQuoted(sourceName))") else {
                DispatchQueue.main.async {
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: activeConnection.lastErrorMessage() ?? "")
                }
                return
            }

            result.returnDataAsStrings = true
            guard let row = result.getRowAsArray(), row.count > 2, let createSyntax = row[2] as? String else {
                DispatchQueue.main.async {
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"),
                                              message: NSLocalizedString("Couldn't get create syntax.", comment: "message of panel when table information cannot be retrieved"))
                }
                return
            }

            let escapedSource = NSRegularExpression.escapedPattern(for: Self.backtickQuoted(sourceName))
            let pattern = "(?<=\(keyword) )\(escapedSource)"
            let renamedSyntax = createSyntax.replacingOccurrences(of: pattern,
                                                                  with: Self.backtickQuoted(targetName),
                                                                  options: .regularExpression)
            _ = activeConnection.queryString(renamedSyntax)
            if !activeConnection.queryErrored(), dropSource {
                _ = activeConnection.queryString("DROP \(keyword) \(Self.backtickQuoted(database)).\(Self.backtickQuoted(sourceName))")
            }

            let error = activeConnection.queryErrored() ? activeConnection.lastErrorMessage() : nil
            DispatchQueue.main.async {
                if let error = error, !error.isEmpty {
                    self.showLightweightError(title: NSLocalizedString("Error", comment: "error"), message: error)
                    return
                }

                self.lightweightStructureController.clearCachedTables()
                self.lightweightContentController.clearCachedTables()
                self.handleLightweightPinnedTableRename(from: sourceName, to: targetName)
                self.loadTables(for: database, restoringTable: targetName)
            }
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
                self.lightweightDatabases = databases
                let selectedDatabase = self.selectedDatabase.flatMap { databases.contains($0) ? $0 : nil }
                self.databaseToolbarController.reloadDatabases(databases, selectedDatabase: selectedDatabase)
            }
        }
    }

    private func selectLightweightDatabaseInToolbar(_ database: String) {
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

    private func clearLightweightDatabaseSelection(afterRemoving database: String) {
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

    private func applyLightweightDatabaseRename(from oldDatabase: String, to newDatabase: String) {
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

    private func postLightweightDatabaseCreatedRemovedRenamedNotification() {
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

    @objc func legacyDatabaseDocumentForMenuAction() -> SPDatabaseDocument {
        return installLegacyDatabaseDocumentIfNeeded(selectingDatabase: selectedDatabase, item: selectedTable)
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

    private func toggleLightweightConsole() {
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

    private static func sqlString(_ value: String) -> String {
        return "'\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func displayString(for value: Any?) -> String {
        guard let value = value else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return "\(value)"
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func typeGrouping(forColumnType type: String) -> String {
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
        alert.window.animationBehavior = .none

        alert.runModalCentered(over: window)
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
        alert.window.animationBehavior = .none

        alert.runModalCentered(over: window)
    }

    private func showLightweightCreateSyntaxError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Error", comment: "error message title")
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        alert.window.animationBehavior = .none

        alert.runModalCentered(over: window)
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

private extension SPWindowController {
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

    private func lightweightConnectionDisplayName() -> String {
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

    private func lightweightConsoleConnectionName() -> String {
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

    private func lightweightConsoleDatabaseName() -> String {
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
        password = info.password.isEmpty && !info.connectionKeychainItemName.isEmpty ? "SequelAceSecretPassword" : info.password
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
        sshPassword = info.sshPassword.isEmpty && !info.connectionSSHKeychainItemName.isEmpty ? "SequelAceSecretPassword" : info.sshPassword
        sshKeyLocationEnabled = info.sshKeyLocationEnabled
        sshKeyLocation = info.sshKeyLocation
        sshPort = info.sshPort
        connectionKeychainID = info.connectionKeychainID
        connectionKeychainItemName = info.connectionKeychainItemName
        connectionKeychainItemAccount = info.connectionKeychainItemAccount
        connectionSSHKeychainItemName = info.connectionSSHKeychainItemName
        connectionSSHKeychainItemAccount = info.connectionSSHKeychainItemAccount
    }
}
