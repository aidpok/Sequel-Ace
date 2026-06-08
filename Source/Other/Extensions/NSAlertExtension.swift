//
//  NSAlertExtension.swift
//  Sequel Ace
//
//  Created by Jakub Kaspar on 05.07.2020.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import AppKit

@objc extension NSAlert {
    @objc(runModalCenteredInKeyWindow)
    @discardableResult
    func runModalCenteredInKeyWindow() -> NSApplication.ModalResponse {
        return runModalCentered(over: NSAlert.sequelAcePresentationWindow(excluding: window))
    }

    @discardableResult
    func runModalCentered(over parentWindow: NSWindow?) -> NSApplication.ModalResponse {
        window.animationBehavior = .none
        window.isRestorable = false

        let presentationWindow = parentWindow ?? NSAlert.sequelAcePresentationWindow(excluding: window)
        let centerAlert = { [weak self, weak presentationWindow] in
            guard let self = self else { return }
            self.centerOverPresentationWindow(presentationWindow)
        }

        let centerNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification
        ]
        let observers = centerNotifications.map { notification in
            NotificationCenter.default.addObserver(forName: notification, object: window, queue: .main) { _ in
                centerAlert()
            }
        }

        centerAlert()
        DispatchQueue.main.async { [weak self, weak presentationWindow] in
            self?.centerOverPresentationWindow(presentationWindow)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            centerAlert()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            centerAlert()
        }

