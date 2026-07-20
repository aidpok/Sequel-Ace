//
//  SPWindowController+LightweightPrinting.swift
//  Sequel Ace
//

import Cocoa

// MARK: - Lightweight Printing

struct SALightweightPrintTarget {
    let sourceView: NSView
    let title: String
    let attributedSnapshot: NSAttributedString?

    init(sourceView: NSView, title: String, attributedSnapshot: NSAttributedString? = nil) {
        self.sourceView = sourceView
        self.title = title
        self.attributedSnapshot = attributedSnapshot
    }
}

private final class SALightweightPrintableTableView: NSView {
    private let title: String
    private let columns: [(title: String, width: CGFloat)]
    private let rows: [[String]]
    private let bodyFont: NSFont
    private let headerFont: NSFont
    private let drawsGridlines: Bool
    private let margin: CGFloat = 36
    private let titleHeight: CGFloat = 28
    private let headerHeight: CGFloat = 22
    private let rowHeight: CGFloat

    override var isFlipped: Bool { true }

    init(title: String, columns: [(title: String, width: CGFloat)], rows: [[String]], bodyFont: NSFont, headerFont: NSFont, drawsGridlines: Bool) {
        self.title = title
        self.columns = columns
        self.rows = rows
        self.bodyFont = bodyFont
        self.headerFont = headerFont
        self.drawsGridlines = drawsGridlines
        self.rowHeight = max(18, ceil(bodyFont.ascender - bodyFont.descender + 8))

        let contentWidth = columns.reduce(0) { $0 + $1.width }
        let width = max(640, contentWidth + (margin * 2))
        let height = margin + titleHeight + headerHeight + (CGFloat(max(rows.count, 1)) * rowHeight) + margin
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 15),
            .foregroundColor: NSColor.black
        ]
        title.draw(in: NSRect(x: margin, y: margin - 4, width: bounds.width - (margin * 2), height: titleHeight), withAttributes: titleAttributes)

        guard !columns.isEmpty else { return }

        let gridColor = NSColor(calibratedWhite: 0.78, alpha: 1)
        let headerFill = NSColor(calibratedWhite: 0.92, alpha: 1)
        let alternateFill = NSColor(calibratedWhite: 0.975, alpha: 1)
        let headerAttributes = paragraphAttributes(font: headerFont, color: .black)
        let bodyAttributes = paragraphAttributes(font: bodyFont, color: .black)
        let drawsBackgrounds = UserDefaults.standard.bool(forKey: printBackgroundPreferenceKey)

        var y = margin + titleHeight
        var x = margin

        if drawsBackgrounds {
            headerFill.setFill()
            NSRect(x: margin, y: y, width: bounds.width - (margin * 2), height: headerHeight).fill()
        }

        for column in columns {
            drawString(column.title, in: NSRect(x: x + 4, y: y + 3, width: column.width - 8, height: headerHeight - 4), attributes: headerAttributes)
            if drawsGridlines {
                drawLine(from: NSPoint(x: x, y: y), to: NSPoint(x: x, y: y + headerHeight), color: gridColor)
            }
            x += column.width
        }
        drawLine(from: NSPoint(x: margin, y: y), to: NSPoint(x: x, y: y), color: gridColor)
        drawLine(from: NSPoint(x: margin, y: y + headerHeight), to: NSPoint(x: x, y: y + headerHeight), color: gridColor)
        if drawsGridlines {
            drawLine(from: NSPoint(x: x, y: y), to: NSPoint(x: x, y: y + headerHeight), color: gridColor)
        }

        y += headerHeight
        if rows.isEmpty {
            let emptyText = NSLocalizedString("No rows to print.", comment: "lightweight print empty table text")
            drawString(emptyText, in: NSRect(x: margin + 4, y: y + 3, width: bounds.width - (margin * 2) - 8, height: rowHeight - 4), attributes: bodyAttributes)
            drawLine(from: NSPoint(x: margin, y: y + rowHeight), to: NSPoint(x: x, y: y + rowHeight), color: gridColor)
            return
        }

        for (rowIndex, row) in rows.enumerated() {
            if drawsBackgrounds && rowIndex.isMultiple(of: 2) == false {
                alternateFill.setFill()
                NSRect(x: margin, y: y, width: bounds.width - (margin * 2), height: rowHeight).fill()
            }

            x = margin
            for (columnIndex, column) in columns.enumerated() {
                let value = columnIndex < row.count ? row[columnIndex] : ""
                drawString(value, in: NSRect(x: x + 4, y: y + 3, width: column.width - 8, height: rowHeight - 4), attributes: bodyAttributes)
                if drawsGridlines {
                    drawLine(from: NSPoint(x: x, y: y), to: NSPoint(x: x, y: y + rowHeight), color: gridColor)
                }
                x += column.width
            }
            if drawsGridlines {
                drawLine(from: NSPoint(x: x, y: y), to: NSPoint(x: x, y: y + rowHeight), color: gridColor)
            }
            drawLine(from: NSPoint(x: margin, y: y + rowHeight), to: NSPoint(x: x, y: y + rowHeight), color: gridColor)
            y += rowHeight
        }
    }

    func paragraphAttributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    func drawString(_ string: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        (string as NSString).draw(in: rect, withAttributes: attributes)
    }

    func drawLine(from start: NSPoint, to end: NSPoint, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 0.5
        path.stroke()
    }
}

