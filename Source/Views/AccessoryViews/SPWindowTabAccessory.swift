//
//  SPWindowTabAccessory.swift
//  Sequel Ace
//
//  Created by Parker Erway on 10/26/21.
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

import Cocoa

final class SPWindowTabAccessory: NSView {
    private var activationNotificationObservers = [NSObjectProtocol]()

    // MARK: Initializers
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 0))

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        addSubviews(tabAccessoryViewImage, tabText)

        tabText.snp.makeConstraints {
            $0.leading.top.bottom.equalToSuperview()
            $0.trailing.equalTo(tabAccessoryViewImage.snp.leading)
        }

        tabAccessoryViewImage.snp.makeConstraints {
            $0.size.equalTo(20)
            $0.trailing.equalToSuperview()
            $0.centerY.equalToSuperview()
        }
    }

    deinit {
        removeActivationObservers()
    }
    
    // MARK: Subviews
    
    private lazy var tabText: NSTextField = {
        let text = NSTextField()
        text.userActivity = .none
        text.backgroundColor = .clear
        text.isEditable = false
        text.isHidden = false
        text.alignment = .center
        text.isBordered = false
        text.textColor = tabTitleTextColor
        return text
    }()

    private lazy var tabAccessoryViewImage: NSImageView = {
        var image = NSImage(imageLiteralResourceName: "fallback_lock.fill")
        if #available(macOS 11, *), let systemImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
            image = systemImage
        }
        let imageView = NSImageView(image: image)
        imageView.toolTip = NSLocalizedString("Connection Secured via SSL", comment: "Connection Secured via SSL information text")
        imageView.isHidden = true
        return imageView
    }()
    
    // MARK: Setters
    
    func update(color: NSColor?, isSSL: Bool) {
        var tabColor = color
        if #available(macOS 10.13, *) {
            if let tabColorName = favoriteTabColorName(for: tabColor) {
                tabColor = NSColor(named: NSColor.Name(tabColorName), bundle: .main) ?? tabColor
            }
        }

        layer?.backgroundColor = tabColor?.cgColor
        tabAccessoryViewImage.isHidden = !isSSL
    }

    func setTitle(title: String) {
        tabText.stringValue = title
        refreshTitleAppearance()
    }
    
    // MARK: Callbacks

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil {
            self.snp.remakeConstraints {
                $0.leading.equalToSuperview().offset(35)
                $0.trailing.equalToSuperview().offset(-35)
                $0.top.equalToSuperview().offset(5)
                $0.bottom.equalToSuperview()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshActivationObservers()
        refreshTitleAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshTitleAppearance()
    }

    private var tabTitleTextColor: NSColor {
        if NSApp.isActive {
            return .labelColor
        }

        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedWhite: 0.68, alpha: 1)
        }

        return NSColor(calibratedWhite: 0.38, alpha: 1)
    }

    private func favoriteTabColorName(for color: NSColor?) -> String? {
        guard let colorName = color?.colorNameComponent else { return nil }

        for favoriteColorName in ["favoriteRed", "favoriteOrange", "favoriteYellow", "favoriteGreen", "favoriteBlue", "favoritePurple", "favoriteGraphite"] {
            if colorName == favoriteColorName || colorName.contains(favoriteColorName) {
                return favoriteColorName + "-tab"
            }
        }

        return nil
    }

    private func refreshActivationObservers() {
        removeActivationObservers()

        let notificationCenter = NotificationCenter.default
        let refreshTitleAppearance: (Notification) -> Void = { [weak self] _ in
            self?.refreshTitleAppearance()
        }

        activationNotificationObservers.append(notificationCenter.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main, using: refreshTitleAppearance))
        activationNotificationObservers.append(notificationCenter.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main, using: refreshTitleAppearance))

        guard let window = window else { return }
        activationNotificationObservers.append(notificationCenter.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main, using: refreshTitleAppearance))
        activationNotificationObservers.append(notificationCenter.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main, using: refreshTitleAppearance))
    }

    private func removeActivationObservers() {
        activationNotificationObservers.forEach(NotificationCenter.default.removeObserver)
        activationNotificationObservers.removeAll()
    }

    private func refreshTitleAppearance() {
        tabText.textColor = tabTitleTextColor
        tabText.needsDisplay = true
    }
}