        let response = runModal()
        observers.forEach(NotificationCenter.default.removeObserver)
        return response
    }

    private func centerOverPresentationWindow(_ parentWindow: NSWindow?) {
        guard let parentWindow else {
            window.center()
            return
        }

        window.contentView?.layoutSubtreeIfNeeded()

        let parentFrame = parentWindow.frame
        let alertFrame = window.frame
        var origin = NSPoint(x: parentFrame.midX - alertFrame.width / 2,
                             y: parentFrame.midY - alertFrame.height / 2)

        if let visibleFrame = parentWindow.screen?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - alertFrame.width)
            origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - alertFrame.height)
        }

        window.setFrameOrigin(origin)
    }

    private static func sequelAcePresentationWindow(excluding excludedWindow: NSWindow? = nil) -> NSWindow? {
        let directCandidates = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
        if let window = directCandidates.first(where: { isUsablePresentationWindow($0, excluding: excludedWindow) }) {
            return window
        }

        return NSApp.orderedWindows.first(where: { isUsablePresentationWindow($0, excluding: excludedWindow) })
    }

    private static func isUsablePresentationWindow(_ window: NSWindow, excluding excludedWindow: NSWindow?) -> Bool {
        if let excludedWindow = excludedWindow, window === excludedWindow {
            return false
        }

        guard window.isVisible,
              !window.isMiniaturized,
              !(window is NSPanel),
              window.contentView != nil else {
            return false
        }

        return true
    }

	/// Creates an alert with primary colored button (also accepts "Enter" key) and cancel button (also accepts escape key), main title and informative subtitle message.
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - primaryButtonTitle: String for main confirm button
	///   - primaryButtonHandler: Optional block that's invoked when user hits primary button or Enter
	///   - cancelButtonHandler: Optional block that's invoked when user hits cancel button or Escape
	/// - Returns: Nothing
	static func createDefaultAlert(title: String,
								   message: String,
								   primaryButtonTitle: String,
								   primaryButtonHandler: (() -> ())? = nil,
								   cancelButtonHandler: (() -> ())? = nil) {

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
            if alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn {
                primaryButtonHandler?()
            } else {
                cancelButtonHandler?()
            }
        }
	}

	/// Creates an alert with primary colored button (also accepts "Enter" key) and cancel button (also accepts escape key), main title and informative subtitle message, and showsSuppressionButton
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - suppressionKey: String key to set in user defaults
	///   - primaryButtonTitle: String for main confirm button
	///   - primaryButtonHandler: Optional block that's invoked when user hits primary button or Enter
	///   - cancelButtonHandler: Optional block that's invoked when user hits cancel button or Escape
	/// - Returns: Nothing
	static func createDefaultAlertWithSuppression(title: String,
												  message: String,
                                                  suppressionKey: String? = nil,
												  primaryButtonTitle: String,
												  primaryButtonHandler: (() -> ())? = nil,
												  cancelButtonHandler: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message

            if suppressionKey != nil {
                alert.showsSuppressionButton = true
            }
            // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

            if alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn {
                primaryButtonHandler?()
            } else {
                cancelButtonHandler?()
            }

            // if they check the box, set the bool
            if let suppressionButton = alert.suppressionButton, let suppressionKey = suppressionKey,
               suppressionButton.state == .on {
                UserDefaults.standard.set(true, forKey: suppressionKey)
            }
        }
	}

	/// Creates an alert with primary colored button (also accepts "Enter" key) and secondary colored button (also accepts escape key), main title and informative subtitle message.
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - primaryButtonTitle: String for main button
	///   - secondaryButtonTitle: String for secondary button
	///   - primaryButtonHandler: Optional block that's invoked when user hits primary button or Enter
	///   - secondaryButtonHandler: Optional block that's invoked when user hits cancel button or Escape
	/// - Returns: Nothing
	static func createAlert(title: String,
							message: String,
							primaryButtonTitle: String,
							secondaryButtonTitle: String,
							primaryButtonHandler: (() -> ())? = nil,
							secondaryButtonHandler: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: secondaryButtonTitle)
            if alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn {
                primaryButtonHandler?()
            } else {
                secondaryButtonHandler?()
            }
        }
	}


	/// Creates an alert with primary colored OK button that triggers callback
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: string for informative message
	///   - callback: Optional block that's invoked when user hits OK button
	@objc(createWarningAlertWithTitle:message:callback:)
	static func createWarningAlert(title: String,
								   message: String,
								   callback: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModalCenteredInKeyWindow()
            callback?()
        }
	}

    /// Creates an informational alert with primary colored OK button that triggers callback
    /// - Parameters:
    ///   - title: String for title of the alert
    ///   - message: string for informative message
    ///   - callback: Optional block that's invoked when user hits OK button
    static func createInfoAlert(title: String,
                                   message: String,
                                   callback: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModalCenteredInKeyWindow()
            callback?()
        }
    }

	/// Creates an alert with primary colored button (also accepts "Enter" key) and cancel button (also accepts escape key), main title, informative subtitle message and accessory view.
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - accessoryView: NSView to be used as accessory view
	///   - primaryButtonTitle: String for main confirm button
	///   - primaryButtonHandler: Optional block that's invoked when user hits primary button or Enter
	///   - cancelButtonHandler: Optional block that's invoked when user hits cancel button or Escape
	/// - Returns: Nothing
	static func createAccessoryAlert(title: String,
									 message: String,
									 accessoryView: NSView,
									 primaryButtonTitle: String,
									 primaryButtonHandler: (() -> ())? = nil,
									 cancelButtonHandler: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.accessoryView = accessoryView
            // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
            alert.addButton(withTitle: primaryButtonTitle)
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
            if alert.runModalCenteredInKeyWindow() == .alertFirstButtonReturn {
                primaryButtonHandler?()
            } else {
                cancelButtonHandler?()
            }
        }
	}

	/// Creates an alert with primary colored button (also accepts "Enter" key) and cancel button (also accepts escape key), main title, informative subtitle message and accessory view.
	/// - Parameters:
	///   - title: String for title of the alert
	///   - message: String for informative message
	///   - accessoryView: NSView to be used as accessory view
	///   - callback: Optional block that's invoked when user hits OK button
	/// - Returns: Nothing
	static func createAccessoryWarningAlert(title: String,
											message: String,
											accessoryView: NSView,
                                            callback: (() -> ())? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = title
            alert.informativeText = message
            alert.accessoryView = accessoryView
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModalCenteredInKeyWindow()
            callback?()
        }
	}
}
