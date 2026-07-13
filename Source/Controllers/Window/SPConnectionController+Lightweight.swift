//
//  SPConnectionController+Lightweight.swift
//  Sequel Ace
//

import Cocoa

extension SPConnectionController {
    func applyLightweightConnectionInfo(_ info: SAConnectionInfoObjC) {
        type = info.type.rawValue
        name = info.name
        host = info.host
        user = info.user
        password = info.password.isEmpty && !info.connectionKeychainItemName.isEmpty ? SAConnectionInfoObjC.keychainPasswordPlaceholder : info.password
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
        sshPassword = info.sshPassword.isEmpty && !info.connectionSSHKeychainItemName.isEmpty ? SAConnectionInfoObjC.keychainPasswordPlaceholder : info.sshPassword
        sshKeyLocationEnabled = info.sshKeyLocationEnabled
        sshKeyLocation = info.sshKeyLocation
        sshPort = info.sshPort
        sshRemoteSocketPath = info.sshRemoteSocketPath
        vaultHost = info.vaultHost
        vaultPort = info.vaultPort
        vaultOIDCMount = info.vaultOIDCMount
        vaultCredentialsPath = info.vaultCredentialsPath
        connectionKeychainID = info.connectionKeychainID
        connectionKeychainItemName = info.connectionKeychainItemName
        connectionKeychainItemAccount = info.connectionKeychainItemAccount
        connectionSSHKeychainItemName = info.connectionSSHKeychainItemName
        connectionSSHKeychainItemAccount = info.connectionSSHKeychainItemAccount
    }
}
