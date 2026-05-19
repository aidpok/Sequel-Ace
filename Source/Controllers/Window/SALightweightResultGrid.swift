//
//  SALightweightResultGrid.swift
//  Sequel Ace
//
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

import AppKit
import UniformTypeIdentifiers

let SALightweightResultGridCopyWithColumnsTag = 2002
let SALightweightResultGridCopyAsSQLTag = 2003
let SALightweightResultGridCopyAsSQLNoAutoIncTag = 2004

protocol SALightweightResultGridTableViewDelegate: AnyObject {
    func resultGridTableViewCopyRows(_ sender: Any?)
    func resultGridTableViewCopyRowsAsSQL(_ sender: Any?)
    func resultGridTableViewCanCopyRows(_ tableView: NSTableView) -> Bool
    func resultGridTableViewPrepareContextMenu(_ tableView: NSTableView, for event: NSEvent)
}

private protocol SALightweightDenseAccessibilityTable: AnyObject {
    var lightweightAccessibilityLabel: String? { get set }
}

final class SALightweightDenseTableView: SPTableView, SALightweightDenseAccessibilityTable {
    var lightweightAccessibilityLabel: String?

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .table
    }

    override func accessibilityLabel() -> String? {
        lightweightAccessibilityLabel ?? super.accessibilityLabel()
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    override func accessibilityColumns() -> [Any]? {
        []
    }
}

final class SALightweightResultGridTableView: SPCopyTable, SALightweightDenseAccessibilityTable {
    weak var resultGridDelegate: SALightweightResultGridTableViewDelegate?
    var lightweightAccessibilityLabel: String?

    @objc(copy:)
    override func copy(_ sender: Any?) {
        if let menuItem = sender as? NSMenuItem,
           menuItem.tag == SALightweightResultGridCopyAsSQLTag || menuItem.tag == SALightweightResultGridCopyAsSQLNoAutoIncTag {
            resultGridDelegate?.resultGridTableViewCopyRowsAsSQL(sender)
            return
        }

        resultGridDelegate?.resultGridTableViewCopyRows(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return resultGridDelegate?.resultGridTableViewCanCopyRows(self) ?? false
        }

        return super.validateUserInterfaceItem(item)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        resultGridDelegate?.resultGridTableViewPrepareContextMenu(self, for: event)
        return super.menu(for: event)
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .table
    }

    override func accessibilityLabel() -> String? {
        lightweightAccessibilityLabel ?? super.accessibilityLabel()
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    override func accessibilityColumns() -> [Any]? {
        []
    }
}

enum SALightweightResultGrid {
    static let tabularPasteboardType = NSPasteboard.PasteboardType("public.utf8-tab-separated-values-text")

    static func configureTableView(_ tableView: NSTableView, rowHeight: CGFloat, columnAutoresizingStyle: NSTableView.ColumnAutoresizingStyle) {
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.columnAutoresizingStyle = columnAutoresizingStyle
        tableView.gridStyleMask = UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines) ? .solidVerticalGridLineMask : []
        tableView.rowHeight = rowHeight
        tableView.wantsLayer = true
        tableView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        tableView.registerForDraggedTypes([Self.tabularPasteboardType, .string])
        configureDenseGridAccessibility(tableView, label: NSLocalizedString("Result grid", comment: "lightweight result grid accessibility label"))
    }

    static func configureDenseGridAccessibility(_ tableView: NSTableView, label: String) {
        tableView.setAccessibilityElement(true)
        tableView.setAccessibilityLabel(label)
        tableView.setAccessibilityChildren([])
        tableView.setAccessibilityChildrenInNavigationOrder([])
        tableView.setAccessibilityRows([])
        tableView.setAccessibilityColumns([])
        tableView.setAccessibilitySelectedRows([])
        tableView.setAccessibilityVisibleRows([])

        if let tableView = tableView as? SALightweightDenseAccessibilityTable {
            tableView.lightweightAccessibilityLabel = label
        }
    }

