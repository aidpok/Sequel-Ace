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
    func resultGridTableView(_ tableView: NSTableView, canCopyRowsFor item: NSValidatedUserInterfaceItem) -> Bool
    func resultGridTableViewPrepareContextMenu(_ tableView: NSTableView, for event: NSEvent)
    func resultGridTableView(_ tableView: NSTableView, bundleInputFor inputSource: String, blobHandling: Int, onlySelectedRows: Bool, blobFileDirectory: String?) -> String?
}

extension SALightweightResultGridTableViewDelegate {
    func resultGridTableView(_ tableView: NSTableView, bundleInputFor inputSource: String, blobHandling: Int, onlySelectedRows: Bool, blobFileDirectory: String?) -> String? {
        nil
    }
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

    @objc var supportsDataTableBundleCommands = false
    @objc var dataTableBundleSource = "query"

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(invalidRect)
        logInvalidationDiagnostics(reason: "setNeedsDisplay(rect)", rect: invalidRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        logInvalidationDiagnostics(reason: "draw", rect: dirtyRect)
        super.draw(dirtyRect)
    }

    @objc(dataTableBundleInputForInputSource:blobHandling:onlySelectedRows:blobFileDirectory:)
    func dataTableBundleInput(for inputSource: String, blobHandling: Int, onlySelectedRows: Bool, blobFileDirectory: String?) -> String? {
        return resultGridDelegate?.resultGridTableView(self,
                                                       bundleInputFor: inputSource,
                                                       blobHandling: blobHandling,
                                                       onlySelectedRows: onlySelectedRows,
                                                       blobFileDirectory: blobFileDirectory)
    }

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
            return resultGridDelegate?.resultGridTableView(self, canCopyRowsFor: item) ?? false
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

    private func logInvalidationDiagnostics(reason: String, rect: NSRect) {
        // Opt-in hook for activation/focus redraw audits. Keep disabled by default;
        // AppKit legitimately repaints table selections when app/window key state changes.
        guard Self.invalidationDiagnosticsEnabled else { return }

        let visibleRows = rows(in: visibleRect)
        let visibleColumns = columnIndexes(in: visibleRect)
        let firstResponder = window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let currentEventType = NSApp.currentEvent.map { String(describing: $0.type) } ?? "nil"
        NSLog("SA LightweightGridInvalidation %@ id=%@ source=%@ rect=%@ visibleRect=%@ visibleRows=%@ visibleColumns=%@ rows=%ld columns=%ld appActive=%d keyWindow=%d firstResponder=%@ event=%@ caller=%@",
              reason,
              identifier?.rawValue ?? "nil",
              dataTableBundleSource,
              NSStringFromRect(rect),
              NSStringFromRect(visibleRect),
              NSStringFromRange(visibleRows),
              visibleColumns.description,
              numberOfRows,
              numberOfColumns,
              NSApp.isActive ? 1 : 0,
              window?.isKeyWindow == true ? 1 : 0,
              firstResponder,
              currentEventType,
              Self.firstApplicationCaller())
    }

    private static var invalidationDiagnosticsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "SALightweightResultGridInvalidationDiagnostics")
            || ProcessInfo.processInfo.environment["SA_LIGHTWEIGHT_GRID_INVALIDATION_DIAGNOSTICS"] == "1"
    }

    private static func firstApplicationCaller() -> String {
        Thread.callStackSymbols.first { symbol in
            symbol.contains("Sequel Ace")
                && !symbol.contains("SALightweightResultGridTableView")
                && !symbol.contains("logInvalidationDiagnostics")
                && !symbol.contains("firstApplicationCaller")
        } ?? "none"
    }
}

final class SALightweightResultGridDisplayCache {
    private struct Key: Hashable {
        let row: Int
        let column: Int
    }

    private var values: [Key: String] = [:]

    func value(row: Int, column: Int, builder: () -> String) -> String {
        let key = Key(row: row, column: column)
        if let value = values[key] {
            return value
        }

        let value = builder()
        values[key] = value
        return value
    }

    func invalidate(row: Int, column: Int) {
        values.removeValue(forKey: Key(row: row, column: column))
    }

    func invalidate(row: Int) {
        values = values.filter { $0.key.row != row }
    }

    func invalidateAll() {
        values.removeAll(keepingCapacity: true)
    }
}

final class SALightweightResultGridColumnWidthCache {
    private var values: [String: CGFloat] = [:]

