//
//  SPWindowController+LightweightDelegates.swift
//  Sequel Ace
//

import Cocoa
import ObjectiveC

private var lightweightCSVImportSourceReturnURLAssociationKey: UInt8 = 0

final class SALightweightImportOpenPanelAccessory: NSObject, NSOpenSavePanelDelegate {
    enum ImportFormat: Int {
        case automatic
        case sql
        case csv
        case tsv
    }

    private enum Layout {
        static let width: CGFloat = 384
        static let verticalPadding: CGFloat = 8
        static let formatHeight: CGFloat = 34
        static let csvTitleHeight: CGFloat = 18
    }

    let encodingAccessory: SALightweightSQLImportEncodingAccessory
    let csvAccessory: SALightweightCSVImportAccessory

    private let rootView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: 282))
    private let stackView = NSStackView()
    private let formatView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.formatHeight))
    private let formatPopup = NSPopUpButton(frame: NSRect(x: 74, y: 4, width: 246, height: 26), pullsDown: false)
    private let csvTitleLabel = NSTextField(labelWithString: NSLocalizedString("CSV/TSV Options", comment: "lightweight CSV import accessory title"))
    private var selectedURL: URL?

    var view: NSView {
        return rootView
    }

    var selectedEncoding: String.Encoding {
        return encodingAccessory.selectedEncoding
    }

    private var selectedImportFormat: ImportFormat {
        return ImportFormat(rawValue: formatPopup.selectedItem?.tag ?? ImportFormat.automatic.rawValue) ?? .automatic
    }

    init(selectedEncoding: String.Encoding, initialURL: URL? = nil) {
        self.encodingAccessory = SALightweightSQLImportEncodingAccessory(selectedEncoding: selectedEncoding)
        self.csvAccessory = SALightweightCSVImportAccessory(inferringFrom: initialURL)

        super.init()

        configureView()
        updateSelection(for: initialURL)
    }

    @discardableResult
    func saveCSVSettings() -> SALightweightCSVImportSettings {
        return csvAccessory.saveSettings()
    }

    @discardableResult
    func saveCSVSettings(for url: URL) -> SALightweightCSVImportSettings {
        var settings = csvAccessory.saveSettings()
        if selectedImportFormat == .tsv {
            settings.fieldTerminator = "\t"
        } else if selectedImportFormat == .automatic {
            settings = settings.applyingFileTypeInference(from: url)
        }
        return settings
    }

    func importFileKind(for url: URL) -> SPWindowController.LightweightImportFileKind? {
        switch selectedImportFormat {
        case .automatic:
            return SPWindowController.lightweightImportFileKind(for: url)
        case .sql:
            return .sql
        case .csv, .tsv:
            return .csv
        }
    }

    func needsTemporaryCSVImportCopy(for url: URL) -> Bool {
        guard selectedImportFormat == .csv || selectedImportFormat == .tsv else { return false }
        return !SALightweightCSVImportController.isSupportedFileURL(url)
    }

    func temporaryCSVFileExtension(for url: URL) -> String {
        let baseExtension = selectedImportFormat == .tsv ? "tsv" : "csv"
        let lowercasedName = url.lastPathComponent.lowercased()
        if lowercasedName.hasSuffix(".gz") {
            return "\(baseExtension).gz"
        }
        if lowercasedName.hasSuffix(".bz2") {
            return "\(baseExtension).bz2"
        }
        return baseExtension
    }

    func panelSelectionDidChange(_ sender: Any?) {
        guard let panel = sender as? NSOpenPanel else { return }
        updateSelection(for: panel.url)
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        if url.hasDirectoryPath { return true }

        return true
    }

    private func configureView() {
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.widthAnchor.constraint(equalToConstant: Layout.width).isActive = true

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = Layout.verticalPadding
        stackView.translatesAutoresizingMaskIntoConstraints = false

        csvTitleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        csvTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureFormatView()
        stackView.addArrangedSubview(encodingAccessory.view)
        stackView.addArrangedSubview(formatView)
        stackView.addArrangedSubview(csvTitleLabel)
        stackView.addArrangedSubview(csvAccessory.rootView)

        rootView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: rootView.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor)
        ])
    }

    private func configureFormatView() {
        formatView.widthAnchor.constraint(equalToConstant: Layout.width).isActive = true
        formatView.heightAnchor.constraint(equalToConstant: Layout.formatHeight).isActive = true

        let label = NSTextField(labelWithString: NSLocalizedString("Format:", comment: "lightweight import format popup label"))
        label.frame = NSRect(x: 0, y: 8, width: 68, height: 18)
        label.alignment = .right
        formatView.addSubview(label)

        formatPopup.addItem(withTitle: NSLocalizedString("Automatic", comment: "lightweight import automatic format menu item"))
        formatPopup.lastItem?.tag = ImportFormat.automatic.rawValue
        formatPopup.addItem(withTitle: NSLocalizedString("SQL", comment: "lightweight import SQL format menu item"))
        formatPopup.lastItem?.tag = ImportFormat.sql.rawValue
        formatPopup.addItem(withTitle: NSLocalizedString("CSV", comment: "lightweight import CSV format menu item"))
        formatPopup.lastItem?.tag = ImportFormat.csv.rawValue
        formatPopup.addItem(withTitle: NSLocalizedString("TSV", comment: "lightweight import TSV format menu item"))
        formatPopup.lastItem?.tag = ImportFormat.tsv.rawValue
        formatPopup.target = self
        formatPopup.action = #selector(importFormatChanged(_:))
        formatView.addSubview(formatPopup)
    }

    @objc private func importFormatChanged(_ sender: Any?) {
        updateSelection(for: selectedURL)
    }

    private func updateSelection(for url: URL?) {
        selectedURL = url

        let isCSV = importFileKind(for: url) == .csv
        csvTitleLabel.isHidden = !isCSV
        csvAccessory.rootView.isHidden = !isCSV

        if isCSV {
            var settings = csvAccessory.loadCurrentSettings(inferringFrom: selectedImportFormat == .automatic ? url : nil)
            if selectedImportFormat == .tsv {
                settings.fieldTerminator = "\t"
                csvAccessory.updateUI(with: settings)
            }
        }
    }

    private func importFileKind(for url: URL?) -> SPWindowController.LightweightImportFileKind? {
        guard let url else {
            switch selectedImportFormat {
            case .csv, .tsv:
                return .csv
            case .sql:
                return .sql
            case .automatic:
                return nil
            }
        }

        return importFileKind(for: url)
    }
}