    static func configureScrollView(_ scrollView: NSScrollView) {
        scrollView.wantsLayer = true
        scrollView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    static func contextMenu(target: AnyObject,
                            copyAction: Selector,
                            copySQLAction: Selector,
                            exportCSVAction: Selector,
                            exportXMLAction: Selector,
                            copyCommentPrefix: String,
                            exportCommentPrefix: String) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = true

        let copyItem = NSMenuItem(title: NSLocalizedString("Copy", comment: "\(copyCommentPrefix) copy rows menu item"),
                                  action: copyAction,
                                  keyEquivalent: "")
        copyItem.target = target
        menu.addItem(copyItem)

        let copyWithColumnsItem = NSMenuItem(title: NSLocalizedString("Copy With Column Names", comment: "\(copyCommentPrefix) copy rows with column names menu item"),
                                             action: copyAction,
                                             keyEquivalent: "")
        copyWithColumnsItem.target = target
        copyWithColumnsItem.tag = SALightweightResultGridCopyWithColumnsTag
        menu.addItem(copyWithColumnsItem)

        let copyAsSQLItem = NSMenuItem(title: NSLocalizedString("Copy as SQL INSERT", comment: "\(copyCommentPrefix) copy rows as sql insert menu item"),
                                       action: copySQLAction,
                                       keyEquivalent: "")
        copyAsSQLItem.target = target
        copyAsSQLItem.tag = SALightweightResultGridCopyAsSQLTag
        menu.addItem(copyAsSQLItem)

        let copyAsSQLNoAutoIncItem = NSMenuItem(title: NSLocalizedString("Copy as SQL INSERT (no auto_inc)", comment: "\(copyCommentPrefix) copy rows as sql insert without auto increment menu item"),
                                                action: copySQLAction,
                                                keyEquivalent: "")
        copyAsSQLNoAutoIncItem.target = target
        copyAsSQLNoAutoIncItem.tag = SALightweightResultGridCopyAsSQLNoAutoIncTag
        menu.addItem(copyAsSQLNoAutoIncItem)

        menu.addItem(.separator())

        let exportCSVItem = NSMenuItem(title: NSLocalizedString("Export Result as CSV...", comment: "\(exportCommentPrefix) export result as csv context menu item"),
                                       action: exportCSVAction,
                                       keyEquivalent: "")
        exportCSVItem.target = target
        menu.addItem(exportCSVItem)

        let exportXMLItem = NSMenuItem(title: NSLocalizedString("Export Result as XML...", comment: "\(exportCommentPrefix) export result as xml context menu item"),
                                       action: exportXMLAction,
                                       keyEquivalent: "")
        exportXMLItem.target = target
        menu.addItem(exportXMLItem)

        return menu
    }

