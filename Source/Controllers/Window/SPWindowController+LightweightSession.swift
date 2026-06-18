//
//  SPWindowController+LightweightSession.swift
//  Sequel Ace
//

import Cocoa

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

    @objc var hasSelectedLightweightTable: Bool {
        return hasActiveLightweightConnection && selectedTable?.isEmpty == false
    }

    @objc var selectedLightweightTableObjectType: Int {
        guard hasSelectedLightweightTable, let selectedTable = selectedTable else { return SALightweightTableObjectType.none.rawValue }

        return (lightweightTableTypes[selectedTable] ?? .table).rawValue
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
        connectionController.applyLightweightConnectionInfo(info)
        connectionController.initiateConnection(nil)
        return true
    }

    @objc(applyLightweightConnectionDictionary:autoConnect:)
    func applyLightweightConnectionDictionary(_ connectionDictionary: NSDictionary?, autoConnect: Bool) -> Bool {
        guard loadedDatabaseDocument == nil,
              let connectionDictionary = connectionDictionary,
              let info = lightweightConnectionInfo(from: connectionDictionary),
              let connectionController = connectionController else { return false }

        selectedDatabase = info.database.isEmpty ? nil : info.database
        if autoConnect {
            activeConnectionInfo = info
        }
        connectionController.applyLightweightConnectionInfo(info)
        if autoConnect {
            connectionController.initiateConnection(nil)
        }
        return true
    }

    @objc(applyLightweightFavoriteDictionary:autoConnect:)
    func applyLightweightFavoriteDictionary(_ favoriteDictionary: NSDictionary?, autoConnect: Bool) -> Bool {
        guard let favoriteDictionary = favoriteDictionary else { return false }

        let info = SAConnectionInfoObjC.info(fromFavoriteDictionary: favoriteDictionary)
        return applyLightweightConnectionInfo(info, autoConnect: autoConnect)
    }

    @objc func connectSelectedLightweightConnection() -> Bool {
        guard loadedDatabaseDocument == nil,
              let connectionController = connectionController else { return false }

        connectionController.initiateConnection(nil)
        return true
    }

    private func applyLightweightConnectionInfo(_ info: SAConnectionInfoObjC, autoConnect: Bool) -> Bool {
        guard loadedDatabaseDocument == nil,
              let connectionController = connectionController else { return false }

        selectedDatabase = info.database.isEmpty ? nil : info.database
        if autoConnect {
            activeConnectionInfo = info
        }
        connectionController.applyLightweightConnectionInfo(info)
        if autoConnect {
            connectionController.initiateConnection(nil)
        }
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
            if !info.sshRemoteSocketPath.isEmpty {
                connection[SALightweightConnectionDictionaryKey.sshRemoteSocketPath] = info.sshRemoteSocketPath
            }
            if includePasswords {
                connection[SALightweightConnectionDictionaryKey.sshPassword] = info.sshPassword
            }
        }

        if info.type == .vault {
            if !info.vaultHost.isEmpty {
                connection[SALightweightConnectionDictionaryKey.vaultHost] = info.vaultHost
            }
            if !info.vaultPort.isEmpty {
                connection[SALightweightConnectionDictionaryKey.vaultPort] = info.vaultPort
            }
            if !info.vaultOIDCMount.isEmpty {
                connection[SALightweightConnectionDictionaryKey.vaultOIDCMount] = info.vaultOIDCMount
            }
            if !info.vaultCredentialsPath.isEmpty {
                connection[SALightweightConnectionDictionaryKey.vaultCredentialsPath] = info.vaultCredentialsPath
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
        info.sshRemoteSocketPath = Self.stringValue(connection[SALightweightConnectionDictionaryKey.sshRemoteSocketPath])
        info.vaultHost = Self.stringValue(connection[SALightweightConnectionDictionaryKey.vaultHost])
        info.vaultPort = Self.stringValue(connection[SALightweightConnectionDictionaryKey.vaultPort])
        info.vaultOIDCMount = Self.stringValue(connection[SALightweightConnectionDictionaryKey.vaultOIDCMount])
        info.vaultCredentialsPath = Self.stringValue(connection[SALightweightConnectionDictionaryKey.vaultCredentialsPath])
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
        case .vault:
            return "SPVaultConnection"
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
        case "SPVaultConnection":
            return .vault
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
