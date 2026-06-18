//
//  SALightweightCSVImportAccessory.swift
//  Sequel Ace
//

import AppKit

/// Small AppKit-only CSV/TSV settings accessory for lightweight import flows.
///
/// This view controller intentionally only owns CSV parser options backed by
/// `SALightweightCSVImportSettings`. Encoding selection/autodetect is omitted
/// from this slice; callers that need encoding control should compose this view
/// with the existing encoding accessory.
final class SALightweightCSVImportAccessory: NSViewController {
    private enum Layout {
        static let viewWidth: CGFloat = 360
        static let viewHeight: CGFloat = 176
        static let labelWidth: CGFloat = 136
        static let fieldWidth: CGFloat = 156
        static let controlHeight: CGFloat = 22
        static let edgePadding: CGFloat = 12
        static let rowSpacing: CGFloat = 8
    }

    private let userDefaults: UserDefaults
    private let inferredFileURL: URL?

    private let fieldTerminatorField = SALightweightCSVImportAccessory.makeTextField()
    private let lineTerminatorField = SALightweightCSVImportAccessory.makeTextField()
    private let fieldEnclosedByField = SALightweightCSVImportAccessory.makeTextField()
    private let escapeCharacterField = SALightweightCSVImportAccessory.makeTextField()
    private let firstLineIsHeaderButton = NSButton(checkboxWithTitle: NSLocalizedString("First line contains field names", comment: "CSV import first line is header checkbox"), target: nil, action: nil)

    private(set) var settings: SALightweightCSVImportSettings

    var rootView: NSView {
        _ = view
        return view
    }

    init(userDefaults: UserDefaults = .standard, inferringFrom fileURL: URL? = nil) {
        self.userDefaults = userDefaults
        self.inferredFileURL = fileURL
        self.settings = SALightweightCSVImportSettings.load(from: userDefaults, inferringFrom: fileURL)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.userDefaults = .standard
        self.inferredFileURL = nil
        self.settings = SALightweightCSVImportSettings.load()

        super.init(coder: coder)
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.viewWidth, height: Layout.viewHeight))
        rootView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = Layout.rowSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(makeRow(label: NSLocalizedString("Fields terminated by:", comment: "CSV import field terminator label"), control: fieldTerminatorField))
        stackView.addArrangedSubview(makeRow(label: NSLocalizedString("Lines terminated by:", comment: "CSV import line terminator label"), control: lineTerminatorField))
        stackView.addArrangedSubview(makeRow(label: NSLocalizedString("Fields enclosed by:", comment: "CSV import enclosed by label"), control: fieldEnclosedByField))
        stackView.addArrangedSubview(makeRow(label: NSLocalizedString("Fields escaped by:", comment: "CSV import escape character label"), control: escapeCharacterField))
        stackView.addArrangedSubview(firstLineIsHeaderButton)

        rootView.addSubview(stackView)
        view = rootView

        configureControls()
        NSLayoutConstraint.activate([
            rootView.widthAnchor.constraint(equalToConstant: Layout.viewWidth),
            rootView.heightAnchor.constraint(equalToConstant: Layout.viewHeight),
            stackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Layout.edgePadding),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -Layout.edgePadding),
            stackView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Layout.edgePadding),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -Layout.edgePadding)
        ])

        applySettingsToControls(settings)
    }

    @discardableResult
    func loadCurrentSettings(from userDefaults: UserDefaults? = nil, inferringFrom fileURL: URL? = nil) -> SALightweightCSVImportSettings {
        let loadedSettings = SALightweightCSVImportSettings.load(from: userDefaults ?? self.userDefaults,
                                                                 inferringFrom: fileURL ?? inferredFileURL)
        updateUI(with: loadedSettings)
        return loadedSettings
    }

    func updateUI(with settings: SALightweightCSVImportSettings) {
        self.settings = settings
        _ = view
        applySettingsToControls(settings)
    }

    func readSettingsFromUI() -> SALightweightCSVImportSettings {
        _ = view

        return SALightweightCSVImportSettings(
            fieldTerminator: fieldTerminatorField.stringValue,
            lineTerminator: lineTerminatorField.stringValue,
            fieldEnclosedBy: fieldEnclosedByField.stringValue,
            escapeCharacter: escapeCharacterField.stringValue,
            firstLineIsHeader: firstLineIsHeaderButton.state == .on
        )
    }

    @discardableResult
    func saveSettings(to userDefaults: UserDefaults? = nil) -> SALightweightCSVImportSettings {
        let updatedSettings = readSettingsFromUI()
        updatedSettings.save(to: userDefaults ?? self.userDefaults)
        settings = updatedSettings
        return updatedSettings
    }

    private func configureControls() {
        let textFields = [fieldTerminatorField, lineTerminatorField, fieldEnclosedByField, escapeCharacterField]
        for textField in textFields {
            textField.delegate = self
            textField.target = self
            textField.action = #selector(controlValueChanged(_:))
        }

        firstLineIsHeaderButton.target = self
        firstLineIsHeaderButton.action = #selector(controlValueChanged(_:))

        fieldTerminatorField.toolTip = NSLocalizedString("Use \\t for tab-separated files.", comment: "CSV import field terminator tooltip")
        lineTerminatorField.toolTip = NSLocalizedString("Common values are \\n, \\r, or \\r\\n.", comment: "CSV import line terminator tooltip")
        fieldEnclosedByField.toolTip = NSLocalizedString("Usually a double quote.", comment: "CSV import enclosed by tooltip")
        escapeCharacterField.toolTip = NSLocalizedString("Legacy default is \\ or \".", comment: "CSV import escape character tooltip")
    }

    private func applySettingsToControls(_ settings: SALightweightCSVImportSettings) {
        fieldTerminatorField.stringValue = settings.fieldTerminator
        lineTerminatorField.stringValue = settings.lineTerminator
        fieldEnclosedByField.stringValue = settings.fieldEnclosedBy
        escapeCharacterField.stringValue = settings.escapeCharacter
        firstLineIsHeaderButton.state = settings.firstLineIsHeader ? .on : .off
    }

    private func makeRow(label labelText: String, control: NSControl) -> NSView {
        let label = NSTextField(labelWithString: labelText)
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: Layout.labelWidth),
            control.widthAnchor.constraint(equalToConstant: Layout.fieldWidth),
            control.heightAnchor.constraint(equalToConstant: Layout.controlHeight)
        ])

        return row
    }

    @objc private func controlValueChanged(_ sender: Any?) {
        settings = readSettingsFromUI()
    }

    private static func makeTextField() -> NSTextField {
        let textField = NSTextField(frame: .zero)
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.controlSize = .small
        textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return textField
    }
}

extension SALightweightCSVImportAccessory: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        settings = readSettingsFromUI()
    }
}