    static func selectContextRow(in tableView: NSTableView, event: NSEvent) {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let clickedRow = tableView.row(at: point)

        if clickedRow >= 0 && !tableView.selectedRowIndexes.contains(clickedRow) {
            tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
    }

    static func reloadCell(in tableView: NSTableView, row: Int, columnIndex: Int) {
        guard row >= 0,
              row < tableView.numberOfRows,
              let displayColumnIndex = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == "\(columnIndex)" }) else { return }

        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: displayColumnIndex))
    }

    static func matchingRowCount(for query: String, connection: SPMySQLConnection) -> Int? {
        guard let result = connection.queryString(query) else { return nil }

        result.returnDataAsStrings = true
        result.defaultRowReturnType = SPMySQLResultRowAsArray

        guard let row = result.getRowAsArray(),
              let value = row.first else { return nil }

        return Int(String(describing: value))
    }

    static func shouldUseFieldEditor(typeGrouping: String, value: Any?, displayValue: @autoclosure () -> String) -> Bool {
        if UserDefaults.standard.bool(forKey: SPEditInSheetEnabled) {
            return true
        }

        if typeGrouping == "textdata" || typeGrouping == "blobdata" || value is Data {
            return true
        }

        if value is NSNull {
            return false
        }

        if UserDefaults.standard.bool(forKey: SPEditInSheetForLongText),
           let threshold = UserDefaults.standard.object(forKey: SPEditInSheetForLongTextLengthThreshold) as? NSNumber,
           displayValue().count > threshold.intValue {
            return true
        }

        if UserDefaults.standard.bool(forKey: SPEditInSheetForMultiLineText),
           displayValue().rangeOfCharacter(from: .newlines) != nil {
            return true
        }

        return false
    }

    static func tableCellPreviewString(_ value: String, maximumCharacters: Int) -> String {
        let source = value as NSString
        let length = source.length
        guard length > 0, maximumCharacters > 0 else { return "" }

        var end = min(length, maximumCharacters)
        var isTruncated = length > maximumCharacters
        if end > 0 {
            for index in 0..<end {
                let character = source.character(at: index)
                if character == 10 || character == 13 {
                    end = index
                    isTruncated = true
                    break
                }
            }
        }

        let preview = source.substring(to: end)
            .replacingOccurrences(of: "\t", with: " ")
        return isTruncated ? preview + "..." : preview
    }

    static func copyStringToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([Self.tabularPasteboardType, .string], owner: nil)
        pasteboard.setString(value, forType: Self.tabularPasteboardType)
        pasteboard.setString(value, forType: .string)
    }

    static func copySQLStringToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(value, forType: .string)
    }

    static func writeRows(_ value: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.declareTypes([Self.tabularPasteboardType, .string], owner: nil)
        pasteboard.setString(value, forType: Self.tabularPasteboardType)
        pasteboard.setString(value, forType: .string)
        return true
    }

    static func exportResult(fileExtension: String, content: String, defaultName: String) {
        let panel = NSSavePanel()
        if let contentType = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [contentType]
        }
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultName

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    static func tabString(includeHeaders: Bool,
                          rowIndexes: IndexSet,
                          tableColumns: [NSTableColumn],
                          rowCount: Int,
                          columnName: (NSTableColumn) -> String,
                          value: (Int, NSTableColumn) -> String?) -> String? {
        guard !rowIndexes.isEmpty else { return nil }

        var lines: [String] = []
        if includeHeaders {
            lines.append(tableColumns.map { copyEscaped(columnName($0)) }.joined(separator: "\t"))
        }

        rowIndexes.forEach { rowIndex in
            guard rowIndex < rowCount else { return }
            lines.append(tableColumns.map { tableColumn in
                guard let value = value(rowIndex, tableColumn) else { return "" }
                return copyEscaped(value)
            }.joined(separator: "\t"))
        }

        return lines.joined(separator: "\n")
    }

    static func csvString(rowCount: Int,
                          tableColumns: [NSTableColumn],
                          columnName: (NSTableColumn) -> String,
                          value: (Int, NSTableColumn) -> String?) -> String {
        var lines = [tableColumns.map { csvEscaped(columnName($0)) }.joined(separator: ",")]
        lines.append(contentsOf: (0..<rowCount).map { rowIndex in
            tableColumns.map { tableColumn in
                csvEscaped(value(rowIndex, tableColumn) ?? "")
            }.joined(separator: ",")
        })
        return lines.joined(separator: "\n")
    }

    static func xmlString(rowCount: Int,
                          tableColumns: [NSTableColumn],
                          columnName: (NSTableColumn) -> String,
                          value: (Int, NSTableColumn) -> String?) -> String {
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<resultset>"]
        for rowIndex in 0..<rowCount {
            lines.append("\t<row>")
            for tableColumn in tableColumns {
                let name = xmlEscaped(columnName(tableColumn))
                let value = xmlEscaped(value(rowIndex, tableColumn) ?? "")
                lines.append("\t\t<field name=\"\(name)\">\(value)</field>")
            }
            lines.append("\t</row>")
        }
        lines.append("</resultset>")
        return lines.joined(separator: "\n")
    }

    static func copyEscaped(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\n", with: "\u{21B5}")
            .replacingOccurrences(of: "\t", with: "\u{21E5}")
    }

    static func csvEscaped(_ value: String) -> String {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func xmlEscaped(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    static func singleQuoted(_ value: String) -> String {
        return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}
