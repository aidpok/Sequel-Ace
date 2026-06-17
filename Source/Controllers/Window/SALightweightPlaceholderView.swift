//
//  SALightweightPlaceholderView.swift
//  Sequel Ace
//

import AppKit
import SwiftUI

final class SALightweightPlaceholderView: NSView {
    var message: String = "" {
        didSet {
            updateContent()
        }
    }

    private lazy var hostingView = NSHostingView(rootView: contentView())

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    private func updateContent() {
        hostingView.rootView = contentView()
    }

    private func contentView() -> SALightweightPlaceholderContentView {
        return SALightweightPlaceholderContentView(message: message)
    }
}

private struct SALightweightPlaceholderContentView: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .background(Color.clear)
    }
}
