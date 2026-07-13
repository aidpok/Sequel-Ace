//
//  SPWindowController+LightweightShell.swift
//  Sequel Ace
//

import Cocoa
import UniformTypeIdentifiers

extension SPWindowController {
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

    func lightweightQueryText() -> String {
        lightweightQueryController.saveCurrentSessionState()
        return lightweightQueryController.textView.string
    }

    func lightweightQueryCount() -> Int {
        let text = lightweightQueryText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }

        let count = text
            .split(separator: ";")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        return max(count, 1)
    }

    func saveLightweightQuerySheet() {
        let queryText = lightweightQueryText()
        guard !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let openedSQLFileURL = lightweightQueryController.openedSQLFileURL,
           !openedSQLFileURL.path.isEmpty {
            do {
                try queryText.write(to: openedSQLFileURL,
                                    atomically: true,
                                    encoding: lightweightQueryController.openedSQLFileEncoding ?? .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
            return
        }

        let panel = NSSavePanel()
        panel.allowsOtherFileTypes = false
        panel.canSelectHiddenExtension = true
        if let contentType = UTType(filenameExtension: SPFileExtensionSQL as String) {
            panel.allowedContentTypes = [contentType]
        }
        panel.nameFieldStringValue = UserDefaults.standard.string(forKey: "lastSqlFileName") ?? ""
        panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow()) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try queryText.write(to: url, atomically: true, encoding: .utf8)
                self.lightweightQueryController.setSQLFile(url: url, encoding: .utf8)
                UserDefaults.standard.set(url.lastPathComponent, forKey: "lastSqlFileName")
                UserDefaults.standard.set(String.Encoding.utf8.rawValue, forKey: SPLastSQLFileEncoding)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func saveLightweightSession(to url: URL, options: SALightweightSaveConnectionOptions) {
        let userInfo: [String: Any] = [
            "contextInfo": "saveSession",
            "encrypted": options.encrypt,
            "saveConnectionEncryptString": options.encryptionPassword,
            "auto_connect": options.autoConnect,
            "save_password": options.savePassword,
            "include_session": options.includeSession,
            "save_editor_content": options.includeQuery
        ]
        NotificationCenter.default.post(name: .SPDocumentSaveToSPF, object: url.path, userInfo: userInfo)
    }

    func saveLightweightConnection(to url: URL, options: SALightweightSaveConnectionOptions) {
        synchronizeLightweightDocumentScope(for: url)

        do {
            try writeLightweightConnection(to: url, options: options)
            lightweightConnectionSaveOptions = options
            (NSApp.delegate as? SPAppController)?.setSpfSessionDocData([
                "encrypted": options.encrypt,
                "e_string": options.encryptionPassword,
                "auto_connect": options.autoConnect,
                "save_password": options.savePassword,
                "include_session": options.includeSession,
                "save_editor_content": options.includeQuery
            ])
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            lightweightConnectionFileURL = url
            updateLightweightWindowTitle()
            markLightweightResumeStateChanged()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc(setLightweightConnectionSaveOptionsEncrypted:encryptionPassword:autoConnect:savePassword:includeSession:includeQuery:)
    func setLightweightConnectionSaveOptions(encrypted: Bool,
                                             encryptionPassword: String,
                                             autoConnect: Bool,
                                             savePassword: Bool,
                                             includeSession: Bool,
                                             includeQuery: Bool) {
        lightweightConnectionSaveOptions = SALightweightSaveConnectionOptions(encrypt: encrypted,
                                                                              encryptionPassword: encryptionPassword,
                                                                              autoConnect: autoConnect,
                                                                              savePassword: savePassword,
                                                                              includeSession: includeSession,
                                                                              includeQuery: includeQuery)
    }

    @objc(saveLightweightConnectionFileAtPathUsingCurrentSaveOptions:)
    func saveLightweightConnectionFileAtPathUsingCurrentSaveOptions(_ path: String) -> Bool {
        do {
            let url = URL(fileURLWithPath: path)
            synchronizeLightweightDocumentScope(for: url)
            try writeLightweightConnection(to: url, options: lightweightConnectionSaveOptions)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    @objc(saveLightweightConnectionFileAtPath:encrypted:encryptionPassword:autoConnect:savePassword:includeSession:includeQuery:)
    func saveLightweightConnectionFile(atPath path: String,
                                       encrypted: Bool,
                                       encryptionPassword: String,
                                       autoConnect: Bool,
                                       savePassword: Bool,
                                       includeSession: Bool,
                                       includeQuery: Bool) -> Bool {
        do {
            let url = URL(fileURLWithPath: path)
            synchronizeLightweightDocumentScope(for: url)
            try writeLightweightConnection(to: url,
                                           options: SALightweightSaveConnectionOptions(encrypt: encrypted,
                                                                                       encryptionPassword: encryptionPassword,
                                                                                       autoConnect: autoConnect,
                                                                                       savePassword: savePassword,
                                                                                       includeSession: includeSession,
                                                                                       includeQuery: includeQuery))
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    @objc func lightweightConnectionFileURLForSessionBundle() -> URL? {
        return lightweightConnectionFileURL
    }

    func writeLightweightConnection(to url: URL, options: SALightweightSaveConnectionOptions) throws {
        guard let spfStructure = lightweightConnectionSPFStructure(options: options) else { return }

        let data = try PropertyListSerialization.data(fromPropertyList: spfStructure,
                                                      format: .xml,
                                                      options: 0)
        try data.write(to: url, options: .atomic)
    }

    func lightweightConnectionSPFStructure(options: SALightweightSaveConnectionOptions) -> NSMutableDictionary? {
        guard let state = lightweightLegacyStateDictionary(includePasswords: options.savePassword,
                                                           includeSession: options.includeSession,
                                                           includeQuery: options.includeQuery) else { return nil }

        let spfStructure = NSMutableDictionary()
        spfStructure[SPFVersionKey] = 1
        spfStructure[SPFFormatKey] = SPFConnectionContentType
        spfStructure["rdbms_type"] = "mysql"
        if let activeServerVersion = activeServerVersion, !activeServerVersion.isEmpty {
            spfStructure["rdbms_version"] = activeServerVersion
        }
        spfStructure["auto_connect"] = options.autoConnect
        spfStructure["encrypted"] = options.encrypt
        if let favorites = lightweightQueryController.documentScopedQueryFavoritesForSPF() {
            spfStructure[SPQueryFavorites] = favorites
        }
        if let contentFilters = lightweightContentController.documentScopedContentFiltersForSPF() {
            spfStructure[SPContentFilters] = contentFilters
        }

        if options.encrypt {
            let dataToEncrypt = NSMutableData()
            let archiver = NSKeyedArchiver(forWritingWith: dataToEncrypt)
            archiver.encode(state, forKey: "data")
            archiver.finishEncoding()
            spfStructure["data"] = (dataToEncrypt as Data as NSData).dataEncrypted(withPassword: options.encryptionPassword)
        } else {
            spfStructure["data"] = state
        }

        return spfStructure
    }

    func synchronizeLightweightDocumentScope(for url: URL) {
        lightweightQueryController.setDocumentURLForLegacyQueryConsumers(url)
        lightweightContentController.setContentFilterDocumentURL(lightweightQueryController.effectiveDocumentURLForLegacyQueryConsumers)
    }

    func lightweightLegacyStateDictionary(includePasswords: Bool, includeSession: Bool, includeQuery: Bool) -> NSDictionary? {
        guard let activeConnectionInfo = activeConnectionInfo else { return nil }

        let state = NSMutableDictionary()
        state["connection"] = lightweightConnectionDictionary(for: activeConnectionInfo, includePasswords: includePasswords)
        let session = NSMutableDictionary()
        if includeSession {
            if let selectedDatabase = selectedDatabase, !selectedDatabase.isEmpty {
                session["database"] = selectedDatabase
            }
            if let selectedTable = selectedTable, !selectedTable.isEmpty {
                session["table"] = selectedTable
            }
            session["view"] = lightweightLegacyViewName()
            if let encoding = activeConnection?.encoding(), !encoding.isEmpty {
                session["connectionEncoding"] = encoding
            }
            state["lightweightSession"] = lightweightSessionSnapshotDictionary(includeQueryText: includeQuery, includeContentState: includeSession)
        }
        if includeQuery {
            let queryText = lightweightQueryText()
            if !queryText.isEmpty {
                session["queries"] = queryText
            }
        }
        if session.count > 0 {
            state["session"] = session
        }
        return state
    }

    func lightweightLegacyViewName() -> String {
        switch activeLightweightViewMode {
        case .structure:
            return "SP_VIEW_STRUCTURE"
        case .content:
            return "SP_VIEW_CONTENT"
        case .query:
            return "SP_VIEW_CUSTOMQUERY"
        case .status:
            return "SP_VIEW_STATUS"
        case .relations:
            return "SP_VIEW_RELATIONS"
        case .triggers:
            return "SP_VIEW_TRIGGERS"
        }
    }

    func lightweightNavigatorDatabaseNames() -> [String] {
        let databases = !lightweightDatabases.isEmpty
            ? lightweightDatabases
            : (activeConnection?.databases() as? [String] ?? [])
        var seen = Set<String>()
        return databases.filter { database in
            let key = database.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    func lightweightNavigatorTableTypeNumber(for type: SALightweightTableObjectType?) -> NSNumber {
        switch type {
        case .view:
            return 1
        case .procedure:
            return 2
        case .function:
            return 3
        default:
            return 0
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
    func performExplicitLegacyFallback(reason: String,
                                       selectingDatabase database: String? = nil,
                                       item: String? = nil,
                                       source: String = "Swift explicit legacy fallback",
                                       file: StaticString = #fileID,
                                       function: StaticString = #function,
                                       line: UInt = #line) -> SPDatabaseDocument {
        recordLightweightDBViewFallback(reason: reason,
                                        source: source,
                                        file: file,
                                        function: function,
                                        line: line)

        if lightweightDBViewFallbackIsBlocked {
            NSLog("[SA UI Diagnostics] DBView fallback blocked: %@", reason)
            showBlockedDBViewFallbackAlert(reason: reason)
            preconditionFailure("DBView fallback blocked: \(reason)")
        }

        return installLegacyDatabaseDocumentIfNeeded(selectingDatabase: database, item: item)
    }

    private var lightweightDBViewFallbackIsBlocked: Bool {
        #if SA_LIGHTWEIGHT_NO_DBVIEW
        return true
        #else
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["SA_LIGHTWEIGHT_NO_DBVIEW"] ?? environment["SALightweightDisableDBViewFallback"] {
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedValue == "1" || normalizedValue == "true" || normalizedValue == "yes" {
                return true
            }
        }

        return UserDefaults.standard.bool(forKey: "SALightweightDisableDBViewFallback")
        #endif
    }

    private func showBlockedDBViewFallbackAlert(reason: String) {
        let presentAlert = { [weak self] in
            guard let self = self else { return }
            let alert = NSAlert()
            alert.window.animationBehavior = .none
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Legacy database view fallback blocked", comment: "no DBView fallback gate title")
            alert.informativeText = String(format: NSLocalizedString("The lightweight no-DBView gate blocked a request to load the legacy database view.\n\nReason: %@", comment: "no DBView fallback gate message"), reason)
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))

            alert.runModalCenteredInKeyWindow()
        }

        if Thread.isMainThread {
            presentAlert()
        } else {
            DispatchQueue.main.sync(execute: presentAlert)
        }
    }

    @discardableResult
    private func installLegacyDatabaseDocumentIfNeeded(selectingDatabase database: String? = nil, item: String? = nil) -> SPDatabaseDocument {
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
            document.connectionController()?.applyLightweightConnectionInfo(activeConnectionInfo)
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

    enum LightweightDBViewLayout {
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
        lightweightTableInfoView.frame = lightweightTableInfoPane.bounds
        lightweightTableInfoView.autoresizingMask = [.width, .height]
        lightweightTableInfoPane.addSubview(lightweightTableInfoView)

        lightweightSidebarSplitView.addArrangedSubview(lightweightTablesPane)
        lightweightSidebarSplitView.addArrangedSubview(lightweightTableInfoPane)
        lightweightSidebarView.addSubview(lightweightSidebarSplitView)
        tablesListView.tableColumns.first?.width = tableScrollView.bounds.width

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
    func installLightweightDetailSubview(_ detailSubview: NSView, key: LightweightDetailKey) -> Bool {
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
        addLightweightSidebarAction(NSLocalizedString("Copy Create Table Syntax", comment: "copy create table syntax menu item"), #selector(copyLightweightCreateTableSyntax(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Show Create Table Syntax...", comment: "show create table syntax menu item"), #selector(showLightweightCreateTableSyntax(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Rename Table...", comment: "rename table menu title"), #selector(renameLightweightTable(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Duplicate Table...", comment: "duplicate table menu title"), #selector(duplicateLightweightTable(_:)), to: actionButton.menu)
        actionButton.menu?.addItem(.separator())
        addLightweightSidebarAction(NSLocalizedString("Truncate Table...", comment: "truncate table menu title"), #selector(truncateLightweightTable(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Remove Table...", comment: "remove table menu title"), #selector(removeLightweightTable(_:)), to: actionButton.menu)
        actionButton.menu?.addItem(.separator())
        addLightweightSidebarAction(NSLocalizedString("Toggle Pin Table", comment: "toggle pin table menu item"), #selector(togglePinLightweightTable(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Open Table in New Tab", comment: "open table in new tab title"), #selector(openLightweightTableInNewTab(_:)), to: actionButton.menu)
        addLightweightSidebarAction(NSLocalizedString("Open Table in New Window", comment: "open table in new window title"), #selector(openLightweightTableInNewWindow(_:)), to: actionButton.menu)
        actionButton.menu?.addItem(.separator())
        let exportItem = NSMenuItem(title: NSLocalizedString("Export", comment: "export selected table submenu title"), action: nil, keyEquivalent: "")
        let exportMenu = NSMenu(title: exportItem.title)
        addLightweightSidebarAction(NSLocalizedString("As SQL dump...", comment: "export selected table as sql menu item"),
                                    #selector(exportSelectedLightweightTableAs(_:)),
                                    to: exportMenu,
                                    tag: 0)
        addLightweightSidebarAction(NSLocalizedString("As CSV file...", comment: "export selected table as csv menu item"),
                                    #selector(exportSelectedLightweightTableAs(_:)),
                                    to: exportMenu,
                                    tag: 1)
        addLightweightSidebarAction(NSLocalizedString("As XML file...", comment: "export selected table as xml menu item"),
                                    #selector(exportSelectedLightweightTableAs(_:)),
                                    to: exportMenu,
                                    tag: 2)
        addLightweightSidebarAction(NSLocalizedString("As Dot file...", comment: "export selected table as dot menu item"),
                                    #selector(exportSelectedLightweightTableAs(_:)),
                                    to: exportMenu,
                                    tag: 3)
        exportItem.submenu = exportMenu
        lightweightSelectedTableExportMenuItem = exportItem
        actionButton.menu?.addItem(exportItem)
        actionButton.menu?.addItem(.separator())
        addLightweightSidebarAction(NSLocalizedString("Refresh Tables", comment: "refresh tables menu item"), #selector(refreshLightweightTables), to: actionButton.menu)
        tablesListView.menu = actionButton.menu
        updateLightweightSidebarActionMenuState()
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

    func addLightweightSidebarAction(_ title: String, _ action: Selector, to menu: NSMenu?, tag: Int = 0) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        menu?.addItem(item)
    }
}
