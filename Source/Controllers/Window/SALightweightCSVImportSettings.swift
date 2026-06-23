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
        guard let fileURL else {
            return self
        }

        var inferred = self

        if Self.isTabSeparatedFile(fileURL) {
            inferred.fieldTerminator = "\t"
        }

        if !Self.isCompressedFile(fileURL), let lineTerminator = Self.inferredLineTerminator(from: fileURL) {
            inferred.lineTerminator = lineTerminator
        }

        return inferred
    }

    static func isTabSeparatedFile(_ fileURL: URL) -> Bool {
        let fileName = fileURL.lastPathComponent.lowercased()
        return fileName.hasSuffix(".tsv") || fileName.hasSuffix(".tsv.gz") || fileName.hasSuffix(".tsv.bz2")
    }

    private static func isCompressedFile(_ fileURL: URL) -> Bool {
        let fileName = fileURL.lastPathComponent.lowercased()
        return fileName.hasSuffix(".gz") || fileName.hasSuffix(".bz2")
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

    private static func inferredLineTerminator(from fileURL: URL) -> String? {
        let sniffByteCount = 64 * 1024

        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer {
            fileHandle.closeFile()
        }

        let data = fileHandle.readData(ofLength: sniffByteCount + 1)
        guard !data.isEmpty else {
            return nil
        }

        let bytes = [UInt8](data)
        let scanLimit = min(sniffByteCount, bytes.count)
        var index = 0
        var crlfCount = 0
        var lfCount = 0
        var crCount = 0
        var firstLineTerminator: String?

        while index < scanLimit {
            switch bytes[index] {
            case 0x0D:
                if bytes.indices.contains(index + 1), bytes[index + 1] == 0x0A {
                    crlfCount += 1
                    if firstLineTerminator == nil {
                        firstLineTerminator = "\\r\\n"
                    }

                    index += 2
                    continue
                }

                crCount += 1
                if firstLineTerminator == nil {
                    firstLineTerminator = "\\r"
                }

                index += 1

            case 0x0A:
                lfCount += 1
                if firstLineTerminator == nil {
                    firstLineTerminator = "\\n"
                }

                index += 1

            default:
                index += 1
            }
        }

        if crlfCount > lfCount, crlfCount > crCount {
            return "\\r\\n"
        }

        if lfCount > crlfCount, lfCount > crCount {
            return "\\n"
        }

        if crCount > crlfCount, crCount > lfCount {
            return "\\r"
        }

        return firstLineTerminator
    }
}