    func value(key: String, builder: () -> CGFloat) -> CGFloat {
        if let value = values[key] {
            return value
        }

        let value = builder()
        values[key] = value
        return value
    }

    func invalidateAll() {
        values.removeAll(keepingCapacity: true)
    }
}

final class SALightweightResultGridAutosizeCoordinator {
    private var isLiveScrolling = false
    private var pendingAutosize: DispatchWorkItem?

    deinit {
        cancel()
    }

    func cancel() {
        pendingAutosize?.cancel()
        pendingAutosize = nil
    }

    func willStartLiveScroll() {
        isLiveScrolling = true
        cancel()
    }

    func didEndLiveScroll() {
        isLiveScrolling = false
    }

    func schedule(delay: TimeInterval = 0.05, _ block: @escaping () -> Void) {
        guard !isLiveScrolling else { return }

        cancel()
        let workItem = DispatchWorkItem(block: block)
        pendingAutosize = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

enum SALightweightResultGrid {
    static let tabularPasteboardType = NSPasteboard.PasteboardType("public.utf8-tab-separated-values-text")
    static let automaticColumnMaximumWidth: CGFloat = 420
    static let wideTextColumnWidth: CGFloat = 500
    static let tableCellDisplayMaximumCharacters = 96
    static let tableCellDisplayMaximumBytes = 48
    static let autosizeColumnBuffer = 6

    struct ColumnDescriptor {
        let name: String
        let type: String
        let typeGrouping: String
        let length: String
        let values: [String]
        let isNullable: Bool

        init(name: String, type: String, typeGrouping: String, length: String, values: [String] = [], isNullable: Bool = false) {
            self.name = name
            self.type = type
            self.typeGrouping = typeGrouping
            self.length = length
            self.values = values
            self.isNullable = isNullable
        }
    }

    static func rowHeight(for font: NSFont) -> CGFloat {
        return 4.0 + "{ǞṶḹÜ∑zgyf".size(withAttributes: [.font: font]).height
    }

    static func headerFont(for font: NSFont) -> NSFont {
        return NSFontManager.shared.convert(font, toSize: max(font.pointSize * 0.75, 11.0))
    }

    static func configureTableView(_ tableView: NSTableView, rowHeight: CGFloat, columnAutoresizingStyle: NSTableView.ColumnAutoresizingStyle) {
        tableView.focusRingType = .none
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
        scrollView.focusRingType = .none
        scrollView.wantsLayer = true
        scrollView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    static func configureResultScrollView(_ scrollView: NSScrollView, lineScroll: CGFloat = 18) {
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.verticalLineScroll = lineScroll
        scrollView.horizontalLineScroll = lineScroll
        scrollView.contentView.drawsBackground = false
        configureScrollView(scrollView)
    }

    static func dataCell(for descriptor: ColumnDescriptor, font: NSFont, editable: Bool) -> NSCell {
        let cell: NSCell
        let typeGrouping = descriptor.typeGrouping.lowercased()

        if typeGrouping == "enum" {
            let comboCell = SPComboBoxCell(textCell: "")
            comboCell.isButtonBordered = false
            comboCell.isBezeled = false
            comboCell.drawsBackground = false
            comboCell.completes = true
            comboCell.controlSize = .small
            comboCell.usesSingleLineMode = true
            if descriptor.isNullable {
                comboCell.addItem(withObjectValue: UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL")
            }
            comboCell.addItems(withObjectValues: descriptor.values)
            cell = comboCell
        } else {
            cell = NSTextFieldCell(textCell: "")
        }

        cell.isEditable = editable
        cell.isSelectable = true
        cell.lineBreakMode = .byTruncatingTail
        cell.font = font

        if typeGrouping == "integer" || typeGrouping == "float" {
            cell.alignment = .right
        }

        let formatter = SPDataCellFormatter()
        formatter.fieldType = descriptor.type
        if (typeGrouping == "string" || typeGrouping == "bit"),
           let limit = Int(descriptor.length) {
            formatter.textLimit = limit
        }
        cell.formatter = formatter

        return cell
    }

    static func configuredColumn(identifier: Int,
                                 title: String,
                                 descriptor: ColumnDescriptor,
                                 font: NSFont,
                                 editable: Bool,
                                 headerToolTip: String?,
                                 headerAttributedString: NSAttributedString,
                                 savedWidth: CGFloat?,
                                 minWidth: CGFloat,
                                 maxWidth: CGFloat = 20_000,
                                 resizingMask: NSTableColumn.ResizingOptions = [.autoresizingMask, .userResizingMask]) -> NSTableColumn {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(identifier)"))
        tableColumn.title = title
        tableColumn.isEditable = editable
        tableColumn.width = savedWidth ?? (isWideTextColumn(typeGrouping: descriptor.typeGrouping)
            ? wideTextColumnWidth
            : defaultColumnWidth(for: descriptor))
        tableColumn.minWidth = minWidth
        tableColumn.maxWidth = maxWidth
        tableColumn.resizingMask = resizingMask
        tableColumn.headerToolTip = headerToolTip
        tableColumn.headerCell.font = headerFont(for: font)
        tableColumn.headerCell.attributedStringValue = headerAttributedString
        tableColumn.dataCell = dataCell(for: descriptor, font: font, editable: editable)
        return tableColumn
    }

    static func updateColumn(_ tableColumn: NSTableColumn,
                             identifier: Int,
                             title: String,
                             descriptor: ColumnDescriptor,
                             font: NSFont,
                             editable: Bool,
                             headerToolTip: String?,
                             headerAttributedString: NSAttributedString) {
        tableColumn.identifier = NSUserInterfaceItemIdentifier("\(identifier)")
        tableColumn.title = title
        tableColumn.isEditable = editable
        tableColumn.headerToolTip = headerToolTip
        tableColumn.headerCell.font = headerFont(for: font)
        tableColumn.headerCell.attributedStringValue = headerAttributedString

        if let cell = tableColumn.dataCell as? NSCell,
           !(descriptor.typeGrouping.lowercased() == "enum" && !(cell is SPComboBoxCell)) {
            cell.isEditable = editable
            cell.font = font
        } else {
            tableColumn.dataCell = dataCell(for: descriptor, font: font, editable: editable)
        }
    }

    static func applySortIndicator(to tableView: NSTableView, columnIndex: Int?, ascending: Bool) {
        if !tableView.sortDescriptors.isEmpty {
            tableView.sortDescriptors = []
        }
        tableView.highlightedTableColumn = nil
        for column in tableView.tableColumns {
            column.sortDescriptorPrototype = nil
            tableView.setIndicatorImage(nil, in: column)
        }

        guard let columnIndex,
              let tableColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("\(columnIndex)")) else { return }

        tableView.highlightedTableColumn = tableColumn
        tableView.setIndicatorImage(NSImage(named: ascending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator"), in: tableColumn)
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

    static func reloadVisibleCells(in tableView: NSTableView, columnBuffer: Int = 2) {
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.length > 0 else {
            tableView.setNeedsDisplay(tableView.visibleRect)
            return
        }

        let rowIndexes = IndexSet(integersIn: visibleRows.location..<min(tableView.numberOfRows, visibleRows.location + visibleRows.length))
        let columnIndexes = visibleColumnIndexes(in: tableView, buffer: columnBuffer)
        guard !rowIndexes.isEmpty, !columnIndexes.isEmpty else {
            tableView.setNeedsDisplay(tableView.visibleRect)
            return
        }

        tableView.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
    }

    static func visibleColumnIndexes(in tableView: NSTableView, buffer: Int = 2) -> IndexSet {
        let columnCount = tableView.tableColumns.count
        guard columnCount > 0 else { return IndexSet() }

        let visibleColumns = tableView.columnIndexes(in: tableView.visibleRect)
        guard !visibleColumns.isEmpty else {
            return IndexSet(integersIn: 0..<min(columnCount, max(1, buffer * 2 + 1)))
        }

        let lowerBound = max(0, visibleColumns.first! - buffer)
        let upperBound = min(columnCount, visibleColumns.last! + buffer + 1)
        return IndexSet(integersIn: lowerBound..<upperBound)
    }

    static func isWideTextColumn(typeGrouping: String) -> Bool {
        let typeGrouping = typeGrouping.lowercased()
        return typeGrouping == "textdata" || typeGrouping == "blobdata"
    }

    static func defaultColumnWidth(for descriptor: ColumnDescriptor) -> CGFloat {
        if isWideTextColumn(typeGrouping: descriptor.typeGrouping) {
            return wideTextColumnWidth
        }

        let headerWidth = CGFloat(descriptor.name.count * 9 + 32)

        switch descriptor.typeGrouping {
        case "integer", "float", "date", "time", "bit":
            return max(70, min(150, headerWidth))
        case "string":
            if let length = Int(descriptor.length), length > 0 {
                return max(90, min(260, max(headerWidth, CGFloat(length * 7 + 28))))
            }
            return max(100, min(220, headerWidth))
        default:
            return max(90, min(220, headerWidth))
        }
    }

    static func fittedColumnWidth(_ targetWidth: CGFloat, minimumWidth: CGFloat) -> CGFloat {
        min(ceil(max(targetWidth, minimumWidth)), automaticColumnMaximumWidth)
    }

    static func measuredHeaderWidth(for tableColumn: NSTableColumn) -> CGFloat {
        let headerCell = tableColumn.headerCell

        if headerCell.attributedStringValue.length > 0 {
            return max(headerCell.cellSize.width, headerCell.attributedStringValue.size().width)
        }

        let title = headerCell.stringValue as NSString
        let font = headerCell.font ?? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        return max(headerCell.cellSize.width, title.size(withAttributes: [.font: font]).width)
    }

    static func measuredCellWidth(_ value: String, in tableColumn: NSTableColumn) -> CGFloat {
        guard let cell = (tableColumn.dataCell as? NSCell)?.copy() as? NSCell else {
            return (value as NSString).size(withAttributes: [.font: UserDefaults.getFont()]).width
        }

        cell.stringValue = value
        let font = cell.font ?? UserDefaults.getFont()
        return max(cell.cellSize.width, (value as NSString).size(withAttributes: [.font: font]).width)
    }

    static func autodetectedColumnWidth(for tableColumn: NSTableColumn,
                                        columnIndex: Int,
                                        visibleRows: Range<Int>,
                                        isEnumColumn: Bool,
                                        displayValue: (Int, Int) -> String) -> CGFloat {
        var maxCellWidth: CGFloat = 0
        for row in visibleRows {
            let cellWidth = measuredCellWidth(displayValue(row, columnIndex), in: tableColumn)
            maxCellWidth = max(maxCellWidth, cellWidth)
        }

        if isEnumColumn {
            maxCellWidth += 8
        }

        let headerWidth = measuredHeaderWidth(for: tableColumn) + 10
        return ceil(max(maxCellWidth + 24, headerWidth, tableColumn.minWidth))
    }

    static func autosizeColumns(in tableView: NSTableView,
                                displayColumnIndexes: IndexSet,
                                visibleRows: Range<Int>,
                                columnWidthCache: SALightweightResultGridColumnWidthCache,
                                shouldSkipColumn: (Int, NSTableColumn) -> Bool,
                                cacheKey: (Int, NSTableColumn, Range<Int>) -> String,
                                isEnumColumn: (Int) -> Bool,
                                displayValue: (Int, Int) -> String) {
        var widthsByIdentifier: [String: CGFloat] = [:]

        for displayColumnIndex in displayColumnIndexes {
            guard displayColumnIndex < tableView.tableColumns.count else { continue }
            let tableColumn = tableView.tableColumns[displayColumnIndex]
            guard let columnIndex = Int(tableColumn.identifier.rawValue) else { continue }

            if shouldSkipColumn(columnIndex, tableColumn) {
                continue
            }

            let cacheKey = cacheKey(columnIndex, tableColumn, visibleRows)
            widthsByIdentifier[tableColumn.identifier.rawValue] = columnWidthCache.value(key: cacheKey) {
                autodetectedColumnWidth(for: tableColumn,
                                        columnIndex: columnIndex,
                                        visibleRows: visibleRows,
                                        isEnumColumn: isEnumColumn(columnIndex),
                                        displayValue: displayValue)
            }
        }

        for tableColumn in tableView.tableColumns {
            guard let targetWidth = widthsByIdentifier[tableColumn.identifier.rawValue] else { continue }
            let width = fittedColumnWidth(targetWidth, minimumWidth: tableColumn.minWidth)
            guard abs(tableColumn.width - width) > 0.5 else { continue }
            tableColumn.width = width
        }
    }

    static func logPerformance(_ action: String, start: CFAbsoluteTime, details: String = "", minimumMilliseconds: Double = 8) {
        let milliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        guard milliseconds >= minimumMilliseconds else { return }

        NSLog("SA LightweightGridPerformance %@ %.2f ms %@", action, milliseconds, details)
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

    static func displayString(for value: Any?, descriptor: ColumnDescriptor? = nil, truncate: Bool = false) -> String {
        guard let value = value, !(value is NSNull) else {
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        if let data = value as? Data {
            if UserDefaults.standard.bool(forKey: SPDisplayBinaryDataAsHex),
               shouldDisplayDataAsHex(descriptor: descriptor) {
                if truncate && data.count > tableCellDisplayMaximumBytes {
                    return "0x" + data.prefix(tableCellDisplayMaximumBytes).map { String(format: "%02X", $0) }.joined() + "..."
                }
                return "0x" + data.map { String(format: "%02X", $0) }.joined()
            }

            return displayString(String(data: data, encoding: .utf8) ?? "", truncate: truncate)
        }

        if let geometry = value as? SPMySQLGeometryData {
            return displayString(geometry.wktString() ?? "", truncate: truncate)
        }

        return displayString(String(describing: value), truncate: truncate)
    }

    static func displayString(_ value: String, truncate: Bool) -> String {
        guard truncate else { return value }
        return tableCellPreviewString(value, maximumCharacters: tableCellDisplayMaximumCharacters)
    }

    static func shouldDisplayDataAsHex(descriptor: ColumnDescriptor?) -> Bool {
        let typeGrouping = descriptor?.typeGrouping.lowercased() ?? ""
        let type = descriptor?.type.lowercased() ?? ""

        return typeGrouping == "binary"
            || typeGrouping == "blobdata"
            || type.contains("binary")
            || type.hasSuffix("blob")
    }

    static func columnIndex(for tableColumn: NSTableColumn?) -> Int? {
        guard let columnIdentifier = tableColumn?.identifier.rawValue else { return nil }
        return Int(columnIdentifier)
    }

    static func objectValue(row: Int,
                            rowCount: Int,
                            tableColumn: NSTableColumn?,
                            columnCount: (Int) -> Int,
                            displayValue: (Int, Int) -> String) -> Any? {
        guard row >= 0,
              row < rowCount,
              let columnIndex = columnIndex(for: tableColumn),
              columnIndex < columnCount(row) else { return nil }

        return displayValue(row, columnIndex)
    }

    static func emptyToolTip(row: Int,
                             rowCount: Int,
                             tableColumn: NSTableColumn?,
                             columnCount: (Int) -> Int) -> String {
        guard row >= 0,
              row < rowCount,
              let columnIndex = columnIndex(for: tableColumn),
              columnIndex < columnCount(row) else { return "" }

        return ""
    }

    static func configureDisplayCell(_ cell: Any, isNullOrPlaceholder: Bool) {
        guard let textCell = cell as? NSTextFieldCell else { return }
        textCell.textColor = isNullOrPlaceholder ? .secondaryLabelColor : .labelColor
    }

    static func sizeToFitWidthOfColumn(in tableView: NSTableView,
                                       displayColumn: Int,
                                       visibleRows: Range<Int>,
                                       isEnumColumn: Bool = false,
                                       displayValue: (Int, Int) -> String) -> CGFloat {
        guard displayColumn >= 0,
              displayColumn < tableView.tableColumns.count,
              let columnIndex = Int(tableView.tableColumns[displayColumn].identifier.rawValue) else { return 0 }

        return autodetectedColumnWidth(for: tableView.tableColumns[displayColumn],
                                       columnIndex: columnIndex,
                                       visibleRows: visibleRows,
                                       isEnumColumn: isEnumColumn,
                                       displayValue: displayValue)
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
            alert.runModalCenteredInKeyWindow()
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

    private static let currentTimestampExpressionRegex = try? NSRegularExpression(pattern: SPCurrentTimestampPattern)

    static func editedSQLExpression(for value: String, typeGrouping: String, defaultExpression: String? = nil, allowsStringUUIDFunction: Bool = false) -> String? {
        if let defaultExpression = defaultExpression,
           value == defaultExpression {
            return value
        }

        if let currentTimestampExpression = currentTimestampSQLExpression(from: value) {
            return currentTimestampExpression
        }

        if typeGrouping.lowercased() == "date" && value == "NOW()" {
            return "NOW()"
        }

        if allowsStringUUIDFunction && typeGrouping.lowercased() == "string" && value == "UUID()" {
            return "UUID()"
        }

        return nil
    }

    static func currentTimestampSQLExpression(from value: String) -> String? {
        guard let regex = currentTimestampExpressionRegex else { return nil }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.range.location == range.location,
              match.range.length == range.length else { return nil }

        return value
    }

    static func backtickQuoted(_ value: String) -> String {
        return "`\(value.replacingOccurrences(of: "`", with: "``"))`"
    }

    static func singleQuoted(_ value: String) -> String {
        return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}