private final class SALightweightCSVImportProgressSheet: NSObject {
    private enum Layout {
        static let width: CGFloat = 420
        static let height: CGFloat = 58
    }

    private let alert = NSAlert()
    private let progressIndicator = NSProgressIndicator()
    private let progressTextField = NSTextField(labelWithString: "")
    private var isShowing = false
    private var isFinishing = false

    var cancelHandler: (() -> Void)?

    init(sourceName: String) {
        super.init()

        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Importing CSV/TSV", comment: "lightweight CSV import progress title")
        alert.informativeText = String(format: NSLocalizedString("Importing %@…", comment: "lightweight CSV import progress message"), sourceName)
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        alert.accessoryView = makeAccessoryView()
    }

    func begin(on parentWindow: NSWindow?) {
        guard let parentWindow = parentWindow ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }

        isShowing = true
        alert.beginSheetModal(for: parentWindow) { [weak self] response in
            guard let self else { return }

            let shouldCancel = response == .alertFirstButtonReturn && !self.isFinishing
            self.isShowing = false
            self.isFinishing = false

            if shouldCancel {
                self.cancelHandler?()
            }
        }
    }

    func update(rowsImported: Int, bytesRead: UInt64, totalBytes: UInt64) {
        guard isShowing else { return }

        let updateBlock = { [weak self] in
            guard let self, self.isShowing else { return }

            if totalBytes > 1 {
                self.progressIndicator.isIndeterminate = false
                self.progressIndicator.maxValue = Double(totalBytes)
                self.progressIndicator.doubleValue = Double(min(bytesRead, totalBytes))
                self.progressTextField.stringValue = String(
                    format: NSLocalizedString("Imported %ld rows (%@ of %@).", comment: "lightweight CSV import determinate progress"),
                    rowsImported,
                    Self.byteCountString(bytesRead),
                    Self.byteCountString(totalBytes)
                )
            } else {
                self.progressIndicator.isIndeterminate = true
                self.progressIndicator.startAnimation(nil)
                self.progressTextField.stringValue = String(
                    format: NSLocalizedString("Imported %ld rows (%@).", comment: "lightweight CSV import indeterminate progress"),
                    rowsImported,
                    Self.byteCountString(bytesRead)
                )
            }
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }

    func close() {
        guard isShowing else { return }
        isFinishing = true

        if let parentWindow = alert.window.sheetParent {
            parentWindow.endSheet(alert.window, returnCode: .alertSecondButtonReturn)
        } else {
            isShowing = false
            isFinishing = false
        }
    }

    private func makeAccessoryView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: Layout.width).isActive = true
        view.heightAnchor.constraint(equalToConstant: Layout.height).isActive = true

        progressIndicator.controlSize = .small
        progressIndicator.style = .bar
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.isIndeterminate = true
        progressIndicator.usesThreadedAnimation = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.startAnimation(nil)

        progressTextField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        progressTextField.lineBreakMode = .byTruncatingMiddle
        progressTextField.stringValue = NSLocalizedString("Preparing import…", comment: "lightweight CSV import preparing progress")
        progressTextField.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(progressIndicator)
        view.addSubview(progressTextField)

        NSLayoutConstraint.activate([
            progressIndicator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),

            progressTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressTextField.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 8)
        ])

        return view
    }

    private static func byteCountString(_ byteCount: UInt64) -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(min(byteCount, UInt64(Int64.max))), countStyle: .file)
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
        cancelActiveLightweightCSVImportForWindowClose()
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
        scheduleLightweightSkipShowDatabaseWarning(for: connection)

        if pendingLightweightSessionSnapshot != nil {
            applyPendingLightweightSessionSnapshot()
            return
        }

        if let pendingSQLFileOpen = pendingLightweightSQLFileOpen {
            lightweightQueryController.setSQLFile(url: pendingSQLFileOpen.fileURL, encoding: pendingSQLFileOpen.encoding)
            setActiveLightweightViewMode(.query, persist: false)
            if let selectedDatabase = selectedDatabase {
                selectLightweightDatabaseInToolbar(selectedDatabase)
            }
            showLightweightQuery()
            lightweightQueryController.doPerformLoadQueryService(pendingSQLFileOpen.query)
            if let selectedDatabase = selectedDatabase {
                loadTables(for: selectedDatabase, restoringViewMode: .query)
            }
            pendingLightweightSQLFileOpen = nil
            return
        }

        setActiveLightweightViewMode(preferredLightweightViewModeFromPreferences(), persist: false)
        if let selectedDatabase = selectedDatabase {
            selectLightweightDatabaseInToolbar(selectedDatabase)
            loadTables(for: selectedDatabase)
        } else if activeLightweightViewMode == .query {
            showLightweightQuery()
        }
    }

    @objc func connectionDidFail(withError error: String, detail: String?) {
        showLightweightPlaceholder(error)
    }

    private func scheduleLightweightSkipShowDatabaseWarning(for connection: SPMySQLConnection) {
        guard UserDefaults.standard.bool(forKey: SPShowWarningSkipShowDatabase) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak connection] in
            guard let self = self,
                  let connection = connection,
                  self.activeConnection === connection,
                  UserDefaults.standard.bool(forKey: SPShowWarningSkipShowDatabase) else {
                return
            }

            DispatchQueue.global(qos: .utility).async { [weak self, weak connection] in
                guard let self = self,
                      let connection = connection,
                      let result = connection.queryString("SHOW VARIABLES LIKE 'skip_show_database'") else {
                    return
                }

                result.returnDataAsStrings = true
                result.defaultRowReturnType = SPMySQLResultRowAsDictionary

                guard !connection.queryErrored(),
                      result.numberOfRows() == 1,
                      let row = result.getRowAsDictionary() as? [String: Any],
                      self.stringValue(row["Value"] ?? row["VALUE"] ?? row["value"]).caseInsensitiveCompare("on") == .orderedSame else {
                    return
                }

                DispatchQueue.main.async { [weak self, weak connection] in
                    guard let self = self,
                          let connection = connection,
                          self.activeConnection === connection,
                          UserDefaults.standard.bool(forKey: SPShowWarningSkipShowDatabase) else {
                        return
                    }

                    NSAlert.createAlert(
                        title: NSLocalizedString("Warning", comment: "warning"),
                        message: NSLocalizedString("The skip-show-database variable of the database server is set to ON. Thus, you won't be able to list databases unless you have the SHOW DATABASES privilege.\n\nHowever, the databases are still accessible directly through SQL queries depending on your privileges.", comment: "Warning message during connection in case the variable skip-show-database is set to ON"),
                        primaryButtonTitle: NSLocalizedString("OK", comment: "OK button"),
                        secondaryButtonTitle: NSLocalizedString("Never show this again", comment: "Never show this again"),
                        secondaryButtonHandler: {
                            UserDefaults.standard.set(false, forKey: SPShowWarningSkipShowDatabase)
                        }
                    )
                }
            }
        }
    }
}