private final class SALightweightPrintableTextView: NSView {
    private let title: String
    private let attributedString: NSAttributedString
    private let margin: CGFloat = 36
    private let titleHeight: CGFloat = 28
    private let contentWidth: CGFloat

    override var isFlipped: Bool { true }

    init(title: String, attributedString: NSAttributedString, font: NSFont, preservesFontAttributes: Bool = false) {
        self.title = title
        self.contentWidth = 720

        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        if !preservesFontAttributes {
            mutableString.addAttribute(.font, value: font, range: NSRange(location: 0, length: mutableString.length))
        }
        mutableString.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: mutableString.length)) { value, range, _ in
            guard value == nil else { return }
            mutableString.addAttribute(.foregroundColor, value: NSColor.black, range: range)
        }
        self.attributedString = mutableString

        let textHeight = max(24, ceil(mutableString.boundingRect(with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
                                                                 options: [.usesLineFragmentOrigin, .usesFontLeading]).height))
        super.init(frame: NSRect(x: 0, y: 0, width: contentWidth + (margin * 2), height: margin + titleHeight + textHeight + margin))
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 15),
            .foregroundColor: NSColor.black
        ]
        title.draw(in: NSRect(x: margin, y: margin - 4, width: contentWidth, height: titleHeight), withAttributes: titleAttributes)
        attributedString.draw(with: NSRect(x: margin, y: margin + titleHeight, width: contentWidth, height: bounds.height - margin - titleHeight),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

extension SPWindowController {
    func lightweightPrintTarget() -> SALightweightPrintTarget? {
        guard activeConnection != nil, loadedDatabaseDocument == nil else { return nil }

        switch activeLightweightViewMode {
        case .content:
            guard let tableView = findSubview(in: lightweightContentController.view, identifier: "TableContentTableView", type: NSTableView.self),
                  tableView.numberOfColumns > 0 else { return nil }

            let tableName = selectedTable ?? NSLocalizedString("Table", comment: "lightweight print fallback table title")
            return SALightweightPrintTarget(sourceView: tableView,
                                            title: String(format: NSLocalizedString("Table Content - %@", comment: "lightweight table content print job title"), tableName))

        case .query:
            let editor = lightweightQueryController.textView
            if isLightweightQueryEditorActive(), !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return SALightweightPrintTarget(sourceView: editor,
                                                title: NSLocalizedString("Query Editor", comment: "lightweight query editor print job title"))
            }

            if let tableView = findSubview(in: lightweightQueryController.view, identifier: "LightweightQueryTable", type: NSTableView.self),
               tableView.numberOfColumns > 0,
               tableView.numberOfRows > 0 {
                return SALightweightPrintTarget(sourceView: tableView,
                                                title: NSLocalizedString("Query Result", comment: "lightweight query result print job title"))
            }

            if !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return SALightweightPrintTarget(sourceView: editor,
                                                title: NSLocalizedString("Query Editor", comment: "lightweight query editor print job title"))
            }

            return nil

        case .structure:
            guard let tableView = findSubview(in: lightweightStructureController.view, identifier: "TableStructureColumnsTableView", type: NSTableView.self),
                  tableView.numberOfColumns > 0,
                  tableView.numberOfRows > 0 else { return nil }

            let tableName = selectedTable ?? NSLocalizedString("Table", comment: "lightweight print fallback table title")
            return SALightweightPrintTarget(sourceView: tableView,
                                            title: String(format: NSLocalizedString("Table Structure - %@", comment: "lightweight table structure print job title"), tableName))

        case .status:
            guard let snapshot = lightweightTableInfoController.printableSnapshot() else { return nil }

            let tableName = selectedTable ?? NSLocalizedString("Table", comment: "lightweight print fallback table title")
            return SALightweightPrintTarget(sourceView: lightweightTableInfoController.view,
                                            title: String(format: NSLocalizedString("Table Information - %@", comment: "lightweight table info print job title"), tableName),
                                            attributedSnapshot: snapshot)

        case .relations:
            return lightweightMetadataPrintTarget(in: lightweightRelationsController.view,
                                                  titleFormat: NSLocalizedString("Table Relations - %@", comment: "lightweight table relations print job title"))

        case .triggers:
            return lightweightMetadataPrintTarget(in: lightweightTriggersController.view,
                                                  titleFormat: NSLocalizedString("Table Triggers - %@", comment: "lightweight table triggers print job title"))
        }
    }

    func lightweightMetadataPrintTarget(in view: NSView, titleFormat: String) -> SALightweightPrintTarget? {
        guard let tableView = firstTableView(in: view),
              tableView.numberOfColumns > 0,
              tableView.numberOfRows > 0 else { return nil }

        let tableName = selectedTable ?? NSLocalizedString("Table", comment: "lightweight print fallback table title")
        return SALightweightPrintTarget(sourceView: tableView,
                                        title: String(format: titleFormat, tableName))
    }

    func isLightweightQueryEditorActive() -> Bool {
        guard let firstResponder = window?.firstResponder else { return false }

        let editor = lightweightQueryController.textView
        if firstResponder === editor {
            return true
        }

        guard let firstResponderView = firstResponder as? NSView else { return false }
        return firstResponderView === editor || firstResponderView.isDescendant(of: editor)
    }

    func shouldWarnBeforePrintingLightweightContent(_ target: SALightweightPrintTarget) -> Bool {
        guard activeLightweightViewMode == .content,
              let tableView = target.sourceView as? NSTableView else { return false }

        let rowLimit = UserDefaults.standard.integer(forKey: SPPrintWarningRowLimit)
        return tableView.numberOfRows > rowLimit
    }

    func warnBeforePrintingLightweightContent(_ target: SALightweightPrintTarget, primaryButtonHandler: @escaping () -> Void) {
        let rowCount = (target.sourceView as? NSTableView)?.numberOfRows ?? 0
        let rowCountString = NumberFormatter.decimalStyleFormatter.string(from: NSNumber(value: rowCount)) ?? "\(rowCount)"
        let tableName = selectedTable ?? NSLocalizedString("Table", comment: "lightweight print fallback table title")
        let message = String(format: NSLocalizedString("Are you sure you want to print the current content view of the table '%@'?\n\nIt currently contains %@ rows, which may take a significant amount of time to print.", comment: "continue to print informative message"), tableName, rowCountString)

        NSAlert.createDefaultAlert(title: NSLocalizedString("Continue to print?", comment: "continue to print message"),
                                   message: message,
                                   primaryButtonTitle: NSLocalizedString("Print", comment: "print button"),
                                   primaryButtonHandler: primaryButtonHandler,
                                   cancelButtonHandler: nil)
    }

    func runLightweightPrintOperation(for target: SALightweightPrintTarget) {
        target.sourceView.layoutSubtreeIfNeeded()
        let printView = lightweightPrintableView(for: target)

        let printInfo = SAPrintUtility.configuredPrintInfo()
        printInfo.horizontalPagination = .fit
        printInfo.isHorizontallyCentered = false

        let operation = NSPrintOperation(view: printView, printInfo: printInfo)
        operation.jobTitle = target.title
        operation.canSpawnSeparateThread = false

        let printPanel = operation.printPanel
        printPanel.options.insert([.showsOrientation, .showsScaling, .showsPaperSize])
        printPanel.addAccessoryController(SAPrintAccessoryController(webView: nil))
        operation.printPanel = printPanel

        if let window = window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    func lightweightPrintableView(for target: SALightweightPrintTarget) -> NSView {
        if let attributedSnapshot = target.attributedSnapshot {
            return SALightweightPrintableTextView(title: target.title,
                                                  attributedString: attributedSnapshot,
                                                  font: UserDefaults.getFont(),
                                                  preservesFontAttributes: true)
        }

        if let tableView = target.sourceView as? NSTableView {
            return lightweightPrintableTableView(from: tableView, title: target.title)
        }

        if let textView = target.sourceView as? NSTextView {
            let font = textView.font ?? UserDefaults.getFont()
            let textStorage = textView.textStorage ?? NSTextStorage(string: textView.string)
            return SALightweightPrintableTextView(title: target.title, attributedString: textStorage, font: font)
        }

        return target.sourceView
    }

    func lightweightPrintableTableView(from tableView: NSTableView, title: String) -> NSView {
        let tableColumns = tableView.tableColumns.filter { !$0.isHidden }
        let bodyFont = tableColumns.compactMap { ($0.dataCell as? NSCell)?.font }.first ?? UserDefaults.getFont()
        let headerFont = tableColumns.compactMap { $0.headerCell.font }.first ?? NSFont.boldSystemFont(ofSize: bodyFont.pointSize)
        let columns = tableColumns.map { tableColumn -> (title: String, width: CGFloat) in
            let title = tableColumn.headerCell.stringValue.isEmpty ? tableColumn.identifier.rawValue : tableColumn.headerCell.stringValue
            return (title: title, width: min(max(tableColumn.width, 70), 260))
        }

        let rows = (0..<tableView.numberOfRows).map { row in
            tableColumns.map { tableColumn in
                return printableString(for: tableView.dataSource?.tableView?(tableView, objectValueFor: tableColumn, row: row),
                                       tableColumn: tableColumn)
            }
        }

        return SALightweightPrintableTableView(title: title,
                                               columns: columns,
                                               rows: rows,
                                               bodyFont: bodyFont,
                                               headerFont: headerFont,
                                               drawsGridlines: UserDefaults.standard.bool(forKey: SPDisplayTableViewVerticalGridlines))
    }

    func printableString(for value: Any?, tableColumn: NSTableColumn) -> String {
        guard let value = value else { return "" }

        if tableColumn.dataCell is NSButtonCell {
            if let boolValue = value as? Bool {
                return boolValue ? "✓" : ""
            }
            if let number = value as? NSNumber {
                return number.boolValue ? "✓" : ""
            }
            let string = String(describing: value)
            return string == "1" || string.caseInsensitiveCompare("YES") == .orderedSame ? "✓" : ""
        }

        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }

        if value is NSNull {
            return UserDefaults.standard.string(forKey: SPNullValue) ?? "NULL"
        }

        return String(describing: value)
    }

    func showLightweightPrintUnsupportedAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Nothing printable in the current lightweight view.", comment: "lightweight print unsupported alert title")
        alert.informativeText = NSLocalizedString("Printing is currently available for lightweight content, query editor/results, table structure, table information, relations, and triggers views.", comment: "lightweight print unsupported alert message")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))

        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    func firstTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView {
            return tableView
        }

        for subview in view.subviews {
            if let tableView = firstTableView(in: subview) {
                return tableView
            }
        }

        return nil
    }

    func findSubview<View: NSView>(in view: NSView, identifier: String, type: View.Type) -> View? {
        if let matchedView = view as? View, view.identifier?.rawValue == identifier {
            return matchedView
        }

        for subview in view.subviews {
            if let matchedView = findSubview(in: subview, identifier: identifier, type: type) {
                return matchedView
            }
        }

        return nil
    }
}
