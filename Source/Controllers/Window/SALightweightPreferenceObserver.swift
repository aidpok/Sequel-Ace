//
//  SALightweightPreferenceObserver.swift
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

import Foundation

final class SALightweightPreferenceObserver: NSObject {
    typealias ChangeHandler = (String) -> Void

    private let userDefaults: UserDefaults
    private let keys: [String]
    private let keySet: Set<String>
    private let options: NSKeyValueObservingOptions
    private let changeHandler: ChangeHandler
    private var isObserving = false

    init(keys: [String],
         userDefaults: UserDefaults = .standard,
         options: NSKeyValueObservingOptions = [.new],
         changeHandler: @escaping ChangeHandler) {
        var uniqueKeys: [String] = []
        for key in keys where !uniqueKeys.contains(key) {
            uniqueKeys.append(key)
        }

        self.userDefaults = userDefaults
        self.keys = uniqueKeys
        self.keySet = Set(uniqueKeys)
        self.options = options
        self.changeHandler = changeHandler
    }

    func start() {
        guard !isObserving else { return }

        for key in keys {
            userDefaults.addObserver(self, forKeyPath: key, options: options, context: nil)
        }
        isObserving = true
    }

    func invalidate() {
        guard isObserving else { return }

        for key in keys {
            userDefaults.removeObserver(self, forKeyPath: key)
        }
        isObserving = false
    }

    deinit {
        invalidate()
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath, keySet.contains(keyPath) else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        changeHandler(keyPath)
    }
}