extension SPWindowController {
    enum LightweightSQLImportErrorChoice {
        case `continue`
        case ignoreAll
        case stop
    }

    enum LightweightImportFileKind {
        case sql
        case csv
    }

    enum LightweightClipboardImportKind {
        case sql
        case csv
        case tsv
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
                             message: NSLocalizedString("Select a database in the active lightweight connection before importing.", comment: "lightweight import unavailable message"))
    }

    static func lightweightImportFileKind(for url: URL) -> LightweightImportFileKind? {
        if isLightweightSQLImportFileURL(url) {
            return .sql
        }

        if SALightweightCSVImportController.isSupportedFileURL(url) {
            return .csv
        }

        return nil
    }

    func lightweightImportFileKind(for url: URL) -> LightweightImportFileKind? {
        return Self.lightweightImportFileKind(for: url)
    }

    func validateLightweightImportFileURL(_ url: URL, importKind: LightweightImportFileKind? = nil) -> Bool {
        guard importKind ?? lightweightImportFileKind(for: url) != nil else {
            NSSound.beep()
            showLightweightError(title: NSLocalizedString("Import Unsupported", comment: "lightweight import unsupported file title"),
                                 message: NSLocalizedString("This file was not imported. Lightweight import supports .sql, .sql.gz, .sql.bz2, .csv, .csv.gz, .csv.bz2, .tsv, .tsv.gz, and .tsv.bz2 files.", comment: "lightweight import unsupported file message"))
            return false
        }

        return true
    }

    func confirmLightweightSQLImport(sourceName: String) -> Bool {
        guard let selectedDatabase = selectedDatabase else { return false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Import SQL", comment: "lightweight SQL import confirmation title")
        if lightweightTables.isEmpty {
            alert.informativeText = String(format: NSLocalizedString("Import %@ into database “%@”?", comment: "lightweight SQL import confirmation message"), sourceName, selectedDatabase)
        } else {
            alert.informativeText = String(format: NSLocalizedString("Import %@ into database “%@”? The current database already has tables, so the import may overwrite data.", comment: "lightweight SQL import overwrite warning"), sourceName, selectedDatabase)
        }
        alert.addButton(withTitle: NSLocalizedString("Import", comment: "import button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        return runLightweightModalAlert(alert) == .alertFirstButtonReturn
    }

    func validateLightweightSQLImportFileURL(_ url: URL) -> Bool {
        guard isLightweightSQLImportFileURL(url) else {
            NSSound.beep()
            showLightweightError(title: NSLocalizedString("Import Unsupported", comment: "lightweight import unsupported file title"),
                                 message: NSLocalizedString("Lightweight SQL import supports .sql, .sql.gz, and .sql.bz2 files.", comment: "lightweight SQL import unsupported file message"))
            return false
        }

        return true
    }

    static func isLightweightSQLImportFileURL(_ url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        return filename.hasSuffix(".sql")
            || filename.hasSuffix(".sql.gz")
            || filename.hasSuffix(".sql.bz2")
    }

    func isLightweightSQLImportFileURL(_ url: URL) -> Bool {
        return Self.isLightweightSQLImportFileURL(url)
    }

    func isLightweightCSVImportFileURL(_ url: URL) -> Bool {
        return SALightweightCSVImportController.isSupportedFileURL(url)
    }

    func validateLightweightSQLImportFileSize(url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            _ = values.fileSize
        } catch {
            NSSound.beep()
            showLightweightError(title: NSLocalizedString("Import Error", comment: "Import Error title"),
                                 message: NSLocalizedString("The SQL file you selected could not be inspected.", comment: "lightweight SQL import file inspection error"))
            return false
        }

        return true
    }

    func startLightweightImport(url: URL, encoding: String.Encoding, csvSettings: SALightweightCSVImportSettings? = nil, importKind: LightweightImportFileKind? = nil, sourceName: String? = nil, sourceReturnURL: URL? = nil) {
        guard validateLightweightImportFileURL(url, importKind: importKind) else { return }

        switch importKind ?? lightweightImportFileKind(for: url) {
        case .sql:
            guard validateLightweightSQLImportFileSize(url: url) else { return }
            guard confirmLightweightSQLImport(sourceName: sourceName ?? url.lastPathComponent) else { return }
            guard let resolvedEncoding = resolvedLightweightSQLImportEncoding(for: url, selectedEncoding: encoding) else {
                NSSound.beep()
                showLightweightError(title: NSLocalizedString("File read error", comment: "File read error title (Import Dialog)"),
                                     message: NSLocalizedString("The SQL file encoding could not be detected. Choose an explicit encoding and try again.", comment: "lightweight SQL import autodetect read error"))
                return
            }
            startLightweightSQLImport(url: url, encoding: resolvedEncoding, sourceName: sourceName)
        case .csv:
            startLightweightCSVImport(url: url,
                                      encoding: encoding,
                                      settings: csvSettings ?? SALightweightCSVImportSettings.load(inferringFrom: url),
                                      sourceName: sourceName,
                                      sourceReturnURL: sourceReturnURL)
        case .none:
            return
        }
    }

    func resolvedLightweightSQLImportEncoding(for url: URL, selectedEncoding: String.Encoding) -> String.Encoding? {
        guard selectedEncoding.rawValue == 0 else { return selectedEncoding }

        let detectedEncoding = FileManager.default.detectEncodingforFile(atPath: url.path)
        guard detectedEncoding != 0 else { return nil }

        return String.Encoding(rawValue: detectedEncoding)
    }

    @discardableResult
    func startLightweightCSVImport(url: URL, encoding: String.Encoding = String.Encoding(rawValue: 0), settings: SALightweightCSVImportSettings, sourceName: String? = nil, sourceReturnURL: URL? = nil) -> Bool {
        guard !isLightweightConnectionBusyForImport(), let activeConnection, let database = selectedDatabase else {
            showLightweightImportUnavailableReason()
            return false
        }

        let controller = SALightweightCSVImportController(connection: activeConnection,
                                                         databaseName: database,
                                                         selectedTableName: selectedTable,
                                                         tableNames: lightweightTables,
                                                         fileURL: url)
        setLightweightCSVImportSourceReturnURL(sourceReturnURL, for: controller)
        controller.sourceEncoding = encoding.rawValue
        controller.captureSettings(withFieldTerminator: settings.fieldTerminator,
                                   lineTerminator: settings.lineTerminator,
                                   fieldEnclosedBy: settings.fieldEnclosedBy,
                                   escapeCharacter: settings.escapeCharacter,
                                   firstLineIsHeader: settings.firstLineIsHeader)

        retainActiveLightweightCSVImportController(controller)

        if controller.responds(to: #selector(SALightweightCSVImportController.beginFieldMapping(with:completion:))) {
            controller.beginFieldMapping(with: window) { [weak self, weak controller] accepted, error in
                guard let self,
                      let controller,
                      self.activeLightweightCSVImportController === controller else {
                    return
                }

                guard accepted else {
                    DispatchQueue.main.async { [weak self, weak controller] in
                        guard let self,
                              let controller,
                              self.activeLightweightCSVImportController === controller else {
                            return
                        }

                        let sourceReturnRequest = controller.fieldMappingSourceReturnRequest
                        let shouldReturnToSource = sourceReturnRequest != .none
                        let preservedSettings = self.lightweightCSVImportSettings(from: controller, fallback: settings)
                        let selectedSourceURL = sourceReturnRequest == .file ? self.lightweightCSVImportSourceReturnURL(for: controller) : nil
                        let clipboardKind = self.lightweightClipboardImportKind(forCSVImportURL: controller.fileURL,
                                                                                 settings: preservedSettings)

                        self.clearActiveLightweightCSVImportController(controller)

                        controller.clearTemporaryState()

                        if shouldReturnToSource {
                            if sourceReturnRequest == .clipboard {
                                self.importLightweightSQLFromClipboard(nil,
                                                                       csvSettings: preservedSettings,
                                                                       preferredDelimitedKind: clipboardKind)
                                return
                            }

                            self.presentLightweightImportOpenPanel(initialURL: selectedSourceURL,
                                                                   csvSettings: preservedSettings)
                            return
                        }

                        if !self.isLightweightCSVFieldMappingCancellation(error) {
                            self.showLightweightCSVImportFailed(sourceName: sourceName ?? url.lastPathComponent,
                                                                importError: nil,
                                                                rowErrors: [],
                                                                previewError: error)
                        }
                    }
                    return
                }

                self.beginActiveLightweightCSVImport(controller: controller,
                                                     sourceName: sourceName ?? url.lastPathComponent,
                                                     database: database,
                                                     previewError: nil)
            }
            return true
        }

        var previewError: Error?
        do {
            _ = try controller.prepareFieldMapperWithParsedPreviewRows()
        } catch {
            previewError = error
        }

        beginActiveLightweightCSVImport(controller: controller,
                                        sourceName: sourceName ?? url.lastPathComponent,
                                        database: database,
                                        previewError: previewError)
        return true
    }

    func lightweightCSVImportSettings(from controller: SALightweightCSVImportController,
                                      fallback: SALightweightCSVImportSettings) -> SALightweightCSVImportSettings {
        let capturedSettings = controller.capturedSettings()
        let firstLineIsHeader: Bool
        if let boolValue = capturedSettings["firstLineIsHeader"] as? Bool {
            firstLineIsHeader = boolValue
        } else if let numberValue = capturedSettings["firstLineIsHeader"] as? NSNumber {
            firstLineIsHeader = numberValue.boolValue
        } else {
            firstLineIsHeader = fallback.firstLineIsHeader
        }

        return SALightweightCSVImportSettings(
            fieldTerminator: capturedSettings["fieldTerminator"] as? String ?? fallback.fieldTerminator,
            lineTerminator: capturedSettings["lineTerminator"] as? String ?? fallback.lineTerminator,
            fieldEnclosedBy: capturedSettings["fieldEnclosedBy"] as? String ?? fallback.fieldEnclosedBy,
            escapeCharacter: capturedSettings["escapeCharacter"] as? String ?? fallback.escapeCharacter,
            firstLineIsHeader: firstLineIsHeader
        )
    }

    func lightweightClipboardImportKind(forCSVImportURL url: URL?,
                                        settings: SALightweightCSVImportSettings) -> LightweightClipboardImportKind {
        if let url, SALightweightCSVImportSettings.isTabSeparatedFile(url) {
            return .tsv
        }

        return settings.fieldTerminator == "\t" || settings.fieldTerminator == "\\t" ? .tsv : .csv
    }

    func retainActiveLightweightCSVImportController(_ controller: SALightweightCSVImportController) {
        activeLightweightCSVImportController = controller
        isLightweightImportRunning = true
        processing = true
    }

    func setLightweightCSVImportSourceReturnURL(_ url: URL?, for controller: SALightweightCSVImportController) {
        objc_setAssociatedObject(controller, &lightweightCSVImportSourceReturnURLAssociationKey, url, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func lightweightCSVImportSourceReturnURL(for controller: SALightweightCSVImportController) -> URL? {
        return objc_getAssociatedObject(controller, &lightweightCSVImportSourceReturnURLAssociationKey) as? URL ?? controller.fileURL
    }

    @discardableResult
    func clearActiveLightweightCSVImportController(_ controller: SALightweightCSVImportController) -> Bool {
        guard activeLightweightCSVImportController === controller else { return false }

        activeLightweightCSVImportController = nil
        isLightweightImportRunning = false
        processing = false
        return true
    }

    func cancelActiveLightweightCSVImportForWindowClose() {
        guard let controller = activeLightweightCSVImportController else { return }

        controller.cancelAndClearTemporaryState()
        _ = clearActiveLightweightCSVImportController(controller)
        setLightweightConsoleQueryMode(0)
    }

    func beginActiveLightweightCSVImport(controller: SALightweightCSVImportController, sourceName: String, database: String, previewError: Error?) {
        let progressSheet = SALightweightCSVImportProgressSheet(sourceName: sourceName)
        progressSheet.cancelHandler = { [weak controller] in
            controller?.cancelImport()
        }
        progressSheet.begin(on: window)

        setLightweightConsoleQueryMode(2)
        controller.beginImport(with: window, progress: { rowsImported, bytesRead, totalBytes in
            progressSheet.update(rowsImported: rowsImported,
                                 bytesRead: bytesRead,
                                 totalBytes: totalBytes)
        }) { [weak self, weak controller] result in
            guard let self,
                  let controller else {
                return
            }

            let importCreatedNewTable = controller.importIntoNewTable
            let targetTable = controller.selectedTableTarget
            guard self.clearActiveLightweightCSVImportController(controller) else { return }
            self.setLightweightConsoleQueryMode(0)
            progressSheet.close()

            if result.isCancelled {
                return
            }

            self.requestLightweightDatabases(forceReload: true)
            self.loadTables(for: database,
                            preservingSelection: !importCreatedNewTable,
                            restoringTable: importCreatedNewTable ? targetTable : nil)

            if let error = result.error {
                self.logLightweightCSVImportErrorsToConsole(sourceName: sourceName,
                                                            importError: error,
                                                            rowErrors: result.errors,
                                                            previewError: previewError)
                self.showLightweightCSVImportFailed(sourceName: sourceName,
                                                    importError: error,
                                                    rowErrors: result.errors,
                                                    previewError: previewError)
                return
            }

            if !result.errors.isEmpty {
                self.logLightweightCSVImportErrorsToConsole(sourceName: sourceName,
                                                            importError: nil,
                                                            rowErrors: result.errors,
                                                            previewError: previewError)
                self.showLightweightCSVImportCompletedWithErrors(sourceName: sourceName,
                                                                 rowsImported: result.rowsImported,
                                                                 errors: result.errors)
                return
            }

            self.showLightweightCSVImportComplete(sourceName: sourceName,
                                                  rowsImported: result.rowsImported)
        }
    }

    func isLightweightCSVFieldMappingCancellation(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return false }

        return error.domain == SALightweightCSVImportControllerErrorDomain && error.code == 9
    }

    func logLightweightCSVImportErrorsToConsole(sourceName: String, importError: Error?, rowErrors: [String], previewError: Error?) {
        let prefs = UserDefaults.standard
        guard prefs.bool(forKey: SPConsoleEnableLogging),
              prefs.bool(forKey: SPConsoleEnableImportExportLogging),
              prefs.bool(forKey: SPConsoleEnableErrorLogging) else {
            return
        }

        if let previewError = previewError {
            logLightweightConsoleError(String(format: NSLocalizedString("/* CSV import preview error for %@: %@ */", comment: "lightweight CSV import preview console error"), sourceName, previewError.localizedDescription))
        }

        if let importError = importError {
            logLightweightConsoleError(String(format: NSLocalizedString("/* CSV import error for %@: %@ */", comment: "lightweight CSV import console error"), sourceName, importError.localizedDescription))
        }

        for rowError in rowErrors {
            logLightweightConsoleError(rowError)
        }
    }

    func showLightweightCSVImportFailed(sourceName: String, importError: Error?, rowErrors: [String], previewError: Error?) {
        NSSound.beep()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("CSV Import Failed", comment: "lightweight CSV import failed title")

        var details = [
            String(format: NSLocalizedString("The lightweight CSV/TSV import for %@ could not finish.", comment: "lightweight CSV import failed message"), sourceName)
        ]

        if let previewError = previewError {
            details.append(String(format: NSLocalizedString("Preview/field mapper preparation did not complete: %@", comment: "lightweight CSV preview preparation warning"), previewError.localizedDescription))
        }

        if let importError = importError {
            details.append(importError.localizedDescription)
        }

        if !rowErrors.isEmpty {
            details.append(rowErrors.prefix(20).joined(separator: "\n"))
        }

        details.append(NSLocalizedString("Review the details, adjust the file or import settings, and try again.", comment: "lightweight CSV terminal failure message"))

        alert.informativeText = details.joined(separator: "\n\n")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        _ = runLightweightModalAlert(alert)
    }

    func showLightweightCSVImportCompletedWithErrors(sourceName: String, rowsImported: Int, errors: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("CSV Import Completed With Errors", comment: "lightweight CSV import completed with errors title")
        let shownErrors = errors.prefix(30).joined(separator: "\n")
        alert.informativeText = String(format: NSLocalizedString("Imported %ld rows from %@, but MySQL reported row errors:\n\n%@", comment: "lightweight CSV import completed with errors message"), rowsImported, sourceName, shownErrors)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        _ = runLightweightModalAlert(alert)
    }

    func showLightweightCSVImportComplete(sourceName: String, rowsImported: Int) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("CSV Import Complete", comment: "lightweight CSV import complete title")
        alert.informativeText = String(format: NSLocalizedString("Imported %ld rows from %@.", comment: "lightweight CSV import complete message"), rowsImported, sourceName)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        _ = runLightweightModalAlert(alert)
    }

    func startLightweightSQLImport(url: URL, encoding: String.Encoding, sourceName: String? = nil, removeTemporaryFileWhenFinished: Bool = false) {
        guard !isLightweightConnectionBusyForImport(), let activeConnection, let database = selectedDatabase else {
            if removeTemporaryFileWhenFinished {
                try? FileManager.default.removeItem(at: url)
            }
            showLightweightImportUnavailableReason()
            return
        }

        let displaySourceName = sourceName ?? url.lastPathComponent
        let fieldNames = selectedTable.flatMap { table in
            lightweightStructureController.cachedColumnMetadata(for: table, database: database)
        }?.compactMap { $0["name"] } ?? []
        lightweightQueryController.loadQuery(database: database,
                                             table: selectedTable,
                                             connection: activeConnection,
                                             databases: lightweightDatabases,
                                             tables: lightweightTables,
                                             tableTypes: lightweightTableTypes,
                                             fieldNames: fieldNames)

        isLightweightImportRunning = true
        processing = true
        setLightweightConsoleQueryMode(2)
        showLightweightQuery()

        lightweightQueryController.startStreamingSQLImport(from: url,
                                                           encoding: encoding,
                                                           ignoresErrorsByDefault: lightweightSQLImportIgnoresErrorsByDefault(),
                                                           errorChoice: { [weak self] error in
                                                               self?.lightweightSQLImportErrorChoice(error) ?? .stop
                                                           },
                                                            charsetErrorChoice: { [weak self] in
                                                                self?.confirmLightweightCharsetImportError() ?? false
                                                            }) { [weak self] result in
            guard let self else { return }
            if removeTemporaryFileWhenFinished {
                try? FileManager.default.removeItem(at: url)
            }

            self.isLightweightImportRunning = false
            self.processing = false
            self.setLightweightConsoleQueryMode(0)
            self.requestLightweightDatabases(forceReload: true)
            if !SASQLDatabaseContext.databaseNameChanged(from: result.initialDatabaseContext,
                                                          to: result.databaseContext) {
                self.loadTables(for: database, preservingSelection: true)
            }

            if let readError = result.readError {
                NSSound.beep()
                switch readError {
                case .cannotOpenFile:
                    self.showLightweightError(title: NSLocalizedString("Import Error", comment: "Import Error title"),
                                              message: NSLocalizedString("The SQL file you selected could not be found or read.", comment: "SQL file open error"))
                case .cannotDecode:
                    self.showLightweightError(title: NSLocalizedString("File read error", comment: "File read error title (Import Dialog)"),
                                              message: String(format: NSLocalizedString("The SQL file could not be read using %@.", comment: "lightweight SQL import encoding read error"), String.localizedName(of: encoding)))
                }
            } else if result.errors.isEmpty {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Import Complete", comment: "lightweight SQL import complete title")
                alert.informativeText = String(format: NSLocalizedString("Imported %ld SQL statements from %@.", comment: "lightweight SQL import complete message"), result.queriesPerformed, displaySourceName)
                alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
                self.deliverLightweightSQLImportFinishedNotification(sourceName: displaySourceName)
                _ = self.runLightweightModalAlert(alert)
            } else {
                self.showLightweightSQLImportErrors(result.errors.joined(separator: "\n"))
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
            var ignoreSQLErrors = self.lightweightSQLImportIgnoresErrorsByDefault()
            var ignoreCharsetError = false
            var connectionEncodingToRestore: String?
            var sqlModeToRestore: String?
            var databaseContext: String? = database
            var droppedSelectedDatabaseContext: String?
            var databaseNamesAreCaseSensitive = false
            var databaseNameCaseSensitivityWasLoaded = false
            let serverVersion = Int(connection.serverMajorVersion()) * 10_000
                + Int(connection.serverMinorVersion()) * 100
                + Int(connection.serverReleaseVersion())
            let serverIsMariaDB = connection.serverVersionString()?.range(of: "mariadb", options: .caseInsensitive) != nil

            defer {
                if let connectionEncodingToRestore = connectionEncodingToRestore {
                    _ = connection.queryString("SET NAMES '\(connectionEncodingToRestore)'")
                }
                if let sqlModeToRestore = sqlModeToRestore {
                    _ = connection.queryString("SET SQL_MODE=\(Self.sqlSingleQuoted(sqlModeToRestore))")
                }
                connection.retryQueriesOnConnectionFailure = oldRetryQueries

                let completedDatabaseContext = databaseContext
                let completedDroppedSelectedDatabaseContext = droppedSelectedDatabaseContext

                DispatchQueue.main.async {
                    self.isLightweightImportRunning = false
                    self.processing = false
                    self.setLightweightConsoleQueryMode(0)
                    self.requestLightweightDatabases(forceReload: true)
                    if let completedDatabaseContext, !completedDatabaseContext.isEmpty {
                        self.loadTables(for: completedDatabaseContext, preservingSelection: true)
                    } else if let completedDroppedSelectedDatabaseContext, !completedDroppedSelectedDatabaseContext.isEmpty {
                        self.clearLightweightDatabaseSelection(afterRemoving: completedDroppedSelectedDatabaseContext)
                    } else {
                        self.loadTables(for: database, preservingSelection: true)
                    }

                    if errors.isEmpty {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("Import Complete", comment: "lightweight SQL import complete title")
                        alert.informativeText = String(format: NSLocalizedString("Imported %ld SQL statements from %@.", comment: "lightweight SQL import complete message"), queriesPerformed, sourceName)
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
                        self.deliverLightweightSQLImportFinishedNotification(sourceName: sourceName)
                        _ = self.runLightweightModalAlert(alert)
                    } else {
                        self.showLightweightSQLImportErrors(errors.joined(separator: "\n"))
                    }
                }
            }

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

                // Only a case-only DROP comparison needs lower_case_table_names.
                // Keep this immediately before the user statement so the
                // import query remains the source for connection status calls.
                if !databaseNameCaseSensitivityWasLoaded,
                   SASQLDatabaseContext.requiresDatabaseNameCaseSensitivityLookup(for: query,
                                                                                   currentDatabase: databaseContext,
                                                                                   serverVersion: serverVersion,
                                                                                   serverIsMariaDB: serverIsMariaDB) {
                    let lowerCaseTableNames = connection.getFirstField(fromQuery: "SELECT @@lower_case_table_names",
                                                                       assertingDatabase: databaseContext)
                    let lowerCaseTableNamesValue = (lowerCaseTableNames as? NSNumber)?.intValue
                        ?? (lowerCaseTableNames as? String).flatMap(Int.init)
                    databaseNamesAreCaseSensitive = lowerCaseTableNamesValue == 0
                    databaseNameCaseSensitivityWasLoaded = true
                }

                _ = connection.queryString(query,
                                           usingEncoding: encoding.rawValue,
                                           with: SPMySQLResultAsResult,
                                           assertingDatabaseContext: databaseContext)

                if connection.queryErrored(), connection.lastErrorMessage() != "Query was empty" {
                    let error = connection.lastErrorMessage() ?? NSLocalizedString("Unknown MySQL error.", comment: "unknown mysql error")
                    let detailedError = String(format: NSLocalizedString("[ERROR in query %ld] %@", comment: "error text when multiple custom query failed"), index + 1, error)
                    errors.append(detailedError)

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
                            self.lightweightSQLImportErrorChoice(detailedError)
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
                else {
                    let updatedDatabaseContext = SASQLDatabaseContext.databaseName(afterSuccessfulQuery: query,
                                                                                    currentDatabase: databaseContext,
                                                                                    databaseNamesAreCaseSensitive: databaseNamesAreCaseSensitive,
                                                                                    serverVersion: serverVersion,
                                                                                    serverIsMariaDB: serverIsMariaDB)
                    if SASQLDatabaseContext.databaseNameChanged(from: databaseContext, to: updatedDatabaseContext),
                       updatedDatabaseContext == nil {
                        droppedSelectedDatabaseContext = databaseContext
                    }
                    databaseContext = updatedDatabaseContext
                }

                queriesPerformed += 1
            }
        }
    }

    func lightweightSQLQueries(in text: String) -> [String] {
        // Bounded in-memory lightweight imports intentionally pre-split SQL.
        // Unlike the streaming file importer, this cannot adjust parser
        // noBackslashEscapes after mid-file SQL_MODE changes.
        let parser = SPSQLParser(string: text)
        parser.setDelimiterSupport(true)
        guard let rawQueries = parser.splitString(byCharacter: Character(";").utf16.first!) as? [String] else { return [] }

        return rawQueries.compactMap { query in
            let normalised = parser.containsCarriageReturns() ? (SPSQLParser.normaliseQuery(forExecution: query) ?? query) : query
            let trimmed = normalised.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    func lightweightSQLImportErrorChoice(_ error: String) -> SALightweightSQLImportErrorChoice {
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

    func lightweightSQLImportIgnoresErrorsByDefault() -> Bool {
        let prefs = UserDefaults.standard
        guard prefs.object(forKey: SPSQLImportErrorHandlingSelection) != nil else { return false }

        return prefs.integer(forKey: SPSQLImportErrorHandlingSelection) == Int(SPSQLImportIgnoreErrors.rawValue)
    }

    func deliverLightweightSQLImportFinishedNotification(sourceName: String) {
        let notification = NSUserNotification()
        notification.title = "Import Finished"
        notification.informativeText = String(format: NSLocalizedString("Finished importing %@", comment: "description for finished importing notification"), sourceName)
        notification.soundName = NSUserNotificationDefaultSoundName

        NSUserNotificationCenter.default.deliver(notification)
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
           mode != .query,
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

extension SPWindowController {
    func lightweightEditedString(from object: Any?) -> String {
        if let string = object as? String {
            return string
        }

        if let attributedString = object as? NSAttributedString {
            return attributedString.string
        }

        return object.map { String(describing: $0) } ?? ""
    }

    private func commitActiveLightweightEditBeforeSidebarSelection() -> Bool {
        if !commitActiveLightweightSidebarEdit() {
            return false
        }

        switch activeLightweightViewMode {
        case .structure:
            return lightweightStructureController.commitActiveStructureEditBeforeSidebarSelection()
        case .content:
            return lightweightContentController.commitActiveContentEditBeforeSidebarSelection()
        default:
            return true
        }
    }

    private func commitActiveLightweightSidebarEdit() -> Bool {
        guard tablesListView.editedRow >= 0 || tablesListView.editedColumn >= 0 else { return true }
        guard let window = tablesListView.window else { return true }

        return window.makeFirstResponder(tablesListView)
    }
}

extension SPWindowController: NSTableViewDataSource, NSTableViewDelegate {
    private func isLightweightTablesListView(_ tableView: NSTableView) -> Bool {
        return lightweightTablesListViewReference === tableView
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        guard isLightweightTablesListView(tableView) else { return 0 }
        return lightweightSidebarRows().count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard isLightweightTablesListView(tableView) else { return nil }
        switch lightweightSidebarRow(at: row) {
        case .group(let title):
            return title
        case .object(let table):
            return table
        case .none:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard isLightweightTablesListView(tableView),
              let oldName = lightweightTableName(atSidebarRow: row),
              let selectedDatabase = selectedDatabase else { return }
        guard canStartLightweightMutation() else {
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            return
        }

        let newName = lightweightEditedString(from: object).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, oldName != newName else {
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            return
        }

        let tableType = lightweightTableTypes[oldName] ?? .table
        let viewModeToRestore = activeLightweightViewMode
        guard validateLightweightObjectName(newName, type: tableType, ignoring: oldName) else {
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            return
        }

        if tableType == .procedure || tableType == .function {
            guard confirmLightweightRenameIfNeeded(from: oldName, to: newName, type: tableType) else {
                tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
                return
            }
            duplicateLightweightRoutine(oldName, to: newName, type: tableType, database: selectedDatabase, dropSource: true)
            return
        }

        guard confirmLightweightRenameIfNeeded(from: oldName, to: newName, type: tableType) else {
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
            return
        }

        let statement = "RENAME TABLE \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(oldName)) TO \(Self.backtickQuoted(selectedDatabase)).\(Self.backtickQuoted(newName))"
        runLightweightDatabaseMutation(status: String(format: NSLocalizedString("Renaming %@...", comment: "Renaming table task string"), oldName), statement: statement) { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.refreshLightweightObjectsAfterMutation(database: selectedDatabase,
                                                            restoringTable: oldName,
                                                            restoringViewMode: viewModeToRestore)
                return
            }

            self.handleLightweightPinnedTableRename(from: oldName, to: newName)
            self.renameLightweightHistory(from: oldName, to: newName)
            self.refreshLightweightObjectsAfterMutation(database: selectedDatabase,
                                                        restoringTable: newName,
                                                        restoringViewMode: viewModeToRestore)
        }
    }

    private func confirmLightweightRenameIfNeeded(from oldName: String, to newName: String, type: SALightweightTableObjectType) -> Bool {
        guard UserDefaults.standard.bool(forKey: SPQueryWarningEnabled) else { return true }

        let alert = NSAlert()
        alert.window.animationBehavior = .none
        alert.messageText = String(format: NSLocalizedString("Rename %@", comment: "rename table/view/routine warning title"), type.localizedName)
        alert.informativeText = String(format: NSLocalizedString("Do you want to rename '%@' %@ to '%@'?", comment: "rename table/view/routine description"), oldName, type.localizedName, newName)
        alert.addButton(withTitle: NSLocalizedString("Confirm", comment: "Confirmation for renaming table"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
        return runLightweightModalAlert(alert) == .alertFirstButtonReturn
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return isLightweightTablesListView(tableView) &&
            !processing &&
            !isLightweightImportRunning &&
            !databaseListIsLoading &&
            lightweightTableName(atSidebarRow: row) != nil
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard isLightweightTablesListView(tableView) else { return }
        guard let cell = cell as? SPTableTextFieldCell else { return }

        cell.font = UserDefaults.getFont()
        cell.setIndentationLevel(0)
        cell.setNote("")

        guard let table = lightweightTableName(atSidebarRow: row) else {
            cell.image = nil
            return
        }

        cell.image = (lightweightTableTypes[table] ?? .table).imageName.flatMap { NSImage(named: NSImage.Name($0)) }
        var notes: [String] = []
        if UserDefaults.standard.bool(forKey: SPDisplayCommentsInTablesList),
           let comment = lightweightTableComments[table],
           !comment.isEmpty {
            notes.append(comment)
        }
        if lightweightPinnedTables.contains(table) {
            notes.append(NSLocalizedString("Pinned", comment: "pinned table list note"))
        }
        cell.setNote(notes.joined(separator: " — "))
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard isLightweightTablesListView(tableView) else { return false }
        if case .group = lightweightSidebarRow(at: row) {
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard isLightweightTablesListView(tableView) else { return true }
        guard lightweightTableName(atSidebarRow: row) != nil else { return false }

        guard commitActiveLightweightEditBeforeSidebarSelection() else {
            NSSound.beep()
            return false
        }

        return true
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if isLightweightTablesListView(tableView), case .group = lightweightSidebarRow(at: row) {
            return 25
        }

        return tableView.rowHeight
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView, isLightweightTablesListView(tableView) else { return }
        guard !isRestoringLightweightHistory else { return }
        guard !tablesListView.selectedRowIndexes.isEmpty else {
            selectedTable = nil
            updateLightweightSidebarActionMenuState()
            setLightweightFallbackToolbarItemsEnabled(true)
            updateLightweightWindowTitle()
            markLightweightResumeStateChanged()
            return
        }
        guard let table = primarySelectedLightweightTable() else { return }

        selectLightweightTable(table)
    }
}
