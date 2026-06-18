//
//  SALightweightCSVImportSettings.swift
//  Sequel Ace
//

import Foundation

struct SALightweightCSVImportSettings: Equatable {
    var fieldTerminator: String
    var lineTerminator: String
    var fieldEnclosedBy: String
    var escapeCharacter: String
    var firstLineIsHeader: Bool

    static let legacyDefaults = SALightweightCSVImportSettings(
        fieldTerminator: ",",
        lineTerminator: "\\n",
        fieldEnclosedBy: "\"",
        escapeCharacter: "\\ or \"",
        firstLineIsHeader: true
    )

    static func load(from userDefaults: UserDefaults = .standard) -> SALightweightCSVImportSettings {
        SALightweightCSVImportSettings(
            fieldTerminator: userDefaults.string(forKey: SPCSVImportFieldTerminator) ?? legacyDefaults.fieldTerminator,
            lineTerminator: userDefaults.string(forKey: SPCSVImportLineTerminator) ?? legacyDefaults.lineTerminator,
            fieldEnclosedBy: userDefaults.string(forKey: SPCSVImportFieldEnclosedBy) ?? legacyDefaults.fieldEnclosedBy,
            escapeCharacter: userDefaults.string(forKey: SPCSVImportFieldEscapeCharacter) ?? legacyDefaults.escapeCharacter,
            firstLineIsHeader: boolValue(forKey: SPCSVImportFirstLineIsHeader, in: userDefaults, defaultValue: legacyDefaults.firstLineIsHeader)
        )
    }

    static func load(from userDefaults: UserDefaults = .standard, inferringFrom fileURL: URL?) -> SALightweightCSVImportSettings {
        load(from: userDefaults).applyingFileTypeInference(from: fileURL)
    }

    func save(to userDefaults: UserDefaults = .standard) {
        userDefaults.set(fieldTerminator, forKey: SPCSVImportFieldTerminator)
        userDefaults.set(lineTerminator, forKey: SPCSVImportLineTerminator)
        userDefaults.set(fieldEnclosedBy, forKey: SPCSVImportFieldEnclosedBy)
        userDefaults.set(escapeCharacter, forKey: SPCSVImportFieldEscapeCharacter)
        userDefaults.set(firstLineIsHeader, forKey: SPCSVImportFirstLineIsHeader)
    }

    func applyingFileTypeInference(from fileURL: URL?) -> SALightweightCSVImportSettings {
        guard let fileURL, Self.isTabSeparatedFile(fileURL) else {
            return self
        }

        var inferred = self
        inferred.fieldTerminator = "\t"
        return inferred
    }

    static func isTabSeparatedFile(_ fileURL: URL) -> Bool {
        let fileName = fileURL.lastPathComponent.lowercased()
        return fileName.hasSuffix(".tsv") || fileName.hasSuffix(".tsv.gz") || fileName.hasSuffix(".tsv.bz2")
    }

    private static func boolValue(forKey key: String, in userDefaults: UserDefaults, defaultValue: Bool) -> Bool {
        guard let value = userDefaults.object(forKey: key) else {
            return defaultValue
        }

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }

        return defaultValue
    }
}
